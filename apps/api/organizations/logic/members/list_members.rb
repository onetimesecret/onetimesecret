# apps/api/organizations/logic/members/list_members.rb
#
# frozen_string_literal: true

module OrganizationAPI::Logic
  module Members
    # List all members of an organization with their roles
    #
    # GET /api/organizations/:extid/members
    #
    # Requires: Organization membership (any role)
    #
    # Response includes:
    #   - Member details (id, email, display_name)
    #   - Role for each member
    #   - Joined date
    #
    class ListMembers < OrganizationAPI::Logic::Base
      attr_reader :organization, :memberships

      def process_params
        @extid = sanitize_identifier(params['extid'])
      end

      def raise_concerns
        raise_form_error('Authentication required', error_type: :unauthorized) if cust.anonymous?

        @organization = load_organization(@extid)
        verify_organization_member(@organization)
      end

      def process
        OT.ld "[ListMembers] Listing members for org #{@organization.extid}"

        # Fetch all active memberships with role data
        @memberships = Onetime::OrganizationMembership.active_for_org(@organization)

        OT.info "[ListMembers] Found #{@memberships.size} active members"

        success_data
      end

      def success_data
        {
          user_id: cust.objid,
          organization_id: @organization.extid,
          records: @memberships.map { |m| serialize_membership(m) },
          count: @memberships.size,
        }
      end

      protected

      # Serialize membership with member details for API response
      #
      # @param membership [Onetime::OrganizationMembership]
      # @return [Hash] Serialized member data
      def serialize_membership(membership)
        member = membership.customer
        return nil unless member

        {
          extid: member.extid,
          email: member.email,
          role: membership.role,
          joined_at: membership.joined_at,
          is_owner: membership.owner?,
          is_current_user: member.objid == cust.objid,
        }
      end
    end
  end
end
