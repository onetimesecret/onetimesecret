# apps/web/billing/operations/catalog/pull.rb
#
# frozen_string_literal: true

module Billing
  module Operations
    module Catalog
      # Pull products and prices from Stripe to Redis cache.
      #
      # Wraps Plan.refresh_from_stripe and Plan.upsert_config_only_plans
      # for CLI and programmatic use. Never writes to stdout directly.
      #
      # @example
      #   result = Pull.call(region: 'ca', progress: ->(msg) { print "\r#{msg}" })
      #   if result.success
      #     puts "Synced #{result.plans_synced} plans"
      #   end
      #
      class Pull
        Result = Data.define(
          :success,
          :plans_synced,
          :plans_pruned,
          :config_plans_loaded,
          :cache_cleared,
          :errors,
        ) do
          def initialize(success:, plans_synced: 0, plans_pruned: 0, config_plans_loaded: 0, cache_cleared: false, errors: [])
            super
          end
        end

        # @param region [String, nil] Region filter for Stripe products
        # @param clear_cache [Boolean] Clear existing cache before pulling
        # @param progress [Proc, nil] Called with status messages
        # @return [Result]
        def self.call(region: nil, clear_cache: false, progress: nil)
          new(region: region, clear_cache: clear_cache, progress: progress).call
        end

        def initialize(region:, clear_cache:, progress:)
          @region      = region
          @clear_cache = clear_cache
          @progress    = progress
        end

        def call
          errors        = []
          cache_cleared = false

          if @clear_cache
            report('Clearing existing plan cache...')
            Billing::Plan.clear_cache
            cache_cleared = true
            report('Cache cleared')
          end

          report('Pulling from Stripe to Redis cache...')

          plans_synced = Billing::Plan.refresh_from_stripe(
            progress: @progress,
          )

          config_plans_loaded = Billing::Plan.upsert_config_only_plans

          Result.new(
            success: true,
            plans_synced: plans_synced,
            plans_pruned: 0,
            config_plans_loaded: config_plans_loaded,
            cache_cleared: cache_cleared,
            errors: errors,
          )
        rescue Stripe::StripeError => ex
          Result.new(
            success: false,
            errors: ["Stripe error: #{ex.message}"],
          )
        rescue StandardError => ex
          Result.new(
            success: false,
            errors: ["#{ex.class}: #{ex.message}"],
          )
        end

        private

        def report(message)
          @progress&.call(message)
        end
      end
    end
  end
end
