# apps/web/billing/controllers/capabilities.rb

require_relative 'base'

module Billing
  module Controllers
    class Capabilities
      include Controllers::Base

      # Get organization capabilities and limits
      #
      # Returns the organization's plan capabilities and limits for
      # feature availability checks in the frontend.
      #
      # GET /billing/capabilities/:org_id
      #
      # Response:
      #   {
      #     "planid": "identity_v1",
      #     "plan_name": "Identity Plus",
      #     "capabilities": ["create_secrets", "create_team", "custom_domains"],
      #     "limits": {
      #       "teams": 1,
      #       "members_per_team": null,
      #       "secret_lifetime": 2592000
      #     },
      #     "is_legacy": false
      #   }
      #
      # @return [Hash] Capabilities and limits data
      def show
        org = load_organization(req.params[:org_id])

        data = {
          planid: org.planid,
          plan_name: Onetime::Billing.plan_name(org.planid),
          capabilities: org.capabilities,
          limits: build_limits_hash(org),
          is_legacy: Onetime::Billing.legacy_plan?(org.planid)
        }

        json_response(data)
      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue StandardError => ex
        billing_logger.error "Failed to load capabilities", {
          exception: ex,
          org_id: req.params[:org_id]
        }
        json_error("Failed to load capabilities", status: 500)
      end

      # Check specific capability for organization
      #
      # Validates whether the organization has a specific capability,
      # returning upgrade information if not available.
      #
      # GET /billing/check/:org_id/:capability
      #
      # Response (allowed):
      #   {
      #     "allowed": true,
      #     "capability": "custom_domains",
      #     "current_plan": "identity_v1",
      #     "upgrade_needed": false
      #   }
      #
      # Response (denied):
      #   {
      #     "allowed": false,
      #     "capability": "api_access",
      #     "current_plan": "identity_v1",
      #     "upgrade_needed": true,
      #     "upgrade_to": "multi_team_v1",
      #     "upgrade_plan_name": "Multi-Team",
      #     "message": "This feature requires Multi-Team. Upgrade your plan to access API."
      #   }
      #
      # @return [Hash] Capability check result
      def check
        org = load_organization(req.params[:org_id])
        capability = req.params[:capability]

        if capability.to_s.empty?
          return json_error("Capability parameter required", status: 400)
        end

        # Use organization's check_capability method
        result = org.check_capability(capability)

        # Enhance with upgrade messaging if needed
        if result[:upgrade_needed] && result[:upgrade_to]
          result[:upgrade_plan_name] = Onetime::Billing.plan_name(result[:upgrade_to])
          result[:message] = build_upgrade_message(capability, result[:upgrade_to])
        end

        json_response(result)
      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue StandardError => ex
        billing_logger.error "Failed capability check", {
          exception: ex,
          org_id: req.params[:org_id],
          capability: req.params[:capability]
        }
        json_error("Failed to check capability", status: 500)
      end

      # List all available capabilities
      #
      # Returns a reference list of all defined capabilities with descriptions.
      # Useful for documentation and feature discovery.
      #
      # GET /billing/capabilities
      #
      # Response:
      #   {
      #     "capabilities": {
      #       "core": ["create_secrets", "basic_sharing", "view_metadata"],
      #       "collaboration": ["create_team", "create_teams"],
      #       "infrastructure": ["custom_domains", "api_access"],
      #       "support": ["priority_support"],
      #       "advanced": ["audit_logs", "advanced_analytics", "extended_lifetime"]
      #     },
      #     "plans": {
      #       "free": { ... },
      #       "identity_v1": { ... },
      #       "multi_team_v1": { ... }
      #     }
      #   }
      #
      # @return [Hash] Capability reference data
      def list
        data = {
          capabilities: Onetime::Billing::CAPABILITY_CATEGORIES,
          plans: build_plans_summary
        }

        json_response(data)
      rescue StandardError => ex
        billing_logger.error "Failed to list capabilities", {
          exception: ex
        }
        json_error("Failed to list capabilities", status: 500)
      end

      private

      # Build limits hash with symbolic limit names
      #
      # @param org [Onetime::Organization] Organization instance
      # @return [Hash] Limits with nil for infinity
      def build_limits_hash(org)
        plan = ::Billing::Models::PlanCache.load(org.planid)
        return {} unless plan

        limits = plan.parsed_limits
        limits.transform_values do |value|
          value == Float::INFINITY ? nil : value
        end
      end

      # Build upgrade message for missing capability
      #
      # @param capability [String] Required capability
      # @param upgrade_plan [String] Suggested plan ID
      # @return [String] User-friendly upgrade message
      def build_upgrade_message(capability, upgrade_plan)
        plan_name = Onetime::Billing.plan_name(upgrade_plan)
        capability_name = capability.to_s.tr('_', ' ')

        "This feature requires #{plan_name}. Upgrade your plan to access #{capability_name}."
      end

      # Build summary of all available plans
      #
      # @return [Hash] Plan summaries keyed by plan ID
      def build_plans_summary
        summary = {}

        ::Billing::Models::PlanCache.list_plans.each do |plan|
          next unless plan

          summary[plan.plan_id] = {
            name: plan.name,
            capabilities: plan.parsed_capabilities,
            limits: plan.parsed_limits.transform_values { |v| v == Float::INFINITY ? nil : v }
          }
        end

        summary
      end

    end
  end
end
