# apps/api/organizations/logic/invitations/list_invitations.rb
#
# frozen_string_literal: true

module OrganizationAPI::Logic
  module Invitations
    # List pending invitations for an organization
    #
    # GET /api/org/:extid/invitations
    #
    # Members need manage_members and organization-wide scope.
    #
    class ListInvitations < OrganizationAPI::Logic::Base
      attr_reader :organization, :invitations

      def process_params
        @extid = sanitize_identifier(params['extid'])
      end

      def raise_concerns
        verify_authenticated!

        @organization = load_organization(@extid)
        require_capability_in!(@organization, 'manage_members')
        return unless membership_in(@organization)&.domain_scoped?

        raise Onetime::Forbidden.new(
          'Domain-scoped members cannot perform this action',
          error_key: 'api.organizations.errors.domain_scoped_forbidden',
        )
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
    end
  end
end
