# apps/api/organizations/logic/organizations/delete_organization.rb
#
# frozen_string_literal: true

module OrganizationAPI::Logic
  module Organizations
    class DeleteOrganization < OrganizationAPI::Logic::Base
      attr_reader :organization

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

        # Verify user is owner
        verify_organization_owner(@organization)
      end

      def process
        OT.ld "[DeleteOrganization] Deleting organization #{@orgid} for user #{cust.custid}"

        # Get organization info before deletion
        orgid = @organization.orgid
        display_name = @organization.display_name

        # Remove all members first
        members = @organization.list_members
        members.each do |member|
          @organization.remove_member(member)
        end

        # Remove from global values set (Familia v2 uses 'remove' not 'rem')
        Onetime::Organization.values.remove(orgid)

        # Delete the organization
        @organization.destroy!

        OT.info "[DeleteOrganization] Deleted organization #{orgid} (#{display_name})"

        success_data
      end

      def success_data
        {
          user_id: cust.objid,
          deleted: true,
          orgid: @orgid,
        }
      end

      def form_fields
        {
          orgid: @orgid,
        }
      end
    end
  end
end
