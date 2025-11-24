# apps/web/billing/cli/prices_generate_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require 'yaml'

module Onetime
  module CLI
    # Generate Stripe price creation commands from billing-plans.yaml
    class BillingPricesGenerateCommand < Command
      include BillingHelpers

      desc 'Generate price creation commands from billing-plans.yaml'

      option :product_id, type: :string, desc: 'Stripe Product ID (e.g., prod_xxx) - required for each plan'
      option :plan, type: :string, desc: 'Generate for specific plan only (e.g., identity_plus_v1)'
      option :catalog, type: :string, default: 'etc/billing-plans.yaml',
        desc: 'Path to billing plans catalog'

      def call(product_id: nil, plan: nil, catalog: 'etc/billing-plans.yaml', **)
        # No need to boot application or connect to Stripe - just read YAML
        catalog_path = File.expand_path(catalog, Dir.pwd)

        unless File.exist?(catalog_path)
          puts "❌ Catalog not found: #{catalog_path}"
          return
        end

        plans_data = YAML.load_file(catalog_path)

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

          if product_id
            puts "# Product ID: #{product_id}"
          else
            puts '# NOTE: Replace PRODUCT_ID below with the actual Stripe product ID'
          end

          puts

          plan_data['prices'].each do |price|
            amount = price['amount']
            currency = price['currency'] || 'usd'
            interval = price['interval']
            interval_count = price['interval_count'] || 1

            # Format amount for display
            amount_display = format('%.2f', amount / 100.0)

            # Build command
            cmd_parts = []
            cmd_parts << 'bin/ots billing prices create'
            cmd_parts << (product_id || 'PRODUCT_ID')
            cmd_parts << "--amount=#{amount}"
            cmd_parts << "--currency=#{currency}"
            cmd_parts << "--interval=#{interval}"
            cmd_parts << "--interval-count=#{interval_count}" if interval_count != 1

            puts "# #{currency.upcase} $#{amount_display} / #{interval_count > 1 ? "#{interval_count} " : ''}#{interval}#{interval_count > 1 ? 's' : ''}"
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
