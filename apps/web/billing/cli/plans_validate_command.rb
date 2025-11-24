# apps/web/billing/cli/plans_validate_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Validate product-price relationships for production readiness
    class BillingPlansValidateCommand < Command
      include BillingHelpers

      desc 'Validate plan production readiness (products + prices)'

      option :strict, type: :boolean, default: false,
        desc: 'Fail on warnings (default: only fail on errors)'

      def call(strict: false, **)
        boot_application!

        return unless stripe_configured?

        puts 'Validating plan production readiness...'
        puts

        errors = []
        warnings = []

        # Fetch products and prices from Stripe
        products = fetch_products
        prices_by_product = fetch_prices_by_product

        if products.empty?
          puts 'No products found'
          return
        end

        # Validate each product has prices
        products.each do |product|
          validate_product_prices(product, prices_by_product, errors, warnings)
        end

        # Report results
        print_plan_summary(products, prices_by_product, errors, warnings)
        print_validation_results(errors, warnings, strict)
      end

      private

      def fetch_products
        products = Stripe::Product.list({ active: true, limit: 100 }).auto_paging_each
        products.select { |p| p.metadata['app'] == 'onetimesecret' }.to_a
      rescue Stripe::StripeError => e
        puts "❌ Stripe API error: #{e.message}"
        []
      end

      def fetch_prices_by_product
        all_prices = Stripe::Price.list({ active: true, limit: 100 }).auto_paging_each.to_a
        all_prices.group_by(&:product)
      rescue Stripe::StripeError => e
        puts "❌ Stripe API error fetching prices: #{e.message}"
        {}
      end

      def validate_product_prices(product, prices_by_product, errors, warnings)
        product_id = product.id
        plan_id = product.metadata['plan_id'] || 'unknown'
        prices = prices_by_product[product_id] || []

        # Filter to recurring prices only
        recurring_prices = prices.select { |p| p.type == 'recurring' }

        # Critical: Product must have at least one recurring price
        if recurring_prices.empty?
          errors << "Product #{product_id} (#{plan_id}): NO RECURRING PRICES - Cannot be used"
          return
        end

        # Check for both monthly and yearly pricing
        intervals = recurring_prices.map { |p| p.recurring.interval }.uniq
        if intervals.size == 1
          missing = (%w[month year] - intervals).first
          warnings << "Product #{product_id} (#{plan_id}): Missing #{missing}ly price (recommend both)"
        end

        # Check for duplicate intervals with same currency
        recurring_prices.group_by { |p| [p.recurring.interval, p.currency] }.each do |(interval, currency), group|
          if group.size > 1
            warnings << "Product #{product_id} (#{plan_id}): #{group.size} duplicate #{interval}ly #{currency.upcase} prices"
          end
        end

        # Validate required metadata
        validate_product_metadata(product, errors)

        # Check plan_id uniqueness (detect duplicates)
        validate_plan_id_uniqueness(product, errors)
      end

      def validate_product_metadata(product, errors)
        required_fields = %w[app plan_id tier region]

        required_fields.each do |field|
          unless product.metadata[field]
            errors << "Product #{product.id}: Missing required metadata '#{field}'"
          end
        end

        # Validate app field value
        if product.metadata['app'] && product.metadata['app'] != 'onetimesecret'
          errors << "Product #{product.id}: Invalid app metadata (expected: 'onetimesecret', got: '#{product.metadata['app']}')"
        end
      end

      def validate_plan_id_uniqueness(product, errors)
        # This will be checked across all products in the summary
        # Individual validation just ensures plan_id exists
        return if product.metadata['plan_id']

        errors << "Product #{product.id}: Missing plan_id metadata"
      end

      def check_plan_id_duplicates(products, errors)
        # Check for duplicate plan_ids across products
        plan_ids = products.map { |p| p.metadata['plan_id'] }.compact
        duplicates = plan_ids.select { |id| plan_ids.count(id) > 1 }.uniq

        duplicates.each do |plan_id|
          matching_products = products.select { |p| p.metadata['plan_id'] == plan_id }
          product_ids = matching_products.map(&:id).join(', ')
          errors << "Duplicate plan_id '#{plan_id}' found in products: #{product_ids}"
        end
      end

      def print_plan_summary(products, prices_by_product, errors, warnings)
        # Check for plan_id duplicates across all products
        check_plan_id_duplicates(products, errors)

        puts
        puts format('%-18s %-20s %-15s %-8s %s',
                    'PRODUCT ID', 'PLAN ID', 'REGION', 'PRICES', 'STATUS')
        puts '-' * 90

        products.sort_by { |p| -(p.metadata['display_order']&.to_i || 0) }.each do |product|
          plan_id = product.metadata['plan_id'] || '(none)'
          region = product.metadata['region'] || '(none)'
          prices = prices_by_product[product.id] || []
          recurring_prices = prices.select { |p| p.type == 'recurring' }

          # Build price summary
          intervals = recurring_prices.map { |p| p.recurring.interval }.uniq.sort
          price_summary = if recurring_prices.empty?
                           '0 prices'
                          else
                            "#{recurring_prices.size} (#{intervals.join(', ')})"
                          end

          # Determine status
          product_errors = errors.select { |e| e.include?(product.id) || e.include?(plan_id) }
          product_warnings = warnings.select { |w| w.include?(product.id) || w.include?(plan_id) }

          status = if recurring_prices.empty?
                    '✗ NOT READY - No prices'
                  elsif product_errors.any?
                    '✗ INVALID'
                  elsif product_warnings.any?
                    '⚠️  WARNING'
                  else
                    '✓ Ready'
                  end

          puts format('%-18s %-20s %-15s %-8s %s',
                      product.id[0..16], plan_id[0..18], region[0..13], price_summary, status)
        end

        puts
        ready_count = products.count do |p|
          prices = prices_by_product[p.id] || []
          prices.any? { |price| price.type == 'recurring' }
        end

        puts "Plans ready for production: #{ready_count}/#{products.size}"
      end

      def print_validation_results(errors, warnings, strict)
        puts

        if errors.any?
          puts '  ' + '━' * 62
          puts "   ❌  VALIDATION FAILED: #{errors.size} error(s) found"
          puts '  ' + '━' * 62
          puts
          errors.each { |error| puts "  ✗ #{error}" }
          puts
          puts 'Plans with errors are NOT production-ready'
          puts
        elsif warnings.any? && strict
          puts '  ' + '━' * 62
          puts "   ❌  VALIDATION FAILED: #{warnings.size} warning(s) in strict mode"
          puts '  ' + '━' * 62
          puts
          warnings.each { |warning| puts "  • #{warning}" }
          puts
        elsif warnings.any?
          puts '  ' + '━' * 62
          puts '   ✅  VALIDATION PASSED (warnings only)'
          puts '  ' + '━' * 62
          puts
          puts "  ⚠️  #{warnings.size} warning(s):"
          puts
          warnings.each { |warning| puts "  • #{warning}" }
          puts
        else
          puts '  ' + '━' * 62
          puts '   ✅  ALL PLANS PRODUCTION-READY'
          puts '  ' + '━' * 62
          puts
        end

        if errors.empty? && warnings.empty?
          exit 0
        elsif errors.empty? && !strict
          exit 0
        elsif errors.any? || (warnings.any? && strict)
          exit 1
        end
      end
    end
  end
end

Onetime::CLI.register 'billing plans validate', Onetime::CLI::BillingPlansValidateCommand
