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
        # Called AFTER Stripe sync to add plans with `prices: []` in billing.yaml,
        # and from #load_all_from_config so the Stripe-less fallback path builds
        # the same catalog. These plans are not synced from Stripe since they have
        # no prices, but should still appear in the plan catalog for entitlement
        # materialization and display on pricing pages.
        #
        # Since this runs after prune_stale_plans, config-only plans are upserted fresh
        # each sync cycle with active=true, ensuring they persist in the catalog.
        #
        # @return [Integer] Number of config-only plans upserted
        def upsert_config_only_plans
          plans_hash = OT.billing_config.plans
          return 0 if plans_hash.empty?

          upserted_count = 0

          # One page, one currency: when this runs after a Stripe sync (Pull),
          # config-only plans inherit the currency the Stripe-sourced plans
          # carry, instead of being stamped with OT.billing_config.currency.
          # Otherwise a deployment whose Stripe catalog bills in EUR would
          # render a pricing grid mixing EUR paid plans with a USD free tier.
          # Nil when no Stripe-sourced plan is cached (e.g. the full config
          # fallback path, where everything already shares config currency).
          inherited_currency = stripe_catalog_currency(OT.billing_config.region)

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

            plan = upsert_plan_from_config(plan_id, plan_def, nil, currency_override: inherited_currency)
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
        # Price-less plans (free tier) are delegated to #upsert_config_only_plans
        # so both the Stripe-sync path (Pull) and this fallback path produce the
        # same catalog. See that method for the show_on_plans_page gate and the
        # region-inheritance rule that priced plans don't get.
        #
        # Uses ConfigResolver to load from spec/billing.test.yaml in test environment.
        #
        # @param clear_first [Boolean] Whether to clear existing cache before loading (default: true)
        # @return [Integer] Number of plans loaded into Redis, priced plans plus
        #   config-only plans
        def load_all_from_config(clear_first: true)
          plans_hash = OT.billing_config.plans
          return 0 if plans_hash.empty?

          # Clear existing cache if requested
          Billing::Plan.clear_cache if clear_first

          plans_count = 0

          plans_hash.each do |plan_key, plan_def|
            prices_list = plan_def['prices'] || []

            # Price-less plans are handled by upsert_config_only_plans below.
            # Checked before the region filter so a config-only plan that omits
            # `region` isn't logged as a region skip here and then loaded there.
            next if prices_list.empty?

            # Skip plans not matching the configured region
            configured_region = OT.billing_config.region
            plan_region       = Billing::RegionNormalizer.normalize(plan_def['region'])
            unless Billing::RegionNormalizer.match?(plan_region, configured_region)
              OT.ld "[ConfigLoader] Skipping plan for region #{plan_region}: #{plan_key}"
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

          # Config-only plans belong in the catalog too: entitlement
          # materialization and the plans page both read from it. Without this
          # the free tier would exist after a Stripe sync (Pull calls
          # upsert_config_only_plans) but vanish whenever Stripe is unreachable
          # and boot falls back to this method.
          plans_count += upsert_config_only_plans

          # Rebuild price ID cache after loading
          PlanPersister.rebuild_stripe_price_id_cache

          OT.li "[ConfigLoader] Cached #{plans_count} plans from config"
          plans_count
        end

        # Currency carried by already-persisted Stripe-sourced plans for a region
        #
        # Stripe-sourced plans are identified by a non-empty stripe_product_id
        # (config-loaded plans never have one). Inactive (pruned) plans and
        # plans from other regions are ignored.
        #
        # The point of inheriting is that one pricing grid renders one
        # currency, and the grid only renders plans marked show_on_plans_page
        # (see BillingController#list_plans). So visible plans decide the
        # currency; hidden ones are consulted only when nothing is visible,
        # where matching the Stripe catalog still beats the config default.
        #
        # When the deciding plans carry mixed currencies the most common one
        # wins, ties broken alphabetically so the choice cannot flap between
        # boots with Redis key order. Mixed currencies mean the Stripe catalog
        # itself is incoherent, so a warning is logged for the operator.
        #
        # @param region [String, nil] Deployment region to match
        # @return [String, nil] Inherited currency, or nil when no
        #   Stripe-sourced plan exists in the cache
        def stripe_catalog_currency(region)
          stripe_plans = Billing::Plan.list_plans.select do |plan|
            !plan.stripe_product_id.to_s.empty? &&
              plan.active.to_s == 'true' &&
              Billing::RegionNormalizer.match?(plan.region, region)
          end

          visible    = stripe_plans.select { |plan| plan.show_on_plans_page.to_s == 'true' }
          currencies = named_currencies(visible)
          # Fall back on the currency, not on the plan: a visible set that
          # carries no currency at all decides nothing.
          currencies = named_currencies(stripe_plans) if currencies.empty?

          return nil if currencies.empty?

          distinct = currencies.uniq
          return distinct.first if distinct.size == 1

          tallies = currencies.tally
          chosen  = tallies.min_by { |currency, count| [-count, currency] }.first
          OT.lw '[ConfigLoader] Stripe-sourced plans carry mixed currencies for region; ' \
                'using most common (ties broken alphabetically)',
            {
              region: region,
              currencies: tallies,
              chosen: chosen,
            }
          chosen
        end

        # Non-empty currencies carried by the given plans
        #
        # @param plans [Array<Billing::Plan>]
        # @return [Array<String>]
        def named_currencies(plans)
          plans.filter_map do |plan|
            currency = plan.currency.to_s
            currency.empty? ? nil : currency
          end
        end

        # Upsert a single plan from config definition
        #
        # @param plan_id [String] Plan identifier
        # @param plan_def [Hash] Plan definition from YAML
        # @param prices_list [Array, nil] List of price definitions, or nil for config-only plans
        # @param currency_override [String, nil] Currency inherited from Stripe-sourced
        #   siblings; outranks the config default everywhere a currency is
        #   written, and yields only to a currency the price row states itself
        # @return [Billing::Plan, nil] The upserted plan or nil on failure
        # rubocop:disable Metrics/PerceivedComplexity
        def upsert_plan_from_config(plan_id, plan_def, prices_list, currency_override: nil)
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
          family_currency = currency_override || OT.billing_config.currency

          if prices_list && !prices_list.empty?
            prices_list.each do |price|
              interval       = price['interval'].to_sym # :month or :year
              plan_currency  = price['currency'] || currency_override || OT.billing_config.currency

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
            # No caller combines an override with price rows today
            # (upsert_config_only_plans only handles `prices: []`, and
            # load_all_from_config passes no override), so this is a coherence
            # guard, not a live path: an inherited currency must not be
            # downgraded to the config default just because a price row is
            # silent about its own. The price rows above follow the same
            # precedence, since the plans page reads currency off the price
            # row, not off the plan.
            family_currency = prices_list.first['currency'] || currency_override || OT.billing_config.currency
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

          # Populate prices hashkey with JSON per interval.
          #
          # The guard is deliberate: Pull calls upsert_config_only_plans AFTER
          # sync_from_stripe, so a config-only upsert must not touch prices that
          # Stripe just wrote for the same plan_id. Clearing unconditionally
          # would wipe live price data on every catalog pull whenever a Stripe
          # product's plan_id metadata matches a plan declared `prices: []`.
          #
          # Trade-off: a plan that keeps an orphaned prices hash (e.g. its Stripe
          # product was pruned) is then served as a priced plan by the plans
          # page. That's cosmetic and recoverable with
          # `bin/ots billing catalog sync --clear`; a wiped price is not.
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
