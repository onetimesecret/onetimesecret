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
      #       entitlements: ["create_secrets", "view_metadata"],
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
        # @return [Array<Hash>] Array of plan hashes
        def load_plans_from_stripe_cache
          plans = ::Billing::Plan.list_plans

          # Convert to hash format, deduplicating by tier
          seen_tiers = {}
          plans_array = []

          plans.each do |plan|
            # Skip yearly if we already have monthly for this tier
            # (prefer monthly for simplicity in testing UI)
            next if seen_tiers[plan.tier] && plan.interval == 'year'

            plans_array << {
              planid: plan.plan_id,
              name: plan.name,
              tier: plan.tier,
              entitlements: plan.entitlements.to_a,
              limits: plan.limits.hgetall || {},
            }

            seen_tiers[plan.tier] = true
          end

          plans_array
        rescue StandardError => ex
          OT.le '[GetAvailablePlans] Error loading plans from cache', {
            exception: ex,
            message: ex.message,
          }
          []
        end
      end
    end
  end
end
