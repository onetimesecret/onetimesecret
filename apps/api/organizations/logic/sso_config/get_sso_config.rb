# apps/api/organizations/logic/sso_config/get_sso_config.rb
#
# frozen_string_literal: true

require 'onetime/models/org_sso_config'
require_relative 'serializers'

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
    # - client_secret_masked: Masked (e.g., "••••••••abcd")
    # - tenant_id: For Entra ID
    # - issuer: For OIDC
    # - display_name: Human-readable name
    # - allowed_domains: Array of allowed email domains
    # - enabled: Whether SSO is active
    # - created_at: Unix timestamp
    # - updated_at: Unix timestamp
    #
    class GetSsoConfig < OrganizationAPI::Logic::Base
      include Serializers

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
    end
  end
end
