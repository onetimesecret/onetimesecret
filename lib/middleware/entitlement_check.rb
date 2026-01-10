# lib/middleware/entitlement_check.rb
#
# frozen_string_literal: true

module Rack
  # EntitlementCheck Middleware
  #
  # Rack middleware for protecting routes with entitlement-based authorization.
  # Checks if the organization (from Otto auth result) has a required entitlement.
  #
  # ## Usage
  #
  # In a Roda application:
  #
  #   use Rack::EntitlementCheck, entitlement: 'custom_domains'
  #   use Rack::EntitlementCheck, entitlement: 'api_access'
  #
  # ## Request Flow
  #
  # 1. Extract organization from env['otto.strategy_result']
  # 2. Check if org.can?(entitlement)
  # 3. If yes: pass request through
  # 4. If no: return 403 with upgrade information
  #
  # ## Response Format (403)
  #
  #   {
  #     "error": "Feature not available",
  #     "entitlement": "custom_domains",
  #     "current_plan": "free",
  #     "upgrade_to": "identity_v1"
  #   }
  #
  class EntitlementCheck
    include Middleware::Logging

    def initialize(app, options = {})
      @app           = app
      @entitlement   = options.fetch(:entitlement).to_s
      @custom_logger = options[:logger]
    end

    # Override logger to allow custom logger injection
    def logger
      @custom_logger || super
    end

    def call(env)
      # Extract organization from Otto auth result
      org = extract_organization(env)

      # If no org context, deny access (auth should happen upstream)
      unless org
        logger.warn('[EntitlementCheck] No organization in request context')
        return denial_response(
          error: 'Authentication required',
          entitlement: @entitlement,
        )
      end

      # Check if organization has entitlement
      if org.can?(@entitlement)
        logger.debug("[EntitlementCheck] #{org.objid} has #{@entitlement}")
        @app.call(env)
      else
        logger.info(
          "[EntitlementCheck] #{org.objid} denied #{@entitlement}",
          {
            current_plan: org.planid,
            upgrade_to: Billing::PlanHelpers.upgrade_path_for(@entitlement, org.planid),
          },
        )

        denial_response(
          error: 'Feature not available',
          entitlement: @entitlement,
          current_plan: org.planid,
          upgrade_to: Billing::PlanHelpers.upgrade_path_for(@entitlement, org.planid),
          message: upgrade_message(org),
        )
      end
    end

    private

    # Extract organization from Otto auth strategy result
    #
    # @param env [Hash] Rack environment
    # @return [Onetime::Organization, nil] Organization or nil
    def extract_organization(env)
      # Otto stores auth result in env['otto.strategy_result']
      strategy_result = env['otto.strategy_result']
      return nil unless strategy_result

      # Strategy result should have an organization attribute
      # This assumes Otto strategies include organization context
      strategy_result.organization if strategy_result.respond_to?(:organization)
    end

    # Generate user-friendly upgrade message
    #
    # @param org [Onetime::Organization] Organization
    # @return [String] Upgrade message
    def upgrade_message(org)
      upgrade_plan = Billing::PlanHelpers.upgrade_path_for(@entitlement, org.planid)
      plan_name    = Billing::PlanHelpers.plan_name(upgrade_plan) if upgrade_plan

      if plan_name
        "This feature requires #{plan_name}. Upgrade your plan to access #{@entitlement.tr('_', ' ')}."
      else
        'This feature is not available on your current plan.'
      end
    end

    # Build 403 denial response
    #
    # @param payload [Hash] Response data
    # @return [Array] Rack response triple
    def denial_response(**payload)
      [
        403,
        {
          'Content-Type' => 'application/json',
          'X-Entitlement-Required' => @entitlement,
        },
        [payload.to_json],
      ]
    end
  end
end
