# apps/api/organizations/logic/organizations/update_sharing_policy.rb
#
# frozen_string_literal: true

module OrganizationAPI::Logic
  module Organizations
    # @api Replaces the sharing controls for the organization named in the URL.
    #   Requires an active owner with organization-wide management access.
    class UpdateSharingPolicy < OrganizationAPI::Logic::Base
      SCHEMAS = { response: 'organization' }.freeze

      def process_params
        @extid = sanitize_identifier(params['extid'])
      end

      def raise_concerns
        verify_authenticated!
        @organization = load_organization(@extid)
        require_org_wide_capability!(@organization, 'manage_org')
        membership    = membership_in(@organization)
        return if membership&.active? && membership.owner?

        raise Onetime::Forbidden.new(
          'Only the organization owner can change sharing controls',
          error_key: 'api.organizations.errors.organization_owner_required',
        )
      end

      def process
        @organization.replace_sharing_policy!(params['sharing_policy'])
        { user_id: cust.extid, record: serialize_organization(@organization) }
      rescue Onetime::Organization::SharingPolicy::Invalid => ex
        raise_form_error(
          error_key: 'api.organizations.errors.invalid_sharing_policy',
          field: ex.field,
          error_type: :invalid,
        )
      end
    end
  end
end
