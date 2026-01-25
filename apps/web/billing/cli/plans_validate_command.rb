# apps/web/billing/cli/plans_validate_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require_relative 'validation_helpers'

module Onetime
  module CLI
    # Validate product-price relationships for production readiness
    class BillingPlansValidateCommand < Command
      include BillingHelpers
      include ValidationHelpers

      desc 'Validate plan production readiness (products + prices)'

      option :strict,
        type: :boolean,
        default: false,
        desc: 'Fail on warnings (default: only fail on errors)'

      def call(strict: false, **)
        boot_application!

        return unless stripe_configured?

        puts 'Validating plan production readiness...'
        puts

        errors   = []
        warnings = []

        # Fetch products and prices from Stripe
        products          = fetch_products
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
      rescue Stripe::StripeError => ex
        puts "❌ Stripe API error: #{ex.message}"
        []
      end

      def fetch_prices_by_product
        all_prices = Stripe::Price.list({ active: true, limit: 100 }).auto_paging_each.to_a
        all_prices.group_by(&:product)
      rescue Stripe::StripeError => ex
        puts "❌ Stripe API error fetching prices: #{ex.message}"
        {}
      end

      def validate_product_prices(product, prices_by_product, errors, warnings)
        product_id = product.id
        plan_id    = product.metadata['plan_id'] || 'unknown'
        prices     = prices_by_product[product_id] || []

        # Filter to recurring prices only
        recurring_prices = prices.select { |p| p.type == 'recurring' }

        # Critical: Product must have at least one recurring price
        if recurring_prices.empty?
          errors << {
            product_id: product_id,
            plan_id: plan_id,
            type: :no_recurring_prices,
            message: 'No recurring prices',
            details: 'Product has 0 recurring prices and cannot be used for subscriptions.',
            resolution: [
              'Create monthly and yearly prices',
              'Or archive product if no longer offered',
              "See: #{stripe_dashboard_url(:product, product_id)}",
            ],
          }
          return
        end

        # Check for both monthly and yearly pricing
        intervals = recurring_prices.map { |p| p.recurring.interval }.uniq
        if intervals.size == 1
          missing = (%w[month year] - intervals).first
          warnings << {
            product_id: product_id,
            plan_id: plan_id,
            type: :missing_interval,
            message: "Missing #{missing}ly price",
            details: "Product only has #{intervals.first}ly pricing. Annual pricing is recommended for better LTV.",
            resolution: ["Add #{missing}ly price option"],
          }
        end

        # Check for duplicate intervals with same currency
        recurring_prices.group_by { |p| [p.recurring.interval, p.currency] }.each do |(interval, currency), group|
          next unless group.size > 1

          warnings << {
            product_id: product_id,
            plan_id: plan_id,
            type: :duplicate_prices,
            message: 'Duplicate interval pricing',
            details: "#{group.size} duplicate #{interval}ly #{currency.upcase} prices found.",
            resolution: ['Consider archiving extras to avoid confusion'],
          }
        end

        # Validate required metadata
        validate_product_metadata(product, errors)

        # Check plan_id uniqueness (detect duplicates)
        validate_plan_id_uniqueness(product, errors)
      end

      def validate_product_metadata(product, errors)
        required_fields = %w[app plan_id tier region]
        missing_fields  = required_fields.reject { |field| product.metadata[field] }

        if missing_fields.any?
          errors << {
            product_id: product.id,
            plan_id: product.metadata['plan_id'] || 'unknown',
            type: :missing_metadata,
            message: 'Missing required metadata',
            details: "Required metadata fields missing: #{missing_fields.join(', ')}",
            resolution: [
              "Update product metadata: bin/ots billing products update #{product.id}",
              "See: #{stripe_dashboard_url(:product, product.id)}",
            ],
          }
        end

        # Validate app field value
        return unless product.metadata['app'] && product.metadata['app'] != 'onetimesecret'

        errors << {
          product_id: product.id,
          plan_id: product.metadata['plan_id'] || 'unknown',
          type: :invalid_app_metadata,
          message: 'Invalid app metadata',
          details: "Expected 'onetimesecret', got '#{product.metadata['app']}'",
          resolution: ['Update app metadata to onetimesecret'],
        }
      end

      def validate_plan_id_uniqueness(product, errors)
        # This will be checked across all products in the summary
        # Individual validation just ensures plan_id exists
        return if product.metadata['plan_id']

        errors << {
          product_id: product.id,
          plan_id: 'none',
          type: :missing_plan_id,
          message: 'Missing plan_id metadata',
          details: 'Product is missing required plan_id metadata field',
          resolution: ["Add plan_id metadata: bin/ots billing products update #{product.id} --plan_id YOUR_PLAN_ID"],
        }
      end

      def check_plan_id_duplicates(products, errors)
        # Check for duplicate plan_ids across products
        plan_ids   = products.map { |p| p.metadata['plan_id'] }.compact
        duplicates = plan_ids.select { |id| plan_ids.count(id) > 1 }.uniq

        duplicates.each do |plan_id|
          matching_products = products.select { |p| p.metadata['plan_id'] == plan_id }
          product_ids       = matching_products.map(&:id).join(', ')
          errors << {
            product_id: product_ids,
            plan_id: plan_id,
            type: :duplicate_plan_id,
            message: "Duplicate plan_id '#{plan_id}'",
            details: "Multiple products share the same plan_id: #{product_ids}",
            resolution: [
              'Each product must have a unique plan_id',
              'Update or archive duplicate products',
            ],
          }
        end
      end

      def print_plan_summary(products, prices_by_product, errors, warnings)
        # Check for plan_id duplicates across all products
        check_plan_id_duplicates(products, errors)

        # Count ready/not ready products
        ready_count = products.count do |p|
          prices = prices_by_product[p.id] || []
          prices.any? { |price| price.type == 'recurring' }
        end

        # Count items using shared helper
        count_valid_items(products, errors, warnings, :id)
        error_count   = errors.select { |e| e.is_a?(Hash) }.map { |e| e[:product_id] }.compact.uniq.size
        warning_count = warnings.select { |w| w.is_a?(Hash) }.map { |w| w[:product_id] }.compact.uniq.size

        # Print summary section
        print_section_header('SUMMARY')
        puts "  Total products:      #{products.size}"
        puts "  Production ready:    #{ready_count}"
        puts "  Not ready:           #{products.size - ready_count}"
        puts "  Issues found:        #{error_count} errors, #{warning_count} warnings"
        puts

        # Print table section
        print_section_header('PLANS')
        puts format(
          '%-22s %-20s %-7s %-16s %s',
          'PRODUCT ID',
          'PLAN ID',
          'REGION',
          'PRICES',
          'STATUS',
        )
        print_separator

        products.sort_by { |p| -(p.metadata['display_order']&.to_i || 0) }.each do |product|
          plan_id          = product.metadata['plan_id'] || '(none)'
          region           = product.metadata['region'] || '(none)'
          prices           = prices_by_product[product.id] || []
          recurring_prices = prices.select { |p| p.type == 'recurring' }

          # Build price summary
          intervals        = recurring_prices.map { |p| p.recurring.interval }.uniq.sort
          price_summary    = if recurring_prices.empty?
                           '0 prices'
                          else
                            "#{recurring_prices.size} (#{intervals.join(', ')})"
                          end

          # Determine status using structured errors/warnings
          product_errors   = errors.select { |e| e.is_a?(Hash) && (e[:product_id] == product.id || e[:plan_id] == plan_id) }
          product_warnings = warnings.select { |w| w.is_a?(Hash) && (w[:product_id] == product.id || w[:plan_id] == plan_id) }

          status = if recurring_prices.empty?
                    STATUS_NOT_READY
                  elsif product_errors.any?
                    STATUS_ERROR
                  elsif product_warnings.any?
                    STATUS_INCOMPLETE
                  else
                    STATUS_READY
                  end

          # Full product ID (no truncation)
          puts format(
            '%-22s %-20s %-7s %-16s %s',
            product.id,
            plan_id[0..18],
            region[0..5],
            price_summary,
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

        # Exit with appropriate code
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
