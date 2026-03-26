# apps/api/organizations/logic/organizations/get_organization.rb
#
# frozen_string_literal: true

module OrganizationAPI::Logic
  module Organizations
    # Get Organization
    #
    # @api Retrieves an organization by its external ID. Returns the
    #   organization details along with a list of all members and their
    #   roles. Requires the requesting user to be a member.
    class GetOrganization < OrganizationAPI::Logic::Base
      SCHEMAS = { response: 'organization' }.freeze

      attr_reader :organization, :members

      def process_params
        @extid = sanitize_identifier(params['extid'])
      end

      def raise_concerns
        # Require authenticated user
        verify_authenticated!

        # Validate extid parameter
        raise_form_error('Organization ID required', field: :extid, error_type: :missing) if @extid.to_s.empty?

        # Load organization
        @organization = load_organization(@extid)

        # Verify user is a member
        verify_organization_member(@organization)
      end

      def process
        OT.ld "[GetOrganization] Getting organization #{@extid} for user #{cust.extid}"

        # Get organization members
        @members = @organization.list_members

        success_data
      end

      def success_data
        record = serialize_organization(organization)

        # Add members list for detailed view
        record[:members] = members.map do |member|
          {
            id: member.objid,
            email: member.email,
            role: determine_user_role(organization, member),
          }
        end

        {
          user_id: cust.extid,
          record: record,
        }
      end
    end
  end
end
