# apps/web/billing/models/plan.rb
#
# frozen_string_literal: true

require 'stripe'
require_relative '../metadata'

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
  #     "capabilities": "create_secrets,create_team,custom_domains",
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
  # - `set :capabilities` - O(1) membership checks (create_secrets, custom_domains, etc.)
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
    field :is_soft_deleted          # Boolean: soft-deleted in Stripe

    # Additional Stripe Price fields
    field :active                   # Boolean: whether price is available for new subscriptions
    field :billing_scheme           # 'per_unit' or 'tiered'
    field :usage_type               # 'licensed' or 'metered'
    field :trial_period_days        # Trial period in days (null if none)
    field :nickname                 # Internal nickname for the price

    # Cache management
    field :last_synced_at           # Timestamp of last Stripe sync

    set :capabilities
    set :features
    hashkey :limits
    stringkey :stripe_data_snapshot, default_expiration: 12.hour  # Cached Stripe Product+Price JSON for recovery

    def init
      super
      @stripe_updated_at ||= 0
      @is_soft_deleted   ||= false
      @active            ||= true
      @limits_hash       = nil  # Memoization cache
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
    rescue JSON::ParserError => e
      Onetime.billing_logger.error 'Failed to parse stripe_data_snapshot', {
        plan_id: plan_id,
        error: e.message
      }
      nil
    end

    class << self
      # Refresh plan cache from Stripe API
      #
      # Fetches all active products and prices from Stripe, filters by app metadata,
      # and caches them in Redis with computed plan IDs.
      #
      # @param progress [Proc, nil] Optional progress callback (called with status messages)
      # @return [Integer] Number of plans cached
      # @raise [Stripe::StripeError] If Stripe API call fails
      def refresh_from_stripe(progress: nil)
        # Skip Stripe sync in CI/test environments without API key
        stripe_key = Onetime.billing_config.stripe_key
        if stripe_key.to_s.strip.empty?
          OT.lw '[Plan.refresh_from_stripe] Skipping Stripe sync: No API key configured'
          return 0
        end

        OT.li '[Plan.refresh_from_stripe] Starting Stripe sync'

        # Fetch all active products with onetimesecret metadata
        products = Stripe::Product.list({
          active: true,
          limit: RECORD_LIMIT,
        },
                                       )

        items_count        = 0
        products_processed = 0

        progress&.call('Fetching products from Stripe...')

        products.auto_paging_each do |product|
          products_processed += 1
          progress&.call("Processing product #{products_processed}: #{product.name[0..40]}...") if products_processed == 1 || products_processed % 5 == 0
          # Skip products without required metadata
          unless product.metadata[Metadata::FIELD_APP] == Metadata::APP_NAME
            OT.ld '[Plan.refresh_from_stripe] Skipping product (not onetimesecret app)', {
              product_id: product.id,
              product_name: product.name,
              app: product.metadata[Metadata::FIELD_APP],
            }
            next
          end

          unless product.metadata[Metadata::FIELD_TIER]
            OT.lw '[Plan.refresh_from_stripe] Skipping product (missing tier)', {
              product_id: product.id,
              product_name: product.name,
            }
            next
          end

          unless product.metadata[Metadata::FIELD_REGION]
            OT.lw '[Plan.refresh_from_stripe] Skipping product (missing region)', {
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

            interval = price.recurring.interval # 'month' or 'year'
            tier     = product.metadata[Metadata::FIELD_TIER]
            region   = product.metadata[Metadata::FIELD_REGION]

            # Use explicit plan_id from metadata with interval appended, or compute from tier_interval_region
            # TODO: Investigate why yearly plans don't appear in API response
            # Current behavior: plan_id from metadata (e.g., "identity_plus_v1") is same for monthly/yearly
            # This may cause yearly to overwrite monthly in cache if plan_id is used as Redis key
            base_plan_id = product.metadata[Metadata::FIELD_PLAN_ID] || "#{tier}_#{region}"
            plan_id = "#{base_plan_id}_#{interval}ly"

            # Extract capabilities from product metadata
            # Expected format: "create_secrets,create_team,custom_domains"
            capabilities_str = product.metadata[Metadata::FIELD_CAPABILITIES] || ''
            capabilities     = capabilities_str.split(',').map(&:strip).reject(&:empty?)

            # Extract limits from product metadata using Metadata helper
            limits = {}
            product.metadata.each do |key, value|
              key_str = key.to_s  # Ensure key is a string
              next unless key_str.start_with?('limit_')

              resource         = key_str.sub('limit_', '').to_sym
              limits[resource] = Metadata.normalize_limit(value)
            end

            # Extract display_order from product metadata (default to 0)
            # Higher values appear first (100 = leftmost, 0 = rightmost)
            display_order = product.metadata[Metadata::FIELD_DISPLAY_ORDER] || '0'

            # Extract show_on_plans_page from product metadata (default to 'true')
            # Accepts: 'true', 'false', '1', '0', 'yes', 'no'
            show_on_plans_page_value = product.metadata[Metadata::FIELD_SHOW_ON_PLANS_PAGE] || 'true'
            show_on_plans_page = %w[true 1 yes].include?(show_on_plans_page_value.to_s.downcase)

            # Create or update plan cache
            plan = new(
              plan_id: plan_id,
              stripe_price_id: price.id,
              stripe_product_id: product.id,
              name: product.name,
              tier: tier,
              interval: interval,
              amount: price.unit_amount.to_s,
              currency: price.currency,
              region: region,
              display_order: display_order,
              show_on_plans_page: show_on_plans_page.to_s,
            )

            # Populate additional Stripe Price fields
            plan.active = price.active.to_s
            plan.billing_scheme = price.billing_scheme
            plan.usage_type = price.recurring&.usage_type || 'licensed'
            plan.trial_period_days = price.recurring&.trial_period_days&.to_s
            plan.nickname = price.nickname
            plan.last_synced_at = Time.now.to_i.to_s

            # Add capabilities to set (unique values)
            plan.capabilities.clear
            capabilities.each { |cap| plan.capabilities.add(cap) }

            # Add features to set
            plan.features.clear
            marketing_features = product.marketing_features&.map(&:name) || []
            marketing_features.each { |feat| plan.features.add(feat) }

            # Add limits to hashkey with flattened keys
            plan.limits.clear
            limits.each do |resource, value|
              # Flatten: "teams" => "teams.max", value -1 => "unlimited"
              key = "#{resource}.max"
              val = value == -1 ? 'unlimited' : value.to_s
              plan.limits[key] = val
            end

            # Store original Stripe data for recovery/debugging
            # Allows re-parsing without full Stripe API sync if logic changes
            stripe_snapshot = {
              product: {
                id: product.id,
                name: product.name,
                metadata: product.metadata.to_h,
                marketing_features: product.marketing_features&.map(&:name) || []
              },
              price: {
                id: price.id,
                type: price.type,
                currency: price.currency,
                unit_amount: price.unit_amount,
                recurring: {
                  interval: price.recurring.interval
                }
              },
              cached_at: Time.now.to_i
            }
            plan.stripe_data_snapshot.value = stripe_snapshot.to_json

            plan.save

            OT.ld "[Plan] Cached plan: #{plan_id}", {
              stripe_price_id: price.id,
              amount: price.unit_amount,
              currency: price.currency,
            }

            items_count += 1
          end
        end

        OT.li "[Plan.refresh_from_stripe] Cached #{items_count} plans"
        items_count
      rescue Stripe::StripeError => ex
        OT.le '[Plan.refresh_from_stripe] Stripe error', {
          exception: ex,
          message: ex.message,
        }
        raise
      end

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

      # Clear all cached plans (for testing or forced refresh)
      def clear_cache
        instances.to_a.each do |plan_id|
          plan = load(plan_id)
          plan&.destroy!
        end
        instances.clear
      end
    end
  end
end
