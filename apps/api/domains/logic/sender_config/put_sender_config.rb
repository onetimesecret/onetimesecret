# apps/api/domains/logic/sender_config/put_sender_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/mailer_config'
require_relative 'base'
require_relative 'serializers'
require_relative 'audit_logger'

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
      # - provider: Required. One of: smtp, ses, sendgrid, lettermint
      # - from_address: Required. Sender email address
      # - from_name: Optional. Display name for sender (defaults to empty)
      # - reply_to: Optional. Reply-to address (defaults to empty)
      # - api_key: Required. Provider API key or credentials
      # - enabled: Optional. Boolean to enable/disable (default: false)
      #
      # Response includes the updated config with masked api_key_masked.
      #
      class PutSenderConfig < Base
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

          # Validate credentials (always required for PUT)
          validate_credentials
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
              provider: @provider,
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
          log_enabled_state_change(was_enabled, @enabled)

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

        def validate_provider
          raise_form_error('Provider is required', field: :provider, error_type: :missing) if @provider.to_s.empty?

          return if VALID_PROVIDER_TYPES.include?(@provider)

          raise_form_error(
            "Invalid provider. Must be one of: #{VALID_PROVIDER_TYPES.join(', ')}",
            field: :provider,
            error_type: :invalid,
          )
        end

        def validate_required_fields
          raise_form_error('From address is required', field: :from_address, error_type: :missing) if @from_address.to_s.empty?
        end

        def validate_credentials
          # PUT semantics: api_key is always required (full replacement)
          raise_form_error('API key is required', field: :api_key, error_type: :missing) if @api_key.to_s.empty?
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

        # Replaces existing sender config with PUT semantics.
        #
        # Uses transaction with commit_fields to prevent race condition where
        # config could be deleted between existence check and update.
        #
        def replace_existing_config
          @mailer_config = @existing_config

          # PUT semantics: full replacement - set ALL fields from request
          @mailer_config.provider     = @provider
          @mailer_config.from_name    = @from_name        # Empty string clears the field
          @mailer_config.from_address = @from_address
          @mailer_config.reply_to     = @reply_to         # Empty string clears the field
          @mailer_config.api_key      = @api_key          # Always required for PUT
          @mailer_config.enabled      = @enabled.to_s

          # Update timestamp for replacement
          @mailer_config.updated = Familia.now.to_i

          # Use transaction to ensure atomic update (prevents race with concurrent delete)
          @mailer_config.transaction do |_conn|
            @mailer_config.commit_fields
          end
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
