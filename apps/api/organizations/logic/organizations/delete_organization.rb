# apps/api/organizations/logic/organizations/delete_organization.rb
#
# frozen_string_literal: true

module OrganizationAPI::Logic
  module Organizations
    # Delete Organization
    #
    # @api Permanently deletes an organization, removing all member
    #   associations first. Only the organization owner can perform
    #   this action. Returns a confirmation of deletion.
    class DeleteOrganization < OrganizationAPI::Logic::Base
      SCHEMAS = { response: 'organizationDelete' }.freeze

      attr_reader :organization

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

        # Verify user is owner
        verify_organization_owner(@organization)
      end

      def process
        OT.ld "[DeleteOrganization] Deleting organization #{@extid} for user #{cust.extid}"

        # Get organization info before deletion
        objid        = @organization.objid
        display_name = @organization.display_name

        # Remove all members first
        members = @organization.list_members
        members.each do |member|
          @organization.remove_members_instance(member)
        end

        # Remove from global instances set (Familia v2 uses 'remove' not 'rem')
        Onetime::Organization.instances.remove(objid)

        # Delete the organization
        @organization.destroy!

        OT.info "[DeleteOrganization] Deleted organization #{objid} (#{display_name})"

        success_data
      end

      def success_data
        {
          user_id: cust.extid,
          deleted: true,
          extid: @extid,
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
