# lib/onetime/application/authorization_policies.rb
#
# frozen_string_literal: true

# Authorization policy module for Logic classes
#
# Provides declarative authorization patterns across all APIs:
# - System role checks (colonel = superuser)
# - Organization role checks (owner, admin, member)
# - Multi-condition authorization with automatic superuser bypass
#
# Located alongside auth_strategies.rb to group authentication and
# authorization concerns together under the application namespace.
#
# Usage:
#   class MyLogic < BaseLogic
#     include Onetime::Application::AuthorizationPolicies
#
#     def raise_concerns
#       verify_authenticated!
#       # Colonel (superuser) automatically bypasses all checks
#       verify_one_of_roles!(org_owner: @organization, org_member: @organization)
#     end
#   end

module Onetime
  module Application
    module AuthorizationPolicies
      # Check if the current user is anonymous (nil or anonymous flag set)
      #
      # This is the canonical way to check for anonymous users across the
      # codebase. It consolidates the pattern `cust.nil? || cust.anonymous?`
      # into a single method.
      #
      # @return [Boolean] true if user is nil or has anonymous? flag set
      def anonymous_user?
        cust.nil? || cust.anonymous?
      end

      # Check if user has a system-level role
      #
      # System roles (not resource-specific):
      # - colonel: Site administrators with full access
      # - admin: Future system admin role
      #
      # Defense in depth: System roles require email verification.
      # This prevents privilege escalation attacks where an attacker
      # registers an admin email before the legitimate owner verifies.
      #
      # @param role [String, Symbol] Role name to check
      # @return [Boolean] true if user has the role AND is verified
      def has_system_role?(role)
        return false if anonymous_user?

        # Defense in depth: elevated roles require verified email
        return false unless cust.verified?

        case role.to_s
        when 'colonel'
          cust.role == 'colonel'
        when 'admin'
          %w[colonel admin].include?(cust.role)
        when 'staff'
          %w[colonel admin staff].include?(cust.role)
        else
          false
        end
      end

      # Verify user is authenticated (not anonymous)
      #
      # Pre-sets the English fallback message so legacy specs/clients that
      # match on FormError#message keep working; edge handlers still see the
      # error_key and localize per request locale.
      #
      # @raise [FormError] If user is anonymous
      def verify_authenticated!
        return unless anonymous_user?

        raise_form_error(
          'Authentication required',
          error_key: 'api.errors.authentication_required',
          field: :user_id,
          error_type: :authentication_required,
        )
      end

      # Verify user has at least one of the specified roles/permissions
      #
      # Supports multi-condition authorization with early return (OR logic):
      # - System roles (colonel = superuser, admin = system admin)
      # - Custom conditions (for resource-level checks)
      #
      # @param colonel [Boolean] Require colonel (superuser) role
      # @param admin [Boolean] Require admin role (includes colonel)
      # @param custom_check [Proc, nil] Custom authorization check
      # @param error_message [String, nil] Override default error message (legacy)
      # @param error_key [String, nil] i18n key for the Forbidden message
      # @param args [Hash] Interpolation args for the i18n key
      # @return [Boolean] true if any condition passes
      # @raise [Forbidden] If no conditions pass
      #
      # @example Colonel-only operation
      #   verify_one_of_roles!(colonel: true)
      #
      # @example Resource-level check with custom condition and i18n key
      #   verify_one_of_roles!(
      #     colonel: true,
      #     custom_check: -> { @organization.owner?(cust) },
      #     error_key: 'api.organizations.errors.organization_owner_required',
      #   )
      def verify_one_of_roles!(colonel: false, admin: false, custom_check: nil,
                               error_message: nil, error_key: nil, args: {})
        # Check colonel (superuser)
        return true if colonel && has_system_role?('colonel')

        # Check admin (includes colonel via has_system_role?)
        return true if admin && has_system_role?('admin')

        # Check custom condition
        return true if custom_check&.call

        # All checks failed
        message = error_message || build_authorization_error_message(
          colonel: colonel,
          admin: admin,
          has_custom: !custom_check.nil?,
        )

        raise Onetime::Forbidden.new(message, error_key: error_key, args: args)
      end

      # Verify user has ALL of the specified roles/permissions
      #
      # Supports multi-condition authorization with AND logic.
      # Must pass ALL checks (colonel AND admin AND custom).
      #
      # @param colonel [Boolean] Require colonel (superuser) role
      # @param admin [Boolean] Require admin role
      # @param custom_check [Proc, nil] Custom authorization check (must return true)
      # @param error_message [String, nil] Override default error message (legacy)
      # @param error_key [String, nil] i18n key for the Forbidden message
      # @param args [Hash] Interpolation args for the i18n key
      # @raise [Onetime::Forbidden] If any condition fails
      #
      # @example Must be colonel AND pass custom check
      #   verify_all_roles!(
      #     colonel: true,
      #     custom_check: -> { @organization.owner?(cust) },
      #     error_key: 'api.organizations.errors.colonel_owner_required',
      #   )
      def verify_all_roles!(colonel: false, admin: false, custom_check: nil,
                            error_message: nil, error_key: nil, args: {})
        # Check colonel if required
        if colonel && !has_system_role?('colonel')
          message = error_message || 'Requires colonel role'
          raise Onetime::Forbidden.new(message, error_key: error_key, args: args)
        end

        # Check admin if required
        if admin && !has_system_role?('admin')
          message = error_message || 'Requires admin role'
          raise Onetime::Forbidden.new(message, error_key: error_key, args: args)
        end

        # Check custom condition if specified
        if custom_check && !custom_check.call
          message = error_message || 'Insufficient permissions'
          raise Onetime::Forbidden.new(message, error_key: error_key, args: args)
        end

        true
      end

      # Verify current user owns the organization
      #
      # Colonels (site admins) have automatic superuser bypass.
      # Otherwise, user must be organization owner.
      #
      # @param organization [Onetime::Organization]
      # @param error_key [String] I18n key for the rejection message
      # @raise [Onetime::Forbidden] If user is not owner and not colonel
      def verify_organization_owner(organization, error_key: 'api.organizations.errors.organization_owner_required')
        verify_one_of_roles!(
          colonel: true,
          custom_check: -> { organization.owner?(cust) },
          error_message: 'Only organization owner can perform this action',
          error_key: error_key,
        )
      end

      # Verify current user is an organization member
      #
      # Colonels (site admins) have automatic superuser bypass.
      # Otherwise, user must be organization member.
      #
      # @param organization [Onetime::Organization]
      # @param error_key [String] I18n key for the rejection message
      # @raise [Onetime::Forbidden] If user is not a member and not colonel
      def verify_organization_member(organization, error_key: 'api.organizations.errors.organization_member_required')
        verify_one_of_roles!(
          colonel: true,
          custom_check: -> { organization.member?(cust) },
          error_message: 'You must be an organization member to perform this action',
          error_key: error_key,
        )
      end

      # Verify current user has admin privileges in the organization
      #
      # Owner is implicitly admin. Colonels (site admins) bypass.
      #
      # @param organization [Onetime::Organization]
      # @param error_key [String] I18n key for the rejection message; defaults to the generic
      #   admin-required message. Per-action callers should pass their own key
      #   (e.g. 'api.domains.errors.add_admin_required').
      # @raise [Onetime::Forbidden] If user is not owner/admin
      def verify_organization_admin(organization, error_key: 'api.organizations.errors.organization_admin_required')
        verify_one_of_roles!(
          colonel: true,
          custom_check: -> { organization.owner?(cust) || organization_admin?(organization) },
          error_message: 'Only organization owners and admins can perform this action',
          error_key: error_key,
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

      # Load organization by external ID, raising not-found on miss
      #
      # @param extid [String] Organization external ID
      # @raise [Onetime::RecordNotFound] If organization not found
      # @return [Onetime::Organization]
      def load_organization(extid)
        organization = Onetime::Organization.find_by_extid(extid)
        if organization.nil?
          raise_not_found(
            "Organization not found: #{extid}",
            error_key: 'api.organizations.errors.organization_not_found',
            args: { extid: extid },
          )
        end
        organization
      end

      private

      # Build user-friendly error message from authorization requirements
      def build_authorization_error_message(colonel:, admin:, has_custom:)
        conditions = []

        conditions << 'site admin' if colonel
        conditions << 'system admin' if admin
        conditions << 'sufficient permissions' if has_custom

        if conditions.empty?
          'Insufficient permissions'
        elsif conditions.size == 1
          "Requires #{conditions.first}"
        else
          last = conditions.pop
          "Requires #{conditions.join(', ')} or #{last}"
        end
      end
    end
  end
end
