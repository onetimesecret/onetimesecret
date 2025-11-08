# apps/api/organizations/logic/organizations/list_organizations.rb
#
# frozen_string_literal: true

module OrganizationAPI::Logic
  module Organizations
    class ListOrganizations < OrganizationAPI::Logic::Base
      attr_reader :organizations

      def process_params
        # No parameters needed - lists all organizations for current user
      end

      def raise_concerns
        # Require authenticated user
        raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?
      end

      def process
        OT.ld "[ListOrganizations] Listing organizations for user #{cust.custid}"

        # Use Familia v2 reverse collection method
        @organizations = cust.organization_instances

        # Fallback if reverse lookup not working - use org: prefix (not organization:)
        if @organizations.empty? && cust.participations.size > 0
          org_keys = cust.participations.to_a.select { |k| k.start_with?('org:') && k.end_with?(':members') }
          org_ids = org_keys.map { |k| k.split(':')[1] }.uniq
          @organizations = Onetime::Organization.load_multi(org_ids).compact if org_ids.any?
        end

        OT.ld "[ListOrganizations] Found #{@organizations.size} organizations"

        success_data
      end

      def success_data
        {
          user_id: cust.objid,
          records: organizations.map do |org|
            {
              orgid: org.orgid,
              display_name: org.display_name,
              description: org.description || '',
              owner_id: org.owner_id,
              is_owner: org.owner?(cust),
              member_count: org.member_count,
              created: org.created,
              updated: org.updated,
            }
          end,
          count: organizations.length,
        }
      end
    end
  end
end
