# apps/api/account/logic/account/get_permissions.rb
#
# frozen_string_literal: true

require_relative '../base'

module AccountAPI::Logic
  module Account
    # Get Permissions API
    #
    # Returns the current user's permissions for resources. Two modes:
    #
    # 1. Bulk mode (no params): Returns all orgs the user belongs to, with
    #    membership details and permissions for each org and its domains.
    #
    # 2. Single-resource mode (with params): Returns permissions for one
    #    specific resource, identified by type and id.
    #
    # ## Bulk Request
    #
    # GET /api/account/permissions
    #
    # ## Bulk Response
    #
    # {
    #   organizations: [
    #     {
    #       extid: "org456",
    #       display_name: "Acme Corp",
    #       is_default: false,
    #       membership: {
    #         role: "admin",
    #         status: "active",
    #         provisioning_source: "invited",
    #         invited_at: "2024-01-15T10:00:00Z",
    #         joined_at: "2024-01-16T14:30:00Z",
    #         entitlements: ["api_access", "custom_domains", ...]
    #       },
    #       permissions: {
    #         can_view: true,
    #         can_edit: true,
    #         can_delete: false,
    #         can_manage_settings: false
    #       },
    #       domains: [
    #         {
    #           extid: "dom789",
    #           display_domain: "example.com",
    #           permissions: {
    #             can_view: true,
    #             can_edit: true,
    #             can_delete: false,
    #             can_manage_settings: false
    #           }
    #         }
    #       ]
    #     }
    #   ]
    # }
    #
    # ## Single-Resource Request
    #
    # GET /api/account/permissions?resource_type=domain&resource_id=<extid>
    #
    # ## Single-Resource Parameters
    #
    # - resource_type: 'domain' | 'organization' (required for single mode)
    # - resource_id: extid of the resource (required for single mode)
    #
    # ## Single-Resource Response
    #
    # {
    #   resource_type: "domain",
    #   resource_id: "abc123",
    #   organization: {
    #     extid: "org456",
    #     display_name: "Acme Corp"
    #   },
    #   membership: { ... },
    #   permissions: { ... }
    # }
    #
    # ## Permission Logic
    #
    # Domain resources:
    # - can_view: user has 'custom_domains' entitlement
    # - can_edit: user has 'custom_domains' entitlement
    # - can_delete: user has 'manage_org' entitlement (owner only)
    # - can_manage_settings: user has 'manage_org' entitlement (owner only)
    #
    # Organization resources:
    # - can_view: user is member of the org (any role)
    # - can_edit: user has 'admin' or 'owner' role
    # - can_delete: user is owner and org is not default
    # - can_manage_settings: user has 'manage_org' entitlement
    #
    # ## Error Responses (single-resource mode only)
    #
    # - 400: Invalid resource_type (when provided)
    # - 403: User is not a member of the resource's organization
    # - 404: Resource not found
    #
    class GetPermissions < AccountAPI::Logic::Base
      include Onetime::LoggerMethods

      SUPPORTED_RESOURCE_TYPES = %w[domain organization].freeze

      attr_reader :resource_type, :resource_id, :resource, :organization, :membership, :bulk_mode

      def process_params
        @resource_type = params['resource_type'].to_s.strip
        @resource_id   = params['resource_id'].to_s.strip
        @bulk_mode     = resource_type.empty? && resource_id.empty?
      end

      def raise_concerns
        verify_authenticated!

        return if bulk_mode

        # Single-resource mode validations
        raise_form_error('resource_type is required when resource_id is provided') if resource_type.empty? && !resource_id.empty?
        raise_form_error('resource_id is required when resource_type is provided') if resource_id.empty?

        unless SUPPORTED_RESOURCE_TYPES.include?(resource_type)
          raise_form_error("resource_type must be one of: #{SUPPORTED_RESOURCE_TYPES.join(', ')}")
        end

        load_resource_and_organization!
        verify_organization_membership!

        # Domain-scope enforcement: deny if member cannot access this domain (#3384)
        if resource_type == 'domain' && @membership && !@membership.can_access_domain?(@resource)
          raise_not_found_error('Domain not found')
        end
      end

      def process
        if bulk_mode
          process_bulk
        else
          process_single
        end
      end

      private

      # Bulk mode: return all orgs with their domains and permissions
      def process_bulk
        organizations = load_user_organizations_with_memberships

        {
          organizations: organizations.map { |org, mem| serialize_org_with_domains(org, mem) },
        }
      end

      # Single-resource mode: return permissions for one resource
      def process_single
        {
          resource_type: resource_type,
          resource_id: resource_id,
          organization: serialize_organization_brief,
          membership: serialize_membership,
          permissions: calculate_permissions,
        }
      end

      def load_user_organizations_with_memberships
        # Get all organizations for this user via Familia participation
        organizations = cust.organization_instances.to_a.reject(&:archived?)

        # Pair each org with its membership
        organizations.filter_map do |org|
          membership = Onetime::OrganizationMembership.find_by_org_customer(
            org.objid, cust.objid
          )
          next unless membership&.active?

          [org, membership]
        end
      end

      def serialize_org_with_domains(org, mem)
        # Domain-scope enforcement: filter by membership scope (#3384)
        domains = org.list_domains.select { |d| mem.can_access_domain?(d) }

        {
          extid: org.extid,
          display_name: org.display_name,
          is_default: org.is_default || false,
          membership: serialize_membership_for(mem),
          permissions: organization_permissions_for(org, mem),
          assignable_roles: compute_assignable_roles(org, mem),
          domains: domains.map { |d| serialize_domain_with_permissions(d, mem) },
        }
      end

      def serialize_domain_with_permissions(domain, mem)
        {
          extid: domain.extid,
          display_domain: domain.display_domain,
          permissions: domain_permissions_for(mem),
        }
      end

      def serialize_membership_for(mem)
        {
          role: mem.role,
          status: mem.status,
          provisioning_source: mem.provisioning_source,
          invited_at: mem.invited_at,
          joined_at: mem.joined_at,
          entitlements: mem.entitlements,
        }
      end

      def serialize_membership
        serialize_membership_for(membership)
      end

      def domain_permissions_for(mem)
        {
          can_view: mem.can?('custom_domains'),
          can_edit: mem.can?('custom_domains'),
          can_delete: mem.can?('manage_org'),
          can_manage_settings: mem.can?('manage_org'),
        }
      end

      def organization_permissions_for(org, mem)
        role              = mem.role
        is_owner          = role == 'owner'
        is_admin_or_owner = %w[owner admin].include?(role)

        {
          can_view: true,
          can_edit: is_admin_or_owner,
          can_delete: is_owner && !org.is_default,
          can_manage_settings: mem.can?('manage_org'),
        }
      end

      # Compute which roles this member can assign to others.
      # Base set always includes 'member'. Admin role assignable only if:
      # 1. The plan allows it (limit != 0)
      # 2. The member has owner or admin role
      #
      # Uses org.limit_for which handles the full fallback chain:
      # materialized limits -> plan cache -> config fallback
      def compute_assignable_roles(org, mem)
        base        = ['member']
        admin_limit = org.limit_for('role_admins_per_org')

        # 0 = feature disabled, Float::INFINITY = unlimited, >0 = quota
        return base if admin_limit == 0
        return base unless %w[owner admin].include?(mem.role)

        base + ['admin']
      end

      # Single-resource mode helpers

      def load_resource_and_organization!
        case resource_type
        when 'domain'
          load_domain_resource!
        when 'organization'
          load_organization_resource!
        end
      end

      def load_domain_resource!
        @resource = Onetime::CustomDomain.find_by_extid(resource_id)
        raise_not_found_error('Domain not found') unless @resource

        @organization = @resource.primary_organization
        raise_not_found_error('Domain has no associated organization') unless @organization
      end

      def load_organization_resource!
        @resource = Onetime::Organization.find_by_extid(resource_id)
        raise_not_found_error('Organization not found') unless @resource

        @organization = @resource
      end

      def verify_organization_membership!
        @membership = Onetime::OrganizationMembership.find_by_org_customer(
          organization.objid, cust.objid
        )

        unless @membership&.active?
          raise_forbidden_error('You are not a member of this organization')
        end
      end

      def serialize_organization_brief
        {
          extid: organization.extid,
          display_name: organization.display_name,
        }
      end

      def calculate_permissions
        case resource_type
        when 'domain'
          domain_permissions_for(membership)
        when 'organization'
          organization_permissions_for(organization, membership)
        end
      end

      def raise_not_found_error(message)
        raise OT::RecordNotFound, message
      end

      def raise_forbidden_error(message)
        raise OT::Forbidden, message
      end

      def raise_form_error(message)
        raise OT::FormError, message
      end
    end
  end
end
