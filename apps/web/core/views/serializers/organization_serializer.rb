# apps/web/core/views/serializers/organization_serializer.rb
#
# frozen_string_literal: true

require 'onetime/logger_methods'

module Core
  module Views
    # Serializes organization data for the frontend bootstrap payload
    #
    # Provides the current user's organization context to the frontend,
    # enabling domain context initialization without race conditions.
    # The organization is loaded via OrganizationLoader in the auth strategy.
    module OrganizationSerializer
      extend Onetime::LoggerMethods

      # Serializes organization data from view variables
      #
      # @param view_vars [Hash] The view variables containing organization info
      # @return [Hash] Serialized organization data
      def self.serialize(view_vars)
        output = output_template

        is_authenticated = view_vars['authenticated']
        org              = view_vars['organization']

        return output unless is_authenticated && org

        # Serialize minimal organization data needed for frontend initialization
        # Full organization details can be fetched via API when needed
        output['organization'] = serialize_organization(org, view_vars['cust'])

        output
      end

      class << self
        # Provides the base template for organization serializer output
        #
        # @return [Hash] Template with organization output fields
        def output_template
          {
            'organization' => nil,
          }
        end

        private

        # Serialize organization to frontend format
        #
        # Includes only the fields needed for:
        # - Domain context initialization (id, extid)
        # - Basic display (display_name, is_default)
        # - Plan identity and role (planid, current_user_role)
        # - Feature gating and quota display (entitlements, limits)
        #
        # entitlements and limit_for resolve through the request-scoped
        # preview context (ADR-020), so this bootstrap payload reflects
        # colonel preview mode without any per-consumer wiring.
        #
        # @param org [Onetime::Organization] Organization to serialize
        # @param cust [Onetime::Customer] Current user for role calculation
        # @return [Hash] Serialized organization data
        def serialize_organization(org, cust)
          {
            'objid' => org.objid,
            'extid' => org.extid,
            'display_name' => org.display_name,
            'is_default' => org.is_default || false,
            'planid' => org.planid,
            'current_user_role' => determine_user_role(org, cust),
            'entitlements' => org.entitlements,
            'limits' => serialize_limits(org),
          }
        end

        # Limits for the bootstrap payload, matching the safe_dump shape
        # (organization/features/safe_dump_fields.rb): Float::INFINITY
        # normalizes to -1 for JSON serialization (unlimited).
        #
        # @param org [Onetime::Organization] Organization
        # @return [Hash] Normalized limits
        def serialize_limits(org)
          normalize = ->(val) { val == Float::INFINITY ? -1 : val.to_i }
          {
            'teams' => normalize.call(org.limit_for(:teams)),
            'total_members_per_org' => normalize.call(org.limit_for(:total_members_per_org)),
            'custom_domains' => normalize.call(org.limit_for(:custom_domains)),
          }
        end

        # Determine the current user's role in the organization
        #
        # @param org [Onetime::Organization] Organization
        # @param cust [Onetime::Customer] Current user
        # @return [String, nil] Role name or nil
        def determine_user_role(org, cust)
          return nil unless cust && !cust.anonymous?

          if org.owner?(cust)
            'owner'
          elsif org.member?(cust)
            membership = Onetime::OrganizationMembership.find_by_org_customer(
              org.objid, cust.objid
            )
            membership&.role || 'member'
          end
        end
      end

      SerializerRegistry.register(self, ['AuthenticationSerializer'])
    end
  end
end
