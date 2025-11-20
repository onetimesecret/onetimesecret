# apps/web/billing/models/catalog_cache.rb
#
# frozen_string_literal: true

require 'stripe'

module Billing
  module Models
    # CatalogCache - Stripe Product + Price Catalog Cache
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
    #     "region": "us-east",
    #     "capabilities": "create_secrets,create_team,custom_domains",
    #     "limit_teams": "1",
    #     "limit_members_per_team": "-1"
    #   }
    #
    # ## Catalog ID Format
    #
    # Catalog IDs combine tier, interval, and region:
    #   - single_team_monthly_us_east
    #   - multi_team_yearly_eu_west
    #
    class CatalogCache < Familia::Horreum
      using Familia::Refinements::TimeLiterals

      prefix :billing_catalog

      feature :safe_dump
      feature :expiration

      default_expiration 1.hour # Auto-expire after 1 hour

      identifier_field :plan_id   # Computed: tier_interval_region

      # Catalog entry fields
      field :plan_id              # Computed: tier_interval_region (identifier)
      field :stripe_price_id      # Stripe Price ID (price_xxx)
      field :stripe_product_id    # Stripe Product ID (prod_xxx)
      field :stripe_updated_at    # Stripe's updated timestamp (for idempotency)
      field :name                 # Product name
      field :tier                 # e.g., 'single_team', 'multi_team'
      field :interval             # 'month' or 'year'
      field :amount               # Price in cents
      field :currency             # 'usd', 'eur', etc.
      field :region               # 'us-east', 'eu-west', etc.
      field :deleted              # Boolean: soft-deleted in Stripe

      # Metadata stored as JSON strings
      field :capabilities         # JSON: Capability strings array
      field :features             # JSON: Feature list (marketing)
      field :limits               # JSON: Usage limits (teams, members_per_team, etc.)

      def init
        @capabilities ||= '[]'
        @features     ||= '[]'
        @limits       ||= '{}'
        @stripe_updated_at ||= '0'
        @deleted ||= 'false'
        nil
      end

      # Override save to track plans in class-level sorted set
      def save(**)
        result = super
        self.class.instances.add(plan_id) if result && plan_id
        result
      end

      # Parse JSON fields
      def parsed_capabilities
        JSON.parse(capabilities)
      rescue JSON::ParserError
        []
      end

      def parsed_features
        JSON.parse(features)
      rescue JSON::ParserError
        []
      end

      def parsed_limits
        parsed = JSON.parse(limits)
        # Convert -1 to Float::INFINITY for unlimited resources
        parsed.transform_values { |v| v == -1 ? Float::INFINITY : v }
      rescue JSON::ParserError
        {}
      end

      class << self
        # Refresh plan cache from Stripe API
        #
        # Fetches all active products and prices from Stripe, filters by app metadata,
        # and caches them in Redis with computed plan IDs.
        #
        # @return [Integer] Number of plans cached
        def refresh_from_stripe
          # Skip Stripe sync in CI/test environments without API key
          stripe_key = Onetime.billing_config.stripe_key
          if stripe_key.to_s.strip.empty?
            OT.lw '[CatalogCache.refresh_from_stripe] Skipping Stripe sync: No API key configured'
            return 0
          end

          # Configure Stripe SDK with API key
          Stripe.api_key = stripe_key

          OT.li '[CatalogCache.refresh_from_stripe] Starting Stripe sync'

          # Fetch all active products with onetimesecret metadata
          products = Stripe::Product.list({
            active: true,
            limit: 100,
          },
                                         )

          plan_count = 0

          products.auto_paging_each do |product|
            # Skip products without required metadata
            unless product.metadata['app'] == 'onetimesecret'
              OT.ld "[CatalogCache.refresh_from_stripe] Skipping product (not onetimesecret app)", {
                product_id: product.id,
                product_name: product.name,
                app: product.metadata['app']
              }
              next
            end

            unless product.metadata['tier']
              OT.lw "[CatalogCache.refresh_from_stripe] Skipping product (missing tier)", {
                product_id: product.id,
                product_name: product.name
              }
              next
            end

            unless product.metadata['region']
              OT.lw "[CatalogCache.refresh_from_stripe] Skipping product (missing region)", {
                product_id: product.id,
                product_name: product.name
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
              tier     = product.metadata['tier']
              region   = product.metadata['region']

              # Use explicit plan_id from metadata, or compute from tier_interval_region
              plan_id = product.metadata['plan_id'] || "#{tier}_#{interval}ly_#{region}"

              # Extract capabilities from product metadata
              # Expected format: "create_secrets,create_team,custom_domains"
              capabilities_str = product.metadata['capabilities'] || ''
              capabilities     = capabilities_str.split(',').map(&:strip).reject(&:empty?)

              # Extract limits from product metadata
              # -1 or "infinity" means Float::INFINITY
              limits = {}
              product.metadata.each do |key, value|
                next unless key.start_with?('limit_')

                resource         = key.sub('limit_', '').to_sym
                limits[resource] = if value.to_s == '-1' || value.to_s.downcase == 'infinity'
                                     Float::INFINITY
                                   else
                                     value.to_i
                                   end
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
                capabilities: capabilities.to_json,
                features: (product.marketing_features&.map(&:name) || []).to_json,
                limits: limits.to_json,
              )
              plan.save

              OT.ld "[CatalogCache] Cached plan: #{plan_id}", {
                stripe_price_id: price.id,
                amount: price.unit_amount,
                currency: price.currency,
              }

              plan_count += 1
            end
          end

          OT.li "[CatalogCache.refresh_from_stripe] Cached #{plan_count} plans"
          plan_count
        rescue Stripe::StripeError => ex
          OT.le '[CatalogCache.refresh_from_stripe] Stripe error', {
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
        # @param tier [String] Plan tier (e.g., 'single_team')
        # @param interval [String] Billing interval ('monthly' or 'yearly')
        # @param region [String] Region code (e.g., 'us-east')
        # @return [CatalogCache, nil] Cached plan or nil if not found
        def get_plan(tier, interval, region = 'us-east')
          # Normalize interval to singular form (monthly -> month)
          interval = interval.to_s.sub(/ly$/, '')

          # Search through all cached plans for matching tier/interval/region
          list_catalog.find do |plan|
            plan.tier == tier &&
              plan.interval == interval &&
              plan.region == region
          end
        end

        # List all cached plans
        #
        # @return [Array<CatalogCache>] All cached plans
        def list_catalog
          load_multi(instances.to_a)
        end

        # Clear all cached plans (for testing or forced refresh)
        def clear_cache
          values.to_a.each do |plan_id|
            plan = load(plan_id)
            plan&.destroy!
          end
          values.clear
        end
      end
    end
  end
end
