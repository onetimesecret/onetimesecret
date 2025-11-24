# apps/web/billing/cli/products_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # List Stripe products
    #
    # NOTE: Product deletion is intentionally not implemented.
    # To delete products, use the Stripe CLI directly:
    #   stripe products delete PRODUCT_ID
    #
    # We support creating and updating products, but not deleting them
    # to prevent accidental data loss.
    class BillingProductsCommand < Command
      include BillingHelpers

      desc 'List all Stripe products and manage product operations'

      option :active_only, type: :boolean, default: true,
        desc: 'Show only active products'

      option :help, type: :boolean, default: false,
        desc: 'Show available subcommands'

      def call(active_only: true, help: false, **)
        if help
          show_help
          return 0
        end

        boot_application!

        return unless stripe_configured?

        puts 'Fetching products from Stripe...'
        products = Stripe::Product.list({ active: active_only, limit: 100 })

        if products.data.empty?
          puts 'No products found'
          return
        end

        puts format('%-22s %-30s %-12s %-12s %-10s %-8s %-10s %s',
          'ID', 'NAME', 'TIER', 'TENANCY', 'REGION', 'ORDER', 'SHOW', 'ACTIVE'
        )
        puts '-' * 125

        products.data.each do |product|
          puts format_product_row(product)
        end

        puts "\nTotal: #{products.data.size} product(s)"
        puts "\nNote: To delete products, use: stripe products delete PRODUCT_ID"
      end

      private

      def show_help
        puts <<~HELP
          Manage Stripe products including creation, updates, listing, and validation.

          Available subcommands:
            (none)     - List all Stripe products
            create     - Create a new Stripe product with metadata
            show       - Show details for a specific product
            update     - Update product metadata
            validate   - Validate product metadata completeness
            events     - Show product-related events

          Examples:
            bin/ots billing products                      # List all products
            bin/ots billing products validate            # Validate metadata
            bin/ots billing products show prod_xxx       # Show product details
            bin/ots billing products create --interactive  # Create new product

          Use 'bin/ots billing products SUBCOMMAND --help' for more information.
        HELP
      end
    end
  end
end

Onetime::CLI.register 'billing products', Onetime::CLI::BillingProductsCommand
