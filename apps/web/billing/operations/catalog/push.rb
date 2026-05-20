# apps/web/billing/operations/catalog/push.rb
#
# frozen_string_literal: true

require_relative 'stripe_retry'
require_relative 'stripe_reader'

module Billing
  module Operations
    module Catalog
      # Push billing catalog to Stripe (create/update products and prices).
      #
      # Syncs YAML catalog to Stripe. Prices are NEVER updated - only created
      # when all required fields are provided. Extracted from BillingCatalogPushCommand.
      #
      # @example
      #   result = Push.call(dry_run: true, progress: ->(msg) { puts msg })
      #   puts "Would create #{result.products_created} products"
      #
      class Push
        Result = Data.define(
          :success,
          :dry_run,
          :products_created,
          :products_updated,
          :prices_created,
          :no_changes,
          :errors,
        ) do
          def initialize(success:, dry_run: false, products_created: 0, products_updated: 0, prices_created: 0, no_changes: false, errors: [])
            super
          end
        end

        # @param dry_run [Boolean] Preview changes without applying
        # @param plan_filter [String, nil] Push only a specific plan
        # @param skip_prices [Boolean] Skip price creation
        # @param progress [Proc, nil] Called with status messages
        # @return [Result]
        def self.call(dry_run: false, plan_filter: nil, skip_prices: false, progress: nil)
          new(dry_run: dry_run, plan_filter: plan_filter, skip_prices: skip_prices, progress: progress).call
        end

        def initialize(dry_run:, plan_filter:, skip_prices:, progress:)
          @dry_run     = dry_run
          @plan_filter = plan_filter
          @skip_prices = skip_prices
          @progress    = progress
        end

        def call
          catalog = load_catalog
          return Result.new(success: false, errors: ['Catalog not found or failed to load']) unless catalog

          app_identifier   = catalog['app_identifier'] || Billing::Metadata::APP_NAME
          plans            = catalog['plans'] || {}
          match_fields     = catalog['match_fields'] || ['plan_id']
          region_filter    = catalog['region']
          catalog_currency = (catalog['currency'] || 'cad').to_s.strip.downcase

          return Result.new(success: false, errors: ['No plans found in catalog']) if plans.empty?

          if @plan_filter
            unless plans.key?(@plan_filter)
              return Result.new(success: false, errors: ["Plan '#{@plan_filter}' not found. Available: #{plans.keys.join(', ')}"])
            end

            plans = { @plan_filter => plans[@plan_filter] }
          end

          report("App identifier: #{app_identifier}")
          report("Match fields: #{match_fields.join(', ')}")
          report("Region filter: #{region_filter || '(none)'}")
          report("Plans to process: #{plans.keys.join(', ')}")

          override_product_ids = plans.values
            .map { |plan_def| plan_def['stripe_product_id'] }
            .compact
            .to_set

          existing_products = StripeReader.fetch_products(
            app_identifier: app_identifier,
            region_filter: region_filter,
            match_fields: match_fields,
            override_product_ids: override_product_ids,
          )
          existing_prices   = StripeReader.fetch_prices(existing_products)

          changes = analyze_changes(plans, existing_products, existing_prices, match_fields, catalog_currency)

          if changes[:products_to_create].empty? &&
             changes[:products_to_update].empty? &&
             changes[:prices_to_create].empty?
            return Result.new(success: true, no_changes: true, dry_run: @dry_run)
          end

          report_changes(changes)

          if @dry_run
            return Result.new(
              success: true,
              dry_run: true,
              products_created: changes[:products_to_create].size,
              products_updated: changes[:products_to_update].size,
              prices_created: changes[:prices_to_create].size,
            )
          end

          apply_changes(changes, app_identifier, catalog_currency)

          Result.new(
            success: true,
            products_created: changes[:products_to_create].size,
            products_updated: changes[:products_to_update].size,
            prices_created: changes[:prices_to_create].size,
          )
        rescue Stripe::StripeError => ex
          Result.new(success: false, errors: ["Stripe error: #{ex.message}"])
        rescue StandardError => ex
          Result.new(success: false, errors: ["#{ex.class}: #{ex.message}"])
        end

        private

        def report(message)
          @progress&.call(message)
        end

        def load_catalog
          return nil unless Billing::Config.config_exists?

          catalog = Billing::Config.safe_load_config
          catalog.empty? ? nil : catalog
        end

        def build_match_key_from_plan(plan_id, plan_def, match_fields)
          values = match_fields.map do |field|
            field == 'plan_id' ? plan_id : plan_def[field]&.to_s
          end
          return nil if values.any?(&:nil?)

          values.join('|')
        end

        def analyze_changes(plans, existing_products, existing_prices, match_fields, catalog_currency)
          changes = {
            products_to_create: [],
            products_to_update: [],
            prices_to_create: [],
          }

          plans.each do |plan_id, plan_def|
            existing  = resolve_existing_product(plan_id, plan_def, existing_products, match_fields)
            match_key = build_match_key_from_plan(plan_id, plan_def, match_fields)

            if existing
              updates = detect_product_updates(plan_id, existing, plan_def, catalog_currency)
              unless updates.empty?
                changes[:products_to_update] << {
                  plan_id: plan_id,
                  product: existing,
                  updates: updates,
                  plan_def: plan_def,
                }
              end
            elsif plan_def['legacy']
              report("  ⏭ #{plan_id}: skipping (legacy plan, product not found)")
              next
            else
              changes[:products_to_create] << {
                plan_id: plan_id,
                plan_def: plan_def,
              }
            end

            next if @skip_prices

            price_changes = analyze_price_changes(
              plan_id, plan_def, existing, existing_prices[match_key] || [], catalog_currency
            )
            changes[:prices_to_create].concat(price_changes)
          end

          changes
        end

        def resolve_existing_product(plan_id, plan_def, existing_products, match_fields)
          if (override_id = plan_def['stripe_product_id'])
            product = existing_products.values.find { |p| p.id == override_id }
            if product
              report("  ℹ #{plan_id}: using stripe_product_id override (#{override_id})")
              return product
            else
              report("  ⚠ #{plan_id}: stripe_product_id '#{override_id}' not found")
              return nil
            end
          end

          match_key = build_match_key_from_plan(plan_id, plan_def, match_fields)
          existing_products[match_key]
        end

        def detect_product_updates(plan_id, existing, plan_def, catalog_currency)
          updates = {}

          if existing.name != plan_def['name']
            updates[:name] = { from: existing.name, to: plan_def['name'] }
          end

          existing_features = existing.marketing_features&.map(&:name) || []
          config_features   = plan_def['features'] || []
          if existing_features.sort != config_features.sort
            updates[:marketing_features] = { from: existing_features, to: config_features }
          end

          metadata_fields = build_syncable_metadata(plan_id, plan_def, catalog_currency)

          metadata_fields.each do |field, expected|
            current = existing.metadata[field]
            next if current.to_s == expected.to_s

            updates[:"metadata_#{field}"] = { from: current, to: expected }
          end

          updates
        end

        def build_syncable_metadata(plan_id, plan_def, catalog_currency)
          metadata_fields                                   = {}
          metadata_fields[Billing::Metadata::FIELD_PLAN_ID] = plan_id
          limits                                            = plan_def['limits'] || {}

          Billing::Metadata::SYNCABLE_FIELDS.each do |field_name, yaml_key|
            value = plan_def[yaml_key]

            serialized = case field_name
                         when Billing::Metadata::FIELD_ENTITLEMENTS
                           (value || []).join(',')
                         when Billing::Metadata::FIELD_IS_POPULAR
                           (value == true).to_s
                         when Billing::Metadata::FIELD_REGION
                           Billing::RegionNormalizer.normalize(value)
                         else
                           value.to_s
                         end

            metadata_fields[field_name] = serialized if serialized
          end

          metadata_fields[Billing::Metadata::FIELD_CURRENCY] = catalog_currency

          Billing::Metadata::LIMIT_FIELDS.each do |field_name, yaml_key|
            metadata_fields[field_name] = limits[yaml_key].to_s
          end

          metadata_fields
        end

        def analyze_price_changes(plan_id, plan_def, existing_product, existing_prices, catalog_currency)
          changes        = []
          catalog_prices = plan_def['prices'] || []

          return changes if catalog_prices.empty?

          product_id = existing_product&.id

          catalog_prices.each_with_index do |price_def, idx|
            resolved_currency = (price_def['currency'] || catalog_currency).to_s.strip.downcase

            missing = []
            missing << 'amount' unless price_def['amount']
            missing << 'interval' unless price_def['interval']

            unless missing.empty?
              report("  ⚠ #{plan_id} price[#{idx}]: skipping - missing #{missing.join(', ')}")
              next
            end

            if existing_product
              matching = existing_prices.find do |p|
                p.unit_amount == price_def['amount'] &&
                  p.currency == resolved_currency &&
                  p.recurring&.interval == price_def['interval']
              end
              next if matching
            end

            changes << {
              plan_id: plan_id,
              product_id: product_id,
              amount: price_def['amount'],
              currency: resolved_currency,
              interval: price_def['interval'],
            }
          end

          changes
        end

        def report_changes(changes)
          unless changes[:products_to_create].empty?
            report("Products to CREATE: #{changes[:products_to_create].size}")
            changes[:products_to_create].each do |item|
              report("  + #{item[:plan_id]}: #{item[:plan_def]['name']}")
            end
          end

          unless changes[:products_to_update].empty?
            report("Products to UPDATE: #{changes[:products_to_update].size}")
            changes[:products_to_update].each do |item|
              report("  ~ #{item[:plan_id]} (#{item[:product].id})")
            end
          end

          return if changes[:prices_to_create].empty?

          report("Prices to CREATE: #{changes[:prices_to_create].size}")
          changes[:prices_to_create].each do |item|
            report("  + #{item[:plan_id]}: #{item[:amount]}/#{item[:interval]}")
          end
        end

        def apply_changes(changes, app_identifier, catalog_currency)
          new_products = {}

          changes[:products_to_create].each do |item|
            product                      = create_product(item[:plan_id], item[:plan_def], app_identifier, catalog_currency)
            new_products[item[:plan_id]] = product if product
          end

          changes[:products_to_update].each do |item|
            update_product(item[:product], item[:plan_def], item[:updates])
          end

          changes[:prices_to_create].each do |item|
            product_id = item[:product_id] || new_products[item[:plan_id]]&.id
            next unless product_id

            create_price(product_id, item)
          end
        end

        def create_product(plan_id, plan_def, app_identifier, catalog_currency)
          metadata           = build_create_metadata(plan_id, plan_def, app_identifier, catalog_currency)
          marketing_features = (plan_def['features'] || []).map { |f| { name: f } }

          product = StripeRetry.with_retry do
            Stripe::Product.create(
              name: plan_def['name'],
              metadata: metadata,
              marketing_features: marketing_features,
            )
          end

          report("  Created product: #{product.id} (#{plan_id})")
          product
        rescue Stripe::StripeError => ex
          report("  ERROR creating #{plan_id}: #{ex.message}")
          nil
        end

        def update_product(existing, _plan_def, updates)
          params = {}

          params[:name] = updates[:name][:to] if updates[:name]

          if updates[:marketing_features]
            params[:marketing_features] = updates[:marketing_features][:to].map { |f| { name: f } }
          end

          metadata_updates = {}
          updates.each do |field, change|
            next unless field.to_s.start_with?('metadata_')

            key                   = field.to_s.sub('metadata_', '')
            metadata_updates[key] = change[:to]
          end

          params[:metadata] = metadata_updates unless metadata_updates.empty?

          return if params.empty?

          StripeRetry.with_retry do
            Stripe::Product.update(existing.id, params)
          end
          report("  Updated product: #{existing.id}")
        rescue Stripe::StripeError => ex
          report("  ERROR updating #{existing.id}: #{ex.message}")
        end

        def create_price(product_id, price_def)
          params = {
            product: product_id,
            unit_amount: price_def[:amount],
            currency: price_def[:currency].downcase,
            recurring: {
              interval: price_def[:interval],
            },
          }

          params[:metadata] = price_def[:metadata] if price_def[:metadata]&.any?

          StripeRetry.with_retry do
            Stripe::Price.create(params)
          end
          report("  Created price: #{price_def[:amount]}/#{price_def[:interval]} for #{price_def[:plan_id]}")
        rescue Stripe::StripeError => ex
          report("  ERROR creating price: #{ex.message}")
        end

        def build_create_metadata(plan_id, plan_def, app_identifier, catalog_currency)
          limits = plan_def['limits'] || {}

          metadata = {
            Billing::Metadata::FIELD_APP => app_identifier,
            Billing::Metadata::FIELD_PLAN_ID => plan_id,
            Billing::Metadata::FIELD_CREATED => Time.now.utc.iso8601,
          }

          Billing::Metadata::SYNCABLE_FIELDS.each do |field_name, yaml_key|
            value = plan_def[yaml_key]
            next unless value

            serialized = case field_name
                         when Billing::Metadata::FIELD_ENTITLEMENTS
                           value.join(',')
                         when Billing::Metadata::FIELD_IS_POPULAR
                           value == true ? 'true' : nil
                         when Billing::Metadata::FIELD_REGION
                           Billing::RegionNormalizer.normalize(value)
                         else
                           value.to_s
                         end

            metadata[field_name] = serialized if serialized
          end

          metadata[Billing::Metadata::FIELD_CURRENCY] = catalog_currency

          Billing::Metadata::LIMIT_FIELDS.each do |field_name, yaml_key|
            value                = limits[yaml_key]
            metadata[field_name] = value.to_s if value
          end

          metadata
        end
      end
    end
  end
end
