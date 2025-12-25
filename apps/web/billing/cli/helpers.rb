# apps/web/billing/cli/helpers.rb
#
# frozen_string_literal: true

# Load billing models
require_relative '../models'
require_relative '../metadata'

module Onetime
  module CLI
    # Base module for billing command helpers
    module BillingHelpers
      # Use constants from Billing::Metadata module to avoid magic strings
      REQUIRED_METADATA_FIELDS = ::Billing::Metadata::REQUIRED_FIELDS

      # Retry configuration for Stripe API calls
      MAX_STRIPE_RETRIES      = 3
      STRIPE_RETRY_BASE_DELAY = 2 # seconds

      # Execute Stripe API call with automatic retry on network/rate-limit errors
      #
      # Retries Stripe API calls with different backoff strategies:
      # - Linear backoff for network errors (2s, 4s, 6s)
      # - Exponential backoff for rate limits (4s, 8s, 16s)
      # Retries up to MAX_STRIPE_RETRIES times before raising the exception.
      #
      # @param max_retries [Integer] Maximum number of retry attempts (default: 3)
      # @yield Block containing Stripe API call to execute
      # @return Result of the yielded block
      # @raise [Stripe::StripeError] If all retries exhausted or non-retryable error
      #
      # @example
      #   customer = with_stripe_retry do
      #     Stripe::Customer.create(email: 'user@example.com')
      #   end
      #
      def with_stripe_retry(max_retries: MAX_STRIPE_RETRIES)
        retries = 0
        begin
          yield
        rescue Stripe::APIConnectionError => ex
          retries += 1
          if retries <= max_retries
            delay = STRIPE_RETRY_BASE_DELAY * retries
            OT.lw "Stripe API connection error: #{ex.message}, retrying in #{delay}s (attempt #{retries}/#{max_retries})"
            sleep(delay)
            retry
          end
          OT.le "Stripe API connection failed after #{max_retries} retries: #{ex.message}"
          raise
        rescue Stripe::RateLimitError => ex
          retries += 1
          if retries <= max_retries
            # Exponential backoff for rate limits
            delay = STRIPE_RETRY_BASE_DELAY * (2**retries)
            OT.lw "Stripe rate limit hit: #{ex.message}, backing off #{delay}s (attempt #{retries}/#{max_retries})"
            sleep(delay)
            retry
          end
          OT.le "Stripe rate limit exceeded after #{max_retries} retries: #{ex.message}"
          raise
        end
      end

      # Format Stripe error for user-friendly CLI output
      #
      # @param context [String] Context description (e.g., "Failed to create customer")
      # @param error [Stripe::StripeError] The Stripe error to format
      # @return [String] Formatted error message
      def format_stripe_error(context, error)
        case error
        when Stripe::InvalidRequestError
          "#{context}: Invalid parameters - #{error.message}"
        when Stripe::AuthenticationError
          "#{context}: Authentication failed - check STRIPE_KEY configuration"
        when Stripe::CardError
          "#{context}: Card error - #{error.message}"
        when Stripe::APIConnectionError
          "#{context}: Network error - please check connectivity and retry"
        when Stripe::RateLimitError
          "#{context}: Rate limited - please try again in a moment"
        when Stripe::StripeError
          "#{context}: #{error.message}"
        else
          "#{context}: Unexpected error - #{error.class}: #{error.message}"
        end
      end

      def stripe_configured?
        unless OT.billing_config.enabled?
          puts 'Error: Billing not enabled in etc/billing.yaml'
          return false
        end

        stripe_key = OT.billing_config.stripe_key
        if stripe_key.to_s.strip.empty? || stripe_key == 'nostripkey'
          puts 'Error: STRIPE_KEY environment variable not set or billing.yaml has no valid key'
          return false
        end

        require 'stripe'
        Stripe.api_key     = stripe_key
        Stripe.api_version = OT.billing_config.stripe_api_version if OT.billing_config.stripe_api_version
        true
      rescue LoadError
        puts 'Error: stripe gem not installed'
        false
      end

      def format_product_row(product)
        tier                  = product.metadata[Billing::Metadata::FIELD_TIER] || 'N/A'
        tenancy               = product.metadata[Billing::Metadata::FIELD_TENANCY] || 'N/A'
        region                = product.metadata[Billing::Metadata::FIELD_REGION] || 'N/A'
        display_order         = product.metadata[Billing::Metadata::FIELD_DISPLAY_ORDER] || '100'
        show_on_plans         = product.metadata[Billing::Metadata::FIELD_SHOW_ON_PLANS_PAGE] || 'true'
        show_on_plans_display = %w[true 1 yes].include?(show_on_plans.downcase) ? 'yes' : 'no'
        active                = product.active ? 'yes' : 'no'

        format('%-22s %-30s %-12s %-12s %-10s %-8s %-10s %s',
          product.id[0..21],
          product.name[0..29],
          tier[0..11],
          tenancy[0..11],
          region[0..9],
          display_order[0..7],
          show_on_plans_display,
          active,
        )
      end

      def format_price_row(price)
        amount       = format_amount(price.unit_amount, price.currency)
        interval     = price.recurring&.interval || 'one-time'
        price_active = price.active ? 'yes' : 'no'

        # Fetch product details if price.product is an ID (string)
        # Otherwise use expanded product object
        if price.product.is_a?(String)
          begin
            product        = Stripe::Product.retrieve(price.product)
            product_name   = product.name[0..24]
            product_status = product.active ? 'active' : 'inactive'
            plan_id        = product.metadata[Billing::Metadata::FIELD_PLAN_ID] || 'N/A'
          rescue Stripe::StripeError
            product_name   = price.product[0..24]
            product_status = '?'
            plan_id        = 'N/A'
          end
        else
          product_name   = price.product.name[0..24]
          product_status = price.product.active ? 'active' : 'inactive'
          plan_id        = price.product.metadata[Billing::Metadata::FIELD_PLAN_ID] || 'N/A'
        end

        # Format product name with status
        product_with_status = "#{product_name} (#{product_status})"

        format('%-22s %-35s %-15s %-12s %-10s %s',
          price.id[0..21],
          product_with_status[0..34],
          plan_id[0..14],
          amount[0..11],
          interval[0..9],
          price_active,
        )
      end

      def format_plan_row(plan)
        amount             = format_amount(plan.amount, plan.currency)
        entitlements_count = plan.entitlements.size

        format('%-20s %-18s %-10s %-10s %-12s %d',
          plan.plan_id[0..19],
          plan.tier[0..17],
          plan.interval[0..9],
          amount[0..9],
          plan.region[0..11],
          entitlements_count,
        )
      end

      def format_amount(amount_cents, currency)
        return 'N/A' unless amount_cents

        dollars = amount_cents.to_f / 100
        "#{currency&.upcase || 'USD'} #{format('%.2f', dollars)}"
      end

      def validate_product_metadata(product)
        errors = []

        REQUIRED_METADATA_FIELDS.each do |field|
          unless product.metadata[field]
            errors << "Missing required metadata field: #{field}"
          end
        end

        unless product.metadata[Billing::Metadata::FIELD_APP] == Billing::Metadata::APP_NAME
          errors << "Invalid app metadata (should be '#{Billing::Metadata::APP_NAME}')"
        end

        errors
      end

      def prompt_for_metadata
        metadata = {}

        # Always include all metadata fields (using constants)
        metadata[Billing::Metadata::FIELD_APP] = Billing::Metadata::APP_NAME

        print 'Plan ID (optional, e.g., identity_plus_v1): '
        metadata[Billing::Metadata::FIELD_PLAN_ID] = $stdin.gets.chomp

        print 'Tier (e.g., single_team, multi_team): '
        metadata[Billing::Metadata::FIELD_TIER] = $stdin.gets.chomp

        print 'Region (e.g., EU, global): '
        metadata[Billing::Metadata::FIELD_REGION] = $stdin.gets.chomp

        print 'Tenancy (e.g., single, multi): '
        metadata[Billing::Metadata::FIELD_TENANCY] = $stdin.gets.chomp

        print 'Entitlements (comma-separated, e.g., create_secrets,create_team): '
        metadata[Billing::Metadata::FIELD_ENTITLEMENTS] = $stdin.gets.chomp

        print 'Display order (higher = earlier, default: 0): '
        display_order                                    = $stdin.gets.chomp
        metadata[Billing::Metadata::FIELD_DISPLAY_ORDER] = display_order.empty? ? '0' : display_order

        print 'Show on plans page? (yes/no, default: yes): '
        show_on_plans                                         = $stdin.gets.chomp
        # Default to 'yes' if empty, otherwise check for truthy value
        show_on_plans_value                                   = show_on_plans.empty? ? true : Onetime::Utils.yes?(show_on_plans)
        metadata[Billing::Metadata::FIELD_SHOW_ON_PLANS_PAGE] = show_on_plans_value.to_s

        print 'Limit teams (-1 for unlimited): '
        metadata[Billing::Metadata::FIELD_LIMIT_TEAMS] = $stdin.gets.chomp

        print 'Limit members per team (-1 for unlimited): '
        metadata[Billing::Metadata::FIELD_LIMIT_MEMBERS_PER_TEAM] = $stdin.gets.chomp

        metadata[Billing::Metadata::FIELD_CREATED] = Time.now.utc.iso8601

        metadata
      end

      def format_subscription_row(subscription)
        customer_id = subscription.customer[0..21]
        status      = subscription.status[0..11]
        # Note: current_period_end is now at the subscription item level in Stripe API 2025-11-17.clover
        period_end_ts = subscription.items&.data&.first&.current_period_end
        current_period_end = period_end_ts ? Time.at(period_end_ts).strftime('%Y-%m-%d') : 'N/A'

        format('%-22s %-22s %-12s %-12s',
          subscription.id[0..21],
          customer_id,
          status,
          current_period_end,
        )
      end

      def format_customer_row(customer)
        email   = customer.email || 'N/A'
        name    = customer.name || 'N/A'
        created = Time.at(customer.created).strftime('%Y-%m-%d')

        format('%-22s %-30s %-25s %s',
          customer.id[0..21],
          email[0..29],
          name[0..24],
          created,
        )
      end

      def format_invoice_row(invoice)
        customer_id = invoice.customer[0..21]
        amount      = format_amount(invoice.amount_due, invoice.currency)
        status      = invoice.status || 'N/A'
        created     = Time.at(invoice.created).strftime('%Y-%m-%d')

        format('%-22s %-22s %-12s %-10s %s',
          invoice.id[0..21],
          customer_id,
          amount[0..11],
          status[0..9],
          created,
        )
      end

      def format_event_row(event)
        event_type = event.type[0..34]
        created    = Time.at(event.created).strftime('%Y-%m-%d %H:%M:%S')

        format('%-22s %-35s %s',
          event.id[0..21],
          event_type,
          created,
        )
      end

      def format_timestamp(timestamp)
        return 'N/A' unless timestamp

        Time.at(timestamp.to_i).strftime('%Y-%m-%d %H:%M:%S UTC')
      rescue StandardError
        'invalid'
      end

      # Measure API call execution time
      #
      # @yield Block containing API call to measure
      # @return [Array] Result of block and elapsed time in milliseconds
      def measure_api_time
        start_time = Time.now
        result     = yield
        elapsed_ms = ((Time.now - start_time) * 1000).to_i
        [result, elapsed_ms]
      end

      # Load plan IDs from billing catalog
      #
      # @return [Array<String>] Array of plan IDs from catalog
      def load_catalog_plan_ids
        return [] unless Billing::Config.config_exists?

        catalog = Billing::Config.safe_load_config
        plans   = catalog['plans'] || {}
        plans.keys
      end

      # Detect duplicate products (same name + region)
      #
      # @param products [Array<Stripe::Product>] Products to check
      # @return [Hash] Hash with duplicate groups keyed by "name|region"
      def detect_duplicate_products(products)
        product_groups = {}

        products.each do |product|
          region                = product.metadata[Billing::Metadata::FIELD_REGION] || 'global'
          key                   = "#{product.name}|#{region}"
          product_groups[key] ||= []
          product_groups[key] << product
        end

        # Return only groups with duplicates
        product_groups.select { |_, prods| prods.size > 1 }
      end

      # Format validation table header with box-drawing characters
      def print_validation_section_header(title)
        puts "┌─ #{title} " + ('─' * (67 - title.length - 4))
        puts
      end

      # Format validation table footer
      def print_validation_section_footer
        puts ' ' * 67
        puts '└' + ('─' * 67)
      end

      # Print a simple table row for validation output
      #
      # @param name [String] Product name
      # @param id [String] Product ID
      # @param plan_id [String] Plan ID
      # @param status [String] Validation status marker (✓ or ✗)
      def print_validation_row(name, id, plan_id, status)
        name_display    = name[0..19].ljust(20)
        id_display      = id[0..21].ljust(22)
        plan_id_display = plan_id[0..13].ljust(14)

        puts "│  #{status} #{name_display}  #{id_display}  #{plan_id_display}│"
      end

      # Print duplicate comparison (side-by-side)
      #
      # @param group_name [String] Name of the duplicate group
      # @param products [Array<Stripe::Product>] Products in the group
      def print_duplicate_group(group_name, products)
        # Sort: valid products first
        sorted = products.sort_by do |p|
          has_plan_id = p.metadata[Billing::Metadata::FIELD_PLAN_ID]
          has_plan_id ? 0 : 1
        end

        puts "│  #{group_name}" + (' ' * (59 - group_name.length)) + '│'

        sorted.each do |product|
          plan_id         = product.metadata[Billing::Metadata::FIELD_PLAN_ID]
          status          = plan_id ? '✓' : '✗'
          plan_id_display = plan_id || '(no plan_id)'
          validation      = plan_id ? 'VALID' : 'INVALID'

          line    = "    #{status} #{product.id.ljust(22)}  #{plan_id_display.ljust(14)} #{validation}"
          padding = 61 - line.length
          puts "│#{line}" + (' ' * padding) + '│'
        end

        puts '│' + (' ' * 61) + '│'
      end

      # Print compact duplicate comparison with region and active status
      #
      # @param name [String] Product name
      # @param products [Array<Stripe::Product>] Products in the group
      def print_duplicate_group_compact(name, products)
        # Sort: active products first
        sorted = products.sort_by { |p| p.active ? 0 : 1 }

        # Header with name and Active? column
        puts "  #{name.ljust(52)} Active?"

        sorted.each do |product|
          plan_id = product.metadata[Billing::Metadata::FIELD_PLAN_ID] || 'n/a'
          region  = product.metadata[Billing::Metadata::FIELD_REGION] || 'n/a'
          active  = product.active ? 'YES' : 'NO'
          status  = '✓'

          # Format: ✓ prod_id  plan_id  region  active
          puts "    #{status} #{product.id.ljust(20)}  #{plan_id.ljust(18)} #{region.ljust(10)} #{active.ljust(7)}"
        end

        puts
      end
    end
  end
end
