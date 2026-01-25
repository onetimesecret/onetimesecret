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
        # - Entitlement checks (planid, entitlements, limits)
        #
        # @param org [Onetime::Organization] Organization to serialize
        # @param cust [Onetime::Customer] Current user for role calculation
        # @return [Hash] Serialized organization data
        def serialize_organization(org, cust)
          {
            'id' => org.objid,
            'extid' => org.extid,
            'display_name' => org.display_name,
            'is_default' => org.is_default || false,
            'planid' => org.planid,
            'current_user_role' => determine_user_role(org, cust),
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
            # Check through model for specific role
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
