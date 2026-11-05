# apps/api/domains/logic/sender_config/put_sender_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/mailer_config'
require_relative 'base'
require_relative 'serializers'
require_relative 'change_logger'
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
        include ChangeLogger
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
          raise_form_error('Authentication required', field: :user_id, error_type: :authentication_required) if cust.anonymous?

          # Validate domain_id parameter
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          # Load domain and organization, verify ownership and entitlement
          authorize_sender_config!(@domain_id)

          # Check if config already exists
          @existing_config = Onetime::CustomDomain::MailerConfig.find_by_domain_id(@custom_domain.identifier)

          # Enforce domain restriction BEFORE validating. A blank from_address is
          # normalized to noreply@<domain> for the (non-flexible) custom-mail-sender
          # entitlement, so an operator can enable the sender without hand-typing an
          # address. In flexible-from-domain mode the address is returned unchanged,
          # so validate_required_fields still requires an explicit value.
          @from_address = enforce_from_domain(@from_address, @custom_domain, @organization)

          # Validate required fields (against the normalized address)
          validate_required_fields
        end

        def process
          OT.ld "[PutSenderConfig] Replacing sender config for domain #{@domain_id} by user #{cust.extid}"

          if @existing_config
            # From the record this write replaced, not the one raise_concerns
            # loaded (see replace_existing_config)
            was_enabled = replace_existing_config
            log_sender_config_event(
              event: :domain_sender_config_replaced,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
            )
          else
            was_enabled = nil
            guarded_config_write { create_new_config }
            log_sender_config_event(
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
        # Custom mail sender model: sender identity only, no provider/api_key.
        #
        # Runs on the record update_for_domain! re-reads under WATCH
        # (GuardedConfigWrites): the fields this PUT does not set (verification
        # and provisioning state, which background jobs write) keep their
        # current values, and the verification reset and the enabled event
        # compare against the state this write replaced.
        #
        # @return [Boolean] whether the replaced record was enabled
        def replace_existing_config
          @mailer_config, was_enabled = guarded_config_write do
            Onetime::CustomDomain::MailerConfig.update_for_domain!(@custom_domain.identifier) do |config|
              previously_enabled    = config.enabled?
              original_from_address = config.from_address

              # PUT semantics: full replacement - set ALL sender identity fields
              config.from_name    = @from_name        # Empty string clears the field
              config.from_address = @from_address
              config.reply_to     = @reply_to         # Empty string clears the field
              config.enabled      = @enabled.to_s

              # Reset verification if from_address changed
              if @from_address != original_from_address
                config.verified_at         = nil
                config.verification_status = VERIFICATION_STATUS_PENDING
              end

              # Update timestamp for replacement
              config.updated = Familia.now.to_i
              previously_enabled
            end
          end
          was_enabled
        end

        # Log enabled/disabled state change if it occurred.
        #
        # @param was_enabled [Boolean, nil] Previous enabled state (nil if new config)
        # @param is_enabled [Boolean] New enabled state
        def log_enabled_state_change(was_enabled, is_enabled)
          # Skip if no change (both false, or both true)
          return if was_enabled == is_enabled

          # Log when sender config is enabled (new config or was disabled).
          # !was_enabled covers both nil (new config) and false (was disabled).
          if is_enabled && !was_enabled
            log_sender_config_event(
              event: :domain_sender_config_enabled,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
            )
          elsif was_enabled == true && !is_enabled
            log_sender_config_event(
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
