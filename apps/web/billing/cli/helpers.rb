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
      REQUIRED_METADATA_FIELDS = Billing::Metadata::REQUIRED_FIELDS

      # Retry configuration for Stripe API calls
      MAX_STRIPE_RETRIES = 3
      STRIPE_RETRY_BASE_DELAY = 2 # seconds

      # Execute Stripe API call with automatic retry on network/rate-limit errors
      #
      # Implements exponential backoff for rate limits and network errors.
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
        rescue Stripe::APIConnectionError => e
          retries += 1
          if retries <= max_retries
            delay = STRIPE_RETRY_BASE_DELAY * retries
            OT.lw "Stripe API connection error: #{e.message}, retrying in #{delay}s (attempt #{retries}/#{max_retries})"
            sleep(delay)
            retry
          end
          OT.le "Stripe API connection failed after #{max_retries} retries: #{e.message}"
          raise
        rescue Stripe::RateLimitError => e
          retries += 1
          if retries <= max_retries
            # Exponential backoff for rate limits
            delay = STRIPE_RETRY_BASE_DELAY * (2**retries)
            OT.lw "Stripe rate limit hit: #{e.message}, backing off #{delay}s (attempt #{retries}/#{max_retries})"
            sleep(delay)
            retry
          end
          OT.le "Stripe rate limit exceeded after #{max_retries} retries: #{e.message}"
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
        Stripe.api_key = stripe_key
        true
      rescue LoadError
        puts 'Error: stripe gem not installed'
        false
      end

      def format_product_row(product)
        tier = product.metadata[Billing::Metadata::FIELD_TIER] || 'N/A'
        tenancy = product.metadata[Billing::Metadata::FIELD_TENANCY] || 'N/A'
        region = product.metadata[Billing::Metadata::FIELD_REGION] || 'N/A'
        active = product.active ? 'yes' : 'no'

        format('%-22s %-40s %-12s %-12s %-10s %s',
          product.id[0..21],
          product.name[0..39],
          tier[0..11],
          tenancy[0..11],
          region[0..9],
          active,
        )
      end

      def format_price_row(price)
        amount = format_amount(price.unit_amount, price.currency)
        interval = price.recurring&.interval || 'one-time'
        active = price.active ? 'yes' : 'no'

        format('%-22s %-22s %-12s %-10s %s',
          price.id[0..21],
          price.product[0..21],
          amount[0..11],
          interval[0..9],
          active,
        )
      end

      def format_plan_row(plan)
        amount = format_amount(plan.amount, plan.currency)
        capabilities_count = (plan.capabilities || '').split(',').size

        format('%-20s %-18s %-10s %-10s %-12s %d',
          plan.plan_id[0..19],
          plan.tier[0..17],
          plan.interval[0..9],
          amount[0..9],
          plan.region[0..11],
          capabilities_count,
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

        print 'Plan ID (optional, e.g., identity_v1): '
        metadata[Billing::Metadata::FIELD_PLAN_ID] = $stdin.gets.chomp

        print 'Tier (e.g., single_team, multi_team): '
        metadata[Billing::Metadata::FIELD_TIER] = $stdin.gets.chomp

        print 'Region (e.g., us-east, global): '
        metadata[Billing::Metadata::FIELD_REGION] = $stdin.gets.chomp

        print 'Tenancy (e.g., single, multi): '
        metadata[Billing::Metadata::FIELD_TENANCY] = $stdin.gets.chomp

        print 'Capabilities (comma-separated, e.g., create_secrets,create_team): '
        metadata[Billing::Metadata::FIELD_CAPABILITIES] = $stdin.gets.chomp

        print 'Limit teams (-1 for unlimited): '
        metadata[Billing::Metadata::FIELD_LIMIT_TEAMS] = $stdin.gets.chomp

        print 'Limit members per team (-1 for unlimited): '
        metadata[Billing::Metadata::FIELD_LIMIT_MEMBERS_PER_TEAM] = $stdin.gets.chomp

        metadata[Billing::Metadata::FIELD_CREATED] = Time.now.utc.iso8601

        metadata
      end

      def format_subscription_row(subscription)
        customer_id = subscription.customer[0..21]
        status = subscription.status[0..11]
        current_period_end = Time.at(subscription.current_period_end).strftime('%Y-%m-%d')

        format('%-22s %-22s %-12s %-12s',
          subscription.id[0..21],
          customer_id,
          status,
          current_period_end,
        )
      end

      def format_customer_row(customer)
        email = customer.email || 'N/A'
        name = customer.name || 'N/A'
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
        amount = format_amount(invoice.amount_due, invoice.currency)
        status = invoice.status || 'N/A'
        created = Time.at(invoice.created).strftime('%Y-%m-%d')

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
        created = Time.at(event.created).strftime('%Y-%m-%d %H:%M:%S')

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
    end
  end
end
