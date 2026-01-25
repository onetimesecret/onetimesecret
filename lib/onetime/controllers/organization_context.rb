# lib/onetime/controllers/organization_context.rb
#
# frozen_string_literal: true

#
# Organization Context for Controllers
#
# This module provides convenient access to organization context
# for all controllers across the application.
#
# The organization is accessed via Rack::Request helper methods
# that extract it from StrategyResult metadata.
#
# Usage in controllers:
#   module MyController
#     include Onetime::Controllers::OrganizationContext
#
#     def my_handler
#       # Helper methods automatically available
#       organization.list_domains
#     end
#   end

module Onetime
  module Controllers
    module OrganizationContext
      # Get current organization from request
      #
      # @return [Onetime::Organization, nil] Current organization or nil
      def organization
        req.organization
      end

      # Get current organization ID
      #
      # @return [String, nil] Organization objid or nil
      def organization_id
        req.organization_id
      end

      # Alias for convenience
      def org
        organization
      end

      # Require organization to be present
      #
      # @raise [Onetime::Problem] if organization is nil
      # @return [Onetime::Organization] the organization
      def require_organization!
        raise Onetime::Problem, 'No organization context' unless organization

        organization
      end
    end
  end
end
