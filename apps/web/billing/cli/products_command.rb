# apps/web/billing/cli/products_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # List Stripe products
    class BillingProductsCommand < Command
      include BillingHelpers

      desc 'List all Stripe products'

      option :active_only, type: :boolean, default: true,
        desc: 'Show only active products'

      def call(active_only: true, **)
        boot_application!

        return unless stripe_configured?

        puts 'Fetching products from Stripe...'
        products = Stripe::Product.list({ active: active_only, limit: 100 })

        if products.data.empty?
          puts 'No products found'
          return
        end

        puts format('%-22s %-40s %-12s %-12s %-10s %s',
          'ID', 'NAME', 'TIER', 'TENANCY', 'REGION', 'ACTIVE'
        )
        puts '-' * 101

        products.data.each do |product|
          puts format_product_row(product)
        end

        puts "\nTotal: #{products.data.size} product(s)"
      end
    end
  end
end

Onetime::CLI.register 'billing products', Onetime::CLI::BillingProductsCommand
