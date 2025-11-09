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

require_relative '../../v2/logic/base'

module OrganizationAPI
  module Logic
    class Base < V2::Logic::Base
      # Organization API-specific serialization helper
      #
      # Converts Familia model to JSON hash with native types.
      # Unlike v2's safe_dump which converts all primitives to strings,
      # this preserves JSON types from Familia v2's native storage.
      #
      # @param model [Familia::Horreum] Model instance to serialize
      # @return [Hash] JSON-serializable hash with native types
      def json_dump(model)
        return nil if model.nil?

        # Familia v2 models store fields as JSON types already
        # We just need to convert the model to a hash without string coercion
        model.to_h
      end

      # Override safe_dump to use JSON types in Organization API
      #
      # This allows Organization logic classes to inherit from v2 but get JSON serialization
      # without modifying v2 behavior.
      alias safe_dump json_dump

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
      # Provides consistent serialization across all organization endpoints:
      # - Uses `id` (objid) instead of `orgid`
      # - Timestamps as `created_at`/`updated_at`
      # - Includes `is_default`, `owner_id`, `member_count`
      # - Omits `contact_email` when empty
      # - Includes `current_user_role`
      #
      # @param organization [Onetime::Organization] Organization to serialize
      # @param current_user [Onetime::Customer] Current user for role calculation
      # @return [Hash] Serialized organization data
      def serialize_organization(organization, current_user = cust)
        record = {
          id: organization.extid,  # Use extid (external ID) for URLs, not objid (internal ID)
          display_name: organization.display_name,
          description: organization.description || '',
          is_default: organization.is_default || false,
          created_at: organization.created,
          updated_at: organization.updated,
          owner_id: organization.owner_id,
          member_count: organization.member_count,
          current_user_role: determine_user_role(organization, current_user),
        }

        # Only include contact_email if present and valid
        if organization.contact_email && !organization.contact_email.empty?
          record[:contact_email] = organization.contact_email
        end

        record
      end

      # Determine user's role in organization
      #
      # @param organization [Onetime::Organization]
      # @param user [Onetime::Customer]
      # @return [String] Role: 'owner', 'admin', or 'member'
      def determine_user_role(organization, user)
        return 'owner' if organization.owner?(user)
        # For now, non-owners are 'member'
        # Future: Add admin role support
        'member'
      end

      # Check if user has a system-level role
      #
      # System roles (not organization-specific):
      # - colonel: Site administrators with full access
      # - admin: Future system admin role
      #
      # @param role [String] Role name to check ('colonel', 'admin')
      # @return [Boolean] true if user has the role
      def cust_has_system_role?(role)
        return false if cust.nil? || cust.anonymous?

        case role.to_s
        when 'colonel'
          cust.role == 'colonel'
        when 'admin'
          ['colonel', 'admin'].include?(cust.role)
        else
          false
        end
      end

      # Verify current user owns the organization
      #
      # Allows system admins (colonels) to bypass ownership check.
      # This enables site administrators to manage any organization.
      #
      # @param organization [Onetime::Organization]
      # @raise [FormError] If user is not owner and not admin
      def verify_organization_owner(organization)
        # System admins can manage any organization
        return if cust_has_system_role?('colonel')

        unless organization.owner?(cust)
          raise_form_error('Only organization owner can perform this action', field: :extid, error_type: :forbidden)
        end
      end

      # Verify current user is an organization member
      #
      # Allows system admins (colonels) to bypass membership check.
      # This enables site administrators to view any organization.
      #
      # @param organization [Onetime::Organization]
      # @raise [FormError] If user is not a member and not admin
      def verify_organization_member(organization)
        # System admins can view any organization
        return if cust_has_system_role?('colonel')

        unless organization.member?(cust)
          raise_form_error('You must be an organization member to perform this action', field: :extid, error_type: :forbidden)
        end
      end

      # Load organization and verify it exists
      def load_organization(extid)
        organization = Onetime::Organization.find_by_extid(extid)
        raise_not_found("Organization not found: #{extid}") if organization.nil?
        organization
      end
    end
  end
end
