# apps/web/billing/operations/catalog/config_loader.rb
#
# frozen_string_literal: true

require_relative '../../region_normalizer'
require_relative 'plan_persister'

module Billing
  module Operations
    module Catalog
      # Loads plans from billing.yaml configuration into Redis cache.
      #
      # Handles two scenarios:
      # 1. Config-only plans (free tier) - plans with `prices: []` that have no Stripe presence
      # 2. Full config loading - bypasses Stripe entirely for dev/test environments
      #
      # @example Upsert config-only plans after Stripe sync
      #   ConfigLoader.upsert_config_only_plans
      #
      # @example Load all plans from config (dev/test)
      #   ConfigLoader.load_all_from_config
      #
      module ConfigLoader
        extend self

        # Upsert config-only plans (free tier, etc.) that have no Stripe prices
        #
        # Called AFTER Stripe sync to add plans with `prices: []` in billing.yaml.
        # These plans are not synced from Stripe since they have no prices, but should
        # still appear in the plan catalog for entitlement materialization and display
        # on pricing pages.
        #
        # Since this runs after prune_stale_plans, config-only plans are upserted fresh
        # each sync cycle with active=true, ensuring they persist in the catalog.
        #
        # @return [Integer] Number of config-only plans upserted
        def upsert_config_only_plans
          plans_hash = OT.billing_config.plans
          return 0 if plans_hash.empty?

          upserted_count = 0

          plans_hash.each do |plan_key, plan_def|
            prices = plan_def['prices'] || []

            # Only process config-only plans (no prices)
            next unless prices.empty?

            # Config-only plans don't have interval variants - use plan_key as ID
            plan_id = plan_key.to_s

            # Skip if not configured to show on plans page
            next unless plan_def['show_on_plans_page'] == true

            # Resolve effective region: explicit plan region, or inherit from deployment
            # Config-only plans (free tier) typically don't specify a region in YAML
            # because they're universal - they inherit the deployment's region.
            configured_region = OT.billing_config.region
            plan_region       = Billing::RegionNormalizer.normalize(plan_def['region']) || configured_region

            # Skip plans whose effective region doesn't match deployment
            unless Billing::RegionNormalizer.match?(plan_region, configured_region)
              OT.ld "[ConfigLoader] Skipping config-only plan for region #{plan_region}: #{plan_key}"
              next
            end

            plan = upsert_plan_from_config(plan_id, plan_def, nil)
            next unless plan

            upserted_count += 1
            OT.li "[ConfigLoader] Upserted config-only plan: #{plan_id}"
          end

          OT.li "[ConfigLoader] Upserted #{upserted_count} config-only plans"
          upserted_count
        end

        # Load all plans from billing.yaml config into Redis cache
        #
        # Bypasses Stripe API and loads plans directly from YAML configuration.
        # Creates one Plan instance per family (e.g., "identity_plus_v1") with
        # interval variants stored in the nested `prices` hashkey.
        #
        # Uses ConfigResolver to load from spec/billing.test.yaml in test environment.
        #
        # @param clear_first [Boolean] Whether to clear existing cache before loading (default: true)
        # @return [Integer] Number of plans loaded into Redis
        def load_all_from_config(clear_first: true)
          plans_hash = OT.billing_config.plans
          return 0 if plans_hash.empty?

          # Clear existing cache if requested
          Billing::Plan.clear_cache if clear_first

          plans_count = 0

          plans_hash.each do |plan_key, plan_def|
            # Skip plans not matching the configured region
            configured_region = OT.billing_config.region
            plan_region       = Billing::RegionNormalizer.normalize(plan_def['region'])
            unless Billing::RegionNormalizer.match?(plan_region, configured_region)
              OT.ld "[ConfigLoader] Skipping plan for region #{plan_region}: #{plan_key}"
              next
            end

            prices_list = plan_def['prices'] || []

            # Skip plans without prices (e.g., free tier - handled by upsert_config_only_plans)
            if prices_list.empty?
              OT.ld "[ConfigLoader] Skipping plan without prices: #{plan_key}"
              next
            end

            plan = upsert_plan_from_config(plan_key.to_s, plan_def, prices_list)
            next unless plan

            OT.ld "[ConfigLoader] Cached plan: #{plan_key}",
              {
                tier: plan_def['tier'],
                intervals: prices_list.map { |p| p['interval'] },
                currency: prices_list.first['currency'] || OT.billing_config.currency,
              }

            plans_count += 1
          end

          # Rebuild price ID cache after loading
          PlanPersister.rebuild_stripe_price_id_cache

          OT.li "[ConfigLoader] Cached #{plans_count} plans from config"
          plans_count
        end

        # Upsert a single plan from config definition
        #
        # @param plan_id [String] Plan identifier
        # @param plan_def [Hash] Plan definition from YAML
        # @param prices_list [Array, nil] List of price definitions, or nil for config-only plans
        # @return [Billing::Plan, nil] The upserted plan or nil on failure
        # rubocop:disable Metrics/PerceivedComplexity
        def upsert_plan_from_config(plan_id, plan_def, prices_list)
          # Extract plan attributes from config
          tier               = plan_def['tier']
          tenancy            = plan_def['tenancy'] || 'multi'
          display_order      = plan_def['display_order'] || 0
          entitlements_list  = plan_def['entitlements'] || []
          features_list      = plan_def['features'] || []
          show_on_plans_page = plan_def['show_on_plans_page'] == true

          # Convert limits to flattened format
          limits_hash = (plan_def['limits'] || {}).transform_keys { |k| "#{k}.max" }
          limits_hash = limits_hash.transform_values do |v|
            v.nil? || v == -1 ? 'unlimited' : v.to_s
          end

          # Build nested prices hash from all intervals (if provided)
          prices_data     = {}
          family_currency = OT.billing_config.currency

          if prices_list && !prices_list.empty?
            prices_list.each do |price|
              interval       = price['interval'].to_sym # :month or :year
              plan_currency  = price['currency'] || OT.billing_config.currency

              prices_data[interval] = {
                stripe_price_id: price['price_id'],
                amount: price['amount'].to_s,
                currency: plan_currency,
                billing_scheme: 'per_unit',
                usage_type: 'licensed',
                trial_period_days: nil,
                nickname: nil,
                active: 'true',
              }
            end
            family_currency = prices_list.first['currency'] || OT.billing_config.currency
          end

          # Create or update Plan instance
          plan = Billing::Plan.load(plan_id) || Billing::Plan.new(plan_id: plan_id)

          plan.name               = plan_def['name']
          plan.tier               = tier
          plan.currency           = family_currency
          plan.tenancy            = tenancy
          plan.display_order      = display_order.to_s
          plan.show_on_plans_page = show_on_plans_page.to_s
          plan.description        = plan_def['description']
          plan.stripe_product_id  = nil  # No Stripe product for config-based plans
          plan.active             = 'true'
          plan.plan_code          = plan_def['plan_code']
          plan.plan_name_label    = plan_def['plan_name_label']
          plan.includes_plan      = plan_def['includes_plan']
          plan.is_popular         = (plan_def['is_popular'] == true).to_s
          plan.region             = Billing::RegionNormalizer.normalize(plan_def['region']) || OT.billing_config.region
          plan.last_synced_at     = Time.now.to_i.to_s

          # Save scalar fields before writing collections (sets, hashkeys)
          # which write directly to Redis and expect the parent to exist.
          unless plan.save
            OT.le "[ConfigLoader] Save FAILED for plan: #{plan_id}",
              {
                tier: tier,
                tenancy: tenancy,
              }
            return nil
          end

          # Populate collections after save (these write directly to Redis)
          plan.entitlements.clear
          entitlements_list.each { |ent| plan.entitlements.add(ent) }

          plan.features.clear
          features_list.each { |feat| plan.features.add(feat) }

          plan.limits.clear
          limits_hash.each { |key, val| plan.limits[key] = val }

          # Populate prices hashkey with JSON per interval
          if prices_data.any?
            plan.prices.clear
            prices_data.each do |interval, price_data|
              plan.prices[interval.to_s] = price_data.to_json
            end
          end

          # No stripe_data_snapshot for config-based plans
          plan.stripe_data_snapshot.value = nil

          plan
        end
        # rubocop:enable Metrics/PerceivedComplexity
      end
    end
  end
end
