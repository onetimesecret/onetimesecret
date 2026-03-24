# apps/api/organizations/logic/sso_config/put_sso_config.rb
#
# frozen_string_literal: true

require 'onetime/models/org_sso_config'
require_relative 'serializers'
require_relative 'audit_logger'
require_relative 'ssrf_protection'

module OrganizationAPI::Logic
  module SsoConfig
    # PUT SSO Configuration (full replacement)
    #
    # @api Creates or replaces the SSO configuration for an organization.
    #   Uses PUT semantics: the request body IS the new state.
    #   Empty string or null clears optional fields.
    #   Requires the requesting user to be an organization owner.
    #
    # Request body:
    # - provider_type: Required. One of: oidc, entra_id, google, github
    # - client_id: Required. OAuth client ID
    # - client_secret: Required. OAuth client secret
    # - tenant_id: Required for entra_id provider, empty/null for others
    # - issuer: Required for oidc provider, empty/null for others
    # - display_name: Optional. Human-readable name (defaults to empty)
    # - allowed_domains: Optional. Array of allowed email domains (defaults to empty)
    # - enabled: Optional. Boolean to enable/disable SSO (default: false)
    #
    # Response includes the updated config with masked client_secret_masked.
    #
    class PutSsoConfig < OrganizationAPI::Logic::Base
      include Serializers
      include AuditLogger
      include SsrfProtection

      VALID_PROVIDER_TYPES = Onetime::OrgSsoConfig::PROVIDER_TYPES.freeze

      attr_reader :organization, :sso_config, :existing_config

      def process_params
        @extid           = sanitize_identifier(params['extid'])
        @provider_type   = sanitize_plain_text(params['provider_type'])
        @display_name    = sanitize_plain_text(params['display_name'])
        @client_id       = params['client_id'].to_s.strip
        @client_secret   = params['client_secret'].to_s.strip
        @tenant_id       = sanitize_plain_text(params['tenant_id'])
        @issuer          = sanitize_url(params['issuer'])
        @allowed_domains = parse_allowed_domains(params['allowed_domains'])
        @enabled         = parse_boolean(params['enabled'])
      end

      def raise_concerns
        # Require authenticated user
        raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

        # Validate extid parameter
        raise_form_error('Organization ID required', field: :extid, error_type: :missing) if @extid.to_s.empty?

        # Load organization
        @organization = load_organization(@extid)

        # Verify user is owner (SSO config is sensitive)
        verify_organization_owner(@organization)

        # Check if config already exists
        @existing_config = Onetime::OrgSsoConfig.find_by_org_id(@organization.objid)

        # Validate provider_type
        validate_provider_type

        # Validate client credentials (always required for PUT)
        validate_client_credentials

        # Validate provider-specific fields
        validate_provider_specific_fields
      end

      def process
        OT.ld "[PutSsoConfig] Replacing SSO config for organization #{@extid} by user #{cust.extid}"

        # Track enabled state change for audit
        was_enabled = @existing_config&.enabled?

        if @existing_config
          replace_existing_config
          log_sso_audit_event(
            event: :sso_config_replaced,
            org: @organization,
            actor: cust,
            provider_type: @provider_type,
          )
        else
          create_new_config
          log_sso_audit_event(
            event: :sso_config_created,
            org: @organization,
            actor: cust,
            provider_type: @provider_type,
          )
        end

        # Log enabled state change if it occurred
        log_enabled_state_change(was_enabled, @enabled)

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
          extid: @extid,
          provider_type: @provider_type,
          display_name: @display_name,
          tenant_id: @tenant_id,
          issuer: @issuer,
          allowed_domains: @allowed_domains,
          enabled: @enabled,
        }
      end

      private

      def validate_provider_type
        raise_form_error('Provider type is required', field: :provider_type, error_type: :missing) if @provider_type.to_s.empty?

        return if VALID_PROVIDER_TYPES.include?(@provider_type)

        raise_form_error(
          "Invalid provider type. Must be one of: #{VALID_PROVIDER_TYPES.join(', ')}",
          field: :provider_type,
          error_type: :invalid,
        )
      end

      def validate_client_credentials
        raise_form_error('Client ID is required', field: :client_id, error_type: :missing) if @client_id.to_s.empty?

        # PUT semantics: client_secret is always required (full replacement)
        raise_form_error('Client secret is required', field: :client_secret, error_type: :missing) if @client_secret.to_s.empty?
      end

      def validate_provider_specific_fields
        case @provider_type
        when 'oidc'
          if @issuer.to_s.empty?
            raise_form_error('Issuer URL is required for OIDC provider', field: :issuer, error_type: :missing)
          end

          # SSRF prevention: validate issuer URL host is not internal/private
          unless valid_issuer_host?(@issuer)
            raise_form_error(
              'Issuer URL must be a valid HTTPS URL pointing to a public host',
              field: :issuer,
              error_type: :invalid,
            )
          end
        when 'entra_id'
          if @tenant_id.to_s.empty?
            raise_form_error('Tenant ID is required for Entra ID provider', field: :tenant_id, error_type: :missing)
          end
        end
      end

      def create_new_config
        @sso_config = Onetime::OrgSsoConfig.create!(
          org_id: @organization.objid,
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

      def replace_existing_config
        @sso_config = @existing_config

        # PUT semantics: full replacement - set ALL fields from request
        @sso_config.provider_type   = @provider_type
        @sso_config.display_name    = @display_name    # Empty string clears the field
        @sso_config.client_id       = @client_id
        @sso_config.client_secret   = @client_secret   # Always required for PUT
        @sso_config.tenant_id       = @tenant_id       # Empty string clears the field
        @sso_config.issuer          = @issuer          # Empty string clears the field
        @sso_config.allowed_domains = @allowed_domains # Empty array clears the field
        @sso_config.enabled         = @enabled.to_s

        # Update timestamp for replacement
        @sso_config.updated = Familia.now.to_i

        @sso_config.save
      end

      def parse_allowed_domains(value)
        return [] if value.nil?
        return value if value.is_a?(Array)

        # Handle comma-separated string
        if value.is_a?(String)
          value.split(',').map { it.strip.downcase }.reject(&:empty?)
        else
          []
        end
      end

      def parse_boolean(value)
        case value
        when true, 'true', '1', 1
          true
        else
          false
        end
      end

      def sanitize_url(value)
        return '' if value.nil?

        url = value.to_s.strip
        # Basic URL validation - must start with https:// for security
        return '' unless url.start_with?('https://')

        url
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
            event: :sso_config_enabled,
            org: @organization,
            actor: cust,
            provider_type: @provider_type,
          )
        elsif was_enabled == true && !is_enabled
          log_sso_audit_event(
            event: :sso_config_disabled,
            org: @organization,
            actor: cust,
            provider_type: @provider_type,
          )
        end
      end
    end
  end
end
