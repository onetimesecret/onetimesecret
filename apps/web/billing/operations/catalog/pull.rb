# apps/web/billing/operations/catalog/pull.rb
#
# frozen_string_literal: true

require_relative 'stripe_retry'
require_relative 'stripe_reader'
require_relative 'config_loader'
require_relative 'plan_persister'
require_relative 'data_extractor'
require_relative '../../lib/stripe_circuit_breaker'

module Billing
  module Operations
    module Catalog
      # Pull products and prices from Stripe to Redis cache.
      #
      # Fetches products and prices via StripeReader (wrapped in circuit breaker),
      # transforms them into plan data hashes, and persists to Redis.
      # Never writes to stdout directly.
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
          :config_plans_loaded,
          :cache_cleared,
          :errors,
          :error_type,
        ) do
          def initialize(success:, plans_synced: 0, config_plans_loaded: 0, cache_cleared: false, errors: [], error_type: nil)
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
          cache_cleared       = false
          plans_synced        = 0
          config_plans_loaded = 0

          if @clear_cache
            report('Clearing existing plan cache...')
            Billing::Plan.clear_cache
            cache_cleared = true
            report('Cache cleared')
          end

          # Skip Stripe sync if no API key configured
          stripe_key = Onetime.billing_config.stripe_key
          if stripe_key.to_s.strip.empty?
            OT.lw '[Pull] Skipping Stripe sync: No API key configured'
            config_plans_loaded = ConfigLoader.upsert_config_only_plans
            return Result.new(
              success: true,
              plans_synced: 0,
              config_plans_loaded: config_plans_loaded,
              cache_cleared: cache_cleared,
            )
          end

          report('Pulling from Stripe to Redis cache...')

          plans_synced = StripeRetry.with_retry do
            sync_from_stripe
          end

          config_plans_loaded = ConfigLoader.upsert_config_only_plans

          Result.new(
            success: true,
            plans_synced: plans_synced,
            config_plans_loaded: config_plans_loaded,
            cache_cleared: cache_cleared,
          )
        rescue Stripe::StripeError => ex
          Result.new(
            success: false,
            plans_synced: plans_synced,
            config_plans_loaded: config_plans_loaded,
            cache_cleared: cache_cleared,
            errors: ["Stripe error: #{ex.message}"],
            error_type: :stripe_api,
          )
        rescue Billing::CatalogValidationError => ex
          Result.new(
            success: false,
            plans_synced: plans_synced,
            config_plans_loaded: config_plans_loaded,
            cache_cleared: cache_cleared,
            errors: [ex.message],
            error_type: :validation,
          )
        rescue StandardError => ex
          Result.new(
            success: false,
            plans_synced: plans_synced,
            config_plans_loaded: config_plans_loaded,
            cache_cleared: cache_cleared,
            errors: ["#{ex.class}: #{ex.message}"],
            error_type: :internal,
          )
        end

        private

        # Synchronize Stripe catalog to Redis using StripeReader
        #
        # Stripe API calls are wrapped in circuit breaker to prevent cascade
        # failures during Stripe outages.
        #
        # @return [Integer] Number of plans synced
        def sync_from_stripe
          report('Fetching products from Stripe...')

          # PHASE 1: Fetch all data from Stripe (circuit breaker protected)
          plan_data_list = Billing::StripeCircuitBreaker.call do
            fetch_and_collect_plan_data
          end

          if plan_data_list.empty?
            OT.lw '[Pull] No valid plans collected from Stripe'
            return 0
          end

          report("Upserting #{plan_data_list.size} plans...")

          # Upsert all plans
          upserted_ids  = []
          not_persisted = []

          plan_data_list.each do |plan_data|
            plan = PlanPersister.upsert_from_stripe_data(plan_data)
            upserted_ids << plan.plan_id
            not_persisted << plan.plan_id unless Billing::Plan.instances.member?(plan.plan_id)
          end

          saved_count = upserted_ids.size - not_persisted.size

          if not_persisted.any?
            OT.lw "[Pull] #{not_persisted.size} plan(s) not persisted: #{not_persisted.join(', ')}"
          end

          # Prune stale plans not in current Stripe catalog
          pruned_count = PlanPersister.prune_stale_plans(upserted_ids)

          # Rebuild lookup cache for O(1) price_id lookups
          PlanPersister.rebuild_stripe_price_id_cache

          # Update global sync timestamp
          PlanPersister.update_catalog_sync_timestamp

          OT.li "[Pull] Synced #{saved_count}/#{upserted_ids.size} plans " \
                "(#{not_persisted.size} not persisted), pruned #{pruned_count}"
          saved_count
        end

        # Fetch products and prices from Stripe, return plan data hashes
        #
        # Called inside circuit breaker. All Stripe API calls happen here.
        #
        # @return [Array<Hash>] Plan data hashes ready for upsert
        def fetch_and_collect_plan_data
          products = StripeReader.fetch_products(
            app_identifier: Billing::Metadata::APP_NAME,
            region_filter: @region || Onetime.billing_config.region,
          )

          if products.empty?
            OT.lw '[Pull] No valid products fetched from Stripe'
            return []
          end

          report("Fetching prices for #{products.size} products...")
          prices_by_key = StripeReader.fetch_prices(products)

          collect_plan_data(products, prices_by_key)
        end

        # Collect plan data from StripeReader output
        #
        # Groups products by plan_id (family), merges interval variants,
        # and validates metadata.
        #
        # @param products [Hash<String, Stripe::Product>] Products keyed by match_key (plan_id)
        # @param prices_by_key [Hash<String, Array<Stripe::Price>>] Prices grouped by match_key
        # @return [Array<Hash>] Plan data hashes ready for upsert_from_stripe_data
        def collect_plan_data(products, prices_by_key)
          plan_data_by_family = {}
          validation_errors   = []
          products_processed  = 0

          products.each do |match_key, product|
            products_processed += 1
            if products_processed == 1 || products_processed % 5 == 0
              report("Processing product #{products_processed}: #{product.name[0..40]}...")
            end

            # Validate product metadata using shared validation logic
            validation_result = validate_product_metadata(product)
            if validation_result[:missing].any? || validation_result[:blank].any?
              problems = []
              problems << "missing: #{validation_result[:missing].join(', ')}" if validation_result[:missing].any?
              problems << "blank: #{validation_result[:blank].join(', ')}" if validation_result[:blank].any?
              OT.le '[Pull] Product failed metadata validation',
                { product_id: product.id, product_name: product.name, problems: problems.join('; ') }
              validation_errors << {
                product_id: product.id,
                price_id: nil,
                product_name: product.name,
                error: "invalid metadata: #{problems.join('; ')}",
              }
              next
            end

            # Get prices for this product
            prices = prices_by_key[match_key] || []
            next if prices.empty?

            prices.each do |price|
              # Skip non-recurring prices
              next unless price.type == 'recurring'

              # Extract plan data
              plan_data = DataExtractor.call(product, price)
              plan_id   = plan_data[:plan_id]

              if plan_data_by_family.key?(plan_id)
                # Merge this interval's price data into existing plan entry
                existing          = plan_data_by_family[plan_id]
                existing[:prices] = existing[:prices].merge(plan_data[:prices])
                existing[:active] = 'true' if plan_data[:active] == 'true'

                # Merge stripe_snapshot prices
                existing[:stripe_snapshot][:prices] =
                  existing[:stripe_snapshot][:prices].merge(plan_data[:stripe_snapshot][:prices])
              else
                # First interval variant for this plan family
                plan_data_by_family[plan_id] = plan_data
              end
            end
          end

          # Fail-closed: abort if any managed products had invalid metadata
          if validation_errors.any?
            OT.le '[Pull] Aborting due to validation failures',
              { error_count: validation_errors.size, valid_count: plan_data_by_family.size }
            raise Billing::CatalogValidationError.new(
              "#{validation_errors.size} Stripe products failed metadata validation",
              errors: validation_errors,
            )
          end

          plan_data_by_family.values
        end

        def report(message)
          @progress&.call(message)
        end

        # Validate product has all required metadata for plan creation
        #
        # Checks both key presence AND non-blank values for required fields.
        # Shared validation logic used by both Pull and DataExtractor.
        #
        # @param product [Stripe::Product] The Stripe product
        # @return [Hash] { missing: [...], blank: [...] } — both empty if valid
        def validate_product_metadata(product)
          required = Billing::Metadata::REQUIRED_FIELDS
          metadata = product.metadata || {}
          keys     = metadata.keys.map(&:to_s)
          missing  = required - keys

          # Check present keys for blank values
          blank = (required - missing).select do |key|
            metadata[key].to_s.strip.empty?
          end

          { missing: missing, blank: blank }
        end
      end
    end
  end
end
