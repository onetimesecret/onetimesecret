# apps/web/billing/cli/products_validate_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Validate Stripe product metadata
    class BillingProductsValidateCommand < Command
      include BillingHelpers

      desc 'Validate Stripe product metadata completeness'

      def call(**)
        boot_application!

        return unless stripe_configured?

        puts 'Fetching products from Stripe...'
        puts

        products = Stripe::Product.list({ active: true, limit: 100 })

        if products.data.empty?
          puts 'No products found'
          return 0
        end

        invalid_count = 0
        valid_products = []

        products.data.each do |product|
          errors = validate_product_metadata(product)
          if errors.empty?
            valid_products << product
          else
            invalid_count += 1
            puts "#{product.name} (#{product.id}):"
            errors.each { |error| puts "  ✗ #{error}" }
            puts
          end
        end

        # Summary section
        puts '=' * 60
        if invalid_count.zero?
          puts "✅ All #{products.data.size} product(s) have valid metadata"
          puts
        else
          puts "❌ Validation failed: #{invalid_count} product(s) have metadata errors"
          puts
          puts "Valid products (#{valid_products.size}):"
          valid_products.each { |p| puts "  ✓ #{p.name}" }
          puts
          puts 'Required metadata fields:'
          REQUIRED_METADATA_FIELDS.each { |field| puts "  - #{field}" }
          puts
          puts 'To fix metadata:'
          puts '  bin/ots billing products update PRODUCT_ID [options]'
          puts
          puts 'To delete invalid products:'
          puts '  stripe products delete PRODUCT_ID'
          puts
          exit 1
        end

        0
      end
    end
  end
end

Onetime::CLI.register 'billing products validate', Onetime::CLI::BillingProductsValidateCommand
