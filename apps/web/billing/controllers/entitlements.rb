# apps/web/billing/controllers/entitlements.rb
#
# frozen_string_literal: true

require_relative 'base'
require_relative '../config'
require_relative '../plan_helpers'

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
      #     "entitlements": ["api_access", "custom_domains", "manage_teams"],
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

        # Check if plan cache may be stale (plan assigned but not found)
        plan_cache_stale = plan_cache_stale?(org.planid)
        if plan_cache_stale
          billing_logger.warn 'Plan cache appears stale for entitlements request', {
            extid: req.params['extid'],
            planid: org.planid,
          }
        end

        data = {
          planid: org.planid,
          plan_name: Billing::PlanHelpers.plan_name(org.planid),
          entitlements: org.entitlements,
          limits: build_limits_hash(org),
          is_legacy: Billing::PlanHelpers.legacy_plan?(org.planid),
          cache_stale: plan_cache_stale,
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
        org         = load_organization(req.params['extid'])
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
      #       "core": ["api_access", "custom_privacy_defaults", "extended_default_expiration"],
      #       "collaboration": ["manage_orgs", "manage_teams", "manage_members"],
      #       "infrastructure": ["custom_domains", "custom_branding", "branded_homepage"],
      #       "communication": ["incoming_secrets", "custom_mail_defaults"],
      #       "advanced": ["audit_logs"]
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

      # Check if the plan cache appears stale
      #
      # Returns true if the organization has a planid set but the plan
      # cannot be found in the Redis cache. This can happen when:
      # - Stripe cache hasn't been populated yet
      # - Cache has expired (12-hour TTL)
      # - Redis was flushed
      #
      # @param planid [String] Plan ID to check
      # @return [Boolean] True if cache appears stale
      def plan_cache_stale?(planid)
        return false if planid.to_s.empty?

        plan = ::Billing::Plan.load(planid)
        plan.nil?
      end

      # Build limits hash with symbolic limit names
      #
      # Returns empty hash if:
      # - Organization has no planid
      # - Plan not found in cache
      #
      # @param org [Onetime::Organization] Organization instance
      # @return [Hash] Limits with nil for infinity
      def build_limits_hash(org)
        return {} if org.planid.to_s.empty?

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
        plan_name        = Billing::PlanHelpers.plan_name(upgrade_plan)
        entitlement_name = entitlement.to_s.tr('_', ' ')

        "This feature requires #{plan_name}. Upgrade your plan to access #{entitlement_name}."
      end

      # Build summary of all available plans
      #
      # Falls back to billing.yaml config if Stripe cache is empty.
      # This ensures the plans list endpoint works even when Redis cache
      # hasn't been populated from Stripe yet.
      #
      # @return [Hash] Plan summaries keyed by plan ID
      def build_plans_summary
        plans = begin
          ::Billing::Plan.list_plans
        rescue StandardError => ex
          billing_logger.warn 'Failed to list plans from cache, falling back to config', {
            exception: ex,
          }
          []
        end

        # If Stripe cache is empty, fall back to billing.yaml config
        if plans.empty?
          return build_plans_summary_from_config
        end

        summary = {}
        plans.each do |plan|
          next unless plan

          # Guard against nil entitlements
          entitlements_array = plan.entitlements&.to_a || []
          limits_hash        = plan.limits_hash || {}

          summary[plan.plan_id] = {
            name: plan.name,
            entitlements: entitlements_array,
            limits: limits_hash.transform_values { |v| v == Float::INFINITY ? nil : v },
          }
        end

        summary
      end

      # Build plans summary from billing.yaml config
      #
      # Fallback when Stripe cache is empty. Provides basic plan info
      # from static configuration.
      #
      # @return [Hash] Plan summaries keyed by plan ID
      def build_plans_summary_from_config
        config_plans = ::Billing::Plan.list_plans_from_config
        return {} if config_plans.empty?

        summary = {}
        config_plans.each do |plan_hash|
          next unless plan_hash

          plan_id      = plan_hash[:planid]
          entitlements = plan_hash[:entitlements] || []
          limits       = plan_hash[:limits] || {}

          summary[plan_id] = {
            name: plan_hash[:name],
            entitlements: entitlements,
            limits: limits.transform_values { |v| v == 'unlimited' ? nil : v.to_i },
          }
        end

        summary
      rescue StandardError => ex
        billing_logger.warn 'Failed to load plans from config', {
          exception: ex,
        }
        {}
      end
    end
  end
end
