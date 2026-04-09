# apps/api/domains/logic/sender_config/put_sender_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/mailer_config'
require_relative 'base'
require_relative 'serializers'
require_relative 'audit_logger'
require_relative 'auto_provisioning'

module DomainsAPI
  module Logic
    module SenderConfig
      # PUT Domain Sender Configuration (full replacement)
      #
      # @api Creates or replaces the mail sender configuration for a custom domain.
      #   Uses PUT semantics: the request body IS the new state.
      #   Empty string or null clears optional fields.
      #   Requires the requesting user to be an organization owner
      #   with custom_mail_sender entitlement.
      #
      # Request body:
      # - from_address: Required. Sender email address
      # - from_name: Optional. Display name for sender (defaults to empty)
      # - reply_to: Optional. Reply-to address (defaults to empty)
      # - enabled: Optional. Boolean to enable/disable (default: false)
      #
      # Custom mail sender model: users configure sender identity only.
      # Provider credentials are resolved from installation-level configuration.
      #
      # Response includes the updated config.
      #
      class PutSenderConfig < Base
        include Serializers
        include AuditLogger
        include AutoProvisioning

        attr_reader :mailer_config, :existing_config

        def process_params
          @domain_id    = sanitize_identifier(params['extid'])
          @from_name    = sanitize_plain_text(params['from_name'])
          @from_address = params['from_address'].to_s.strip
          @reply_to     = params['reply_to'].to_s.strip
          @enabled      = parse_boolean(params['enabled'])
        end

        def raise_concerns
          # Require authenticated user
          raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

          # Validate domain_id parameter
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          # Load domain and organization, verify ownership and entitlement
          authorize_sender_config!(@domain_id)

          # Check if config already exists
          @existing_config = Onetime::CustomDomain::MailerConfig.find_by_domain_id(@custom_domain.identifier)

          # Validate required fields
          validate_required_fields

          # Enforce domain restriction based on entitlement
          @from_address = enforce_from_domain(@from_address, @custom_domain, @organization)
        end

        def process
          OT.ld "[PutSenderConfig] Replacing sender config for domain #{@domain_id} by user #{cust.extid}"

          # Track enabled state change for audit
          was_enabled = @existing_config&.enabled?

          if @existing_config
            replace_existing_config
            log_sender_audit_event(
              event: :domain_sender_config_replaced,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
            )
          else
            create_new_config
            log_sender_audit_event(
              event: :domain_sender_config_created,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
            )
          end

          # Log enabled state change if it occurred
          log_enabled_state_change(was_enabled, @enabled)

          # Auto-provision DNS records for platform mode
          # Non-blocking: we continue even if provisioning fails
          auto_provision_if_needed

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            record: serialize_sender_config(@mailer_config),
          }
        end

        def form_fields
          {
            domain_id: @domain_id,
            from_name: @from_name,
            from_address: @from_address,
            reply_to: @reply_to,
            enabled: @enabled,
          }
        end

        private

        def validate_required_fields
          raise_form_error('From address is required', field: :from_address, error_type: :missing) if @from_address.to_s.empty?

          # Validate email format using Truemail
          unless valid_email?(@from_address)
            raise_form_error('Invalid email format for from_address', field: :from_address, error_type: :invalid)
          end
        end

        def create_new_config
          # Custom mail sender model: sender identity only, no provider/api_key
          # Provider credentials resolved from installation-level configuration
          @mailer_config = Onetime::CustomDomain::MailerConfig.create!(
            domain_id: @custom_domain.identifier,
            from_name: @from_name,
            from_address: @from_address,
            reply_to: @reply_to,
            enabled: @enabled,
            sending_mode: 'platform',  # Platform mode: OTS provisions DNS via provider API
          )
        end

        # Replaces existing sender config with PUT semantics.
        #
        # Uses transaction with commit_fields to prevent race condition where
        # config could be deleted between existence check and update.
        #
        # Custom mail sender model: sender identity only, no provider/api_key.
        #
        def replace_existing_config
          @mailer_config = @existing_config

          # Capture original from_address BEFORE mutation (for verification reset check)
          original_from_address = @existing_config.from_address

          # PUT semantics: full replacement - set ALL sender identity fields
          @mailer_config.from_name    = @from_name        # Empty string clears the field
          @mailer_config.from_address = @from_address
          @mailer_config.reply_to     = @reply_to         # Empty string clears the field
          @mailer_config.enabled      = @enabled.to_s

          # Reset verification if from_address changed
          if @from_address != original_from_address
            @mailer_config.verified_at         = nil
            @mailer_config.verification_status = VERIFICATION_STATUS_PENDING
          end

          # Update timestamp for replacement
          @mailer_config.updated = Familia.now.to_i

          # commit_fields uses its own internal transaction for atomicity
          @mailer_config.commit_fields
        end

        # Log enabled/disabled state change if it occurred.
        #
        # @param was_enabled [Boolean, nil] Previous enabled state (nil if new config)
        # @param is_enabled [Boolean] New enabled state
        def log_enabled_state_change(was_enabled, is_enabled)
          # Skip if no change (both false, or both true)
          return if was_enabled == is_enabled

          # Log when sender config is enabled (new config or was disabled)
          if is_enabled && (was_enabled.nil? || was_enabled == false)
            log_sender_audit_event(
              event: :domain_sender_config_enabled,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
            )
          elsif was_enabled == true && !is_enabled
            log_sender_audit_event(
              event: :domain_sender_config_disabled,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
            )
          end
        end
      end
    end
  end
end
