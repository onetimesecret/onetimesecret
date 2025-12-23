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
      # from the Billing::Plan cache. Falls back to minimal hardcoded plans
      # when billing is disabled (dev/standalone environments).
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
      #       planid: "free",
      #       name: "Free",
      #       tier: "free",
      #       entitlements: ["create_secrets", "basic_sharing"],
      #       limits: { "secrets.max" => "10", "recipients.max" => "1" }
      #     },
      #     {
      #       planid: "identity_plus_v1_monthly",
      #       name: "Identity Plus",
      #       tier: "single_team",
      #       entitlements: ["create_secrets", "custom_domains", ...],
      #       limits: { "secrets.max" => "100", ... }
      #     }
      #   ],
      #   source: "stripe"  # or "fallback"
      # }
      #
      # ## Deduplication
      #
      # If both monthly and yearly versions exist (e.g., identity_plus_v1_monthly
      # and identity_plus_v1_yearly), only the monthly version is returned to
      # reduce UI clutter. Colonels test entitlements, not billing intervals.
      #
      # ## Security
      #
      # - Requires colonel role
      class GetAvailablePlans < ColonelAPI::Logic::Base
        # Minimal fallback plans for dev/standalone environments
        # Used when Billing::Plan cache is empty (no Stripe sync)
        FALLBACK_PLANS = [
          {
            planid: 'free',
            name: 'Free',
            tier: 'free',
            entitlements: %w[create_secrets basic_sharing],
            limits: { 'secrets.max' => '10', 'recipients.max' => '1' },
          },
          {
            planid: 'identity_plus_v1_monthly',
            name: 'Identity Plus',
            tier: 'single_team',
            entitlements: %w[create_secrets custom_domains create_organization priority_support],
            limits: { 'secrets.max' => '100', 'recipients.max' => '10', 'organizations.max' => '1' },
          },
          {
            planid: 'multi_team_v1_monthly',
            name: 'Multi-Team',
            tier: 'multi_team',
            entitlements: %w[create_secrets custom_domains create_organization api_access audit_logs advanced_analytics],
            limits: { 'secrets.max' => 'unlimited', 'recipients.max' => 'unlimited', 'organizations.max' => '5' },
          },
        ].freeze

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          # Try loading from Billing::Plan cache first
          cached_plans = load_plans_from_cache

          if cached_plans.any?
            {
              plans: cached_plans,
              source: 'stripe',
            }
          else
            # Fall back to hardcoded plans for dev environments
            {
              plans: FALLBACK_PLANS,
              source: 'fallback',
            }
          end
        end

        private

        # Load plans from Billing::Plan cache
        #
        # @return [Array<Hash>] Array of plan hashes
        def load_plans_from_cache
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

          # Add free tier if not present in cache
          unless plans_array.any? { |p| p[:tier] == 'free' }
            plans_array.unshift(FALLBACK_PLANS.first)
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
