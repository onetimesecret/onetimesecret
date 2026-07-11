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
        if @extid.to_s.empty?
          raise_form_error(
            error_key: 'api.organizations.errors.extid_required',
            field: :extid,
            error_type: :missing,
          )
        end

        # Load organization
        @organization = load_organization(@extid)

        # Verify user has manage_org entitlement in this organization
        require_entitlement_in!(@organization, 'manage_org')
      end

      def process
        OT.ld "[DeleteOrganization] Deleting organization #{@extid} for user #{cust.extid}"

        # Get organization info before deletion
        objid        = @organization.objid
        display_name = @organization.display_name

        # Remove all members first
        members = @organization.list_members

        # Capture member contact info BEFORE the membership records are removed,
        # so we can notify everyone once the organization is gone.
        recipients = members.map do |member|
          { email: member.email, locale: (member.respond_to?(:locale) ? member.locale : nil) }
        end.reject { |r| r[:email].to_s.empty? }

        members.each do |member|
          @organization.remove_members_instance(member)
        end

        # NOTE: pending invitations are cleaned up by Organization#destroy! (see #2878)

        # Remove from global instances set (Familia v2 uses 'remove' not 'rem')
        Onetime::Organization.instances.remove(objid)

        # Delete the organization
        @organization.destroy!

        OT.info "[DeleteOrganization] Deleted organization #{objid} (#{display_name})"

        notify_members_deleted(recipients, display_name)

        success_data
      end

      # Best-effort notification to former members that the organization was
      # deleted. Each send is isolated so one failure doesn't skip the rest,
      # and no failure may affect the (already-completed) deletion.
      def notify_members_deleted(recipients, display_name)
        recipients.each do |recipient|
          Onetime::Jobs::Publisher.enqueue_email(
            :organization_deleted,
            {
              email_address: recipient[:email],
              organization_name: display_name,
              deleted_by: cust.email,
              deleted_at: Time.now.utc.iso8601,
              locale: recipient[:locale] || OT.default_locale,
            },
            fallback: :async_thread,
          )
        rescue StandardError => ex
          OT.le "[DeleteOrganization] Failed to send organization_deleted email: #{ex.message}"
        end
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
