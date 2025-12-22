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
    class BillingCatalogPushCommand < Command
      include BillingHelpers

      desc 'Push billing catalog to Stripe (create/update products)'

      option :dry_run, type: :boolean, default: false,
        desc: 'Preview changes without making them'

      option :force, type: :boolean, default: false,
        desc: 'Skip confirmation prompts'

      option :plan, type: :string,
        desc: 'Push only a specific plan (e.g., identity_plus_v1)'

      option :skip_prices, type: :boolean, default: false,
        desc: 'Skip price creation, only push products'

      def call(dry_run: false, force: false, plan: nil, skip_prices: false, **)
        boot_application!

        return unless stripe_configured?

        catalog = load_catalog
        return unless catalog

        app_identifier = catalog['app_identifier'] || Billing::Metadata::APP_NAME
        plans = catalog['plans'] || {}

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

        puts "Billing Catalog Push#{dry_run ? ' (DRY RUN)' : ''}"
        puts '=' * 50
        puts "App identifier: #{app_identifier}"
        puts "Plans to process: #{plans.keys.join(', ')}"
        puts

        # Fetch existing products from Stripe
        existing_products = fetch_existing_products(app_identifier)
        existing_prices = fetch_existing_prices(existing_products)

        # Analyze changes
        changes = analyze_changes(plans, existing_products, existing_prices, skip_prices)

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

      def fetch_existing_products(app_identifier)
        products = {}

        with_stripe_retry do
          Stripe::Product.list(active: true, limit: 100).auto_paging_each do |product|
            next unless product.metadata['app'] == app_identifier

            plan_id = product.metadata['plan_id']
            products[plan_id] = product if plan_id
          end
        end

        products
      end

      def fetch_existing_prices(products)
        prices = {}
        product_ids = products.values.map(&:id)

        return prices if product_ids.empty?

        with_stripe_retry do
          Stripe::Price.list(active: true, limit: 100).auto_paging_each do |price|
            next unless product_ids.include?(price.product)

            # Find plan_id for this product
            plan_id = products.find { |_k, p| p.id == price.product }&.first
            next unless plan_id

            prices[plan_id] ||= []
            prices[plan_id] << price
          end
        end

        prices
      end

      def analyze_changes(plans, existing_products, existing_prices, skip_prices)
        changes = {
          products_to_create: [],
          products_to_update: [],
          prices_to_create: [],
        }

        plans.each do |plan_id, plan_def|
          existing = existing_products[plan_id]

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
          else
            # New product
            changes[:products_to_create] << {
              plan_id: plan_id,
              plan_def: plan_def,
            }
          end

          # Check prices unless skipped
          unless skip_prices
            price_changes = analyze_price_changes(
              plan_id, plan_def, existing, existing_prices[plan_id] || []
            )
            changes[:prices_to_create].concat(price_changes)
          end
        end

        changes
      end

      def detect_product_updates(existing, plan_def)
        updates = {}

        # Check name
        if existing.name != plan_def['name']
          updates[:name] = { from: existing.name, to: plan_def['name'] }
        end

        # Check metadata fields
        metadata_fields = {
          'tier' => plan_def['tier'],
          'tenancy' => plan_def['tenancy'],
          'region' => plan_def['region'],
          'display_order' => plan_def['display_order'].to_s,
          'show_on_plans_page' => plan_def['show_on_plans_page'].to_s,
          'entitlements' => (plan_def['entitlements'] || []).join(','),
        }

        # Add limit fields (always include so removed limits sync as empty strings)
        limits = plan_def['limits'] || {}
        metadata_fields['limit_teams'] = limits['teams'].to_s
        metadata_fields['limit_members_per_team'] = limits['members_per_team'].to_s
        metadata_fields['limit_custom_domains'] = limits['custom_domains'].to_s
        metadata_fields['limit_secret_lifetime'] = limits['secret_lifetime'].to_s
        metadata_fields['limit_secrets_per_day'] = limits['secrets_per_day'].to_s

        metadata_fields.each do |field, expected|
          current = existing.metadata[field]
          next if current.to_s == expected.to_s

          updates[:"metadata_#{field}"] = { from: current, to: expected }
        end

        updates
      end

      def analyze_price_changes(plan_id, plan_def, existing_product, existing_prices)
        changes = []
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

        unless changes[:prices_to_create].empty?
          puts "#{prefix}Prices to CREATE:"
          changes[:prices_to_create].each do |item|
            amount_display = format_amount(item[:amount], item[:currency])
            puts "  + #{item[:plan_id]}: #{amount_display}/#{item[:interval]}"
          end
          puts
        end
      end

      def apply_changes(changes, app_identifier)
        # Create new products first
        new_products = {}
        changes[:products_to_create].each do |item|
          product = create_product(item[:plan_id], item[:plan_def], app_identifier)
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

        product = with_stripe_retry do
          Stripe::Product.create(
            name: plan_def['name'],
            metadata: metadata
          )
        end

        puts "  Created product: #{product.id} (#{plan_id})"
        product
      rescue Stripe::StripeError => ex
        puts "  ERROR creating #{plan_id}: #{ex.message}"
        nil
      end

      def update_product(existing, plan_def, updates)
        # Build update params
        params = {}

        if updates[:name]
          params[:name] = updates[:name][:to]
        end

        # Collect metadata updates
        metadata_updates = {}
        updates.each do |field, change|
          next unless field.to_s.start_with?('metadata_')

          key = field.to_s.sub('metadata_', '')
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
            }
          )
        end

        amount_display = format_amount(price_def[:amount], price_def[:currency])
        puts "  Created price: #{amount_display}/#{price_def[:interval]} for #{price_def[:plan_id]}"
      rescue Stripe::StripeError => ex
        puts "  ERROR creating price: #{ex.message}"
      end

      def build_metadata(plan_id, plan_def, app_identifier)
        limits = plan_def['limits'] || {}

        metadata = {
          'app' => app_identifier,
          'plan_id' => plan_id,
          'tier' => plan_def['tier'].to_s,
          'tenancy' => plan_def['tenancy'].to_s,
          'region' => plan_def['region'].to_s,
          'entitlements' => (plan_def['entitlements'] || []).join(','),
          'display_order' => plan_def['display_order'].to_s,
          'show_on_plans_page' => plan_def['show_on_plans_page'].to_s,
          'created' => Time.now.utc.iso8601,
        }

        # Add limit fields
        metadata['limit_teams'] = limits['teams'].to_s if limits['teams']
        metadata['limit_members_per_team'] = limits['members_per_team'].to_s if limits['members_per_team']
        metadata['limit_custom_domains'] = limits['custom_domains'].to_s if limits['custom_domains']
        metadata['limit_secret_lifetime'] = limits['secret_lifetime'].to_s if limits['secret_lifetime']
        metadata['limit_secrets_per_day'] = limits['secrets_per_day'].to_s if limits['secrets_per_day']

        metadata
      end
    end
  end
end

Onetime::CLI.register 'billing catalog push', Onetime::CLI::BillingCatalogPushCommand
