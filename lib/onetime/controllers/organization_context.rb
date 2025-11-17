# lib/onetime/controllers/organization_context.rb
#
# frozen_string_literal: true

#
# Organization and Team Context for Controllers
#
# This module provides convenient access to organization and team context
# for all controllers across the application.
#
# The organization and team are accessed via Rack::Request helper methods
# that extract them from StrategyResult metadata.
#
# Usage in controllers:
#   module MyController
#     include Onetime::Controllers::OrganizationContext
#
#     def my_handler
#       # Helper methods automatically available
#       organization.list_domains
#       team.members
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

      # Get current team from request
      #
      # @return [Onetime::Team, nil] Current team or nil
      def team
        req.team
      end

      # Get current team ID
      #
      # @return [String, nil] Team objid or nil
      def team_id
        req.team_id
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

      # Require team to be present
      #
      # @raise [Onetime::Problem] if team is nil
      # @return [Onetime::Team] the team
      def require_team!
        raise Onetime::Problem, 'No team context' unless team

        team
      end
    end
  end
end
