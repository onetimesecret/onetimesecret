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

        # Fetch products with timing
        api_key = Stripe.api_key || 'unknown'
        key_prefix = api_key[0..13]
        api_version = Stripe.api_version || 'unknown'

        printf "Fetching products from Stripe API [#{key_prefix}/#{api_version}]..."
        $stdout.flush

        products, elapsed_ms = measure_api_time do
          Stripe::Product.list({ active: true, limit: 100 })
        end

        puts " found #{products.data.size} product(s) in #{elapsed_ms}ms"
        puts

        if products.data.empty?
          puts 'No products found'
          return 0
        end

        # Detect duplicates
        duplicates = detect_duplicate_products(products.data)

        # Categorize products
        valid_products = []
        invalid_products = []

        products.data.each do |product|
          errors = validate_product_metadata(product)
          if errors.empty?
            valid_products << product
          else
            invalid_products << product
          end
        end

        # Determine overall validation status
        has_duplicates = duplicates.any?
        has_invalid = invalid_products.any?
        validation_passed = !has_duplicates && !has_invalid

        # Display results
        if validation_passed
          display_success(valid_products)
          return 0
        else
          display_failure(duplicates, invalid_products, valid_products)
          exit 1
        end
      end

      private

      def display_success(valid_products)
        puts '  ' + '━' * 62
        puts "   ✅  VALIDATION PASSED: #{valid_products.size} products valid"
        puts '  ' + '━' * 62
        puts
        print_valid_products_section(valid_products)
      end

      def display_failure(duplicates, invalid_products, valid_products)
        total = duplicates.values.flatten.size + invalid_products.size + valid_products.size
        invalid_count = invalid_products.size

        puts '  ' + '━' * 62
        puts "   🔴  VALIDATION FAILED: #{invalid_count} of #{total} products incomplete"
        puts '  ' + '━' * 62
        puts

        # Show duplicates first (issues)
        if duplicates.any?
          print_duplicates_section(duplicates)
          puts
        end

        # Show valid products
        if valid_products.any?
          print_valid_products_section(valid_products)
          puts
        end

        # Show invalid products
        if invalid_products.any?
          print_invalid_products_section(invalid_products)
        end
      end

      def print_duplicates_section(duplicates)
        print_validation_section_header("ISSUES")
        puts "  ⚠️  #{duplicates.size} conflict(s)"
        puts

        duplicates.each do |key, products|
          name, _region = key.split('|')
          print_duplicate_group_compact(name, products)
        end

        print_validation_section_footer
      end

      def print_invalid_products_section(invalid_products)
        print_validation_section_header("INVALID (#{invalid_products.size})")

        invalid_products.each do |product|
          plan_id = product.metadata[Billing::Metadata::FIELD_PLAN_ID] || 'n/a'
          region = product.metadata[Billing::Metadata::FIELD_REGION] || 'n/a'
          active = product.active ? 'YES' : 'NO'

          # Format: ✗ prod_id  name  plan_id  active
          puts "  ✗ #{product.id.ljust(20)}  #{product.name.ljust(20)} #{plan_id.ljust(12)} #{active.ljust(7)}"
        end

        puts
        puts '      See details:'
        puts '        bin/ots billing products --invalid'

        print_validation_section_footer
      end

      def print_valid_products_section(valid_products)
        print_validation_section_header("VALID (#{valid_products.size})")

        # Fetch price counts for all products
        price_counts = fetch_price_counts(valid_products)

        valid_products.each do |product|
          plan_id = product.metadata[Billing::Metadata::FIELD_PLAN_ID] || 'n/a'
          region = product.metadata[Billing::Metadata::FIELD_REGION] || 'n/a'
          name = product.name
          price_count = price_counts[product.id] || 0

          # Format: ✓ prod_id  name  plan_id  region  [N prices]
          price_indicator = price_count.zero? ? "[0 prices]" : "[#{price_count} prices]"
          puts "  ✓ #{product.id.ljust(20)}  #{name.ljust(20)} #{plan_id.ljust(17)} #{region.ljust(6)} #{price_indicator}"
        end

        print_validation_section_footer
      end

      def fetch_price_counts(products)
        # Fetch all prices and count by product
        prices = Stripe::Price.list({ active: true, limit: 100 }).auto_paging_each
        price_counts = Hash.new(0)

        prices.each do |price|
          # Only count recurring prices (subscription prices)
          price_counts[price.product] += 1 if price.type == 'recurring'
        end

        price_counts
      rescue Stripe::StripeError
        # If we can't fetch prices, return empty hash
        {}
      end
    end
  end
end

Onetime::CLI.register 'billing products validate', Onetime::CLI::BillingProductsValidateCommand
