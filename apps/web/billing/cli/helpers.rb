# apps/web/billing/cli/helpers.rb
#
# frozen_string_literal: true

# Load billing models
require_relative '../models'

module Onetime
  module CLI
    # Base module for billing command helpers
    module BillingHelpers
      REQUIRED_METADATA_FIELDS = %w[app tier region capabilities tenancy created].freeze

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
        tier = product.metadata['tier'] || 'N/A'
        tenancy = product.metadata['tenancy'] || 'N/A'
        region = product.metadata['region'] || 'N/A'
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

        unless product.metadata['app'] == 'onetimesecret'
          errors << "Invalid app metadata (should be 'onetimesecret')"
        end

        errors
      end

      def prompt_for_metadata
        metadata = {}

        # Always include all metadata fields
        metadata['app'] = 'onetimesecret'

        print 'Plan ID (optional, e.g., identity_v1): '
        metadata['plan_id'] = $stdin.gets.chomp

        print 'Tier (e.g., single_team, multi_team): '
        metadata['tier'] = $stdin.gets.chomp

        print 'Region (e.g., us-east, global): '
        metadata['region'] = $stdin.gets.chomp

        print 'Tenancy (e.g., single, multi): '
        metadata['tenancy'] = $stdin.gets.chomp

        print 'Capabilities (comma-separated, e.g., create_secrets,create_team): '
        metadata['capabilities'] = $stdin.gets.chomp

        print 'Limit teams (-1 for unlimited): '
        metadata['limit_teams'] = $stdin.gets.chomp

        print 'Limit members per team (-1 for unlimited): '
        metadata['limit_members_per_team'] = $stdin.gets.chomp

        metadata['created'] = Time.now.utc.iso8601

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
