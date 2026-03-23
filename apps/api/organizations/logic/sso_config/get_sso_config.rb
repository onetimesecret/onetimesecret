# apps/api/organizations/logic/sso_config/get_sso_config.rb
#
# frozen_string_literal: true

require 'onetime/models/org_sso_config'

module OrganizationAPI::Logic
  module SsoConfig
    # Get SSO Configuration
    #
    # @api Retrieves the SSO configuration for an organization.
    #   Returns the config with masked client_secret (only last 4 chars visible).
    #   Requires the requesting user to be an organization owner.
    #
    # Response includes:
    # - provider_type: oidc, entra_id, google, github
    # - client_id: Full client ID (not sensitive)
    # - client_secret: Masked (e.g., "••••••••abcd")
    # - tenant_id: For Entra ID
    # - issuer: For OIDC
    # - display_name: Human-readable name
    # - allowed_domains: Array of allowed email domains
    # - enabled: Whether SSO is active
    #
    class GetSsoConfig < OrganizationAPI::Logic::Base
      attr_reader :organization, :sso_config

      def process_params
        @extid = sanitize_identifier(params['extid'])
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

        # Load SSO config
        @sso_config = Onetime::OrgSsoConfig.find_by_org_id(@organization.objid)
        raise_not_found("SSO configuration not found for organization: #{@extid}") if @sso_config.nil?
      end

      def process
        OT.ld "[GetSsoConfig] Getting SSO config for organization #{@extid} by user #{cust.extid}"

        success_data
      end

      def success_data
        {
          user_id: cust.extid,
          record: serialize_sso_config(@sso_config),
        }
      end

      private

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
      #
      # @param concealed [Familia::ConcealedString, nil] Encrypted field
      # @return [String, nil] Plaintext value or nil
      def reveal_or_nil(concealed)
        return nil if concealed.nil?

        concealed.reveal { it }
      rescue StandardError
        nil
      end

      # Mask a secret value, showing only last 4 characters
      #
      # @param concealed [Familia::ConcealedString, nil] Encrypted secret
      # @return [String] Masked secret (e.g., "••••••••abcd")
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
