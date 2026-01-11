# apps/web/billing/models/plan.rb
#
# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength

require 'stripe'
require_relative '../metadata'
require_relative '../config'
require_relative '../lib/stripe_circuit_breaker'

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
    prefix :billing_plan

    feature :safe_dump
    feature :expiration

    default_expiration Billing::Config::CATALOG_TTL  # Auto-expire after 12 hours

    identifier_field :plan_id    # Computed: product_interval

    # Plan entry fields
    field :plan_id                  # Computed: product_interval
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
    field :plan_code                # Deduplication key (e.g., "identity_plus" for monthly+yearly variants)
    field :is_popular               # Boolean: show "Most Popular" badge
    field :plan_name_label          # Display label next to plan name (e.g., "For Teams")

    # Additional Stripe Price fields
    field :active                   # Boolean: whether price is available for new subscriptions
    field :billing_scheme           # 'per_unit' or 'tiered'
    field :usage_type               # 'licensed' or 'metered'
    field :trial_period_days        # Trial period in days (null if none)
    field :nickname                 # Internal nickname for the price

    # Cache management
    field :last_synced_at           # Timestamp of last Stripe sync

    # Class-level timestamp for O(1) catalog freshness checks
    # Key: billing_plan:catalog_synced_at (via Familia)
    # Uses json_string to preserve Float type (Familia.now returns Float)
    class_json_string :catalog_synced_at, default_expiration: Billing::Config::CATALOG_TTL

    set :entitlements
    set :features
    hashkey :limits
    stringkey :stripe_data_snapshot, default_expiration: Billing::Config::CATALOG_TTL  # Cached Stripe Product+Price JSON for recovery

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

    # Check if plan should show "Most Popular" badge
    #
    # Familia v2 deserializes fields to JSON primitives, so is_popular
    # is already a boolean (not a string) but can still be nil.
    #
    # @return [Boolean] True if plan is marked as popular
    def popular?
      !!is_popular
    end

    # Calculate monthly equivalent amount for display
    #
    # For yearly plans, divides the total amount by 12.
    # For monthly plans, returns the amount unchanged.
    #
    # @return [Integer] Monthly equivalent price in cents
    def monthly_equivalent_amount
      amt = amount.to_i
      return amt if interval != 'year'

      (amt / 12.0).round
    end

    # Parse cached Stripe data snapshot
    #
    # @return [Hash, nil] Parsed snapshot or nil if not available
    def parsed_stripe_snapshot
      snapshot = stripe_data_snapshot.value
      return nil if snapshot.nil? || snapshot.empty?

      JSON.parse(snapshot)
    rescue JSON::ParserError => ex
      Onetime.billing_logger.error 'Failed to parse stripe_data_snapshot',
        {
          plan_id: plan_id,
          error: ex.message,
        }
      nil
    end

    module ClassMethods
      # Required metadata keys for OTS products (app check is separate)
      # Note: 'interval' comes from the price object, not product metadata
      REQUIRED_PRODUCT_METADATA = %w[tier region].freeze

      # Validate product has all required metadata for plan creation
      #
      # @param product [Stripe::Product] The Stripe product
      # @return [Array<String>] List of missing keys (empty if valid)
      def validate_product_metadata(product)
        metadata = product.metadata || {}
        missing  = REQUIRED_PRODUCT_METADATA - metadata.keys.map(&:to_s)

        if missing.any?
          OT.lw '[Plan.validate_product_metadata] Product missing required metadata',
            {
              product_id: product.id,
              product_name: product.name,
              missing_keys: missing.join(', '),
            }
        end

        missing
      end

      # Check if product is a valid OTS product with all required metadata
      #
      # @param product [Stripe::Product] The Stripe product
      # @return [Boolean] true if valid OTS product
      def valid_ots_product?(product)
        return false unless product.metadata && product.metadata[Metadata::FIELD_APP] == Metadata::APP_NAME

        missing = validate_product_metadata(product)
        missing.empty?
      end

      # Refresh plan cache from Stripe API
      #
      # Fetches all active products and prices from Stripe, filters by app metadata,
      # and caches them in Redis with computed plan IDs.
      #
      # ## Consistency Guarantee
      #
      # This method uses an upsert pattern to ensure catalog availability:
      # 1. **Fetch phase**: All Stripe data is fetched and validated in memory first
      # 2. **Upsert phase**: Each plan is created or updated individually
      # 3. **Prune phase**: Plans not in current Stripe catalog are soft-deleted
      # 4. **Cache rebuild**: Price ID lookup cache is refreshed
      #
      # The catalog is NEVER cleared during sync, eliminating the empty-window
      # race condition that occurred with the previous clear-then-rebuild pattern.
      # If Stripe API fails during fetch, no cache modifications occur.
      #
      # @param progress [Proc, nil] Optional progress callback (called with status messages)
      # @return [Integer] Number of plans synced
      # @raise [Stripe::StripeError] If Stripe API call fails during fetch phase
      # @raise [Billing::CircuitOpenError] If circuit breaker is open
      def refresh_from_stripe(progress: nil)
        # Skip Stripe sync in CI/test environments without API key
        stripe_key = Onetime.billing_config.stripe_key
        if stripe_key.to_s.strip.empty?
          OT.lw '[Plan.refresh_from_stripe] Skipping Stripe sync: No API key configured'
          return 0
        end

        OT.li '[Plan.refresh_from_stripe] Starting Stripe sync (upsert pattern)'

        # PHASE 1: Fetch all data from Stripe into memory
        # No Redis writes occur during this phase
        # Circuit breaker protects against cascade failures during Stripe outages
        plan_data_list = Billing::StripeCircuitBreaker.call do
          collect_stripe_plans(progress: progress)
        end

        if plan_data_list.empty?
          OT.lw '[Plan.refresh_from_stripe] No valid plans fetched from Stripe'
          return 0
        end

        progress&.call("Upserting #{plan_data_list.size} plans...")

        # PHASE 2: Upsert all plans (NO clear_cache!)
        # Each plan is created or updated individually, ensuring the catalog
        # is never empty during sync
        upserted_ids = []
        plan_data_list.each do |plan_data|
          plan = upsert_from_stripe_data(plan_data)
          upserted_ids << plan.plan_id
        end

        # PHASE 3: Prune stale plans not in current Stripe catalog
        # Soft-deletes plans that are no longer active in Stripe
        pruned_count = prune_stale_plans(upserted_ids)

        # PHASE 4: Rebuild lookup cache for O(1) price_id lookups
        rebuild_stripe_price_id_cache

        # PHASE 5: Update global sync timestamp for O(1) freshness checks
        update_catalog_sync_timestamp

        OT.li "[Plan.refresh_from_stripe] Synced #{upserted_ids.size} plans, pruned #{pruned_count}"
        upserted_ids.size
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
        # Ensure Stripe API key is configured (required for console/CLI usage
        # where StripeSetup initializer may not have run)
        ensure_stripe_configured!

        # Fetch all active products with onetimesecret metadata
        products = Stripe::Product.list(
          {
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

          # Skip products that aren't valid OTS products (wrong app or missing required metadata)
          unless valid_ots_product?(product)
            OT.ld '[Plan.collect_stripe_plans] Skipping invalid product',
              {
                product_id: product.id,
                product_name: product.name,
                app: product.metadata[Metadata::FIELD_APP],
              }
            next
          end

          # Fetch all active prices for this product
          prices = Stripe::Price.list(
            {
              product: product.id,
              active: true,
              limit: 100,
            },
          )

          prices.auto_paging_each do |price|
            # Skip non-recurring prices
            next unless price.type == 'recurring'

            plan_data = extract_plan_data(product, price)
            next if plan_data.nil? # Skip if metadata validation failed

            plan_data_list << plan_data

            OT.ld "[Plan.collect_stripe_plans] Collected plan: #{plan_data[:plan_id]}",
              {
                stripe_price_id: price.id,
                amount: price.unit_amount,
              }
          end
        end

        OT.li "[Plan.collect_stripe_plans] Collected #{plan_data_list.size} plans from Stripe"
        plan_data_list
      end

      public

      # Extracts plan data from Stripe product and price objects
      #
      # @param product [Stripe::Product] Stripe product object
      # @param price [Stripe::Price] Stripe price object
      # @return [Hash, nil] Plan data ready for persistence, or nil if validation fails
      def extract_plan_data(product, price)
        # Early return if missing required metadata
        missing = validate_product_metadata(product)
        if missing.any?
          OT.le '[Plan.extract_plan_data] Cannot extract plan data - missing metadata',
            {
              product_id: product.id,
              missing_keys: missing,
            }
          return nil
        end

        interval = price.recurring.interval # 'month' or 'year'
        tier     = product.metadata[Metadata::FIELD_TIER]
        region   = product.metadata[Metadata::FIELD_REGION]

        # Use explicit plan_id from metadata with interval appended, or fall back to tier
        base_plan_id = product.metadata[Metadata::FIELD_PLAN_ID] || tier
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

        # Extract plan_code from product metadata (used to group monthly/yearly variants)
        plan_code = product.metadata[Metadata::FIELD_PLAN_CODE]

        # Extract is_popular from product metadata (default to 'false')
        is_popular_value = product.metadata[Metadata::FIELD_IS_POPULAR] || 'false'
        is_popular       = %w[true 1 yes].include?(is_popular_value.to_s.downcase)

        # Extract plan_name_label from product metadata (nil if not set or empty)
        plan_name_label_raw = product.metadata[Metadata::FIELD_PLAN_NAME_LABEL]
        plan_name_label     = plan_name_label_raw.to_s.strip.empty? ? nil : plan_name_label_raw

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
          stripe_updated_at: product.updated.to_s, # Unix timestamp for stale update detection
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
          plan_code: plan_code,
          is_popular: is_popular.to_s,
          plan_name_label: plan_name_label,
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

      # Upsert single plan from Stripe data
      #
      # Creates a new plan if it doesn't exist, or updates an existing one.
      # This pattern avoids the empty catalog window that occurs with clear+rebuild.
      #
      # @param plan_data [Hash] Plan data from extract_plan_data or webhook payload
      # @return [Plan] The upserted plan instance
      def upsert_from_stripe_data(plan_data)
        plan_id = plan_data[:plan_id]

        # Load existing or create new - handle expired entries gracefully
        existing = begin
          loaded = load(plan_id)
          loaded if loaded&.exists?
        rescue Familia::NoIdentifier
          # Plan key expired but instances entry persisted - treat as new
          nil
        end

        # Check for stale update (out-of-order webhook delivery)
        # Only skip if BOTH timestamps are valid (> 0)
        if existing && plan_data[:stripe_updated_at]
          incoming_updated = plan_data[:stripe_updated_at].to_i
          existing_updated = existing.stripe_updated_at.to_i

          if incoming_updated > 0 && existing_updated > 0 && incoming_updated <= existing_updated
            OT.ld "[Plan.upsert_from_stripe_data] Skipping stale update for #{plan_id} " \
                  "(incoming: #{incoming_updated}, existing: #{existing_updated})"
            return existing
          end
        end

        plan = existing || new(plan_id: plan_id)

        # Apply scalar fields from plan_data
        plan.stripe_price_id    = plan_data[:stripe_price_id]
        plan.stripe_product_id  = plan_data[:stripe_product_id]
        plan.name               = plan_data[:name]
        plan.tier               = plan_data[:tier]
        plan.interval           = plan_data[:interval]
        plan.amount             = plan_data[:amount]
        plan.currency           = plan_data[:currency]
        plan.region             = plan_data[:region]
        plan.tenancy            = plan_data[:tenancy]
        plan.display_order      = plan_data[:display_order]
        plan.show_on_plans_page = plan_data[:show_on_plans_page]
        plan.description        = plan_data[:description]
        plan.plan_code          = plan_data[:plan_code]
        plan.is_popular         = plan_data[:is_popular]
        plan.plan_name_label    = plan_data[:plan_name_label]
        plan.active             = plan_data[:active]
        plan.billing_scheme     = plan_data[:billing_scheme]
        plan.usage_type         = plan_data[:usage_type]
        plan.trial_period_days  = plan_data[:trial_period_days]
        plan.nickname           = plan_data[:nickname]
        plan.last_synced_at     = Time.now.to_i.to_s

        # Store stripe_updated_at for future stale update comparison
        plan.stripe_updated_at  = plan_data[:stripe_updated_at] || Time.now.to_i.to_s

        # Clear and repopulate entitlements set
        plan.entitlements.clear
        plan_data[:entitlements]&.each { |ent| plan.entitlements.add(ent) }

        # Clear and repopulate features set
        plan.features.clear
        plan_data[:features]&.each { |feat| plan.features.add(feat) }

        # Clear and repopulate limits hashkey with flattened keys
        plan.limits.clear
        plan_data[:limits]&.each do |resource, value|
          key              = "#{resource}.max"
          val              = value == -1 ? 'unlimited' : value.to_s
          plan.limits[key] = val
        end

        # Store Stripe data snapshot for recovery
        if plan_data[:stripe_snapshot]
          plan.stripe_data_snapshot.value = plan_data[:stripe_snapshot].to_json
        end

        plan.save

        action = existing ? 'Updated' : 'Created'
        OT.ld "[Plan.upsert_from_stripe_data] #{action} plan: #{plan_id}"

        plan
      end

      # Remove plans not in current Stripe catalog
      #
      # Uses soft-delete pattern - marks plans as inactive rather than destroying.
      # Handles expired entries gracefully by removing orphaned instances entries.
      #
      # @param current_plan_ids [Array<String>] Plan IDs currently in Stripe catalog
      # @return [Integer] Number of plans marked stale or cleaned up
      def prune_stale_plans(current_plan_ids)
        all_cached_ids = instances.to_a
        stale_ids      = all_cached_ids - current_plan_ids
        pruned_count   = 0

        stale_ids.each do |plan_id|
          plan = load(plan_id)

          if plan&.exists?
            # Plan exists in Redis - soft-delete by marking inactive
            plan.active         = 'false'
            plan.last_synced_at = Time.now.to_i.to_s
            plan.save
            OT.li "[Plan.prune_stale_plans] Marked stale: #{plan_id}"
            pruned_count       += 1
          else
            # Plan key expired - just remove orphaned instances entry
            instances.remove(plan_id)
            OT.ld "[Plan.prune_stale_plans] Removed expired entry: #{plan_id}"
            pruned_count += 1
          end
        rescue Familia::NoIdentifier => _ex
          # Object expired but load returned something invalid - clean up instances
          instances.remove(plan_id)
          OT.ld "[Plan.prune_stale_plans] Cleaned orphan entry: #{plan_id}"
          pruned_count += 1
        rescue StandardError => ex
          # Always clean up orphan entry on unexpected errors to prevent stale references
          instances.remove(plan_id)
          OT.le '[Plan.prune_stale_plans] Error processing stale plan (cleaned orphan)',
            {
              plan_id: plan_id,
              error: ex.message,
            }
        end

        OT.li "[Plan.prune_stale_plans] Pruned #{pruned_count} stale plans" if pruned_count.positive?
        pruned_count
      end

      # Get plan by tier, interval, and region
      #
      # Searches cached plans by tier/interval/region fields instead of
      # direct plan_id lookup. Primarily used in tests to find plans by
      # entitlement tier without knowing exact product names.
      #
      # For production code, prefer Plan.load(plan_id) for direct O(1) lookup
      # or find_by_stripe_price_id(price_id) when resolving from Stripe data.
      #
      # @param tier [String] Entitlement tier (e.g., 'single_team', 'single_identity')
      # @param interval [String] Billing interval ('monthly' or 'yearly')
      # @param region [String] Region code (e.g., 'EU', 'global')
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
        # Filter out nil entries from expired plans (instances entry exists but hash expired)
        load_multi(instances.to_a).compact
      end

      # Find plan by Stripe price ID
      #
      # Uses a cached hash lookup for O(1) performance instead of
      # iterating through all plans on every call.
      #
      # @param price_id [String] Stripe price ID (e.g., "price_xxx")
      # @return [Plan, nil] Plan instance or nil if not found
      def find_by_stripe_price_id(price_id)
        return nil if price_id.nil? || price_id.empty?

        stripe_price_id_cache[price_id]
      end

      # Build and cache price_id to plan hash
      #
      # Lazily builds a hash mapping Stripe price IDs to Plan instances.
      # Cache is invalidated when plans are refreshed.
      #
      # @return [Hash<String, Plan>] Price ID to Plan mapping
      def stripe_price_id_cache
        @stripe_price_id_cache ||= build_stripe_price_id_cache
      end

      # Rebuild the price ID cache
      #
      # Called after plan refresh to ensure cache is up to date.
      #
      # @return [Hash<String, Plan>] Rebuilt cache
      def rebuild_stripe_price_id_cache
        @stripe_price_id_cache = build_stripe_price_id_cache
      end

      private

      # Ensure Stripe API key is configured
      #
      # In web/app context, StripeSetup initializer handles this.
      # In console/CLI context, this ensures Stripe is configured before API calls.
      #
      # @raise [Stripe::AuthenticationError] If no API key is available
      def ensure_stripe_configured!
        return if Stripe.api_key && !Stripe.api_key.to_s.strip.empty?

        stripe_key = Onetime.billing_config.stripe_key
        if stripe_key && !stripe_key.to_s.strip.empty?
          Stripe.api_key     = stripe_key
          Stripe.api_version = Onetime.billing_config.stripe_api_version
          OT.ld '[Plan.ensure_stripe_configured!] Configured Stripe API key',
            {
              key_prefix: stripe_key[0..7],
            }
        else
          OT.le '[Plan.ensure_stripe_configured!] No Stripe API key available'
          raise Stripe::AuthenticationError, 'No Stripe API key available. Check billing configuration.'
        end
      end

      # Build price_id to plan hash from current plan list
      #
      # @return [Hash<String, Plan>] Price ID to Plan mapping
      def build_stripe_price_id_cache
        list_plans.each_with_object({}) do |plan, hash|
          next unless plan&.stripe_price_id

          hash[plan.stripe_price_id] = plan
        end
      end

      public

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
        @stripe_price_id_cache = nil
        catalog_synced_at.delete!
      end

      # Get the last successful catalog sync timestamp
      #
      # Returns the Unix timestamp of the last successful Stripe sync,
      # or nil if no sync has occurred. Uses class_json_string for O(1)
      # lookup instead of loading all plans.
      #
      # @return [Integer, nil] Unix timestamp (truncated from Float) or nil
      def catalog_last_synced_at
        catalog_synced_at.to_i if catalog_synced_at.exists?
      end

      # Update the global catalog sync timestamp
      #
      # Called after successful Stripe sync to record when the catalog
      # was last refreshed. Stores Familia.now (Float) with JSON serialization
      # to preserve type. TTL set via default_expiration.
      #
      def update_catalog_sync_timestamp
        catalog_synced_at.value = Familia.now
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
              stripe_price_id: price.key?('price_id') ? price['price_id'] : nil,
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
            plan.plan_code         = plan_def['plan_code']
            plan.is_popular        = (plan_def['is_popular'] == true).to_s
            plan.plan_name_label   = plan_def['plan_name_label']
            plan.last_synced_at    = Time.now.to_i.to_s

            # Add entitlements to set
            plan.entitlements.clear
            entitlements_list.each { |ent| plan.entitlements.add(ent) }

            # Add features to set (i18n locale keys for UI display)
            features_list = plan_def['features'] || []
            plan.features.clear
            features_list.each { |feat| plan.features.add(feat) }

            # Add limits to hashkey
            plan.limits.clear
            limits_hash.each do |key, val|
              plan.limits[key] = val
            end

            # No stripe_data_snapshot for config-based plans
            plan.stripe_data_snapshot.value = nil

            plan.save

            OT.ld "[Plan.load_all_from_config] Cached plan: #{plan_id}",
              {
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
          plan_code: plan_def['plan_code'],
          is_popular: plan_def['is_popular'] == true,
          plan_name_label: plan_def['plan_name_label'],
          entitlements: plan_def['entitlements'] || [],
          features: plan_def['features'] || [],
          limits: limits,
        }
      end
    end

    extend ClassMethods
  end
end
