# apps/web/billing/cli/prices_create_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Create Stripe price
    class BillingPricesCreateCommand < Command
      include BillingHelpers

      desc 'Create a new Stripe price'

      argument :product_id, required: false, desc: 'Product ID (e.g., prod_xxx)'

      option :amount, type: :integer, desc: 'Amount in cents (e.g., 900 for $9.00)'
      option :currency, type: :string, default: 'usd', desc: 'Currency code'
      option :interval, type: :string, default: 'month',
        desc: 'Billing interval (month, year, week, day)'
      option :interval_count, type: :integer, default: 1,
        desc: 'Number of intervals between billings'

      def call(product_id: nil, amount: nil, currency: 'usd', interval: 'month', interval_count: 1, **)
        boot_application!

        return unless stripe_configured?

        if product_id.nil?
          print 'Product ID: '
          input = $stdin.gets
          product_id = input&.chomp
        end

        if product_id.to_s.strip.empty?
          puts 'Error: Product ID is required'
          return
        end

        # Verify product exists
        product = Stripe::Product.retrieve(product_id)
        puts "Product: #{product.name}"

        if amount.nil?
          print 'Amount in cents (e.g., 900 for $9.00): '
          input = $stdin.gets
          amount = input&.chomp&.to_i || 0
        else
          amount = amount.to_i
        end

        if amount <= 0
          puts 'Error: Amount must be greater than 0'
          return
        end

        unless %w[month year week day].include?(interval)
          puts 'Error: Interval must be one of: month, year, week, day'
          return
        end

        puts "\nCreating price:"
        puts "  Product: #{product_id}"
        puts "  Amount: #{format_amount(amount, currency)}"
        puts "  Interval: #{interval_count} #{interval}(s)"

        print "\nProceed? (y/n): "
        response = $stdin.gets
        return unless response&.chomp&.downcase == 'y'

        price = Stripe::Price.create({
          product: product_id,
          unit_amount: amount,
          currency: currency,
          recurring: {
            interval: interval,
            interval_count: interval_count,
          },
        })

        puts "\nPrice created successfully:"
        puts "  ID: #{price.id}"
        puts "  Amount: #{format_amount(price.unit_amount, price.currency)}"
        puts "  Interval: #{price.recurring.interval_count} #{price.recurring.interval}(s)"
      rescue Stripe::StripeError => e
        puts "Error creating price: #{e.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing prices create', Onetime::CLI::BillingPricesCreateCommand
