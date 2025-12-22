# apps/web/billing/cli/prices_generate_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require 'yaml'

module Onetime
  module CLI
    # Generate Stripe price creation commands from billing-catalog.yaml
    class BillingPricesGenerateCommand < Command
      include BillingHelpers

      desc 'Generate price creation commands from billing.yaml'

      option :product_id, type: :string, desc: 'Stripe Product ID (e.g., prod_xxx) - required for each plan'
      option :plan, type: :string, desc: 'Generate for specific plan only (e.g., identity_plus_v1)'
      option :catalog, type: :string, default: 'etc/billing.yaml',
        desc: 'Path to billing plans catalog'
      option :lookup, type: :boolean, default: true,
        desc: 'Lookup product IDs from Stripe using plan_id metadata (default: true)'
      option :no_lookup, type: :boolean, default: false,
        desc: 'Skip Stripe lookup and use PRODUCT_ID placeholders'

      def call(product_id: nil, plan: nil, catalog: 'etc/billing.yaml', lookup: true, no_lookup: false, **)
        # Allow --no-lookup to override default
        lookup = false if no_lookup

        # Boot application only if lookup is enabled
        if lookup
          boot_application!
          return unless stripe_configured?
        end
        catalog_path = File.expand_path(catalog, Dir.pwd)

        unless Billing::Config.config_exists?
          puts "❌ Catalog not found: #{catalog_path}"
          return
        end

        plans_data = Billing::Config.safe_load_config

        unless plans_data['plans']
          puts '❌ No plans section found in catalog'
          return
        end

        # Filter plans if specific plan requested
        plans_to_generate = if plan
                              { plan => plans_data['plans'][plan] }
                            else
                              plans_data['plans']
                            end

        if plans_to_generate.nil? || plans_to_generate.empty?
          puts "❌ Plan '#{plan}' not found in catalog"
          return
        end

        # Lookup products from Stripe if requested
        products_map = {}
        if lookup
          puts 'Fetching products from Stripe...'
          products = Stripe::Product.list({ active: true, limit: 100 }).auto_paging_each.to_a

          # Map by plan_id from metadata
          products.each do |product|
            plan_id               = product.metadata['plan_id']
            products_map[plan_id] = product.id if plan_id
          end

          puts "Found #{products_map.size} products with plan_id metadata"
          puts
        end

        # Generate commands
        puts '# Generated Stripe price creation commands'
        puts "# Source: #{catalog}"
        puts "# Generated: #{Time.now.utc.iso8601}"
        puts '#'
        puts '# Usage: Copy and paste these commands to create prices in Stripe'
        puts '#        Make sure to replace PRODUCT_ID with actual Stripe product ID'
        puts
        puts '# Required: Set your Stripe API key first'
        puts '# export STRIPE_KEY=sk_test_...'
        puts

        plans_to_generate.each do |plan_id, plan_data|
          next unless plan_data['prices']
          next if plan_data['prices'].empty?

          puts
          puts "# #{plan_data['name']} (#{plan_id})"
          puts "# Tier: #{plan_data['tier']}, Region: #{plan_data['region']}"

          # Determine which product ID to use
          actual_product_id = if product_id
                                # Explicit product_id option takes precedence
                                product_id
                              elsif lookup && products_map[plan_id]
                                # Lookup from Stripe by plan_id metadata
                                products_map[plan_id]
                              end

          if actual_product_id
            puts "# Product ID: #{actual_product_id}"
          elsif lookup
            puts "# ⚠️  WARNING: No product found with plan_id='#{plan_id}' in Stripe"
            puts '# NOTE: Create product first or use --product-id option'
            else
              puts '# NOTE: Replace PRODUCT_ID below with the actual Stripe product ID'
              puts '#       Or use --lookup to auto-fetch from Stripe by plan_id metadata'
          end

          puts

          plan_data['prices'].each do |price|
            amount         = price['amount']
            currency       = price['currency'] || 'usd'
            interval       = price['interval']
            interval_count = price['interval_count'] || 1

            # Format amount for display
            amount_display = format('%.2f', amount / 100.0)

            # Build command
            cmd_parts = []
            cmd_parts << 'bin/ots billing prices create'
            cmd_parts << (actual_product_id || 'PRODUCT_ID')
            cmd_parts << "--amount=#{amount}"
            cmd_parts << "--currency=#{currency}"
            cmd_parts << "--interval=#{interval}"
            cmd_parts << "--interval-count=#{interval_count}" if interval_count != 1

            puts "# #{currency.upcase} $#{amount_display} / #{"#{interval_count} " if interval_count > 1}#{interval}#{'s' if interval_count > 1}"
            puts cmd_parts.join(' ')
            puts
          end
        end

        puts
        puts '# After creating prices, validate them:'
        puts 'bin/ots billing prices validate'
      end

      private

      def format_amount(amount, currency)
        "#{currency.upcase} $#{format('%.2f', amount / 100.0)}"
      end
    end
  end
end

Onetime::CLI.register 'billing prices generate', Onetime::CLI::BillingPricesGenerateCommand
