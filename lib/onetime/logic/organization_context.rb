# lib/onetime/logic/organization_context.rb
#
# frozen_string_literal: true

require_relative '../../../apps/web/auth/operations/create_default_workspace'

#
# Organization Context for Logic Classes
#
# This module provides automatic access to organization context
# for all logic classes across the application.
#
# The organization is extracted from StrategyResult metadata
# (populated by authentication strategies during RouteAuthWrapper execution).
#
# Lazy Creation:
# The auth_org method performs lazy creation of default workspaces for
# authenticated users who don't have an organization. This happens on
# first entitlement-gated access, not during authentication (which is
# read-only to avoid race conditions and negative caching bugs).
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
    # Provides organization context with two distinct accessors:
    #   @organization / #organization — mutable operational context (may be
    #     overwritten by domain-scoped logic like SsoConfig::Base)
    #   #auth_org — immutable, reads from StrategyResult metadata so it
    #     always reflects the authenticated user's organization
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

      # Immutable accessor: returns the organization from the authentication
      # strategy result metadata with lazy creation for authenticated users.
      #
      # If no organization exists in the metadata and we have an authenticated
      # customer, creates a default workspace via the canonical operation.
      # This defers org creation from auth phase (read-only) to first
      # entitlement-gated access, avoiding race conditions and negative caching.
      #
      # @return [Onetime::Organization, nil] The organization (lazy-created if needed)
      def auth_org
        return @auth_org if defined?(@auth_org)

        org = @strategy_result&.metadata&.dig(:organization_context, :organization)

        # Lazy creation for authenticated users without org
        if org.nil? && cust && !cust.anonymous?
          OT.info "[auth_org] Lazy-creating default workspace for #{cust.custid}"
          result = Auth::Operations::CreateDefaultWorkspace.new(customer: cust).call

          # Update metadata so subsequent calls in same request see the org
          if result && (org = result[:organization]) && @strategy_result&.metadata&.dig(:organization_context)
            @strategy_result.metadata[:organization_context][:organization]    = org
            @strategy_result.metadata[:organization_context][:organization_id] = org.objid
          end

          # Fallback: if creation returned nil but org now exists (race condition),
          # fetch it from the customer's organizations
          org ||= cust.organization_instances.first if org.nil?
        end

        @auth_org = org
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
