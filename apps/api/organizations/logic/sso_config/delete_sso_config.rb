# apps/api/organizations/logic/sso_config/delete_sso_config.rb
#
# frozen_string_literal: true

require 'onetime/models/org_sso_config'
require_relative 'audit_logger'

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
      include AuditLogger

      attr_reader :organization, :deleted_provider_type

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

        # Verify config exists and capture provider_type for audit
        existing_config = Onetime::OrgSsoConfig.find_by_org_id(@organization.objid)
        unless existing_config
          raise_not_found("SSO configuration not found for organization: #{@extid}")
        end

        @deleted_provider_type = existing_config.provider_type
      end

      def process
        OT.ld "[DeleteSsoConfig] Deleting SSO config for organization #{@extid} by user #{cust.extid}"

        # Delete the config atomically
        deleted = Onetime::OrgSsoConfig.delete_for_org!(@organization.objid)

        if deleted
          log_sso_audit_event(
            event: :sso_config_deleted,
            org: @organization,
            actor: cust,
            provider_type: @deleted_provider_type,
          )
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
