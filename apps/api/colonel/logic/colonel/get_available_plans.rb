# apps/api/colonel/logic/colonel/get_available_plans.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      # Get Available Plans
      #
      # Returns all available plans for entitlement testing, loaded dynamically
      # from the Billing::Plan cache (Stripe-synced). Falls back to billing.yaml
      # config when cache is empty (dev/standalone environments).
      #
      # ## Request
      #
      # GET /api/colonel/available-plans
      #
      # ## Response
      #
      # {
      #   plans: [
      #     {
      #       planid: "free_v1",
      #       name: "Free",
      #       tier: "free",
      #       entitlements: ["create_secrets", "view_receipt"],
      #       limits: { "teams.max" => "0", "custom_domains.max" => "0" }
      #     },
      #     ...
      #   ],
      #   source: "stripe" | "local_config"
      # }
      #
      # ## Source Indicator
      #
      # - "stripe": Plans loaded from Stripe-synced Redis cache (production)
      # - "local_config": Plans loaded from billing.yaml (dev/no Stripe)
      #
      # The UI should display a warning when source is "local_config" since
      # this indicates the Stripe integration is not configured/available.
      #
      # ## Security
      #
      # - Requires colonel role
      class GetAvailablePlans < ColonelAPI::Logic::Base
        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          # Try loading from Billing::Plan cache (Stripe-synced) first
          cached_plans = load_plans_from_stripe_cache

          if cached_plans.any?
            {
              plans: cached_plans,
              source: 'stripe',
            }
          else
            # Fall back to billing.yaml config
            config_plans = ::Billing::Plan.list_plans_from_config
            {
              plans: config_plans,
              source: 'local_config',
            }
          end
        end

        private

        # Load plans from Billing::Plan cache (Stripe-synced)
        #
        # Deduplicates by tier, preferring monthly plans over yearly.
        # Uses a hash to ensure monthly always wins regardless of iteration order.
        #
        # @return [Array<Hash>] Array of plan hashes
        def load_plans_from_stripe_cache
          plans = ::Billing::Plan.list_plans

          # Key by plan_id (the family identifier). Each Plan holds all interval
          # variants (month/year) in its prices hashkey, so there are no per-
          # interval duplicates to collapse.
          plans_by_id = {}

          plans.each do |plan|
            plans_by_id[plan.plan_id] = {
              planid: plan.plan_id,
              name: plan.name,
              tier: plan.tier,
              tenancy: plan.tenancy,
              region: plan.region,
              display_order: plan.display_order.to_i,
              show_on_plans_page: plan.show_on_plans_page.to_s == 'true',
              description: plan.respond_to?(:description) ? plan.description : nil,
              entitlements: plan.entitlements.to_a,
              limits: plan.limits.hgetall || {},
            }
          end

          plans_by_id.values
        rescue StandardError => ex
          OT.le '[GetAvailablePlans] Error loading plans from cache',
            {
              exception: ex,
              message: ex.message,
            }
          []
        end
      end
    end
  end
end
