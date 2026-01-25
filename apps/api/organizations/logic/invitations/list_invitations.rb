# apps/api/organizations/logic/invitations/list_invitations.rb
#
# frozen_string_literal: true

module OrganizationAPI::Logic
  module Invitations
    # List pending invitations for an organization
    #
    # GET /api/org/:extid/invitations
    #
    # Requires: Owner or Admin role
    #
    class ListInvitations < OrganizationAPI::Logic::Base
      attr_reader :organization, :invitations

      def process_params
        @extid = sanitize_identifier(params['extid'])
      end

      def raise_concerns
        raise_form_error('Authentication required', error_type: :unauthorized) if cust.anonymous?

        @organization = load_organization(@extid)
        verify_organization_admin(@organization)
      end

      def process
        OT.ld "[ListInvitations] Listing invitations for org #{@organization.extid}"

        @invitations = Onetime::OrganizationMembership.pending_for_org(@organization)

        OT.info "[ListInvitations] Found #{@invitations.size} pending invitations"

        success_data
      end

      def success_data
        {
          user_id: cust.extid,
          organization_id: @organization.extid,
          records: @invitations.map(&:safe_dump),
          count: @invitations.size,
        }
      end

      protected

      def verify_organization_admin(organization)
        verify_one_of_roles!(
          colonel: true,
          custom_check: -> { organization.owner?(cust) || organization_admin?(organization) },
          error_message: 'Only organization owners and admins can view invitations',
        )
      end

      def organization_admin?(organization)
        membership = Onetime::OrganizationMembership.find_by_org_customer(
          organization.objid, cust.objid
        )
        membership&.admin?
      end
    end
  end
end
