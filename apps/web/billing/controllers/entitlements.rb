# apps/web/billing/controllers/entitlements.rb
#
# frozen_string_literal: true

require_relative 'base'
require_relative '../config'

module Billing
  module Controllers
    class Entitlements
      include Controllers::Base

      # Get organization entitlements and limits
      #
      # Returns the organization's plan entitlements and limits for
      # feature availability checks in the frontend.
      #
      # GET /billing/entitlements/:extid
      #
      # Response:
      #   {
      #     "planid": "identity_plus_v1",
      #     "plan_name": "Identity Plus",
      #     "entitlements": ["create_secrets", "create_team", "custom_domains"],
      #     "limits": {
      #       "teams": 1,
      #       "members_per_team": null,
      #       "secret_lifetime": 2592000
      #     },
      #     "is_legacy": false
      #   }
      #
      # @return [Hash] Entitlements and limits data
      def show
        org = load_organization(req.params['extid'])

        data = {
          planid: org.planid,
          plan_name: Billing::PlanHelpers.plan_name(org.planid),
          entitlements: org.entitlements,
          limits: build_limits_hash(org),
          is_legacy: Billing::PlanHelpers.legacy_plan?(org.planid),
        }

        json_response(data)
      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue StandardError => ex
        billing_logger.error 'Failed to load entitlements', {
          exception: ex,
          extid: req.params['extid'],
        }
        json_error('Failed to load entitlements', status: 500)
      end

      # Check specific entitlement for organization
      #
      # Validates whether the organization has a specific entitlement,
      # returning upgrade information if not available.
      #
      # GET /billing/check/:extid/:entitlement
      #
      # Response (allowed):
      #   {
      #     "allowed": true,
      #     "entitlement": "custom_domains",
      #     "current_plan": "identity_plus_v1",
      #     "upgrade_needed": false
      #   }
      #
      # Response (denied):
      #   {
      #     "allowed": false,
      #     "entitlement": "api_access",
      #     "current_plan": "identity_plus_v1",
      #     "upgrade_needed": true,
      #     "upgrade_to": "multi_team_v1",
      #     "upgrade_plan_name": "Multi-Team",
      #     "message": "This feature requires Multi-Team. Upgrade your plan to access API."
      #   }
      #
      # @return [Hash] Entitlement check result
      def check
        org        = load_organization(req.params['extid'])
        entitlement = req.params[:entitlement]

        if entitlement.to_s.empty?
          return json_error('Entitlement parameter required', status: 400)
        end

        # Use organization's check_entitlement method
        result = org.check_entitlement(entitlement)

        # Enhance with upgrade messaging if needed
        if result[:upgrade_needed] && result[:upgrade_to]
          result[:upgrade_plan_name] = Billing::PlanHelpers.plan_name(result[:upgrade_to])
          result[:message]           = build_upgrade_message(entitlement, result[:upgrade_to])
        end

        json_response(result)
      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue StandardError => ex
        billing_logger.error 'Failed entitlement check', {
          exception: ex,
          extid: req.params['extid'],
          entitlement: req.params[:entitlement],
        }
        json_error('Failed to check entitlement', status: 500)
      end

      # List all available entitlements
      #
      # Returns a reference list of all defined entitlements with descriptions.
      # Useful for documentation and feature discovery.
      #
      # GET /billing/entitlements
      #
      # Response:
      #   {
      #     "entitlements": {
      #       "core": ["create_secrets", "basic_sharing", "view_metadata"],
      #       "collaboration": ["create_team", "create_teams"],
      #       "infrastructure": ["custom_domains", "api_access"],
      #       "support": ["priority_support"],
      #       "advanced": ["audit_logs", "advanced_analytics", "extended_lifetime"]
      #     },
      #     "plans": {
      #       "free": { ... },
      #       "identity_plus_v1": { ... },
      #       "multi_team_v1": { ... }
      #     }
      #   }
      #
      # @return [Hash] Entitlement reference data
      def list
        data = {
          entitlements: Billing::Config.entitlements_grouped_by_category,
          plans: build_plans_summary,
        }

        json_response(data)
      rescue StandardError => ex
        billing_logger.error 'Failed to list entitlements', {
          exception: ex,
        }
        json_error('Failed to list entitlements', status: 500)
      end

      private

      # Build limits hash with symbolic limit names
      #
      # @param org [Onetime::Organization] Organization instance
      # @return [Hash] Limits with nil for infinity
      def build_limits_hash(org)
        plan = ::Billing::Plan.load(org.planid)
        return {} unless plan

        limits = plan.limits_hash
        limits.transform_values do |value|
          value == Float::INFINITY ? nil : value
        end
      end

      # Build upgrade message for missing entitlement
      #
      # @param entitlement [String] Required entitlement
      # @param upgrade_plan [String] Suggested plan ID
      # @return [String] User-friendly upgrade message
      def build_upgrade_message(entitlement, upgrade_plan)
        plan_name       = Billing::PlanHelpers.plan_name(upgrade_plan)
        entitlement_name = entitlement.to_s.tr('_', ' ')

        "This feature requires #{plan_name}. Upgrade your plan to access #{entitlement_name}."
      end

      # Build summary of all available plans
      #
      # @return [Hash] Plan summaries keyed by plan ID
      def build_plans_summary
        summary = {}

        ::Billing::Plan.list_plans.each do |plan|
          next unless plan

          summary[plan.plan_id] = {
            name: plan.name,
            entitlements: plan.entitlements.to_a,
            limits: plan.limits_hash.transform_values { |v| v == Float::INFINITY ? nil : v },
          }
        end

        summary
      end
    end
  end
end
