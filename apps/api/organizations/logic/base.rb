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

      # Verify current user owns the organization
      def verify_organization_owner(organization)
        unless organization.owner?(cust)
          raise_form_error('Only organization owner can perform this action', field: :orgid, error_type: :forbidden)
        end
      end

      # Verify current user is an organization member
      def verify_organization_member(organization)
        unless organization.member?(cust)
          raise_form_error('You must be an organization member to perform this action', field: :orgid, error_type: :forbidden)
        end
      end

      # Load organization and verify it exists
      def load_organization(orgid)
        organization = Onetime::Organization.load(orgid)
        raise_not_found("Organization not found: #{orgid}") if organization.nil?
        organization
      end
    end
  end
end
