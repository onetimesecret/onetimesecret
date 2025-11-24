# apps/web/billing/cli/prices_validate_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Validate Stripe prices for sanity and consistency
    class BillingPricesValidateCommand < Command
      include BillingHelpers

      desc 'Validate Stripe prices (Stripe API only)'

      option :product, type: :string, default: nil,
        desc: 'Filter by product ID'

      option :strict, type: :boolean, default: false,
        desc: 'Fail on warnings (default: only fail on errors)'

      def call(product: nil, strict: false, **)
        boot_application!

        return unless stripe_configured?

        puts 'Validating Stripe prices...'
        puts

        errors = []
        warnings = []

        # Fetch prices from Stripe
        prices = fetch_prices(product)

        if prices.empty?
          puts 'No prices found'
          return
        end

        # Fetch products for lookup
        products_map = fetch_products_map

        # Validate each price
        prices.each do |price|
          validate_price(price, products_map, errors, warnings)
        end

        # Report results
        print_price_summary(prices, products_map, errors, warnings)
        print_validation_results(errors, warnings, strict)
      end

      private

      def fetch_prices(product_filter = nil)
        params = { active: true, limit: 100 }
        params[:product] = product_filter if product_filter

        Stripe::Price.list(params).auto_paging_each.to_a
      rescue Stripe::StripeError => e
        puts "❌ Stripe API error: #{e.message}"
        []
      end

      def fetch_products_map
        products = Stripe::Product.list({ active: true, limit: 100 }).auto_paging_each.to_a
        products.to_h { |p| [p.id, p] }
      rescue Stripe::StripeError => e
        puts "❌ Warning: Could not fetch products: #{e.message}"
        {}
      end

      def validate_price(price, products_map, errors, warnings)
        # Check if product exists
        product = products_map[price.product]
        unless product
          errors << "Price #{price.id}: Product #{price.product} not found or inactive"
          return
        end

        # Validate price type (should be recurring for subscriptions)
        unless price.type == 'recurring'
          warnings << "Price #{price.id}: Type is '#{price.type}' (expected: recurring for subscriptions)"
        end

        # Validate recurring configuration
        if price.type == 'recurring'
          validate_recurring_price(price, errors, warnings)
        end

        # Validate amount
        validate_price_amount(price, errors, warnings)

        # Validate currency consistency with region
        validate_currency_region(price, product, warnings)

        # Check for reasonable pricing (yearly ~= monthly * 10-12)
        check_pricing_consistency(price, products_map[price.product], products_map, warnings)
      end

      def validate_recurring_price(price, _errors, warnings)
        recurring = price.recurring

        # Check interval
        unless %w[month year].include?(recurring.interval)
          warnings << "Price #{price.id}: Unusual interval '#{recurring.interval}' (expected: month or year)"
        end

        # Check interval_count (should be 1 for standard subscriptions)
        if recurring.interval_count && recurring.interval_count != 1
          warnings << "Price #{price.id}: Interval count is #{recurring.interval_count} (standard subscriptions use 1)"
        end

        # Check usage type
        unless %w[licensed metered].include?(recurring.usage_type)
          warnings << "Price #{price.id}: Unusual usage_type '#{recurring.usage_type}'"
        end
      end

      def validate_price_amount(price, errors, warnings)
        amount = price.unit_amount

        # Check for zero or null amount
        if amount.nil?
          warnings << "Price #{price.id}: Amount is null (metered billing)"
        elsif amount.zero?
          errors << "Price #{price.id}: Amount is zero (use free tier instead)"
        elsif amount < 0
          errors << "Price #{price.id}: Negative amount #{amount}"
        end

        # Warn about suspicious amounts (too low/high for typical SaaS)
        if amount && price.type == 'recurring'
          interval = price.recurring.interval
          if interval == 'month' && amount < 100
            warnings << "Price #{price.id}: Very low monthly price ($#{amount / 100.0})"
          elsif interval == 'year' && amount < 1000
            warnings << "Price #{price.id}: Very low yearly price ($#{amount / 100.0})"
          elsif amount > 1_000_000
            warnings << "Price #{price.id}: Very high price ($#{amount / 100.0})"
          end
        end
      end

      def validate_currency_region(price, product, warnings)
        region = product.metadata['region']
        return unless region

        currency = price.currency
        expected_currencies = {
          'EU' => %w[eur],
          'CA' => %w[cad],
          'US' => %w[usd],
          'global' => %w[usd eur]
        }

        expected = expected_currencies[region]
        if expected && !expected.include?(currency)
          warnings << "Price #{price.id}: Currency '#{currency}' unusual for region '#{region}' (expected: #{expected.join(' or ')})"
        end
      end

      def check_pricing_consistency(price, product, products_map, warnings)
        return unless price.type == 'recurring'
        return unless product

        # Find other prices for the same product
        other_prices = products_map.values
          .flat_map { |p| Stripe::Price.list({ product: p.id, active: true }).data }
          .select { |p| p.product == price.product && p.id != price.id }

        current_interval = price.recurring.interval
        opposite_interval = current_interval == 'month' ? 'year' : 'month'

        # Find opposite interval price
        opposite_price = other_prices.find do |p|
          p.type == 'recurring' &&
            p.recurring.interval == opposite_interval &&
            p.currency == price.currency
        end

        return unless opposite_price

        # Check pricing consistency (yearly should be ~10-12x monthly)
        if current_interval == 'month'
          expected_yearly = price.unit_amount * 10..price.unit_amount * 12
          unless expected_yearly.include?(opposite_price.unit_amount)
            warnings << "Price #{price.id}: Yearly price #{opposite_price.id} ($#{opposite_price.unit_amount / 100.0}) " \
                        "seems inconsistent with monthly ($#{price.unit_amount / 100.0})"
          end
        end
      rescue Stripe::StripeError
        # Silently skip if we can't fetch related prices
      end

      def print_price_summary(prices, products_map, errors, warnings)
        puts format('%-15s %-18s %-15s %-8s %-10s %s',
                    'PRICE ID', 'PRODUCT', 'AMOUNT', 'INTERVAL', 'ACTIVE', 'STATUS')
        puts '-' * 100

        prices.each do |price|
          product = products_map[price.product]
          product_name = product ? product.name[0..15] : '(unknown)'

          amount_str = if price.unit_amount
                        "#{price.currency.upcase} #{price.unit_amount / 100.0}"
                      else
                        'metered'
                      end

          interval_str = price.type == 'recurring' ? price.recurring.interval : price.type
          active_str = price.active ? 'yes' : 'no'

          # Determine status
          price_errors = errors.select { |e| e.include?(price.id) }
          price_warnings = warnings.select { |w| w.include?(price.id) }

          status = if price_errors.any?
                    '✗ INVALID'
                  elsif price_warnings.any?
                    '⚠️  WARNING'
                  else
                    '✓'
                  end

          puts format('%-15s %-18s %-15s %-8s %-10s %s',
                      price.id[0..13], product_name, amount_str, interval_str, active_str, status)
        end

        puts
        puts "Total: #{prices.size} price(s)"
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
          puts '   ✅  VALIDATION PASSED'
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

Onetime::CLI.register 'billing prices validate', Onetime::CLI::BillingPricesValidateCommand
