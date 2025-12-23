# lib/onetime/logic/organization_context.rb
#
# frozen_string_literal: true

#
# Organization Context for Logic Classes
#
# This module provides automatic access to organization context
# for all logic classes across the application.
#
# The organization is extracted from StrategyResult metadata
# (populated by authentication strategies during RouteAuthWrapper execution).
#
# Usage:
#   class MyLogic < Onetime::Logic::Base
#     def process
#       # @organization automatically available
#       @organization.list_domains
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
      # Extract organization from StrategyResult metadata
      #
      # Call this in your initialize method after @strategy_result is set
      #
      # @param strategy_result [Otto::Security::Authentication::StrategyResult]
      def extract_organization_context(strategy_result)
        return unless strategy_result

        org_context   = strategy_result.metadata[:organization_context] || {}
        @organization = org_context[:organization]
      end

      # Make organization readable
      attr_reader :organization

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
    end
  end
end
