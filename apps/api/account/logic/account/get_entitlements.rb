# apps/api/account/logic/account/get_entitlements.rb
#
# frozen_string_literal: true

require_relative '../base'

module AccountAPI::Logic
  module Account
    # Get Entitlements API
    #
    # Returns entitlement definitions and plan-to-entitlement mappings for the frontend.
    # Uses Stripe-synced plan cache with fallback to billing.yaml config.
    #
    # ## Request
    #
    # GET /api/account/entitlements
    #
    # ## Response
    #
    # {
    #   entitlements: [
    #     {
    #       key: "api_access",
    #       display_name: "web.billing.overview.entitlements.api_access",
    #       category: "infrastructure",
    #       description: "Can use REST API endpoints"
    #     },
    #     ...
    #   ],
    #   plans: [
    #     {
    #       plan_id: "free_v1",
    #       name: "Free",
    #       entitlements: ["create_secrets", "view_receipt", "api_access"]
    #     },
    #     ...
    #   ],
    #   source: "stripe" | "local_config"
    # }
    #
    # ## Source Indicator
    #
    # - "stripe": Plans loaded from Stripe-synced Redis cache (production)
    # - "local_config": Plans loaded from billing.yaml (dev/standalone)
    #
    # ## Caching
    #
    # Entitlement definitions are loaded from billing.yaml config (rarely changes).
    # Plan data uses Billing::Plan cache with 12-hour TTL or config fallback.
    #
    # ## Security
    #
    # - Requires authentication (sessionauth or basicauth)
    # - Returns only public entitlement metadata, no sensitive data
    #
    class GetEntitlements < AccountAPI::Logic::Base
      def raise_concerns
        # Basic auth check - requires logged in user
        raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?
      end

      def process
        entitlements_list = build_entitlements_list
        plans_result      = build_plans_list

        {
          entitlements: entitlements_list,
          plans: plans_result[:plans],
          source: plans_result[:source],
        }
      end

      private

      # Build entitlements list from billing config
      #
      # @return [Array<Hash>] Array of entitlement definitions
      def build_entitlements_list
        entitlements_hash = ::Billing::Config.load_entitlements
        return [] if entitlements_hash.empty?

        entitlements_hash.map do |key, definition|
          {
            key: key,
            display_name: definition['display_name'] || "web.billing.overview.entitlements.#{key}",
            category: definition['category'] || 'uncategorized',
            description: definition['description'],
          }
        end
      end

      # Build plans list with entitlement mappings
      #
      # Uses Billing::Plan cache (Stripe-synced) first, falls back to config.
      # Deduplicates by tier, preferring monthly plans.
      #
      # @return [Hash] { plans: Array, source: String }
      def build_plans_list
        # Try loading from Billing::Plan cache (Stripe-synced) first
        cached_plans = load_plans_from_stripe_cache

        if cached_plans.any?
          {
            plans: cached_plans,
            source: 'stripe',
          }
        else
          # Fall back to billing.yaml config
          config_plans = load_plans_from_config
          {
            plans: config_plans,
            source: 'local_config',
          }
        end
      end

      # Load plans from Billing::Plan cache (Stripe-synced)
      #
      # Deduplicates by tier, preferring monthly plans over yearly.
      #
      # @return [Array<Hash>] Array of plan hashes with entitlements
      def load_plans_from_stripe_cache
        plans = ::Billing::Plan.list_plans.compact

        # Group by tier, preferring monthly plans over yearly
        plans_by_tier = {}

        plans.each do |plan|
          existing = plans_by_tier[plan.tier]

          # Keep existing if it's monthly (preferred), otherwise replace
          next if existing && existing[:interval] == 'month'

          plans_by_tier[plan.tier] = {
            interval: plan.interval, # Track for deduplication
            data: {
              plan_id: plan.plan_id,
              name: plan.name,
              entitlements: plan.entitlements.to_a,
            },
          }
        end

        # Extract just the data hashes (without the interval tracking key)
        plans_by_tier.values.map { |entry| entry[:data] }
      rescue StandardError => ex
        OT.le '[GetEntitlements] Error loading plans from cache', {
          exception: ex.class.name,
          message: ex.message,
        }
        []
      end

      # Load plans from billing.yaml config
      #
      # @return [Array<Hash>] Array of plan hashes with entitlements
      def load_plans_from_config
        plans_hash = ::Billing::Config.load_plans
        return [] if plans_hash.empty?

        plans_hash.map do |plan_id, plan_def|
          {
            plan_id: plan_id,
            name: plan_def['name'],
            entitlements: plan_def['entitlements'] || [],
          }
        end
      end
    end
  end
end
