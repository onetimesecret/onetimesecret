# apps/api/organizations/logic/sso_config/delete_sso_config.rb
#
# frozen_string_literal: true

require 'onetime/models/org_sso_config'

module OrganizationAPI::Logic
  module SsoConfig
    # Delete SSO Configuration
    #
    # @api Removes the SSO configuration for an organization.
    #   Requires the requesting user to be an organization owner.
    #   Returns 204 No Content on success.
    #
    # After deletion, organization members will no longer be able to
    # authenticate via SSO. They must use standard email/password
    # authentication or another configured method.
    #
    class DeleteSsoConfig < OrganizationAPI::Logic::Base
      attr_reader :organization

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

        # Verify config exists
        unless Onetime::OrgSsoConfig.exists_for_org?(@organization.objid)
          raise_not_found("SSO configuration not found for organization: #{@extid}")
        end
      end

      def process
        OT.ld "[DeleteSsoConfig] Deleting SSO config for organization #{@extid} by user #{cust.extid}"

        # Delete the config atomically
        deleted = Onetime::OrgSsoConfig.delete_for_org!(@organization.objid)

        if deleted
          OT.info "[DeleteSsoConfig] SSO config deleted for org #{@extid}",
            {
              org_extid: @extid,
              user_extid: cust.extid,
            }
        end

        success_data
      end

      def success_data
        {
          success: true,
          message: "SSO configuration deleted for organization #{@extid}",
        }
      end

      def form_fields
        {
          extid: @extid,
        }
      end
    end
  end
end
