# apps/web/billing/cli/validate_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Validate product metadata
    class BillingValidateCommand < Command
      include BillingHelpers

      desc 'Validate Stripe product metadata'

      def call(**)
        boot_application!

        return unless stripe_configured?

        puts 'Fetching products from Stripe...'
        products = Stripe::Product.list({ active: true, limit: 100 })

        if products.data.empty?
          puts 'No products found'
          return
        end

        invalid_count = 0
        products.data.each do |product|
          errors = validate_product_metadata(product)
          next if errors.empty?

          invalid_count += 1
          puts "\n#{product.name} (#{product.id}):"
          errors.each { |error| puts "  ✗ #{error}" }
        end

        if invalid_count.zero?
          puts "✓ All #{products.data.size} product(s) have valid metadata"
        else
          puts "\n#{invalid_count} product(s) have metadata errors"
          puts "\nRequired metadata fields:"
          REQUIRED_METADATA_FIELDS.each { |field| puts "  - #{field}" }
          puts "\nTo fix: bin/ots billing products update PRODUCT_ID [options]"
          puts "To delete: stripe products delete PRODUCT_ID"
          exit invalid_count
        end
      end
    end
  end
end

Onetime::CLI.register 'billing validate', Onetime::CLI::BillingValidateCommand
