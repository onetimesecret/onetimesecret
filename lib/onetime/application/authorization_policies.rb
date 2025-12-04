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
      # Check if user has a system-level role
      #
      # System roles (not resource-specific):
      # - colonel: Site administrators with full access
      # - admin: Future system admin role
      #
      # @param role [String, Symbol] Role name to check
      # @return [Boolean] true if user has the role
      def has_system_role?(role)
        return false if cust.nil? || cust.anonymous?

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
      # @raise [FormError] If user is anonymous
      def verify_authenticated!
        if cust.nil? || cust.anonymous?
          raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized)
        end
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
      # @param error_message [String, nil] Override default error message
      # @return [Boolean] true if any condition passes
      # @raise [FormError] If no conditions pass
      #
      # @example Colonel-only operation
      #   verify_one_of_roles!(colonel: true)
      #
      # @example System admin operation (colonel or admin)
      #   verify_one_of_roles!(admin: true)
      #
      # @example Resource-level check with custom condition
      #   verify_one_of_roles!(
      #     custom_check: -> { @organization.owner?(cust) || @organization.member?(cust) }
      #   )
      #
      # @example Multiple conditions (OR logic)
      #   verify_one_of_roles!(
      #     admin: true,
      #     custom_check: -> { @resource.public? }
      #   )
      def verify_one_of_roles!(colonel: false, admin: false, custom_check: nil, error_message: nil)
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

        raise Onetime::Forbidden, message
      end

      # Verify user has ALL of the specified roles/permissions
      #
      # Supports multi-condition authorization with AND logic.
      # Must pass ALL checks (colonel AND admin AND custom).
      #
      # @param colonel [Boolean] Require colonel (superuser) role
      # @param admin [Boolean] Require admin role
      # @param custom_check [Proc, nil] Custom authorization check (must return true)
      # @param error_message [String, nil] Override default error message
      # @raise [Onetime::Forbidden] If any condition fails
      #
      # @example Must be colonel AND pass custom check
      #   verify_all_roles!(
      #     colonel: true,
      #     custom_check: -> { @organization.owner?(cust) }
      #   )
      def verify_all_roles!(colonel: false, admin: false, custom_check: nil, error_message: nil)
        # Check colonel if required
        if colonel && !has_system_role?('colonel')
          message = error_message || 'Requires colonel role'
          raise Onetime::Forbidden, message
        end

        # Check admin if required
        if admin && !has_system_role?('admin')
          message = error_message || 'Requires admin role'
          raise Onetime::Forbidden, message
        end

        # Check custom condition if specified
        if custom_check && !custom_check.call
          message = error_message || 'Insufficient permissions'
          raise Onetime::Forbidden, message
        end

        true
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
