# apps/web/billing/cli/prices_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # List Stripe prices
    class BillingPricesCommand < Command
      include BillingHelpers

      desc 'List all Stripe prices'

      option :product, type: :string, desc: 'Filter by product ID'
      option :active_only, type: :boolean, default: true,
        desc: 'Show only active prices'

      def call(product: nil, active_only: true, **)
        boot_application!

        return unless stripe_configured?

        puts 'Fetching prices from Stripe...'
        params = { active: active_only, limit: 100 }
        params[:product] = product if product

        prices = Stripe::Price.list(params)

        if prices.data.empty?
          puts 'No prices found'
          return
        end

        puts format('%-22s %-22s %-12s %-10s %s',
          'ID', 'PRODUCT', 'AMOUNT', 'INTERVAL', 'ACTIVE')
        puts '-' * 78

        prices.data.each do |price|
          puts format_price_row(price)
        end

        puts "\nTotal: #{prices.data.size} price(s)"
      end
    end
  end
end

Onetime::CLI.register 'billing prices', Onetime::CLI::BillingPricesCommand
