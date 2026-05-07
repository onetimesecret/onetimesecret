# apps/web/billing/cli/products_validate_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require_relative 'validation_helpers'

module Onetime
  module CLI
    # Validate Stripe product metadata
    class BillingProductsValidateCommand < Command
      include BillingHelpers
      include ValidationHelpers

      desc 'Validate Stripe product metadata completeness'

      option :check_field_names,
        type: :boolean,
        default: true,
        desc: 'Check metadata keys against canonical Metadata::FIELD_* constants'

      def call(check_field_names: true, **)
        boot_application!

        return unless stripe_configured?

        # Fetch products with timing
        api_key     = Stripe.api_key || 'unknown'
        key_prefix  = api_key[0..13]
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

        errors   = []
        warnings = []

        # Validate each product and collect structured errors
        products.data.each do |product|
          validate_product(product, errors, warnings)
          check_field_name_variants(product, warnings) if check_field_names
        end

        # Fetch price counts for display
        price_counts = fetch_price_counts(products.data)

        # Display results
        print_products_summary(products.data, price_counts, errors, warnings)
        print_errors_section(errors) if errors.any?
        print_warnings_section(warnings) if warnings.any?
        print_final_status(errors, warnings, false)

        errors.any? ? exit(1) : exit(0)
      end

      private

      def validate_product(product, errors, warnings)
        required_fields = %w[app plan_id tier region]
        missing_fields  = required_fields.reject { |field| product.metadata[field] }

        if missing_fields.any?
          errors << {
            product_id: product.id,
            type: :missing_metadata,
            message: 'Missing required metadata',
            details: "Required fields missing: #{missing_fields.join(', ')}",
            resolution: [
              "Update metadata: bin/ots billing products update #{product.id}",
              'Or archive if not needed',
              "See: #{stripe_dashboard_url(:product, product.id)}",
            ],
          }
        end

        # Detect legacy/typo field name variants for plan_id
        detect_plan_id_variants(product, warnings)

        # Check for duplicate plan_ids (will be detected across all products)
        # Individual validation just ensures plan_id exists
        return if product.metadata['plan_id']

        warnings << {
          product_id: product.id,
          type: :missing_plan_id,
          message: 'Missing plan_id',
          details: 'Product metadata missing plan_id field',
        }
      end

      # Detect legacy or typo field name variants for plan_id
      #
      # @param product [Stripe::Product] The Stripe product
      # @param warnings [Array] Warnings collection to append to
      def detect_plan_id_variants(product, warnings)
        metadata = product.metadata || {}

        if metadata['planid']
          warnings << {
            product_id: product.id,
            type: :field_variant,
            message: "Found 'planid', expected 'plan_id'",
            details: 'Metadata uses wrong field name (missing underscore)',
          }
        end

        return unless metadata['plan']

        warnings << {
          product_id: product.id,
          type: :field_variant,
          message: "Found legacy 'plan' field, expected 'plan_id'",
          details: 'Metadata uses deprecated field name',
        }
      end

      # Check all metadata keys against canonical Metadata::FIELD_* constants
      #
      # @param product [Stripe::Product] The Stripe product
      # @param warnings [Array] Warnings collection to append to
      def check_field_name_variants(product, warnings)
        metadata = product.metadata || {}
        return if metadata.empty?

        # Build set of canonical field names from Metadata constants
        canonical_fields = ::Billing::Metadata.constants
          .select { |c| c.to_s.start_with?('FIELD_') }
          .to_set { |c| ::Billing::Metadata.const_get(c) }

        # Also include limit fields
        canonical_fields.merge(::Billing::Metadata::LIMIT_FIELDS.keys)

        metadata.each_key do |key|
          next if canonical_fields.include?(key)

          # Skip known Stripe-managed fields
          next if %w[complimentary].include?(key)

          warnings << {
            product_id: product.id,
            type: :unknown_field,
            message: "Unknown metadata field '#{key}'",
            details: 'Field not in Billing::Metadata::FIELD_* constants',
          }
        end
      end

      def print_products_summary(products, price_counts, errors, warnings)
        valid_count     = count_valid_items(products, errors, warnings, :id)
        error_count     = errors.size
        duplicate_count = detect_duplicate_plan_ids(products)

        # Print summary section
        print_section_header('SUMMARY')
        puts "  Total products:      #{products.size}"
        puts "  Valid metadata:      #{valid_count}"
        puts "  Incomplete:          #{error_count}"
        puts "  Duplicate plan_ids:  #{duplicate_count}"
        puts

        # Print table section
        print_section_header('PRODUCTS')
        puts format(
          '%-22s %-20s %-20s %-7s %-7s %s',
          'PRODUCT ID',
          'NAME',
          'PLAN ID',
          'REGION',
          'PRICES',
          'STATUS',
        )
        print_separator

        products.each do |product|
          product_errors   = errors.select { |e| e.is_a?(Hash) && e[:product_id] == product.id }
          product_warnings = warnings.select { |w| w.is_a?(Hash) && w[:product_id] == product.id }

          name        = product.name[0..18]
          plan_id     = product.metadata['plan_id'] || 'n/a'
          region      = product.metadata['region'] || 'n/a'
          price_count = price_counts[product.id] || 0

          status = if product_errors.any?
                    STATUS_INCOMPLETE
                  elsif product_warnings.any?
                    STATUS_WARNING
                  else
                    STATUS_VALID
                  end

          puts format(
            '%-22s %-20s %-20s %-7s %-7s %s',
            product.id,
            name,
            plan_id[0..18],
            region[0..5],
            price_count,
            status,
          )
        end

        puts
      end

      def detect_duplicate_plan_ids(products)
        plan_ids = products.map { |p| p.metadata['plan_id'] }.compact
        plan_ids.size - plan_ids.uniq.size
      end

      def fetch_price_counts(_products)
        # Fetch all prices and count by product
        prices       = Stripe::Price.list({ active: true, limit: 100 }).auto_paging_each
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
