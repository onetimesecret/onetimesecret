# apps/web/billing/operations/catalog/data_extractor.rb
#
# frozen_string_literal: true

require_relative '../../metadata'

module Billing
  module Operations
    module Catalog
      # Extracts plan data from Stripe product and price objects.
      #
      # Transforms Stripe API objects into the hash format expected by
      # PlanPersister. Validates required metadata and raises on invalid input.
      #
      # @example
      #   data = DataExtractor.call(product, price)
      #   PlanPersister.upsert_from_stripe_data(data)
      #
      module DataExtractor
        extend self

        # Extract plan data from Stripe product and price objects
        #
        # Callers should validate product with Plan.valid_ots_product? before calling.
        # Raises ConfigError on invalid input (missing or blank required metadata).
        #
        # @param product [Stripe::Product] Stripe product object (already validated)
        # @param price [Stripe::Price] Stripe price object
        # @return [Hash] Plan data ready for persistence
        # @raise [Onetime::ConfigError] If required metadata is missing or blank
        def call(product, price)
          validate_metadata!(product)

          interval = price.recurring.interval # 'month' or 'year'
          tier     = product.metadata[Metadata::FIELD_TIER]
          region   = product.metadata[Metadata::FIELD_REGION]
          plan_id  = product.metadata[Metadata::FIELD_PLAN_ID] # Family ID (unsuffixed)

          {
            plan_id: plan_id,
            stripe_product_id: product.id,
            stripe_updated_at: product.updated.to_s,
            name: product.name,
            tier: tier,
            currency: product.metadata[Metadata::FIELD_CURRENCY] || price.currency,
            region: region,
            tenancy: extract_tenancy(product),
            display_order: product.metadata[Metadata::FIELD_DISPLAY_ORDER] || '0',
            show_on_plans_page: extract_boolean(product, Metadata::FIELD_SHOW_ON_PLANS_PAGE, default: true).to_s,
            description: product.description,
            plan_code: product.metadata[Metadata::FIELD_PLAN_CODE],
            is_popular: extract_is_popular(product).to_s,
            plan_name_label: extract_optional_string(product, Metadata::FIELD_PLAN_NAME_LABEL),
            includes_plan: extract_optional_string(product, Metadata::FIELD_INCLUDES_PLAN),
            active: price.active.to_s,
            entitlements: extract_entitlements(product),
            features: product.marketing_features&.map(&:name) || [],
            limits: extract_limits(product),
            stripe_snapshot: build_stripe_snapshot(product, price, interval),
            prices: { interval.to_sym => build_price_data(price) },
          }
        end

        # Validate required metadata, raising on problems
        #
        # @param product [Stripe::Product]
        # @raise [Onetime::ConfigError] If validation fails
        def validate_metadata!(product)
          result   = Billing::Plan.validate_product_metadata(product)
          problems = []
          problems << "missing: #{result[:missing].join(', ')}" if result[:missing].any?
          problems << "blank: #{result[:blank].join(', ')}" if result[:blank].any?
          return if problems.empty?

          raise Onetime::ConfigError,
            "invalid metadata for Stripe product #{product.id} (#{product.name}): #{problems.join('; ')}"
        end

        def extract_tenancy(product)
          product.metadata[Metadata::FIELD_TENANCY] || 'multi'
        end

        def extract_boolean(product, field, default:)
          value = product.metadata[field]
          return default if value.nil? || value.to_s.strip.empty?

          %w[true 1 yes].include?(value.to_s.downcase)
        end

        def extract_optional_string(product, field)
          raw = product.metadata[field]
          raw.to_s.strip.empty? ? nil : raw
        end

        def extract_is_popular(product)
          is_popular_value = product.metadata[Metadata::FIELD_IS_POPULAR]
          if is_popular_value.nil? || is_popular_value.to_s.strip.empty?
            # Fall back to billing.yaml config
            plan_code   = product.metadata[Metadata::FIELD_PLAN_CODE]
            plan_config = OT.billing_config.plans[plan_code] || {}
            plan_config['is_popular'] == true
          else
            %w[true 1 yes].include?(is_popular_value.to_s.downcase)
          end
        end

        def extract_entitlements(product)
          entitlements_str = product.metadata[Metadata::FIELD_ENTITLEMENTS] || ''
          entitlements_str.split(',').map(&:strip).reject(&:empty?)
        end

        def extract_limits(product)
          limits = {}
          product.metadata.each do |key, value|
            key_str = key.to_s
            next unless key_str.start_with?('limit_')

            resource         = key_str.sub('limit_', '').to_sym
            limits[resource] = Metadata.normalize_limit(value)
          end
          limits
        end

        def build_stripe_snapshot(product, price, interval)
          {
            product: {
              id: product.id,
              name: product.name,
              currency: product.metadata[Metadata::FIELD_CURRENCY],
              metadata: product.metadata.to_h,
              marketing_features: product.marketing_features&.map(&:name) || [],
            },
            prices: {
              interval.to_sym => {
                id: price.id,
                type: price.type,
                currency: price.currency,
                unit_amount: price.unit_amount,
                recurring: {
                  interval: price.recurring.interval,
                },
              },
            },
            cached_at: Time.now.to_i,
          }
        end

        def build_price_data(price)
          {
            stripe_price_id: price.id,
            amount: price.unit_amount.to_s,
            currency: price.currency,
            billing_scheme: price.billing_scheme,
            usage_type: price.recurring&.usage_type || 'licensed',
            trial_period_days: price.recurring&.trial_period_days&.to_s,
            nickname: price.nickname,
            active: price.active.to_s,
          }
        end
      end
    end
  end
end
