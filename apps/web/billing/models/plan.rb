# apps/web/billing/models/plan.rb
#
# frozen_string_literal: true

require 'stripe'
require_relative '../metadata'
require_relative '../config'

module Billing
  unless defined?(RECORD_LIMIT)
    # Maximum number of active Stripe products to retrieve at one time.
    # Stripe's API maximum is 100. Using maximum to minimize API calls.
    RECORD_LIMIT = 100
  end

  # Plan - Stripe Product + Price Plan Cache
  #
  # Caches Stripe product/price information in Redis for fast lookups.
  # Combines Product metadata with Price data for application convenience.
  # Refreshes from Stripe API via webhooks or on demand.
  #
  # ## Stripe Product Metadata Requirements
  #
  # Products must include metadata for filtering and organization:
  #
  #   {
  #     "app": "onetimesecret",
  #     "plan_id": "identity_plus_v1",
  #     "tier": "single_team",
  #     "region": "EU",
  #     "entitlements": "api_access,custom_domains,manage_teams",
  #     "limit_teams": "1",
  #     "limit_members_per_team": "-1"
  #   }
  #
  # ## Plan ID Format
  #
  # Plan IDs combine tier, interval, and region:
  #   - single_team_monthly_us_east
  #   - multi_team_yearly_eu_west
  #
  # ## Data Storage
  #
  # Uses Familia v2 native data types for performance:
  # - `set :entitlements` - O(1) membership checks (create_secrets, custom_domains, etc.)
  # - `set :features` - Marketing features (unique, unordered)
  # - `hashkey :limits` - Resource quotas with flattened keys
  # - `stringkey :stripe_data_snapshot` - Cached Stripe Product+Price JSON (12hr TTL)
  #
  # Limits use flattened keys to support future expansion:
  #   - "teams.max" => "1" (allows adding "teams.min", "teams.default" later)
  #   - "members_per_team.max" => "unlimited" (converted to Float::INFINITY)
  #
  # The stripe_data_snapshot enables recovery without re-syncing from Stripe API
  # if parsing logic changes or bugs are fixed.
  #
  class Plan < Familia::Horreum
    using Familia::Refinements::TimeLiterals

    prefix :billing_plan

    feature :safe_dump
    feature :expiration

    default_expiration 12.hour      # Auto-expire after 12 hours

    identifier_field :plan_id    # Computed: tier_interval_region

    # Plan entry fields
    field :plan_id                  # Computed: tier_interval_region (identifier)
    field :stripe_price_id          # Stripe Price ID (price_xxx)
    field :stripe_product_id        # Stripe Product ID (prod_xxx)
    field :stripe_updated_at        # Stripe's updated timestamp (for idempotency)
    field :name                     # Product name
    field :tier                     # e.g., 'single_team', 'multi_team'
    field :interval                 # 'month' or 'year'
    field :amount                   # Price in cents
    field :currency                 # 'usd', 'eur', etc.
    field :region                   # EU, CA, US, NZ, etc
    field :tenancy                  # One of: multitenant, dedicated
    field :display_order            # Display ordering (higher = earlier)
    field :show_on_plans_page       # Boolean: whether to show on plans page
    field :description              # Plan description for display
    field :is_soft_deleted          # Boolean: soft-deleted in Stripe

    # Additional Stripe Price fields
    field :active                   # Boolean: whether price is available for new subscriptions
    field :billing_scheme           # 'per_unit' or 'tiered'
    field :usage_type               # 'licensed' or 'metered'
    field :trial_period_days        # Trial period in days (null if none)
    field :nickname                 # Internal nickname for the price

    # Cache management
    field :last_synced_at           # Timestamp of last Stripe sync

    set :entitlements
    set :features
    hashkey :limits
    stringkey :stripe_data_snapshot, default_expiration: 12.hour  # Cached Stripe Product+Price JSON for recovery

    def init
      super
      @stripe_updated_at ||= 0
      @is_soft_deleted   ||= false
      @active            ||= true
      @limits_hash         = nil  # Memoization cache
    end

    # Get limits as hash with infinity conversion
    #
    # Flattened keys format: "teams.max" => "5", "members_per_team.max" => "unlimited"
    # This format supports future expansion (e.g., "teams.min", "teams.default")
    #
    # @return [Hash] Limits with integers and Float::INFINITY for unlimited resources
    # @example
    #   plan.limits_hash  # => {"teams.max" => 1, "members_per_team.max" => Float::INFINITY}
    def limits_hash
      @limits_hash ||= begin
        # HashKey.hgetall returns Hash
        hash = limits.hgetall || {}
        hash.transform_values do |v|
          v == 'unlimited' ? Float::INFINITY : v.to_i
        end
      end
    end

    # Clear memoization cache when plan is reloaded
    def reload
      @limits_hash = nil
      super
    end

    # Parse cached Stripe data snapshot
    #
    # @return [Hash, nil] Parsed snapshot or nil if not available
    def parsed_stripe_snapshot
      snapshot = stripe_data_snapshot.value
      return nil if snapshot.nil? || snapshot.empty?

      JSON.parse(snapshot)
    rescue JSON::ParserError => ex
      Onetime.billing_logger.error 'Failed to parse stripe_data_snapshot', {
        plan_id: plan_id,
        error: ex.message,
      }
      nil
    end

    class << self
      # Refresh plan cache from Stripe API
      #
      # Fetches all active products and prices from Stripe, filters by app metadata,
      # and caches them in Redis with computed plan IDs.
      #
      # ## Consistency Guarantee
      #
      # This method uses a "collect-then-write" pattern to minimize inconsistency:
      # 1. **Fetch phase**: All Stripe data is fetched and validated in memory first
      # 2. **Write phase**: Only after all data is collected, plans are saved to Redis
      #
      # If Stripe API fails during the fetch phase, no cache modifications occur.
      # If a write fails mid-save, previously cached plans remain valid (12-hour TTL),
      # and the next refresh attempt will overwrite them.
      #
      # @param progress [Proc, nil] Optional progress callback (called with status messages)
      # @return [Integer] Number of plans cached
      # @raise [Stripe::StripeError] If Stripe API call fails during fetch phase
      def refresh_from_stripe(progress: nil)
        # Skip Stripe sync in CI/test environments without API key
        stripe_key = Onetime.billing_config.stripe_key
        if stripe_key.to_s.strip.empty?
          OT.lw '[Plan.refresh_from_stripe] Skipping Stripe sync: No API key configured'
          return 0
        end

        OT.li '[Plan.refresh_from_stripe] Starting Stripe sync (collect-then-write)'

        # PHASE 1: Fetch all data from Stripe into memory
        # No Redis writes occur during this phase
        plan_data_list = collect_stripe_plans(progress: progress)

        if plan_data_list.empty?
          OT.lw '[Plan.refresh_from_stripe] No valid plans fetched from Stripe'
          return 0
        end

        progress&.call("Writing #{plan_data_list.size} plans to cache...")

        # PHASE 2: Write all collected plans to Redis
        # This happens only after all Stripe API calls succeeded
        items_count = persist_collected_plans(plan_data_list)

        OT.li "[Plan.refresh_from_stripe] Cached #{items_count} plans"
        items_count
      end

      private

      # Fetches all plan data from Stripe API into memory
      #
      # No Redis writes occur during this phase. If any Stripe API call fails,
      # the exception propagates up and no cache modifications happen.
      #
      # @param progress [Proc, nil] Optional progress callback
      # @return [Array<Hash>] Array of plan data hashes ready for persistence
      # @raise [Stripe::StripeError] If any Stripe API call fails
      def collect_stripe_plans(progress: nil)
        # Fetch all active products with onetimesecret metadata
        products = Stripe::Product.list({
          active: true,
          limit: RECORD_LIMIT,
        },
                                       )

        plan_data_list     = []
        products_processed = 0

        progress&.call('Fetching products from Stripe...')

        products.auto_paging_each do |product|
          products_processed += 1
          progress&.call("Processing product #{products_processed}: #{product.name[0..40]}...") if products_processed == 1 || products_processed % 5 == 0

          # Skip products without required metadata
          unless product.metadata[Metadata::FIELD_APP] == Metadata::APP_NAME
            OT.ld '[Plan.collect_stripe_plans] Skipping product (not onetimesecret app)', {
              product_id: product.id,
              product_name: product.name,
              app: product.metadata[Metadata::FIELD_APP],
            }
            next
          end

          unless product.metadata[Metadata::FIELD_TIER]
            OT.lw '[Plan.collect_stripe_plans] Skipping product (missing tier)', {
              product_id: product.id,
              product_name: product.name,
            }
            next
          end

          unless product.metadata[Metadata::FIELD_REGION]
            OT.lw '[Plan.collect_stripe_plans] Skipping product (missing region)', {
              product_id: product.id,
              product_name: product.name,
            }
            next
          end

          # Fetch all active prices for this product
          prices = Stripe::Price.list({
            product: product.id,
            active: true,
            limit: 100,
          },
                                     )

          prices.auto_paging_each do |price|
            # Skip non-recurring prices
            next unless price.type == 'recurring'

            plan_data = extract_plan_data(product, price)
            plan_data_list << plan_data

            OT.ld "[Plan.collect_stripe_plans] Collected plan: #{plan_data[:plan_id]}", {
              stripe_price_id: price.id,
              amount: price.unit_amount,
            }
          end
        end

        OT.li "[Plan.collect_stripe_plans] Collected #{plan_data_list.size} plans from Stripe"
        plan_data_list
      end

      # Extracts plan data from Stripe product and price objects
      #
      # @param product [Stripe::Product] Stripe product object
      # @param price [Stripe::Price] Stripe price object
      # @return [Hash] Plan data ready for persistence
      def extract_plan_data(product, price)
        interval = price.recurring.interval # 'month' or 'year'
        tier     = product.metadata[Metadata::FIELD_TIER]
        region   = product.metadata[Metadata::FIELD_REGION]

        # Use explicit plan_id from metadata with interval appended, or compute from tier_interval_region
        base_plan_id = product.metadata[Metadata::FIELD_PLAN_ID] || "#{tier}_#{region}"
        plan_id      = "#{base_plan_id}_#{interval}ly"

        # Extract entitlements from product metadata
        entitlements_str = product.metadata[Metadata::FIELD_ENTITLEMENTS] || ''
        entitlements     = entitlements_str.split(',').map(&:strip).reject(&:empty?)

        # Extract limits from product metadata using Metadata helper
        limits = {}
        product.metadata.each do |key, value|
          key_str = key.to_s
          next unless key_str.start_with?('limit_')

          resource         = key_str.sub('limit_', '').to_sym
          limits[resource] = Metadata.normalize_limit(value)
        end

        # Extract display_order from product metadata (default to 0)
        display_order = product.metadata[Metadata::FIELD_DISPLAY_ORDER] || '0'

        # Extract tenancy from product metadata (default to 'multi')
        tenancy = product.metadata[Metadata::FIELD_TENANCY] || 'multi'

        # Extract show_on_plans_page from product metadata (default to 'true')
        show_on_plans_page_value = product.metadata[Metadata::FIELD_SHOW_ON_PLANS_PAGE] || 'true'
        show_on_plans_page       = %w[true 1 yes].include?(show_on_plans_page_value.to_s.downcase)

        # Build stripe snapshot for recovery
        stripe_snapshot = {
          product: {
            id: product.id,
            name: product.name,
            metadata: product.metadata.to_h,
            marketing_features: product.marketing_features&.map(&:name) || [],
          },
          price: {
            id: price.id,
            type: price.type,
            currency: price.currency,
            unit_amount: price.unit_amount,
            recurring: {
              interval: price.recurring.interval,
            },
          },
          cached_at: Time.now.to_i,
        }

        {
          plan_id: plan_id,
          stripe_price_id: price.id,
          stripe_product_id: product.id,
          name: product.name,
          tier: tier,
          interval: interval,
          amount: price.unit_amount.to_s,
          currency: price.currency,
          region: region,
          tenancy: tenancy,
          display_order: display_order,
          show_on_plans_page: show_on_plans_page.to_s,
          description: product.description,
          active: price.active.to_s,
          billing_scheme: price.billing_scheme,
          usage_type: price.recurring&.usage_type || 'licensed',
          trial_period_days: price.recurring&.trial_period_days&.to_s,
          nickname: price.nickname,
          entitlements: entitlements,
          features: product.marketing_features&.map(&:name) || [],
          limits: limits,
          stripe_snapshot: stripe_snapshot,
        }
      end

      # Persists collected plan data to Redis
      #
      # @param plan_data_list [Array<Hash>] Array of plan data hashes
      # @return [Integer] Number of plans successfully saved
      def persist_collected_plans(plan_data_list)
        sync_timestamp = Time.now.to_i.to_s
        saved_count    = 0

        plan_data_list.each do |data|
          plan = new(
            plan_id: data[:plan_id],
            stripe_price_id: data[:stripe_price_id],
            stripe_product_id: data[:stripe_product_id],
            name: data[:name],
            tier: data[:tier],
            interval: data[:interval],
            amount: data[:amount],
            currency: data[:currency],
            region: data[:region],
            tenancy: data[:tenancy],
            display_order: data[:display_order],
            show_on_plans_page: data[:show_on_plans_page],
            description: data[:description],
          )

          # Populate additional Stripe Price fields
          plan.active            = data[:active]
          plan.billing_scheme    = data[:billing_scheme]
          plan.usage_type        = data[:usage_type]
          plan.trial_period_days = data[:trial_period_days]
          plan.nickname          = data[:nickname]
          plan.last_synced_at    = sync_timestamp

          # Add entitlements to set (unique values)
          plan.entitlements.clear
          data[:entitlements].each { |ent| plan.entitlements.add(ent) }

          # Add features to set
          plan.features.clear
          data[:features].each { |feat| plan.features.add(feat) }

          # Add limits to hashkey with flattened keys
          plan.limits.clear
          data[:limits].each do |resource, value|
            key              = "#{resource}.max"
            val              = value == -1 ? 'unlimited' : value.to_s
            plan.limits[key] = val
          end

          # Store original Stripe data for recovery/debugging
          plan.stripe_data_snapshot.value = data[:stripe_snapshot].to_json

          plan.save

          OT.ld "[Plan.persist_collected_plans] Cached plan: #{data[:plan_id]}"
          saved_count += 1
        rescue StandardError => ex
          # Log but continue - don't let one plan failure stop others
          OT.le '[Plan.persist_collected_plans] Failed to save plan', {
            plan_id: data[:plan_id],
            error: ex.message,
          }
        end

        saved_count
      end

      public

      # Get plan by tier, interval, and region
      #
      # Searches cached plans by tier/interval/region fields instead of
      # constructing a computed plan_id. Supports metadata-based plan IDs.
      #
      # @param tier [String] plan tier (e.g., 'single_team')
      # @param interval [String] Billing interval ('monthly' or 'yearly')
      # @param region [String] Region code (e.g., 'EU')
      # @return [Plan, nil] Cached plan or nil if not found
      def get_plan(tier, interval, region = nil)
        # Normalize interval to singular form (monthly -> month)
        interval = interval.to_s.sub(/ly$/, '')

        # Search through all cached plans for matching tier/interval/region
        list_plans.find do |plan|
          plan.tier == tier &&
            plan.interval == interval &&
            plan.region == region
        end
      end

      # List all cached plans
      #
      # @return [Array<Plan>] All cached plans
      def list_plans
        load_multi(instances.to_a)
      end

      # Load a plan from Stripe cache with fallback to billing.yaml config
      #
      # Use this method when you need to load a plan from either source.
      # Centralizes the fallback pattern used across entitlement testing.
      #
      # @param plan_id [String] Plan ID to load
      # @return [Hash] Hash with :plan (Plan or nil), :config (Hash or nil), :source ('stripe' or 'local_config' or nil)
      def load_with_fallback(plan_id)
        # Try Stripe-synced cache first (production)
        stripe_plan = load(plan_id)
        return { plan: stripe_plan, config: nil, source: 'stripe' } if stripe_plan

        # Fall back to billing.yaml config (dev/standalone)
        config_plan = load_from_config(plan_id)
        return { plan: nil, config: config_plan, source: 'local_config' } if config_plan

        # Not found in either source
        { plan: nil, config: nil, source: nil }
      end

      # Clear all cached plans (for testing or forced refresh)
      def clear_cache
        instances.to_a.each do |plan_id|
          plan = load(plan_id)
          plan&.destroy!
        end
        instances.clear
      end

      # Load all plans from billing.yaml config into Redis cache
      #
      # Bypasses Stripe API and loads plans directly from YAML configuration.
      # Creates Plan instances in Redis for each plan+interval combination.
      # Uses plan_id format: "{plan_key}_{interval}ly" (e.g., "identity_plus_v1_monthly").
      #
      # Uses ConfigResolver to load from spec/billing.test.yaml in test environment.
      #
      # @param clear_first [Boolean] Whether to clear existing cache before loading (default: true)
      # @return [Integer] Number of plans loaded into Redis
      def load_all_from_config(clear_first: true)
        plans_hash = OT.billing_config.plans
        return 0 if plans_hash.empty?

        # Clear existing cache if requested
        clear_cache if clear_first

        plans_count = 0

        plans_hash.each do |plan_key, plan_def|
          prices = plan_def['prices'] || []

          # Skip plans without prices (e.g., free tier)
          if prices.empty?
            OT.ld "[Plan.load_all_from_config] Skipping plan without prices: #{plan_key}"
            next
          end

          # Create a Plan instance for each interval (monthly, yearly)
          prices.each do |price|
            interval = price['interval'] # 'month' or 'year'
            plan_id  = "#{plan_key}_#{interval}ly"

            # Extract plan attributes
            tier               = plan_def['tier']
            region             = plan_def['region'] || 'global'
            tenancy            = plan_def['tenancy'] || 'multi'
            display_order      = plan_def['display_order'] || 0
            show_on_plans_page = plan_def['show_on_plans_page'] == true
            entitlements_list  = plan_def['entitlements'] || []

            # Convert limits to flattened format (e.g., "teams" -> "teams.max")
            limits_hash = (plan_def['limits'] || {}).transform_keys { |k| "#{k}.max" }
            limits_hash = limits_hash.transform_values do |v|
              v.nil? || v == -1 ? 'unlimited' : v.to_s
            end

            # Create Plan instance
            plan = new(
              plan_id: plan_id,
              stripe_price_id: price['price_id'],  # Use price_id from config if available
              stripe_product_id: nil,
              name: plan_def['name'],
              tier: tier,
              interval: interval,
              amount: price['amount'].to_s,
              currency: price['currency'],
              region: region,
              tenancy: tenancy,
              display_order: display_order.to_s,
              show_on_plans_page: show_on_plans_page.to_s,
              description: plan_def['description'],
            )

            # Populate additional fields
            plan.active            = 'true'
            plan.billing_scheme    = 'per_unit'
            plan.usage_type        = 'licensed'
            plan.trial_period_days = nil
            plan.nickname          = nil
            plan.last_synced_at    = Time.now.to_i.to_s

            # Add entitlements to set
            plan.entitlements.clear
            entitlements_list.each { |ent| plan.entitlements.add(ent) }

            # Add features to set (empty for config-based plans)
            plan.features.clear

            # Add limits to hashkey
            plan.limits.clear
            limits_hash.each do |key, val|
              plan.limits[key] = val
            end

            # No stripe_data_snapshot for config-based plans
            plan.stripe_data_snapshot.value = nil

            plan.save

            OT.ld "[Plan.load_all_from_config] Cached plan: #{plan_id}", {
              tier: tier,
              interval: interval,
              amount: price['amount'],
              currency: price['currency'],
            }

            plans_count += 1
          end
        end

        OT.li "[Plan.load_all_from_config] Cached #{plans_count} plans from config"
        plans_count
      end

      # Load a single plan from billing.yaml config
      #
      # Used as fallback when Stripe cache is empty (dev/test environments).
      # Returns an ephemeral Plan-like hash (not persisted to Redis).
      #
      # @param plan_id [String] Plan ID (with or without interval suffix)
      # @return [Hash, nil] Plan hash with :name, :entitlements, :limits or nil
      def load_from_config(plan_id)
        plans_hash = Billing::Config.load_plans
        return nil if plans_hash.empty?

        # Try exact match first (e.g., "free_v1")
        if plans_hash.key?(plan_id)
          return config_plan_to_hash(plan_id, plans_hash[plan_id])
        end

        # Try stripping interval suffix (e.g., "identity_plus_v1_monthly" -> "identity_plus_v1")
        base_id = plan_id.sub(/_(month|year)ly$/, '')
        if plans_hash.key?(base_id)
          return config_plan_to_hash(plan_id, plans_hash[base_id])
        end

        nil
      end

      # Load all plans from billing.yaml config
      #
      # Used as fallback when Stripe cache is empty (dev/test environments).
      # Creates one entry per plan (deduped by tier, preferring monthly).
      #
      # @return [Array<Hash>] Array of plan hashes
      def list_plans_from_config
        plans_hash = Billing::Config.load_plans
        return [] if plans_hash.empty?

        plans_hash.map do |plan_id, plan_def|
          # For plans with prices, use monthly interval in the ID
          interval = plan_def['prices']&.first&.dig('interval') || 'month'
          full_id  = plan_def['prices']&.any? ? "#{plan_id}_#{interval}ly" : plan_id

          config_plan_to_hash(full_id, plan_def)
        end
      end

      private

      # Convert config plan definition to hash format
      #
      # @param plan_id [String] Full plan ID (with interval suffix if applicable)
      # @param plan_def [Hash] Plan definition from YAML
      # @return [Hash] Normalized plan hash
      def config_plan_to_hash(plan_id, plan_def)
        # Convert limits to flattened format (e.g., "teams" -> "teams.max")
        limits = (plan_def['limits'] || {}).transform_keys { |k| "#{k}.max" }
        limits = limits.transform_values do |v|
          v.nil? || v == -1 ? 'unlimited' : v.to_s
        end

        {
          planid: plan_id,
          name: plan_def['name'],
          tier: plan_def['tier'],
          tenancy: plan_def['tenancy'],
          region: plan_def['region'],
          display_order: plan_def['display_order'].to_i,
          show_on_plans_page: plan_def['show_on_plans_page'] == true,
          description: plan_def['description'],
          entitlements: plan_def['entitlements'] || [],
          limits: limits,
        }
      end
    end
  end
end
