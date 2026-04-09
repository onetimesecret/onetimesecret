# apps/api/domains/logic/sender_config/patch_sender_config.rb
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
      # PATCH Domain Sender Configuration (partial update)
      #
      # @api Partially updates the mail sender configuration for a custom domain.
      #   Uses PATCH semantics: only provided fields are updated, empty values
      #   preserve existing data.
      #   Requires the requesting user to be an organization owner
      #   with custom_mail_sender entitlement.
      #
      # Request body:
      # - from_address: Required for create, optional for update (preserves existing if empty)
      # - from_name: Optional. Display name for sender (preserves existing if empty)
      # - reply_to: Optional. Reply-to address (preserves existing if empty)
      # - enabled: Optional. Boolean to enable/disable (preserves existing if omitted)
      #
      # Custom mail sender model: users configure sender identity only.
      # Provider credentials are resolved from installation-level configuration.
      #
      # Response includes the updated config.
      #
      class PatchSenderConfig < Base
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

          # Track which fields were explicitly provided (for PATCH semantics)
          @from_name_provided    = !params['from_name'].nil?
          @from_address_provided = !params['from_address'].nil?
          @reply_to_provided     = !params['reply_to'].nil?
          @enabled_provided      = !params['enabled'].nil?
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

          # Enforce domain restriction based on entitlement.
          # Only when from_address was explicitly provided or this is a new config —
          # PATCH semantics: omitted fields preserve existing values unmodified.
          if @from_address_provided || @existing_config.nil?
            @from_address = enforce_from_domain(@from_address, @custom_domain, @organization)
          end
        end

        def process
          OT.ld "[PatchSenderConfig] Patching sender config for domain #{@domain_id} by user #{cust.extid}"

          # Track enabled state change for audit
          was_enabled = @existing_config&.enabled?

          if @existing_config
            # Compute changes before updating
            changes = compute_sender_changes(@existing_config, params)
            update_existing_config
            log_sender_audit_event(
              event: :domain_sender_config_updated,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              changes: changes,
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
          # Use actual state after update (which may be unchanged if enabled wasn't provided)
          current_enabled = @mailer_config.enabled?
          log_enabled_state_change(was_enabled, current_enabled)

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

        # Validates required fields with PATCH semantics.
        #
        # For new configs: from_address is required
        # For updates: falls back to existing value when not provided
        def validate_required_fields
          if @from_address.to_s.empty?
            if @existing_config
              @from_address = @existing_config.from_address
            else
              raise_form_error('From address is required', field: :from_address, error_type: :missing)
            end
          end

          # Validate email format when from_address is provided
          if @from_address_provided && !valid_email?(@from_address)
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

        # Updates an existing sender config with PATCH semantics.
        #
        # PATCH Semantics:
        # - Only explicitly provided fields are updated
        # - Omitted fields preserve their existing values
        #
        # from_address behavior:
        # - Resets verification state when address changes
        # - Other fields updated directly without affecting verification state
        #
        # Uses transaction with commit_fields to prevent race condition where
        # config could be deleted between existence check and update.
        #
        # Custom mail sender model: sender identity only, no provider/api_key.
        #
        def update_existing_config
          @mailer_config = @existing_config

          # PATCH semantics: only update fields that are explicitly provided
          @mailer_config.from_name = @from_name if @from_name_provided
          @mailer_config.reply_to  = @reply_to if @reply_to_provided
          @mailer_config.enabled   = @enabled.to_s if @enabled_provided

          # Handle from_address change: resets verification state
          if @from_address_provided && !@from_address.to_s.empty? && @from_address != @existing_config.from_address
            @mailer_config.from_address        = @from_address
            @mailer_config.verified_at         = nil
            @mailer_config.verification_status = VERIFICATION_STATUS_PENDING
          end

          # Update timestamp for partial update
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
