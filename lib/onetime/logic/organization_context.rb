# lib/onetime/logic/organization_context.rb
#
# frozen_string_literal: true

#
# Organization and Team Context for Logic Classes
#
# This module provides automatic access to organization and team context
# for all logic classes across the application.
#
# The organization and team are extracted from StrategyResult metadata
# (populated by authentication strategies during RouteAuthWrapper execution).
#
# Usage:
#   class MyLogic < Onetime::Logic::Base
#     def process
#       # @organization and @team automatically available
#       @organization.list_domains
#       @team.members
#     end
#   end
#
# For V3 module-based logic:
#   class MyLogic
#     include V3::Logic::Base
#     include Onetime::Logic::OrganizationContext
#
#     def initialize(strategy_result, params)
#       extract_organization_context(strategy_result)
#     end
#   end

module Onetime
  module Logic
    module OrganizationContext
      # Extract organization and team from StrategyResult metadata
      #
      # Call this in your initialize method after @strategy_result is set
      #
      # @param strategy_result [Otto::Security::Authentication::StrategyResult]
      def extract_organization_context(strategy_result)
        return unless strategy_result

        org_context   = strategy_result.metadata[:organization_context] || {}
        @organization = org_context[:organization]
        @team         = org_context[:team]
      end

      # Make organization and team readable
      attr_reader :organization, :team

      # Alias for convenience
      def org
        @organization
      end

      # Require organization to be present
      #
      # @raise [Onetime::Problem] if organization is nil
      # @return [Onetime::Organization] the organization
      def require_organization!
        raise Onetime::Problem, 'No organization context' unless @organization

        @organization
      end

      # Require team to be present
      #
      # @raise [Onetime::Problem] if team is nil
      # @return [Onetime::Team] the team
      def require_team!
        raise Onetime::Problem, 'No team context' unless @team

        @team
      end
    end
  end
end
