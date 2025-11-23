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
  #     "plan_id": "identity_v1",
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
    field :is_soft_deleted          # Boolean: soft-deleted in Stripe

    set :capabilities
    set :features
    hashkey :limits

    def init
      super
      # @capabilities      ||= []
      # @features          ||= []
      # @limits            ||= {}
      @stripe_updated_at ||= 0
      @is_soft_deleted   ||= false
    end

    # Parse fields - Convert Familia data structures to native Ruby types
    # capabilities and features are Familia::UnsortedSet objects
    # limits is a Familia::HashKey object
    def parsed_capabilities
      capabilities.respond_to?(:members) ? capabilities.members : []
    end

    def parsed_features
      features.respond_to?(:members) ? features.members : []
    end

    def parsed_limits
      return {} unless limits.respond_to?(:all)

      parsed = limits.all
      # Convert -1 to Float::INFINITY for unlimited resources
      parsed.transform_values { |v| v.to_i == -1 ? Float::INFINITY : v.to_i }
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

        # Configure Stripe SDK with API key
        Stripe.api_key = stripe_key

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

            # Use explicit plan_id from metadata, or compute from tier_interval_region
            plan_id = product.metadata[Metadata::FIELD_PLAN_ID] || "#{tier}_#{interval}ly_#{region}"

            # Extract capabilities from product metadata
            # Expected format: "create_secrets,create_team,custom_domains"
            capabilities_str = product.metadata[Metadata::FIELD_CAPABILITIES] || ''
            capabilities     = capabilities_str.split(',').map(&:strip).reject(&:empty?)

            # Extract limits from product metadata using Metadata helper
            limits = {}
            product.metadata.each do |key, value|
              key_str = key.to_s
              next unless key_str.start_with?('limit_')

              resource         = key_str.sub('limit_', '').to_sym
              limits[resource] = Metadata.normalize_limit(value)
            end

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
            )

            # Populate Familia collections after creating instance
            capabilities.each { |cap| plan.capabilities.add(cap) }
            (product.marketing_features&.map(&:name) || []).each { |feat| plan.features.add(feat) }
            limits.each { |resource, limit| plan.limits[resource] = limit }

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
