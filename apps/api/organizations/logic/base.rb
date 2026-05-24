# apps/api/organizations/logic/base.rb
#
# frozen_string_literal: true

# Organization API Logic Base Class
#
# Extends V2 logic with modern API patterns for Organization API.
#
# Key differences from v2:
# 1. Native JSON types (numbers, booleans, null) instead of string-serialized values
# 2. Pure REST semantics - no "success" field (use HTTP status codes)
# 3. Modern naming - "user_id" instead of "custid"
#
# Organization API uses same modern conventions as Account API and Team API for consistency.

require 'onetime/logic/base'

module OrganizationAPI
  module Logic
    class Base < Onetime::Logic::Base
      # Transform v2 response data to Organization API format
      #
      # Organization API changes (same as Account API and Team API):
      # - Remove "success" field (use HTTP status codes)
      # - Rename "custid" to "user_id" (modern naming)
      #
      # @return [Hash] Organization API-formatted response data
      def success_data
        # Get the v2 response data
        v2_data = super

        # Transform for Organization API
        org_data = v2_data.dup

        # Remove success field (Organization API uses HTTP status codes)
        org_data.delete(:success)
        org_data.delete('success')

        # Rename custid to user_id (modern naming)
        if org_data.key?(:custid)
          org_data[:user_id] = org_data.delete(:custid)
        elsif org_data.key?('custid')
          org_data['user_id'] = org_data.delete('custid')
        end

        org_data
      end

      protected

      # Serialize organization to API response format
      #
      # Uses Organization#safe_dump as the base and adds:
      # - `id` alias for `objid` (frontend convention)
      # - `created`/`updated` aliases for `created`/`updated`
      # - `current_user_role` (context-dependent, requires current user)
      #
      # @param organization [Onetime::Organization] Organization to serialize
      # @param current_user [Onetime::Customer] Current user for role calculation
      # @return [Hash] Serialized organization data
      def serialize_organization(organization, current_user = cust)
        # Start with safe_dump which includes all standard fields
        record = organization.safe_dump

        # Add frontend-expected aliases
        record[:id]      = record[:objid]

        # Convert owner_id (custid) to owner_extid (Customer#extid) for opaque identifier pattern
        # This prevents internal ID exposure in API responses
        if record[:owner_id]
          owner                = organization.owner
          record[:owner_extid] = owner&.extid
        end
        record.delete(:owner_id) # Remove internal ID from response

        # Add context-dependent field
        record[:current_user_role] = determine_user_role(organization, current_user)

        record
      end

      # Determine user's role in organization
      #
      # @param organization [Onetime::Organization]
      # @param user [Onetime::Customer]
      # @return [String] Role: 'owner', 'admin', or 'member'
      def determine_user_role(organization, user)
        return 'owner' if organization.owner?(user)

        membership = Onetime::OrganizationMembership.find_by_org_customer(
          organization.objid, user.objid
        )
        membership&.role || 'member'
      end

      # Organization-level authorization helpers (verify_organization_owner,
      # verify_organization_admin, verify_organization_member, organization_admin?,
      # load_organization) are inherited via Onetime::Application::AuthorizationPolicies,
      # which is included by Onetime::Logic::Base.
    end
  end
end
