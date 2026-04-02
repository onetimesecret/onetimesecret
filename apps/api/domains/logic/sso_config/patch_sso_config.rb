# apps/api/domains/logic/sso_config/patch_sso_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/sso_config'
require_relative 'base'
require_relative 'serializers'
require_relative 'audit_logger'
require_relative 'ssrf_protection'

module DomainsAPI
  module Logic
    module SsoConfig
      # PATCH Domain SSO Configuration (partial update)
      #
      # @api Partially updates the SSO configuration for a custom domain.
      #   Uses PATCH semantics: only provided fields are updated, empty values
      #   preserve existing data.
      #   Requires the requesting user to be an organization owner with manage_sso.
      #
      # Request body:
      # - provider_type: Required for create, optional for update (uses existing if empty)
      # - client_id: Required for create, optional for update (uses existing if empty)
      # - client_secret: Required for create, optional for update (preserves existing if empty)
      # - tenant_id: Required for entra_id provider on create (preserves existing if empty)
      # - issuer: Required for oidc provider on create (preserves existing if empty)
      # - display_name: Optional. Human-readable name (preserves existing if empty)
      # - allowed_domains: Optional. Array of allowed email domains (preserves existing if omitted)
      # - enabled: Optional. Boolean to enable/disable SSO (default: false, preserves existing if omitted)
      #
      # Response includes the updated config with masked client_secret_masked.
      #
      class PatchSsoConfig < Base
        include Serializers
        include AuditLogger
        include SsrfProtection

        VALID_PROVIDER_TYPES = Onetime::CustomDomain::SsoConfig::PROVIDER_TYPES.freeze

        attr_reader :sso_config, :existing_config

        def process_params
          @domain_id                = sanitize_identifier(params['extid'])
          @provider_type            = sanitize_plain_text(params['provider_type'])
          @display_name             = sanitize_plain_text(params['display_name'])
          @client_id                = params['client_id'].to_s.strip
          @client_secret            = params['client_secret'].to_s.strip
          @tenant_id                = sanitize_plain_text(params['tenant_id'])
          @issuer                   = sanitize_url(params['issuer'])
          # Track whether allowed_domains was explicitly provided (for PATCH semantics)
          @allowed_domains_provided = params.key?('allowed_domains')
          @allowed_domains          = parse_allowed_domains(params['allowed_domains'])

          # Track whether enabled was explicitly provided (for PATCH semantics)
          @enabled_provided = !params['enabled'].nil?
          @enabled          = parse_boolean(params['enabled'])
        end

        def raise_concerns
          # Require authenticated user
          raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

          # Validate domain_id parameter
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          # Load domain and organization, verify ownership and entitlement
          authorize_domain_sso!(@domain_id)

          # Check if config already exists
          @existing_config = Onetime::CustomDomain::SsoConfig.find_by_domain_id(@custom_domain.identifier)

          # Validate provider_type
          validate_provider_type

          # Validate client credentials
          validate_client_credentials

          # Validate provider-specific fields
          validate_provider_specific_fields
        end

        def process
          OT.ld "[PatchSsoConfig] Patching SSO config for domain #{@domain_id} by user #{cust.extid}"

          # Track enabled state change for audit
          was_enabled = @existing_config&.enabled?

          if @existing_config
            # Compute changes before updating
            changes = compute_sso_changes(@existing_config, params)
            update_existing_config
            log_sso_audit_event(
              event: :domain_sso_config_updated,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              provider_type: @provider_type,
              changes: changes,
            )
          else
            create_new_config
            log_sso_audit_event(
              event: :domain_sso_config_created,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              provider_type: @provider_type,
            )
          end

          # Log enabled state change if it occurred
          # Use actual state after update (which may be unchanged if enabled wasn't provided)
          current_enabled = @sso_config.enabled?
          log_enabled_state_change(was_enabled, current_enabled)

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            record: serialize_sso_config(@sso_config),
          }
        end

        def form_fields
          {
            domain_id: @domain_id,
            provider_type: @provider_type,
            display_name: @display_name,
            tenant_id: @tenant_id,
            issuer: @issuer,
            allowed_domains: @allowed_domains,
            enabled: @enabled,
          }
        end

        private

        # Validates and resolves provider_type with PATCH semantics.
        #
        # For new configs: provider_type is required
        # For updates: falls back to existing config value when not provided
        def validate_provider_type
          if @provider_type.to_s.empty?
            if @existing_config
              @provider_type = @existing_config.provider_type
            else
              raise_form_error('Provider type is required', field: :provider_type, error_type: :missing)
            end
          end

          return if VALID_PROVIDER_TYPES.include?(@provider_type)

          raise_form_error(
            "Invalid provider type. Must be one of: #{VALID_PROVIDER_TYPES.join(', ')}",
            field: :provider_type,
            error_type: :invalid,
          )
        end

        # Validates and resolves client credentials with PATCH semantics.
        #
        # For new configs: client_id and client_secret are required
        # For updates: falls back to existing values when not provided
        def validate_client_credentials
          if @client_id.to_s.empty?
            if @existing_config
              @client_id = @existing_config.client_id
            else
              raise_form_error('Client ID is required', field: :client_id, error_type: :missing)
            end
          end

          # client_secret is required for new configs, optional for updates (preserves existing)
          if @existing_config.nil? && @client_secret.to_s.empty?
            raise_form_error('Client secret is required', field: :client_secret, error_type: :missing)
          end
        end

        def validate_provider_specific_fields
          case @provider_type
          when 'oidc'
            # For PATCH: require issuer if creating new config or if existing config has no issuer
            missing_issuer = @issuer.to_s.empty? &&
                             (@existing_config.nil? || @existing_config.issuer.to_s.empty?)
            if missing_issuer
              raise_form_error('Issuer URL is required for OIDC provider', field: :issuer, error_type: :missing)
            end

            # SSRF prevention: validate issuer URL host is not internal/private
            # Only validate if a new issuer is being provided (not empty)
            if !@issuer.to_s.empty? && !valid_issuer_host?(@issuer)
              raise_form_error(
                'Issuer URL must be a valid HTTPS URL pointing to a public host',
                field: :issuer,
                error_type: :invalid,
              )
            end
          when 'entra_id'
            # For PATCH: require tenant_id if creating new config or if existing config has no tenant_id
            missing_tenant = @tenant_id.to_s.empty? &&
                             (@existing_config.nil? || @existing_config.tenant_id.to_s.empty?)
            if missing_tenant
              raise_form_error('Tenant ID is required for Entra ID provider', field: :tenant_id, error_type: :missing)
            end
          end
        end

        def create_new_config
          @sso_config = Onetime::CustomDomain::SsoConfig.create!(
            domain_id: @custom_domain.identifier,
            provider_type: @provider_type,
            display_name: @display_name,
            client_id: @client_id,
            client_secret: @client_secret,
            tenant_id: @tenant_id,
            issuer: @issuer,
            allowed_domains: @allowed_domains,
            enabled: @enabled,
          )
        end

        # Updates an existing SSO config with PATCH semantics.
        #
        # PATCH Semantics:
        # - Optional fields are preserved when omitted, allowing partial updates.
        # - Provider-specific fields are preserved on provider switch.
        #
        # allowed_domains behavior:
        # - When omitted: preserves existing domains (true PATCH semantics)
        # - When provided as []: explicitly clears all existing domains
        # - When provided with values: replaces with new values
        #
        # Uses transaction with commit_fields to prevent race condition where
        # config could be deleted between existence check and update.
        #
        def update_existing_config
          @sso_config = @existing_config

          # PATCH semantics: only update fields that are provided (non-empty)
          @sso_config.provider_type = @provider_type
          @sso_config.display_name  = @display_name unless @display_name.to_s.empty?
          @sso_config.client_id     = @client_id
          @sso_config.tenant_id     = @tenant_id unless @tenant_id.to_s.empty?
          @sso_config.issuer        = @issuer unless @issuer.to_s.empty?
          @sso_config.enabled       = @enabled.to_s if @enabled_provided

          # Only update client_secret if provided (preserves existing otherwise)
          @sso_config.client_secret = @client_secret unless @client_secret.to_s.empty?

          # Only update allowed_domains if explicitly provided in the request.
          @sso_config.allowed_domains = @allowed_domains if @allowed_domains_provided

          # Update timestamp for partial update
          @sso_config.updated = Familia.now.to_i

          # commit_fields runs its own transaction internally for atomicity
          @sso_config.commit_fields
        end

        # Log enabled/disabled state change if it occurred.
        #
        # @param was_enabled [Boolean, nil] Previous enabled state (nil if new config)
        # @param is_enabled [Boolean] New enabled state
        def log_enabled_state_change(was_enabled, is_enabled)
          # Skip if no change (both false, or both true)
          return if was_enabled == is_enabled

          # Log when SSO is enabled (new config or was disabled)
          if is_enabled && (was_enabled.nil? || was_enabled == false)
            log_sso_audit_event(
              event: :domain_sso_config_enabled,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              provider_type: @provider_type,
            )
          elsif was_enabled == true && !is_enabled
            log_sso_audit_event(
              event: :domain_sso_config_disabled,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              provider_type: @provider_type,
            )
          end
        end
      end
    end
  end
end
