# lib/onetime/logic/authorization_helpers.rb
#
# Shared authorization helpers for Logic classes
#
# Provides consistent authorization patterns across all APIs:
# - System role checks (colonel, admin)
# - Organization role checks (owner, admin, member)
# - Multi-condition authorization
#
# Usage:
#   class MyLogic < BaseLogic
#     include Onetime::Logic::AuthorizationHelpers
#
#     def raise_concerns
#       verify_authenticated!
#       verify_one_of_roles!('colonel', org_owner: @organization)
#     end
#   end

module Onetime
  module Logic
    module AuthorizationHelpers
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
          ['colonel', 'admin'].include?(cust.role)
        when 'staff'
          ['colonel', 'admin', 'staff'].include?(cust.role)
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
      # - System roles (colonel, admin)
      # - Organization ownership
      # - Organization membership
      # - Custom conditions
      #
      # @param system_roles [Array<String>] System role names (colonel, admin)
      # @param org_owner [Organization, nil] Organization to check ownership
      # @param org_member [Organization, nil] Organization to check membership
      # @param custom_check [Proc, nil] Custom authorization check
      # @return [Boolean] true if any condition passes
      # @raise [FormError] If no conditions pass
      #
      # @example Admin or owner
      #   verify_one_of_roles!('colonel', org_owner: @organization)
      #
      # @example Member or custom condition
      #   verify_one_of_roles!(
      #     org_member: @organization,
      #     custom_check: -> { @organization.public? }
      #   )
      def verify_one_of_roles!(*system_roles, org_owner: nil, org_member: nil, org_admin: nil, custom_check: nil, error_message: nil)
        # Check system roles
        system_roles.each do |role|
          return true if has_system_role?(role)
        end

        # Check organization owner
        if org_owner && org_owner.owner?(cust)
          return true
        end

        # Check organization admin (future)
        if org_admin && org_admin.admin?(cust)
          return true
        end

        # Check organization member
        if org_member && org_member.member?(cust)
          return true
        end

        # Check custom condition
        if custom_check && custom_check.call
          return true
        end

        # All checks failed
        message = error_message || build_authorization_error_message(
          system_roles: system_roles,
          org_owner: org_owner,
          org_member: org_member
        )

        raise_form_error(message, field: :user_id, error_type: :forbidden)
      end

      # Verify user has ALL of the specified roles/permissions
      #
      # Supports multi-condition authorization with AND logic:
      # - Must have system role AND resource permission
      #
      # @param system_role [String] Required system role
      # @param org_role [Symbol] Required organization role (:owner, :admin, :member)
      # @param organization [Organization] Organization to check role in
      # @raise [FormError] If any condition fails
      #
      # @example Must be colonel AND org owner
      #   verify_all_roles!('colonel', org_role: :owner, organization: @org)
      def verify_all_roles!(system_role = nil, org_role: nil, organization: nil, error_message: nil)
        # Check system role if specified
        if system_role && !has_system_role?(system_role)
          message = error_message || "Requires #{system_role} role"
          raise_form_error(message, field: :user_id, error_type: :forbidden)
        end

        # Check organization role if specified
        if org_role && organization
          case org_role
          when :owner
            unless organization.owner?(cust)
              message = error_message || "Requires organization owner role"
              raise_form_error(message, field: :user_id, error_type: :forbidden)
            end
          when :admin
            unless organization.admin?(cust)
              message = error_message || "Requires organization admin role"
              raise_form_error(message, field: :user_id, error_type: :forbidden)
            end
          when :member
            unless organization.member?(cust)
              message = error_message || "Requires organization membership"
              raise_form_error(message, field: :user_id, error_type: :forbidden)
            end
          end
        end

        true
      end

      private

      # Build user-friendly error message from authorization requirements
      def build_authorization_error_message(system_roles:, org_owner:, org_member:)
        conditions = []

        conditions << "site admin" if system_roles.include?('colonel')
        conditions << "system admin" if system_roles.include?('admin')
        conditions << "organization owner" if org_owner
        conditions << "organization member" if org_member

        if conditions.empty?
          "Insufficient permissions"
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
