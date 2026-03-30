# apps/api/domains/logic/sender_config/patch_sender_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/mailer_config'
require_relative 'base'
require_relative 'serializers'
require_relative 'audit_logger'

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
      # - provider: Required for create, optional for update (uses existing if empty)
      # - from_address: Required for create, optional for update (preserves existing if empty)
      # - from_name: Optional. Display name for sender (preserves existing if empty)
      # - reply_to: Optional. Reply-to address (preserves existing if empty)
      # - api_key: Required for create, optional for update (preserves existing if empty)
      # - enabled: Optional. Boolean to enable/disable (preserves existing if omitted)
      #
      # Response includes the updated config with masked api_key_masked.
      #
      class PatchSenderConfig < Base
        include Serializers
        include AuditLogger

        VALID_PROVIDER_TYPES = Onetime::CustomDomain::MailerConfig::PROVIDER_TYPES.freeze

        attr_reader :mailer_config, :existing_config

        def process_params
          @domain_id    = sanitize_identifier(params['extid'])
          @provider     = sanitize_plain_text(params['provider'])
          @from_name    = sanitize_plain_text(params['from_name'])
          @from_address = params['from_address'].to_s.strip
          @reply_to     = params['reply_to'].to_s.strip
          @api_key      = params['api_key'].to_s.strip
          @enabled      = parse_boolean(params['enabled'])

          # Track which fields were explicitly provided (for PATCH semantics)
          @provider_provided     = !params['provider'].nil?
          @from_name_provided    = !params['from_name'].nil?
          @from_address_provided = !params['from_address'].nil?
          @reply_to_provided     = !params['reply_to'].nil?
          @api_key_provided      = !params['api_key'].nil?
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

          # Validate provider
          validate_provider

          # Validate required fields
          validate_required_fields

          # Validate credentials
          validate_credentials
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
              provider: @provider,
              changes: changes,
            )
          else
            create_new_config
            log_sender_audit_event(
              event: :domain_sender_config_created,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              provider: @provider,
            )
          end

          # Log enabled state change if it occurred
          # Use actual state after update (which may be unchanged if enabled wasn't provided)
          current_enabled = @mailer_config.enabled?
          log_enabled_state_change(was_enabled, current_enabled)

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
            provider: @provider,
            from_name: @from_name,
            from_address: @from_address,
            reply_to: @reply_to,
            enabled: @enabled,
          }
        end

        private

        # Validates and resolves provider with PATCH semantics.
        #
        # For new configs: provider is required
        # For updates: falls back to existing config value when not provided
        def validate_provider
          if @provider.to_s.empty?
            if @existing_config
              @provider = @existing_config.provider
            else
              raise_form_error('Provider is required', field: :provider, error_type: :missing)
            end
          end

          return if VALID_PROVIDER_TYPES.include?(@provider)

          raise_form_error(
            "Invalid provider. Must be one of: #{VALID_PROVIDER_TYPES.join(', ')}",
            field: :provider,
            error_type: :invalid,
          )
        end

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

        # Validates credentials with PATCH semantics.
        #
        # For new configs: api_key is required
        # For updates: preserves existing if not provided
        def validate_credentials
          # api_key is required for new configs, optional for updates (preserves existing)
          if @existing_config.nil? && @api_key.to_s.empty?
            raise_form_error('API key is required', field: :api_key, error_type: :missing)
          end
        end

        def create_new_config
          @mailer_config = Onetime::CustomDomain::MailerConfig.create!(
            domain_id: @custom_domain.identifier,
            provider: @provider,
            from_name: @from_name,
            from_address: @from_address,
            reply_to: @reply_to,
            api_key: @api_key,
            enabled: @enabled,
          )
        end

        # Updates an existing sender config with PATCH semantics.
        #
        # PATCH Semantics:
        # - Only explicitly provided fields are updated
        # - Omitted fields preserve their existing values
        #
        # from_address behavior:
        # - Uses model's update_from_address if the address changed (resets verification)
        # - Other fields updated directly without affecting verification state
        #
        # Uses transaction with commit_fields to prevent race condition where
        # config could be deleted between existence check and update.
        #
        def update_existing_config
          @mailer_config = @existing_config

          # PATCH semantics: only update fields that are explicitly provided
          @mailer_config.provider  = @provider if @provider_provided && !@provider.to_s.empty?
          @mailer_config.from_name = @from_name if @from_name_provided
          @mailer_config.reply_to  = @reply_to if @reply_to_provided
          @mailer_config.enabled   = @enabled.to_s if @enabled_provided

          # Handle from_address change: resets verification state
          if @from_address_provided && !@from_address.to_s.empty? && @from_address != @existing_config.from_address
            @mailer_config.from_address        = @from_address
            @mailer_config.verified_at         = nil
            @mailer_config.verification_status = VERIFICATION_STATUS_PENDING
          end

          # Only update api_key if explicitly provided and non-empty
          @mailer_config.api_key = @api_key if @api_key_provided && !@api_key.to_s.empty?

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
              provider: @provider,
            )
          elsif was_enabled == true && !is_enabled
            log_sender_audit_event(
              event: :domain_sender_config_disabled,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              provider: @provider,
            )
          end
        end
      end
    end
  end
end
