# lib/middleware/capability_check.rb

module Rack
  # CapabilityCheck Middleware
  #
  # Rack middleware for protecting routes with capability-based authorization.
  # Checks if the organization (from Otto auth result) has a required capability.
  #
  # ## Usage
  #
  # In a Roda application:
  #
  #   use Rack::CapabilityCheck, capability: 'custom_domains'
  #   use Rack::CapabilityCheck, capability: 'api_access'
  #
  # ## Request Flow
  #
  # 1. Extract organization from env['otto.strategy_result']
  # 2. Check if org.can?(capability)
  # 3. If yes: pass request through
  # 4. If no: return 403 with upgrade information
  #
  # ## Response Format (403)
  #
  #   {
  #     "error": "Feature not available",
  #     "capability": "custom_domains",
  #     "current_plan": "free",
  #     "upgrade_to": "identity_v1"
  #   }
  #
  class CapabilityCheck
    include Middleware::Logging

    def initialize(app, capability:, logger: nil)
      @app = app
      @capability = capability.to_s
      @custom_logger = logger
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
        logger.warn("[CapabilityCheck] No organization in request context")
        return denial_response(
          error: 'Authentication required',
          capability: @capability
        )
      end

      # Check if organization has capability
      if org.can?(@capability)
        logger.debug("[CapabilityCheck] #{org.orgid} has #{@capability}")
        @app.call(env)
      else
        logger.info("[CapabilityCheck] #{org.orgid} denied #{@capability}", {
          current_plan: org.planid,
          upgrade_to: Onetime::Billing.upgrade_path_for(@capability, org.planid)
        })

        denial_response(
          error: 'Feature not available',
          capability: @capability,
          current_plan: org.planid,
          upgrade_to: Onetime::Billing.upgrade_path_for(@capability, org.planid),
          message: upgrade_message(org)
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
      upgrade_plan = Onetime::Billing.upgrade_path_for(@capability, org.planid)
      plan_name = Onetime::Billing.plan_name(upgrade_plan) if upgrade_plan

      if plan_name
        "This feature requires #{plan_name}. Upgrade your plan to access #{@capability.tr('_', ' ')}."
      else
        "This feature is not available on your current plan."
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
          'X-Capability-Required' => @capability
        },
        [payload.to_json]
      ]
    end

  end
end
