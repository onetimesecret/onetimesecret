# apps/web/billing/cli/prices_validate_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require_relative 'validation_helpers'

module Onetime
  module CLI
    # Validate Stripe prices for sanity and consistency
    class BillingPricesValidateCommand < Command
      include BillingHelpers
      include ValidationHelpers

      desc 'Validate Stripe prices (Stripe API only)'

      option :product,
        type: :string,
        default: nil,
        desc: 'Filter by product ID'

      option :strict,
        type: :boolean,
        default: false,
        desc: 'Fail on warnings (default: only fail on errors)'

      def call(product: nil, strict: false, **)
        boot_application!

        return unless stripe_configured?

        puts 'Validating Stripe prices...'
        puts

        errors   = []
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
        params           = { active: true, limit: 100 }
        params[:product] = product_filter if product_filter

        Stripe::Price.list(params).auto_paging_each.to_a
      rescue Stripe::StripeError => ex
        puts "❌ Stripe API error: #{ex.message}"
        []
      end

      def fetch_products_map
        # Fetch both active and archived products to distinguish states
        active   = Stripe::Product.list({ active: true, limit: 100 }).auto_paging_each.to_a
        archived = Stripe::Product.list({ active: false, limit: 100 }).auto_paging_each.to_a

        {
          active: active.to_h { |p| [p.id, p] },
          archived: archived.to_h { |p| [p.id, p] },
        }
      rescue Stripe::StripeError => ex
        puts "❌ Warning: Could not fetch products: #{ex.message}"
        { active: {}, archived: {} }
      end

      def validate_price(price, products_map, errors, warnings)
        # Check if product exists in active products
        product = products_map[:active][price.product]

        unless product
          # Check if product is archived
          archived_product = products_map[:archived][price.product]

          errors << if archived_product
            {
              price_id: price.id,
              type: :archived_product,
              message: 'Attached to archived product',
              details: "Product #{price.product} is archived and cannot be used for new subscriptions.",
              resolution: [
                'Create new active product if needed',
                'Archive this price if no longer needed',
                "See: #{stripe_dashboard_url(:price, price.id)}",
              ],
            }
          else
            {
              price_id: price.id,
              type: :missing_product,
              message: 'Product not found',
              details: "Product #{price.product} does not exist in Stripe.",
              resolution: [
                'Verify product ID in Stripe Dashboard',
                'This price may need to be archived',
              ],
            }
                    end
          return
        end

        # Validate price type (should be recurring for subscriptions)
        unless price.type == 'recurring'
          warnings << {
            price_id: price.id,
            type: :wrong_price_type,
            message: "Type is '#{price.type}' (expected: recurring)",
            details: 'Subscription plans should use recurring prices.',
          }
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
          warnings << {
            price_id: price.id,
            type: :unusual_interval,
            message: "Unusual interval '#{recurring.interval}'",
            details: 'Standard subscriptions use monthly or yearly intervals.',
          }
        end

        # Check interval_count (should be 1 for standard subscriptions)
        if recurring.interval_count && recurring.interval_count != 1
          warnings << {
            price_id: price.id,
            type: :unusual_interval_count,
            message: "Interval count is #{recurring.interval_count}",
            details: 'Standard subscriptions use interval_count of 1.',
          }
        end

        # Check usage type
        return if %w[licensed metered].include?(recurring.usage_type)

        warnings << {
          price_id: price.id,
          type: :unusual_usage_type,
          message: "Unusual usage_type '#{recurring.usage_type}'",
          details: 'Expected usage_type: licensed or metered.',
        }
      end

      def validate_price_amount(price, errors, warnings)
        amount = price.unit_amount

        # Check for zero or null amount
        if amount.nil?
          warnings << {
            price_id: price.id,
            type: :null_amount,
            message: 'Amount is null (metered billing)',
            details: 'Metered billing prices have usage-based amounts.',
          }
        elsif amount.zero?
          errors << {
            price_id: price.id,
            type: :zero_amount,
            message: 'Amount is $0.00',
            details: 'Use free tier product instead of zero-price.',
            resolution: [
              'Archive this price',
              'Use proper free tier product for $0 plans',
            ],
          }
        elsif amount < 0
          errors << {
            price_id: price.id,
            type: :negative_amount,
            message: "Negative amount #{amount}",
            details: 'Price amounts must be positive.',
            resolution: ['Fix amount in Stripe Dashboard'],
          }
        end

        # Warn about suspicious amounts (too low/high for typical SaaS)
        return unless amount && price.type == 'recurring'

        interval = price.recurring.interval
        if interval == 'month' && amount < 100
          warnings << {
            price_id: price.id,
            type: :low_monthly_price,
            message: "Very low monthly price ($#{amount / 100.0})",
            details: 'Monthly prices below $1.00 are unusual for SaaS.',
          }
        elsif interval == 'year' && amount < 1000
          warnings << {
            price_id: price.id,
            type: :low_yearly_price,
            message: "Very low yearly price ($#{amount / 100.0})",
            details: 'Yearly prices below $10.00 are unusual for SaaS.',
          }
        elsif amount > 1_000_000
          warnings << {
            price_id: price.id,
            type: :high_price,
            message: "Very high price ($#{amount / 100.0})",
            details: 'Prices above $10,000 are unusual for standard plans.',
          }
        end
      end

      def validate_currency_region(price, product, warnings)
        region = product.metadata['region']
        return unless region

        currency            = price.currency
        expected_currencies = {
          'EU' => %w[eur],
          'CA' => %w[cad],
          'US' => %w[usd],
          'global' => %w[usd eur],
        }

        expected = expected_currencies[region]
        return unless expected && !expected.include?(currency)

        warnings << {
          price_id: price.id,
          type: :currency_region_mismatch,
          message: "Currency '#{currency}' unusual for region '#{region}'",
          details: "Expected: #{expected.join(' or ')}",
          resolution: ['Verify currency matches target market'],
        }
      end

      def check_pricing_consistency(price, product, products_map, warnings)
        return unless price.type == 'recurring'
        return unless product

        # Find other prices for the same product
        other_prices = products_map[:active].values
          .flat_map { |p| Stripe::Price.list({ product: p.id, active: true }).data }
          .select { |p| p.product == price.product && p.id != price.id }

        current_interval  = price.recurring.interval
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
          expected_yearly = (price.unit_amount * 10)..(price.unit_amount * 12)
          unless expected_yearly.include?(opposite_price.unit_amount)
            warnings << {
              price_id: price.id,
              type: :pricing_inconsistency,
              message: 'Pricing consistency issue',
              details: "Yearly price $#{opposite_price.unit_amount / 100.0} is not 10-12x monthly price $#{price.unit_amount / 100.0}.",
              resolution: ['Consider adjusting for typical SaaS discount pattern'],
            }
          end
        end
      rescue Stripe::StripeError
        # Silently skip if we can't fetch related prices
      end

      # stripe_dashboard_url now provided by ValidationHelpers module

      def print_price_summary(prices, products_map, errors, warnings)
        # Count valid prices using shared helper
        valid_count = count_valid_items(prices, errors, warnings, :id)

        # Count error and warning prices
        error_price_ids   = errors.select { |e| e.is_a?(Hash) }.map { |e| e[:price_id] }.compact.uniq
        warning_price_ids = warnings.select { |w| w.is_a?(Hash) }.map { |w| w[:price_id] }.compact.uniq

        # Print summary section
        print_section_header('SUMMARY')
        puts "  Total prices:         #{prices.size}"
        puts "  Valid prices:         #{valid_count}"
        puts "  Prices with errors:   #{error_price_ids.size}"
        puts "  Prices with warnings: #{warning_price_ids.size}"
        puts

        # Print table section
        print_section_header('PRICES', 120)
        puts format(
          '%-31s %-25s %-12s %-9s %s',
          'PRICE ID',
          'PRODUCT',
          'AMOUNT',
          'INTERVAL',
          'STATUS',
        )
        puts '━' * 120

        prices.each do |price|
          product = products_map[:active][price.product]

          # Check if product is archived
          if product.nil?
            archived_product = products_map[:archived][price.product]
            product_name     = archived_product ? '(Archived Product)' : '(Unknown Product)'
          else
            product_name = product.name
          end

          # Truncate product name if too long
          product_name = product_name[0..22] + '...' if product_name.length > 25

          amount_str = if price.unit_amount
                        "#{price.currency.upcase} #{format('%.2f', price.unit_amount / 100.0)}"
                      else
                        'metered'
                      end

          interval_str = price.type == 'recurring' ? price.recurring.interval : price.type

          # Determine status using shared helper
          status = status_for_price(price, errors, warnings)

          puts format(
            '%-31s %-25s %-12s %-9s %s',
            price.id,
            product_name,
            amount_str,
            interval_str,
            status,
          )
        end

        puts
      end

      def print_validation_results(errors, warnings, strict)
        # Use shared helpers for consistent output
        print_errors_section(errors) if errors.any?
        print_warnings_section(warnings) if warnings.any?
        print_final_status(errors, warnings, strict)

        # Exit with appropriate code: fail on errors or warnings in strict mode
        if errors.any? || (warnings.any? && strict)
          exit 1
        else
          exit 0
        end
      end
    end
  end
end

Onetime::CLI.register 'billing prices validate', Onetime::CLI::BillingPricesValidateCommand
