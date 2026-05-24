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
require 'onetime/application/authorization_policies'

module OrganizationAPI
  module Logic
    class Base < Onetime::Logic::Base
      include Onetime::Application::AuthorizationPolicies

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

      # Verify current user owns the organization
      #
      # Colonels (site admins) have automatic superuser bypass.
      # Otherwise, user must be organization owner.
      #
      # @param organization [Onetime::Organization]
      # @param error_key [String] I18n key for the rejection message
      # @raise [FormError] If user is not owner and not admin
      def verify_organization_owner(organization, error_key: 'api.organizations.errors.owner_required')
        verify_one_of_roles!(
          colonel: true,
          custom_check: -> { organization.owner?(cust) },
          error_message: I18n.t(error_key, locale: locale, default: 'Only organization owner can perform this action'),
        )
      end

      # Verify current user is an organization member
      #
      # Colonels (site admins) have automatic superuser bypass.
      # Otherwise, user must be organization member.
      #
      # @param organization [Onetime::Organization]
      # @param error_key [String] I18n key for the rejection message
      # @raise [FormError] If user is not a member and not admin
      def verify_organization_member(organization, error_key: 'api.organizations.errors.member_required')
        verify_one_of_roles!(
          colonel: true,
          custom_check: -> { organization.member?(cust) },
          error_message: I18n.t(error_key, locale: locale, default: 'You must be an organization member to perform this action'),
        )
      end

      # Verify current user has admin privileges in the organization
      #
      # Owner is implicitly admin. Colonels (site admins) bypass.
      #
      # @param organization [Onetime::Organization]
      # @param error_key [String] I18n key for the rejection message; defaults to the generic
      #   admin-required message. Per-action callers should pass their own key
      #   (e.g. 'api.organizations.invitations.errors.create_admin_required').
      # @raise [FormError] If user is not owner/admin
      def verify_organization_admin(organization, error_key: 'api.organizations.errors.admin_required')
        verify_one_of_roles!(
          colonel: true,
          custom_check: -> { organization.owner?(cust) || organization_admin?(organization) },
          error_message: I18n.t(error_key, locale: locale, default: 'Only organization owners and admins can perform this action'),
        )
      end

      # Check if current user holds the admin role in the organization
      #
      # Does not include owner — callers that want owner-or-admin should use
      # verify_organization_admin (which composes owner? || organization_admin?).
      #
      # @param organization [Onetime::Organization]
      # @return [Boolean]
      def organization_admin?(organization)
        return false if cust.nil?

        membership = Onetime::OrganizationMembership.find_by_org_customer(
          organization.objid, cust.objid
        )
        membership&.admin?
      end

      # Load organization and verify it exists
      def load_organization(extid)
        organization = Onetime::Organization.find_by_extid(extid)
        if organization.nil?
          raise_not_found(
            I18n.t('api.organizations.errors.not_found', locale: locale, extid: extid, default: "Organization not found: #{extid}"),
          )
        end
        organization
      end
    end
  end
end
