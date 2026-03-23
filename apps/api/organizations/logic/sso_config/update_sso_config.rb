# apps/api/organizations/logic/sso_config/update_sso_config.rb
#
# frozen_string_literal: true

require 'onetime/models/org_sso_config'

module OrganizationAPI::Logic
  module SsoConfig
    # Update (or Create) SSO Configuration
    #
    # @api Creates or updates the SSO configuration for an organization.
    #   Uses PUT semantics: creates if not exists, updates if exists.
    #   Requires the requesting user to be an organization owner.
    #
    # Request body:
    # - provider_type: Required. One of: oidc, entra_id, google, github
    # - client_id: Required. OAuth client ID
    # - client_secret: Required for create, optional for update (preserves existing if omitted)
    # - tenant_id: Required for entra_id provider
    # - issuer: Required for oidc provider
    # - display_name: Optional. Human-readable name
    # - allowed_domains: Optional. Array of allowed email domains
    # - enabled: Optional. Boolean to enable/disable SSO (default: false)
    #
    # Response includes the updated config with masked client_secret.
    #
    class UpdateSsoConfig < OrganizationAPI::Logic::Base
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

        # Validate client credentials
        validate_client_credentials

        # Validate provider-specific fields
        validate_provider_specific_fields
      end

      def process
        OT.ld "[UpdateSsoConfig] Updating SSO config for organization #{@extid} by user #{cust.extid}"

        if @existing_config
          update_existing_config
        else
          create_new_config
        end

        # Log audit trail
        action = @existing_config ? 'updated' : 'created'
        OT.info "[UpdateSsoConfig] SSO config #{action} for org #{@extid}",
          {
            org_extid: @extid,
            provider_type: @provider_type,
            enabled: @enabled,
            user_extid: cust.extid,
          }

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

        # client_secret is required for new configs, optional for updates (preserves existing)
        if @existing_config.nil? && @client_secret.to_s.empty?
          raise_form_error('Client secret is required', field: :client_secret, error_type: :missing)
        end
      end

      def validate_provider_specific_fields
        case @provider_type
        when 'oidc'
          if @issuer.to_s.empty?
            raise_form_error('Issuer URL is required for OIDC provider', field: :issuer, error_type: :missing)
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

      def update_existing_config
        @sso_config = @existing_config

        # Update fields
        @sso_config.provider_type = @provider_type
        @sso_config.display_name  = @display_name unless @display_name.to_s.empty?
        @sso_config.client_id     = @client_id
        @sso_config.tenant_id     = @tenant_id unless @tenant_id.to_s.empty?
        @sso_config.issuer        = @issuer unless @issuer.to_s.empty?
        @sso_config.enabled       = @enabled.to_s

        # Only update client_secret if provided (preserves existing otherwise)
        @sso_config.client_secret = @client_secret unless @client_secret.to_s.empty?

        # Update allowed_domains
        @sso_config.allowed_domains = @allowed_domains

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

      # Serialize SSO config for API response with masked secrets
      #
      # @param config [Onetime::OrgSsoConfig] SSO config to serialize
      # @return [Hash] Serialized config with masked client_secret
      def serialize_sso_config(config)
        {
          org_id: config.org_id,
          provider_type: config.provider_type,
          display_name: config.display_name,
          enabled: config.enabled?,
          client_id: reveal_or_nil(config.client_id),
          client_secret: mask_secret(config.client_secret),
          tenant_id: config.tenant_id,
          issuer: config.issuer,
          allowed_domains: config.allowed_domains,
        }
      end

      # Reveal encrypted field value or return nil
      def reveal_or_nil(concealed)
        return nil if concealed.nil?

        concealed.reveal { it }
      rescue StandardError
        nil
      end

      # Mask a secret value, showing only last 4 characters
      def mask_secret(concealed)
        return nil if concealed.nil?

        plaintext = concealed.reveal { it }
        return nil if plaintext.nil? || plaintext.empty?

        if plaintext.length <= 4
          '••••••••'
        else
          '••••••••' + plaintext[-4..]
        end
      rescue StandardError
        nil
      end
    end
  end
end
