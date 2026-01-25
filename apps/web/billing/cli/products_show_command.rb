# apps/web/billing/cli/products_show_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Show product details
    class BillingProductsShowCommand < Command
      include BillingHelpers

      desc 'Show detailed product information'

      argument :product_id, required: true, desc: 'Product ID (e.g., prod_xxx)'

      def call(product_id:, **)
        boot_application!

        return unless stripe_configured?

        product = Stripe::Product.retrieve(product_id)

        puts 'Product Details:'
        puts "  ID: #{product.id}"
        puts "  Name: #{product.name}"
        puts "  Active: #{product.active ? 'yes' : 'no'}"
        puts "  Description: #{product.description}" if product.description
        puts

        if product.metadata && product.metadata.any?
          puts 'Metadata:'
          product.metadata.each do |key, value|
            puts "  #{key}: #{value}"
          end
          puts
        end

        # Display marketing features
        if product.marketing_features && product.marketing_features.any?
          puts 'Marketing Features:'
          product.marketing_features.each do |feature|
            puts "  - #{feature.name}"
          end
          puts
        end

        # Get associated prices
        puts 'Prices:'
        prices = Stripe::Price.list({ product: product_id, limit: 100 })

        if prices.data.empty?
          puts '  (none)'
        else
          prices.data.each do |price|
            amount        = format_amount(price.unit_amount, price.currency)
            interval      = price.recurring&.interval || 'one-time'
            interval_text = price.recurring ? "/#{interval}" : ''
            active        = price.active ? 'active' : 'inactive'

            puts "  #{price.id} - #{amount}#{interval_text} (#{active})"
          end
        end
      rescue Stripe::StripeError => ex
        puts "Error retrieving product: #{ex.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing products show', Onetime::CLI::BillingProductsShowCommand
