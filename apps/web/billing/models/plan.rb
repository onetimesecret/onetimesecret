# apps/web/billing/models/plan.rb
#
# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength

require 'stripe'
require_relative '../metadata'
require_relative '../config'
require_relative '../region_normalizer'
require_relative '../operations/catalog/metadata_validator'

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
  # Plan IDs are family-based (unsuffixed), e.g., `identity_plus_v1`.
  # Each Plan stores multiple interval variants in a nested `prices` structure:
  #   plan.prices['month']  # => JSON string of { stripe_price_id: '...', amount: 999, ... }
  #   plan.prices['year']   # => JSON string of { stripe_price_id: '...', amount: 9999, ... }
  #
  # ## Data Storage
  #
  # Uses Familia v2 native data types for performance:
  # - `set :entitlements` - O(1) membership checks (create_secrets, custom_domains, etc.)
  # - `set :features` - Marketing features (unique, unordered)
  # - `hashkey :limits` - Resource quotas with flattened keys
  # - `stringkey :stripe_data_snapshot` - Cached Stripe Product+Price JSON
  # - `hashkey :prices` - Interval-keyed price data (month/year)
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

    identifier_field :plan_id    # Family ID (unsuffixed, e.g., "identity_plus_v1")

    # Plan entry fields (family-level)
    field :plan_id                  # Family ID (unsuffixed, e.g., "identity_plus_v1")
    field :stripe_product_id        # Stripe Product ID (prod_xxx)
    field :stripe_updated_at        # Stripe's updated timestamp (for idempotency)
    field :name                     # Product name
    field :tier                     # e.g., 'single_team', 'multi_team'
    field :currency                 # 'cad', 'eur', etc. (from product metadata)
    field :region                   # EU, CA, US, NZ, etc
    field :tenancy                  # One of: multitenant, dedicated
    field :display_order            # Display ordering (higher = earlier)
    field :show_on_plans_page       # Boolean: whether to show on plans page
    field :description              # Plan description for display
    field :is_soft_deleted          # Boolean: soft-deleted in Stripe
    field :plan_code                # Deduplication key (e.g., "identity_plus" for monthly+yearly variants)
    field :is_popular               # Boolean: show "Most Popular" badge
    field :plan_name_label          # Display label next to plan name (e.g., "For Teams")
    field :includes_plan            # Plan ID this plan includes (for "Includes everything in X" display)
    field :active                   # Boolean: whether any price is available for new subscriptions

    # Cache management
    field :last_synced_at           # Timestamp of last Stripe sync

    # Class-level timestamp for O(1) catalog freshness checks
    # Key: billing_plan:catalog_synced_at (via Familia)
    # Uses json_string to preserve Float type (Familia.now returns Float)
    class_json_string :catalog_synced_at, default_expiration: Billing::Config::CATALOG_TTL

    set :entitlements
    set :features
    hashkey :limits
    hashkey :prices                  # Interval-keyed price data (JSON per interval)
    stringkey :stripe_data_snapshot  # Cached Stripe Product+Price JSON for recovery

    def init
      super
      @stripe_updated_at ||= 0
      @is_soft_deleted   ||= false
      @active            ||= true
      @limits_hash         = nil  # Memoization cache
      @prices_hash         = nil  # Memoization cache
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
      @prices_hash = nil
      super
    end

    # Get prices as hash with parsed interval data
    #
    # Each interval key maps to price attributes:
    #   - stripe_price_id, amount, currency, billing_scheme, usage_type,
    #     trial_period_days, nickname, active
    #
    # @return [Hash{String => Hash}] Interval-keyed price data
    # @example
    #   plan.prices_hash['month']  # => { 'stripe_price_id' => 'price_xxx', 'amount' => 999, ... }
    #   plan.prices_hash['year']   # => { 'stripe_price_id' => 'price_yyy', 'amount' => 9999, ... }
    def prices_hash
      @prices_hash ||= begin
        raw = prices.hgetall || {}
        raw.transform_values { |json_str| JSON.parse(json_str) }
      end
    end

    # Get price data for a specific interval
    #
    # @param interval [String] 'month' or 'year'
    # @return [Hash, nil] Price attributes or nil if interval not available
    def price_for(interval)
      prices_hash[interval.to_s]
    end

    # List all available intervals for this plan
    #
    # @return [Array<String>] Available intervals (e.g., ['month', 'year'])
    def available_intervals
      prices_hash.keys
    end

    # Get all Stripe price IDs for this plan
    #
    # @return [Array<String>] List of Stripe price IDs across all intervals
    def all_stripe_price_ids
      prices_hash.values.map { |p| p['stripe_price_id'] }.compact
    end

    # Check if plan should show "Most Popular" badge
    #
    # is_popular is stored as a string ('true'/'false') in Redis.
    # Must explicitly check for 'true' string value.
    #
    # @return [Boolean] True if plan is marked as popular
    def popular?
      is_popular.to_s == 'true'
    end

    # Calculate monthly equivalent amount for display
    #
    # Uses monthly price if available, otherwise calculates from yearly price.
    # For yearly-only plans, divides the total amount by 12.
    #
    # @return [Integer] Monthly equivalent price in cents, or 0 if no prices
    def monthly_equivalent_amount
      monthly = price_for('month')
      return monthly['amount'].to_i if monthly

      yearly = price_for('year')
      return 0 unless yearly

      (yearly['amount'].to_i / 12.0).round
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
      # Validate product has all required metadata for plan creation
      #
      # Checks both key presence AND non-blank values for all required fields.
      # Returns hash with :missing (keys not present) and :blank (keys with empty values).
      #
      # @param product [Stripe::Product] The Stripe product
      # @return [Hash] { missing: [...], blank: [...] } — both empty if valid
      def validate_product_metadata(product)
        result = Operations::Catalog::MetadataValidator.validate(product)

        if result[:problems].any?
          OT.lw '[Plan.validate_product_metadata] Stripe product invalid metadata',
            {
              product_id: product.id,
              product_name: product.name,
              problems: result[:problems].join('; '),
              hint: 'Add metadata via Stripe Dashboard or `bin/ots billing products update`',
            }
        end

        { missing: result[:missing], blank: result[:blank] }
      end

      # Check if product belongs to OTS (app=onetimesecret in metadata)
      #
      # This only checks ownership, not validity. Products belonging to OTS may
      # still have invalid metadata; callers should use extract_plan_data for
      # fail-closed validation.
      #
      # @param product [Stripe::Product] The Stripe product
      # @return [Boolean] true if product has app=onetimesecret metadata
      def valid_ots_product?(product)
        product.metadata && product.metadata[Metadata::FIELD_APP] == Metadata::APP_NAME
      end

      # Check whether a Stripe product belongs to the configured region
      #
      # Returns true when no region is configured (backward-compatible pass-through).
      # When a region is configured, the product's region metadata must match case-insensitively.
      # Called by Pull operation (refresh path) and the webhook handler.
      #
      # @param product [Stripe::Product] The Stripe product
      # @return [Boolean] true if the product matches the configured region (or no region set)
      def correct_region?(product)
        Billing::RegionNormalizer.match?(
          product.metadata[Metadata::FIELD_REGION],
          Onetime.billing_config.region,
        )
      end

      # Get plan by tier, interval, and region
      #
      # Searches cached plans by tier/region fields and verifies the plan
      # has the requested interval available in its prices hash.
      # Primarily used in tests to find plans by entitlement tier.
      #
      # For production code, prefer Plan.load(plan_id) for direct O(1) lookup
      # or find_by_stripe_price_id(price_id) when resolving from Stripe data.
      #
      # @param tier [String] Entitlement tier (e.g., 'single_team', 'single_identity')
      # @param interval [String] Billing interval ('monthly' or 'yearly' or 'month' or 'year')
      # @param region [String, nil] Region code (e.g., 'EU', 'NZ') or nil when
      #   regionalization is not applicable. There is no "global" region.
      # @return [Plan, nil] Cached plan or nil if not found
      def get_plan(tier, interval, region = nil)
        # Normalize interval to singular form (monthly -> month)
        interval_str = interval.to_s.sub(/ly$/, '')

        # Search through all cached plans for matching tier/region with requested interval
        list_plans.find do |plan|
          plan.tier == tier &&
            plan.region == region &&
            plan.available_intervals.include?(interval_str)
        end
      end

      # List all cached plans
      #
      # @return [Array<Plan>] All cached plans
      def list_plans
        # Filter out plans whose Redis hashes are missing (e.g., after destroy!
        # or clear_cache) but whose instances sorted set entries persist.
        # NOTE: load_multi returns Horreum shells (not nil) for missing keys,
        # so .compact alone is insufficient. See github.com/delano/familia/issues/219
        load_multi(instances.to_a).select { |plan| plan&.exists? }
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
      # Maps all Stripe price IDs (across all intervals) to their parent Plan.
      # A Plan with both monthly and yearly prices has two cache entries.
      #
      # @return [Hash<String, Plan>] Price ID to Plan mapping
      def build_stripe_price_id_cache
        list_plans.each_with_object({}) do |plan, hash|
          plan.all_stripe_price_ids.each do |price_id|
            hash[price_id] = plan
          end
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
        # Phase 1: Destroy plans tracked in instances (cleans up associated data types)
        instances.to_a.each do |plan_id|
          plan = load(plan_id)
          plan&.destroy!
        end

        # Phase 2: Scan for orphaned plan hashes not tracked in instances.
        # These can exist if a previous sync partially failed or if
        # instances was cleared without destroying the corresponding hashes.
        scan_pattern = "#{prefix}:*:object"
        Familia.dbclient.scan_each(match: scan_pattern).each do |key|
          # Extract plan_id using prefix/suffix removal (more robust than split)
          plan_id = key.delete_prefix("#{prefix}:").delete_suffix(':object')
          next if plan_id.nil? || plan_id.empty?

          OT.ld "[Plan.clear_cache] Removing orphaned plan hash: #{plan_id}"
          begin
            plan = load(plan_id)
            plan&.destroy!
          rescue StandardError
            # Fall back to direct key deletion if load fails
            Familia.dbclient.del(key)
          end
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

      # Load a single plan from billing.yaml config
      #
      # Used as fallback when Stripe cache is empty (dev/test environments).
      # Returns an ephemeral Plan-like hash (not persisted to Redis).
      #
      # @param plan_id [String] Canonical family ID (e.g., "identity_plus_v1")
      # @return [Hash, nil] Plan hash with :name, :entitlements, :limits or nil
      def load_from_config(plan_id)
        plans_hash = Billing::Config.load_plans
        return nil if plans_hash.empty?
        return nil unless plans_hash.key?(plan_id)

        config_plan_to_hash(plan_id, plans_hash[plan_id], plans_hash)
      end

      # Load all plans from billing.yaml config
      #
      # Used as fallback when Stripe cache is empty (dev/test environments).
      # Returns one entry per plan family (unsuffixed IDs).
      #
      # @return [Array<Hash>] Array of plan hashes
      def list_plans_from_config
        plans_hash = Billing::Config.load_plans
        return [] if plans_hash.empty?

        plans_hash.map do |plan_id, plan_def|
          # Family-keyed: use plan_id directly (no interval suffix)
          config_plan_to_hash(plan_id.to_s, plan_def, plans_hash)
        end
      end

      private

      # Convert config plan definition to hash format
      #
      # @param plan_id [String] Full plan ID (with interval suffix if applicable)
      # @param plan_def [Hash] Plan definition from YAML
      # @param plans_hash [Hash] All plans hash for resolving includes_plan_name
      # @return [Hash] Normalized plan hash
      def config_plan_to_hash(plan_id, plan_def, plans_hash = {})
        # Convert limits to flattened format (e.g., "teams" -> "teams.max")
        limits = (plan_def['limits'] || {}).transform_keys { |k| "#{k}.max" }
        limits = limits.transform_values do |v|
          v.nil? || v == -1 ? 'unlimited' : v.to_s
        end

        # Resolve includes_plan_name from the referenced plan
        includes_plan      = plan_def['includes_plan']
        includes_plan_name = includes_plan && plans_hash[includes_plan] ? plans_hash[includes_plan]['name'] : nil

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
          includes_plan: includes_plan,
          includes_plan_name: includes_plan_name,
          entitlements: plan_def['entitlements'] || [],
          features: plan_def['features'] || [],
          limits: limits,
        }
      end
    end

    extend ClassMethods
  end
end
