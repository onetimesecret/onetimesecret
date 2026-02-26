# apps/web/billing/cli/catalog_push_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require_relative '../errors'
require_relative '../config'

module Onetime
  module CLI
    # Push catalog to Stripe
    #
    # Syncs the YAML billing catalog to Stripe, creating or updating
    # products as needed. Prices are NEVER updated - only created when
    # all required fields are provided.
    #
    # All plans are synced including free tier. Free plans in Stripe enable:
    # - Downgrade flows (manual or after subscription cancellation)
    # - Targeted free/discounted plans for non-profits
    # - Consistent plan metadata across all tiers
    #
    class BillingCatalogPushCommand < Command
      include BillingHelpers

      desc 'Push billing catalog to Stripe (create/update products)'

      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'Preview changes without making them'

      option :force,
        type: :boolean,
        default: false,
        desc: 'Skip confirmation prompts'

      option :plan,
        type: :string,
        desc: 'Push only a specific plan (e.g., identity_plus_v1)'

      option :skip_prices,
        type: :boolean,
        default: false,
        desc: 'Skip price creation, only push products'

      def call(dry_run: false, force: false, plan: nil, skip_prices: false, **)
        boot_application!

        return unless stripe_configured?

        catalog = load_catalog
        return unless catalog

        app_identifier = catalog['app_identifier'] || Billing::Metadata::APP_NAME
        plans          = catalog['plans'] || {}
        match_fields   = catalog['match_fields'] || ['plan_id']
        region_filter  = catalog['region']

        if plans.empty?
          puts 'No plans found in catalog'
          return
        end

        # Filter to single plan if specified
        if plan
          unless plans.key?(plan)
            puts "Plan '#{plan}' not found in catalog"
            puts "\nAvailable plans: #{plans.keys.join(', ')}"
            return
          end
          plans = { plan => plans[plan] }
        end

        puts "Billing Catalog Push#{' (DRY RUN)' if dry_run}"
        puts '=' * 50
        puts "App identifier: #{app_identifier}"
        puts "Match fields: #{match_fields.join(', ')}"
        puts "Region filter: #{region_filter || '(none)'}"
        puts "Plans to process: #{plans.keys.join(', ')}"
        puts

        # Fetch existing products from Stripe
        existing_products = fetch_existing_products(app_identifier, match_fields, region_filter)
        existing_prices   = fetch_existing_prices(existing_products)

        # Analyze changes
        changes = analyze_changes(plans, existing_products, existing_prices, skip_prices, match_fields)

        if changes[:products_to_create].empty? &&
           changes[:products_to_update].empty? &&
           changes[:prices_to_create].empty?
          puts 'No changes needed - Stripe is in sync with catalog'
          return
        end

        # Display changes
        display_changes(changes, dry_run)

        return if dry_run

        # Confirm unless --force
        unless force
          print "\nProceed with these changes? (y/n): "
          response = $stdin.gets
          return unless response # Handle EOF/Ctrl+D gracefully
          return unless response.chomp.downcase == 'y'
        end

        # Apply changes
        apply_changes(changes, app_identifier)

        puts "\nCatalog push complete!"
        puts 'Run `bin/ots billing catalog pull` to sync to Redis cache'
      end

      private

      def load_catalog
        unless Billing::Config.config_exists?
          puts "Catalog not found: #{Billing::Config.config_path}"
          return nil
        end

        catalog = Billing::Config.safe_load_config
        if catalog.empty?
          puts 'Failed to load catalog (check logs for details)'
          return nil
        end

        catalog
      end

      # Fetch existing products from Stripe, indexed by composite match key.
      #
      # @param app_identifier [String] Filter to products with this app metadata
      # @param match_fields [Array<String>] Fields to build composite match key (e.g., ['plan_id', 'region'])
      # @param region_filter [String, nil] If set, only return products matching this region
      # @return [Hash<String, Stripe::Product>] Products indexed by composite match key
      def fetch_existing_products(app_identifier, match_fields, region_filter)
        products = {}

        with_stripe_retry do
          Stripe::Product.list(active: true, limit: 100).auto_paging_each do |product|
            next unless product.metadata['app'] == app_identifier

            # Region filtering: skip products not matching our region context
            if region_filter && !Billing::RegionNormalizer.match?(product.metadata['region'], region_filter)
              next
            end

            # Build composite match key from metadata fields
            key           = build_match_key_from_metadata(product.metadata, match_fields)
            products[key] = product if key
          end
        end

        products
      end

      # Build composite match key from product metadata.
      #
      # @param metadata [Hash] Stripe product metadata
      # @param match_fields [Array<String>] Fields to include in key
      # @return [String, nil] Composite key or nil if required fields missing
      def build_match_key_from_metadata(metadata, match_fields)
        values = match_fields.map { |f| metadata[f]&.to_s }
        return nil if values.any?(&:nil?)

        values.join('|')
      end

      # Build composite match key from local plan definition.
      #
      # @param plan_id [String] The plan identifier (YAML key)
      # @param plan_def [Hash] Plan definition from catalog
      # @param match_fields [Array<String>] Fields to include in key
      # @return [String, nil] Composite key, or nil if any required field is missing
      def build_match_key_from_plan(plan_id, plan_def, match_fields)
        values = match_fields.map do |field|
          field == 'plan_id' ? plan_id : plan_def[field]&.to_s
        end
        return nil if values.any?(&:nil?)

        values.join('|')
      end

      def fetch_existing_prices(products)
        prices      = {}
        product_ids = products.values.map(&:id)

        return prices if product_ids.empty?

        with_stripe_retry do
          Stripe::Price.list(active: true, limit: 100).auto_paging_each do |price|
            next unless product_ids.include?(price.product)

            # Find match key for this product (composite key like "plan_id|region")
            match_key = products.find { |_k, p| p.id == price.product }&.first
            next unless match_key

            prices[match_key] ||= []
            prices[match_key] << price
          end
        end

        prices
      end

      def analyze_changes(plans, existing_products, existing_prices, skip_prices, match_fields)
        changes = {
          products_to_create: [],
          products_to_update: [],
          prices_to_create: [],
        }

        plans.each do |plan_id, plan_def|
          # Resolve existing product: stripe_product_id override takes precedence
          existing = resolve_existing_product(
            plan_id, plan_def, existing_products, match_fields
          )

          # Build the match key for price lookups (composite key, not Stripe ID)
          match_key = build_match_key_from_plan(plan_id, plan_def, match_fields)

          if existing
            # Check if product needs update
            updates = detect_product_updates(existing, plan_def)
            unless updates.empty?
              changes[:products_to_update] << {
                plan_id: plan_id,
                product: existing,
                updates: updates,
                plan_def: plan_def,
              }
            end
          elsif plan_def['legacy']
            # Legacy plans are never created — they only exist for grandfathered
            # customers. If the product wasn't found (e.g., filtered by region
            # or stripe_product_id mismatch), skip entirely.
            puts "  ⏭ #{plan_id}: skipping (legacy plan, product not found)"
            next
          else
            # New product
            changes[:products_to_create] << {
              plan_id: plan_id,
              plan_def: plan_def,
            }
          end

          # Check prices unless skipped
          next if skip_prices

          price_changes = analyze_price_changes(
            plan_id, plan_def, existing, existing_prices[match_key] || []
          )
          changes[:prices_to_create].concat(price_changes)
        end

        changes
      end

      # Resolve existing Stripe product for a plan.
      #
      # Matching modes (mutually exclusive):
      # 1. stripe_product_id override: Direct 1-to-1 binding to a specific Stripe product.
      #    If specified, this is the ONLY product that can match - no fallback.
      # 2. Composite match key lookup: Match by plan_id + region (or other configured fields).
      #    Only used when NO stripe_product_id is specified.
      #
      # @param plan_id [String] The plan identifier
      # @param plan_def [Hash] Plan definition from catalog
      # @param existing_products [Hash] Products indexed by composite key
      # @param match_fields [Array<String>] Fields used for matching
      # @return [Stripe::Product, nil] Matched product or nil
      def resolve_existing_product(plan_id, plan_def, existing_products, match_fields)
        # Override: direct Stripe product ID binding (explicit 1-to-1 match)
        if (override_id = plan_def['stripe_product_id'])
          product = existing_products.values.find { |p| p.id == override_id }
          if product
            puts "  ℹ #{plan_id}: using stripe_product_id override (#{override_id})"
            return product
          else
            # stripe_product_id is an explicit binding - do NOT fall through to composite matching.
            # The product may exist in Stripe but be filtered out by region, or may not exist at all.
            # Either way, treat this plan as having no existing product (will create new).
            puts "  ⚠ #{plan_id}: stripe_product_id '#{override_id}' not found in fetched products"
            puts '    (product may be filtered by region or not exist - will create new product)'
            return nil
          end
        end

        # Normal matching via composite key (only when no explicit override)
        match_key = build_match_key_from_plan(plan_id, plan_def, match_fields)
        existing_products[match_key]
      end

      def detect_product_updates(existing, plan_def)
        updates = {}

        # Check name
        if existing.name != plan_def['name']
          updates[:name] = { from: existing.name, to: plan_def['name'] }
        end

        # Check marketing_features (i18n locale keys for UI display)
        existing_features = existing.marketing_features&.map(&:name) || []
        config_features   = plan_def['features'] || []
        if existing_features.sort != config_features.sort
          updates[:marketing_features] = { from: existing_features, to: config_features }
        end

        # Check metadata fields using registry from Billing::Metadata
        metadata_fields = build_syncable_metadata(plan_def)

        metadata_fields.each do |field, expected|
          current = existing.metadata[field]
          next if current.to_s == expected.to_s

          updates[:"metadata_#{field}"] = { from: current, to: expected }
        end

        updates
      end

      # Build metadata fields for update detection from plan definition.
      # Uses Billing::Metadata::SYNCABLE_FIELDS and LIMIT_FIELDS registries.
      #
      # All fields are always included (even if empty) so that:
      # - Adding a field value is detected as a change
      # - Removing a field value is detected as a change
      #
      # @param plan_def [Hash] Plan definition from catalog
      # @return [Hash<String, String>] Metadata fields for comparison
      def build_syncable_metadata(plan_def)
        metadata_fields = {}
        limits          = plan_def['limits'] || {}

        # Add all syncable fields from registry (always include for update detection)
        Billing::Metadata::SYNCABLE_FIELDS.each do |field_name, yaml_key|
          value = plan_def[yaml_key]

          # Special handling for certain field types
          metadata_fields[field_name] = case field_name
                                        when Billing::Metadata::FIELD_ENTITLEMENTS
                                          (value || []).join(',')
                                        when Billing::Metadata::FIELD_IS_POPULAR
                                          (value == true).to_s
                                        when Billing::Metadata::FIELD_REGION
                                          normalized = Billing::RegionNormalizer.normalize(value)
                                          next if normalized.nil?

                                          normalized
                                        else
                                          value.to_s
                                        end
        end

        # Add all limit fields from registry (always include for update detection)
        Billing::Metadata::LIMIT_FIELDS.each do |field_name, yaml_key|
          metadata_fields[field_name] = limits[yaml_key].to_s
        end

        metadata_fields
      end

      def analyze_price_changes(plan_id, plan_def, existing_product, existing_prices)
        changes        = []
        catalog_prices = plan_def['prices'] || []

        return changes if catalog_prices.empty?

        # For new products, existing_product will be nil. We still analyze prices
        # and set product_id to nil - it will be resolved in apply_changes after
        # the product is created.
        product_id = existing_product&.id

        catalog_prices.each_with_index do |price_def, idx|
          # Validate all required fields are present
          missing = []
          missing << 'amount' unless price_def['amount']
          missing << 'currency' unless price_def['currency']
          missing << 'interval' unless price_def['interval']

          unless missing.empty?
            puts "  ⚠ #{plan_id} price[#{idx}]: skipping - missing #{missing.join(', ')}"
            next
          end

          # Check if matching price exists (only for existing products)
          if existing_product
            matching = existing_prices.find do |p|
              p.unit_amount == price_def['amount'] &&
                p.currency == price_def['currency'].downcase &&
                p.recurring&.interval == price_def['interval']
            end
            next if matching # Price already exists
          end

          changes << {
            plan_id: plan_id,
            product_id: product_id, # Can be nil for new products
            amount: price_def['amount'],
            currency: price_def['currency'],
            interval: price_def['interval'],
          }
        end

        changes
      end

      def display_changes(changes, dry_run)
        prefix = dry_run ? '[DRY RUN] ' : ''

        unless changes[:products_to_create].empty?
          puts "#{prefix}Products to CREATE:"
          changes[:products_to_create].each do |item|
            puts "  + #{item[:plan_id]}: #{item[:plan_def]['name']}"
          end
          puts
        end

        unless changes[:products_to_update].empty?
          puts "#{prefix}Products to UPDATE:"
          changes[:products_to_update].each do |item|
            puts "  ~ #{item[:plan_id]} (#{item[:product].id}):"
            item[:updates].each do |field, change|
              field_name = field.to_s.sub('metadata_', '')
              puts "      #{field_name}: '#{change[:from]}' -> '#{change[:to]}'"
            end
          end
          puts
        end

        return if changes[:prices_to_create].empty?

        puts "#{prefix}Prices to CREATE:"
        changes[:prices_to_create].each do |item|
          amount_display = format_amount(item[:amount], item[:currency])
          puts "  + #{item[:plan_id]}: #{amount_display}/#{item[:interval]}"
        end
        puts
      end

      def apply_changes(changes, app_identifier)
        # Create new products first
        new_products = {}
        changes[:products_to_create].each do |item|
          product                      = create_product(item[:plan_id], item[:plan_def], app_identifier)
          new_products[item[:plan_id]] = product if product
        end

        # Update existing products
        changes[:products_to_update].each do |item|
          update_product(item[:product], item[:plan_def], item[:updates])
        end

        # Create prices (need product IDs for new products)
        changes[:prices_to_create].each do |item|
          product_id = item[:product_id] || new_products[item[:plan_id]]&.id
          next unless product_id

          create_price(product_id, item)
        end
      end

      def create_product(plan_id, plan_def, app_identifier)
        metadata = build_metadata(plan_id, plan_def, app_identifier)

        # Build marketing_features from config features (i18n locale keys)
        marketing_features = (plan_def['features'] || []).map { |f| { name: f } }

        product = with_stripe_retry do
          Stripe::Product.create(
            name: plan_def['name'],
            metadata: metadata,
            marketing_features: marketing_features,
          )
        end

        puts "  Created product: #{product.id} (#{plan_id})"
        product
      rescue Stripe::StripeError => ex
        puts "  ERROR creating #{plan_id}: #{ex.message}"
        nil
      end

      def update_product(existing, _plan_def, updates)
        # Build update params
        params = {}

        if updates[:name]
          params[:name] = updates[:name][:to]
        end

        # Update marketing_features (i18n locale keys for UI display)
        if updates[:marketing_features]
          params[:marketing_features] = updates[:marketing_features][:to].map { |f| { name: f } }
        end

        # Collect metadata updates
        metadata_updates = {}
        updates.each do |field, change|
          next unless field.to_s.start_with?('metadata_')

          key                   = field.to_s.sub('metadata_', '')
          metadata_updates[key] = change[:to]
        end

        params[:metadata] = metadata_updates unless metadata_updates.empty?

        return if params.empty?

        with_stripe_retry do
          Stripe::Product.update(existing.id, params)
        end

        puts "  Updated product: #{existing.id}"
      rescue Stripe::StripeError => ex
        puts "  ERROR updating #{existing.id}: #{ex.message}"
      end

      def create_price(product_id, price_def)
        with_stripe_retry do
          Stripe::Price.create(
            product: product_id,
            unit_amount: price_def[:amount],
            currency: price_def[:currency].downcase,
            recurring: {
              interval: price_def[:interval],
            },
          )
        end

        amount_display = format_amount(price_def[:amount], price_def[:currency])
        puts "  Created price: #{amount_display}/#{price_def[:interval]} for #{price_def[:plan_id]}"
      rescue Stripe::StripeError => ex
        puts "  ERROR creating price: #{ex.message}"
      end

      # Build metadata for creating a new Stripe product.
      # Uses Billing::Metadata registries for field definitions.
      #
      # Only includes fields with values (don't create empty metadata keys).
      #
      # @param plan_id [String] Plan identifier (YAML key)
      # @param plan_def [Hash] Plan definition from catalog
      # @param app_identifier [String] Application identifier
      # @return [Hash<String, String>] Metadata for Stripe product
      def build_metadata(plan_id, plan_def, app_identifier)
        limits = plan_def['limits'] || {}

        # Required fields (always present)
        metadata = {
          Billing::Metadata::FIELD_APP => app_identifier,
          Billing::Metadata::FIELD_PLAN_ID => plan_id,
          Billing::Metadata::FIELD_CREATED => Time.now.utc.iso8601,
        }

        # Add syncable fields from registry (only if value present for creation)
        Billing::Metadata::SYNCABLE_FIELDS.each do |field_name, yaml_key|
          value = plan_def[yaml_key]
          next unless value

          # Special handling for certain field types
          serialized = case field_name
                       when Billing::Metadata::FIELD_ENTITLEMENTS
                         value.join(',')
                       when Billing::Metadata::FIELD_IS_POPULAR
                         value == true ? 'true' : nil
                       else
                         value.to_s
                       end

          metadata[field_name] = serialized if serialized
        end

        # Add limit fields from registry (only if value present)
        Billing::Metadata::LIMIT_FIELDS.each do |field_name, yaml_key|
          value                = limits[yaml_key]
          metadata[field_name] = value.to_s if value
        end

        metadata
      end
    end
  end
end

Onetime::CLI.register 'billing catalog push', Onetime::CLI::BillingCatalogPushCommand
