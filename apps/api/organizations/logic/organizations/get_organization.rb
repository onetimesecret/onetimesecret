# apps/api/organizations/logic/organizations/get_organization.rb

module OrganizationAPI::Logic
  module Organizations
    class GetOrganization < OrganizationAPI::Logic::Base
      attr_reader :organization, :members

      def process_params
        @orgid = params['orgid']
      end

      def raise_concerns
        # Require authenticated user
        raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

        # Validate orgid parameter
        raise_form_error('Organization ID required', field: :orgid, error_type: :missing) if @orgid.to_s.empty?

        # Load organization
        @organization = load_organization(@orgid)

        # Verify user is a member
        verify_organization_member(@organization)
      end

      def process
        OT.ld "[GetOrganization] Getting organization #{@orgid} for user #{cust.custid}"

        # Get organization members
        @members = @organization.list_members

        success_data
      end

      def success_data
        {
          user_id: cust.objid,
          record: {
            orgid: organization.orgid,
            display_name: organization.display_name,
            description: organization.description,
            contact_email: organization.contact_email,
            owner_id: organization.owner_id,
            is_owner: organization.owner?(cust),
            member_count: organization.member_count,
            created: organization.created,
            updated: organization.updated,
            members: members.map do |member|
              {
                custid: member.custid,
                email: member.email,
                role: (organization.owner?(member) ? 'owner' : 'member'),
              }
            end,
          },
        }
      end
    end
  end
end
