# lib/onetime/cli/billing_command.rb
#
# frozen_string_literal: true

# Load billing models
require_relative '../../../apps/web/billing/models'

module Onetime
  module CLI
    # Base module for billing command helpers
    module BillingHelpers
      REQUIRED_METADATA_FIELDS = %w[app plan_id tier region capabilities].freeze

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
        plan_id = product.metadata['plan_id'] || 'N/A'
        tier = product.metadata['tier'] || 'N/A'
        region = product.metadata['region'] || 'N/A'
        active = product.active ? 'yes' : 'no'

        format('%-22s %-40s %-18s %-12s %-8s %s',
          product.id[0..21],
          product.name[0..39],
          plan_id[0..17],
          tier[0..11],
          region[0..7],
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

        print 'Plan ID (e.g., identity_v1): '
        metadata['plan_id'] = $stdin.gets.chomp

        print 'Tier (e.g., single_team, multi_team): '
        metadata['tier'] = $stdin.gets.chomp

        print 'Region (e.g., us-east, global): '
        metadata['region'] = $stdin.gets.chomp

        print 'Capabilities (comma-separated, e.g., create_secrets,create_team): '
        metadata['capabilities'] = $stdin.gets.chomp

        print 'Limit teams (-1 for unlimited): '
        limit_teams = $stdin.gets.chomp
        metadata['limit_teams'] = limit_teams unless limit_teams.empty?

        print 'Limit members per team (-1 for unlimited): '
        limit_members = $stdin.gets.chomp
        metadata['limit_members_per_team'] = limit_members unless limit_members.empty?

        metadata['app'] = 'onetimesecret'
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

    # Main billing command (show help)
    class BillingCommand < Command
      include BillingHelpers

      desc 'Manage billing, products, and prices'

      def call(**)
        puts <<~HELP
          Billing Management Commands:

          Catalog & Products:
            bin/ots billing catalog            List product catalog from Redis
            bin/ots billing catalog --refresh  Refresh cache from Stripe
            bin/ots billing products           List all Stripe products
            bin/ots billing products create    Create new product
            bin/ots billing products show      Show product details
            bin/ots billing products update    Update product metadata
            bin/ots billing prices             List all Stripe prices
            bin/ots billing prices create      Create price for product

          Customers & Subscriptions:
            bin/ots billing customers          List Stripe customers
            bin/ots billing customers create   Create new customer
            bin/ots billing customers show     Show customer details
            bin/ots billing customers delete   Delete customer
            bin/ots billing subscriptions      List Stripe subscriptions
            bin/ots billing subscriptions cancel  Cancel subscription
            bin/ots billing subscriptions pause   Pause subscription
            bin/ots billing subscriptions resume  Resume paused subscription
            bin/ots billing subscriptions update  Update subscription price/quantity
            bin/ots billing invoices           List Stripe invoices
            bin/ots billing refunds            List Stripe refunds
            bin/ots billing refunds create     Create refund for charge
            bin/ots billing payment-methods set-default  Set default payment method

          Testing:
            bin/ots billing test create-customer  Create test customer with card
            bin/ots billing test trigger-webhook  Trigger test webhook event

          Analytics & Links:
            bin/ots billing sigma queries      List Sigma queries
            bin/ots billing sigma run          Execute Sigma query
            bin/ots billing payment-links      List payment links
            bin/ots billing payment-links create    Create payment link
            bin/ots billing payment-links update    Update payment link
            bin/ots billing payment-links show      Show payment link details
            bin/ots billing payment-links archive   Archive payment link

          Sync & Validation:
            bin/ots billing sync               Full sync from Stripe to Redis
            bin/ots billing validate           Validate product metadata
            bin/ots billing events             View recent Stripe events

          Examples:

            # List all products
            bin/ots billing products

            # List active subscriptions
            bin/ots billing subscriptions --status active

            # Cancel subscription at period end
            bin/ots billing subscriptions cancel sub_xxx

            # Cancel subscription immediately
            bin/ots billing subscriptions cancel sub_xxx --immediately

            # Pause and resume subscriptions
            bin/ots billing subscriptions pause sub_xxx
            bin/ots billing subscriptions resume sub_xxx

            # Find customer by email
            bin/ots billing customers --email user@example.com

            # Show customer details with payment methods
            bin/ots billing customers show cus_xxx

            # Create a new customer
            bin/ots billing customers create --email user@example.com --name "John Doe"

            # Create test customer with payment method
            bin/ots billing test create-customer

            # List refunds
            bin/ots billing refunds

            # Create refund for charge
            bin/ots billing refunds create --charge ch_xxx --reason requested_by_customer

            # Trigger test webhook
            bin/ots billing test trigger-webhook customer.subscription.updated --subscription sub_xxx

            # Create a new product
            bin/ots billing products create --name "Identity Plan" --interactive

            # Create a monthly price
            bin/ots billing prices create --product prod_xxx --amount 900 --interval month

            # Sync everything to cache
            bin/ots billing sync

          Use --help with any command for more details.
        HELP
      end
    end

    # List catalog cache
    class BillingCatalogCommand < Command
      include BillingHelpers

      desc 'List product catalog cache from Redis'

      option :refresh, type: :boolean, default: false,
        desc: 'Refresh cache from Stripe before listing'

      def call(refresh: false, **)
        boot_application!

        return unless stripe_configured?

        if refresh
          puts 'Refreshing catalog from Stripe...'
          count = Billing::Models::CatalogCache.refresh_from_stripe
          puts "Refreshed #{count} catalog entries"
          puts
        end

        catalog = Billing::Models::CatalogCache.list_catalog
        if catalog.empty?
          puts 'No catalog entries found. Run with --refresh to sync from Stripe.'
          return
        end

        puts format('%-20s %-18s %-10s %-10s %-12s %s',
          'CATALOG ID', 'TIER', 'INTERVAL', 'AMOUNT', 'REGION', 'CAPS')
        puts '-' * 90

        catalog.each do |entry|
          puts format_plan_row(entry)
        end

        puts "
Total: #{catalog.size} catalog entries"
      end
    end

    # List Stripe products
    class BillingProductsCommand < Command
      include BillingHelpers

      desc 'List all Stripe products'

      option :active_only, type: :boolean, default: true,
        desc: 'Show only active products'

      def call(active_only: true, **)
        boot_application!

        return unless stripe_configured?

        puts 'Fetching products from Stripe...'
        products = Stripe::Product.list({ active: active_only, limit: 100 })

        if products.data.empty?
          puts 'No products found'
          return
        end

        puts format('%-22s %-40s %-18s %-12s %-8s %s',
          'ID', 'NAME', 'PLAN_ID', 'TIER', 'REGION', 'ACTIVE')
        puts '-' * 110

        products.data.each do |product|
          puts format_product_row(product)
        end

        puts "\nTotal: #{products.data.size} product(s)"
      end
    end

    # Create Stripe product
    class BillingProductsCreateCommand < Command
      include BillingHelpers

      desc 'Create a new Stripe product'

      argument :name, required: false, desc: 'Product name'

      option :interactive, type: :boolean, default: false,
        desc: 'Interactive mode - prompt for all fields'

      option :plan_id, type: :string, desc: 'Plan ID (e.g., identity_v1)'
      option :tier, type: :string, desc: 'Tier (e.g., single_team)'
      option :region, type: :string, desc: 'Region (e.g., us-east)'
      option :capabilities, type: :string, desc: 'Capabilities (comma-separated)'

      def call(name: nil, interactive: false, **options)
        boot_application!

        return unless stripe_configured?

        if interactive || name.nil?
          print 'Product name: '
          name = $stdin.gets.chomp
        end

        if name.to_s.strip.empty?
          puts 'Error: Product name is required'
          return
        end

        metadata = if interactive
          prompt_for_metadata
        else
          {
            'app' => 'onetimesecret',
            'plan_id' => options[:plan_id],
            'tier' => options[:tier],
            'region' => options[:region] || 'global',
            'capabilities' => options[:capabilities],
          }.compact
        end

        puts "\nCreating product '#{name}' with metadata:"
        metadata.each { |k, v| puts "  #{k}: #{v}" }

        print '\nProceed? (y/n): '
        return unless $stdin.gets.chomp.downcase == 'y'

        product = Stripe::Product.create({
          name: name,
          metadata: metadata,
        })

        puts "\nProduct created successfully:"
        puts "  ID: #{product.id}"
        puts "  Name: #{product.name}"
        puts "\nNext steps:"
        puts "  bin/ots billing prices create --product #{product.id}"
      rescue Stripe::StripeError => e
        puts "Error creating product: #{e.message}"
      end
    end

    # Show product details
    class BillingProductsShowCommand < Command
      include BillingHelpers

      desc 'Show detailed product information'

      argument :product_id, required: true, desc: 'Product ID (e.g., prod_xxx)'

      def call(product_id:, **)
        boot_application!

        return unless stripe_configured?

        product = Stripe::Product.retrieve(product_id)

        puts "Product Details:"
        puts "  ID: #{product.id}"
        puts "  Name: #{product.name}"
        puts "  Active: #{product.active ? 'yes' : 'no'}"
        puts "  Description: #{product.description}" if product.description
        puts

        if product.metadata && product.metadata.any?
          puts "Metadata:"
          product.metadata.each do |key, value|
            puts "  #{key}: #{value}"
          end
          puts
        end

        # Get associated prices
        puts "Prices:"
        prices = Stripe::Price.list({ product: product_id, limit: 100 })

        if prices.data.empty?
          puts "  (none)"
        else
          prices.data.each do |price|
            amount = format_amount(price.unit_amount, price.currency)
            interval = price.recurring&.interval || 'one-time'
            interval_text = price.recurring ? "/#{interval}" : ''
            active = price.active ? 'active' : 'inactive'

            puts "  #{price.id} - #{amount}#{interval_text} (#{active})"
          end
        end

      rescue Stripe::StripeError => e
        puts "Error retrieving product: #{e.message}"
      end
    end

    # Update Stripe product metadata
    class BillingProductsUpdateCommand < Command
      include BillingHelpers

      desc 'Update Stripe product metadata'

      argument :product_id, required: true, desc: 'Product ID (e.g., prod_xxx)'

      option :interactive, type: :boolean, default: false,
        desc: 'Interactive mode - prompt for all fields'

      option :plan_id, type: :string, desc: 'Plan ID'
      option :tier, type: :string, desc: 'Tier'
      option :region, type: :string, desc: 'Region'
      option :capabilities, type: :string, desc: 'Capabilities'

      def call(product_id:, interactive: false, **options)
        boot_application!

        return unless stripe_configured?

        product = Stripe::Product.retrieve(product_id)
        puts "Current product: #{product.name}"
        puts "Current metadata:"
        product.metadata.each { |k, v| puts "  #{k}: #{v}" }
        puts

        metadata = if interactive
          prompt_for_metadata
        else
          options.compact.transform_keys(&:to_s)
        end

        if metadata.empty?
          puts 'No metadata fields to update'
          return
        end

        puts "Updating metadata:"
        metadata.each { |k, v| puts "  #{k}: #{v}" }

        print '\nProceed? (y/n): '
        return unless $stdin.gets.chomp.downcase == 'y'

        updated = Stripe::Product.update(product_id, {
          metadata: product.metadata.to_h.merge(metadata),
        })

        puts "\nProduct updated successfully"
        puts "Updated metadata:"
        updated.metadata.each { |k, v| puts "  #{k}: #{v}" }
      rescue Stripe::StripeError => e
        puts "Error updating product: #{e.message}"
      end
    end

    # List Stripe prices
    class BillingPricesCommand < Command
      include BillingHelpers

      desc 'List all Stripe prices'

      option :product, type: :string, desc: 'Filter by product ID'
      option :active_only, type: :boolean, default: true,
        desc: 'Show only active prices'

      def call(product: nil, active_only: true, **)
        boot_application!

        return unless stripe_configured?

        puts 'Fetching prices from Stripe...'
        params = { active: active_only, limit: 100 }
        params[:product] = product if product

        prices = Stripe::Price.list(params)

        if prices.data.empty?
          puts 'No prices found'
          return
        end

        puts format('%-22s %-22s %-12s %-10s %s',
          'ID', 'PRODUCT', 'AMOUNT', 'INTERVAL', 'ACTIVE')
        puts '-' * 78

        prices.data.each do |price|
          puts format_price_row(price)
        end

        puts "\nTotal: #{prices.data.size} price(s)"
      end
    end

    # Create Stripe price
    class BillingPricesCreateCommand < Command
      include BillingHelpers

      desc 'Create a new Stripe price'

      argument :product_id, required: false, desc: 'Product ID (e.g., prod_xxx)'

      option :amount, type: :integer, desc: 'Amount in cents (e.g., 900 for $9.00)'
      option :currency, type: :string, default: 'usd', desc: 'Currency code'
      option :interval, type: :string, default: 'month',
        desc: 'Billing interval (month, year, week, day)'
      option :interval_count, type: :integer, default: 1,
        desc: 'Number of intervals between billings'

      def call(product_id: nil, amount: nil, currency: 'usd', interval: 'month', interval_count: 1, **)
        boot_application!

        return unless stripe_configured?

        if product_id.nil?
          print 'Product ID: '
          product_id = $stdin.gets.chomp
        end

        if product_id.to_s.strip.empty?
          puts 'Error: Product ID is required'
          return
        end

        # Verify product exists
        product = Stripe::Product.retrieve(product_id)
        puts "Product: #{product.name}"

        if amount.nil?
          print 'Amount in cents (e.g., 900 for $9.00): '
          amount = $stdin.gets.chomp.to_i
        end

        if amount <= 0
          puts 'Error: Amount must be greater than 0'
          return
        end

        unless %w[month year week day].include?(interval)
          puts 'Error: Interval must be one of: month, year, week, day'
          return
        end

        puts "\nCreating price:"
        puts "  Product: #{product_id}"
        puts "  Amount: #{format_amount(amount, currency)}"
        puts "  Interval: #{interval_count} #{interval}(s)"

        print '\nProceed? (y/n): '
        return unless $stdin.gets.chomp.downcase == 'y'

        price = Stripe::Price.create({
          product: product_id,
          unit_amount: amount,
          currency: currency,
          recurring: {
            interval: interval,
            interval_count: interval_count,
          },
        })

        puts "\nPrice created successfully:"
        puts "  ID: #{price.id}"
        puts "  Amount: #{format_amount(price.unit_amount, price.currency)}"
        puts "  Interval: #{price.recurring.interval_count} #{price.recurring.interval}(s)"
      rescue Stripe::StripeError => e
        puts "Error creating price: #{e.message}"
      end
    end

    # Sync from Stripe to Redis cache
    class BillingSyncCommand < Command
      include BillingHelpers

      desc 'Sync products and prices from Stripe to Redis cache'

      def call(**)
        boot_application!

        return unless stripe_configured?

        puts 'Syncing from Stripe to Redis cache...'
        puts

        count = Billing::Models::CatalogCache.refresh_from_stripe

        puts "Successfully synced #{count} plan(s) to cache"
        puts "\nTo view cached plans:"
        puts "  bin/ots billing plans"
      rescue StandardError => e
        puts "Error during sync: #{e.message}"
        puts e.backtrace.first(5).join("\n") if OT.debug?
      end
    end

    # Validate product metadata
    class BillingValidateCommand < Command
      include BillingHelpers

      desc 'Validate Stripe product metadata'

      def call(**)
        boot_application!

        return unless stripe_configured?

        puts 'Fetching products from Stripe...'
        products = Stripe::Product.list({ active: true, limit: 100 })

        if products.data.empty?
          puts 'No products found'
          return
        end

        invalid_count = 0
        products.data.each do |product|
          errors = validate_product_metadata(product)
          next if errors.empty?

          invalid_count += 1
          puts "\n#{product.name} (#{product.id}):"
          errors.each { |error| puts "  ✗ #{error}" }
        end

        if invalid_count.zero?
          puts "✓ All #{products.data.size} product(s) have valid metadata"
        else
          puts "\n#{invalid_count} product(s) have metadata errors"
          puts "\nRequired metadata fields:"
          REQUIRED_METADATA_FIELDS.each { |field| puts "  - #{field}" }
        end
      end
    end

    # List Stripe subscriptions
    class BillingSubscriptionsCommand < Command
      include BillingHelpers

      desc 'List Stripe subscriptions'

      option :status, type: :string,
        desc: 'Filter by status (active, past_due, canceled, incomplete, trialing, unpaid)'
      option :customer, type: :string, desc: 'Filter by customer ID'
      option :limit, type: :integer, default: 100, desc: 'Maximum results to return'

      def call(status: nil, customer: nil, limit: 100, **)
        boot_application!

        return unless stripe_configured?

        puts 'Fetching subscriptions from Stripe...'
        params = { limit: limit }
        params[:status] = status if status
        params[:customer] = customer if customer

        subscriptions = Stripe::Subscription.list(params)

        if subscriptions.data.empty?
          puts 'No subscriptions found'
          return
        end

        puts format('%-22s %-22s %-12s %s',
          'ID', 'CUSTOMER', 'STATUS', 'PERIOD END')
        puts '-' * 70

        subscriptions.data.each do |subscription|
          puts format_subscription_row(subscription)
        end

        puts "\nTotal: #{subscriptions.data.size} subscription(s)"
        puts "\nStatuses: active, past_due, canceled, incomplete, trialing, unpaid"
      rescue Stripe::StripeError => e
        puts "Error fetching subscriptions: #{e.message}"
      end
    end

    # List Stripe customers
    class BillingCustomersCommand < Command
      include BillingHelpers

      desc 'List Stripe customers'

      option :email, type: :string, desc: 'Filter by email address'
      option :limit, type: :integer, default: 100, desc: 'Maximum results to return'

      def call(email: nil, limit: 100, **)
        boot_application!

        return unless stripe_configured?

        puts 'Fetching customers from Stripe...'
        params = { limit: limit }
        params[:email] = email if email

        customers = Stripe::Customer.list(params)

        if customers.data.empty?
          puts 'No customers found'
          return
        end

        puts format('%-22s %-30s %-25s %s',
          'ID', 'EMAIL', 'NAME', 'CREATED')
        puts '-' * 90

        customers.data.each do |customer|
          puts format_customer_row(customer)
        end

        puts "\nTotal: #{customers.data.size} customer(s)"
      rescue Stripe::StripeError => e
        puts "Error fetching customers: #{e.message}"
      end
    end

    # List Stripe invoices
    class BillingInvoicesCommand < Command
      include BillingHelpers

      desc 'List Stripe invoices'

      option :status, type: :string, desc: 'Filter by status (draft, open, paid, uncollectible, void)'
      option :customer, type: :string, desc: 'Filter by customer ID'
      option :subscription, type: :string, desc: 'Filter by subscription ID'
      option :limit, type: :integer, default: 100, desc: 'Maximum results to return'

      def call(status: nil, customer: nil, subscription: nil, limit: 100, **)
        boot_application!

        return unless stripe_configured?

        puts 'Fetching invoices from Stripe...'
        params = { limit: limit }
        params[:status] = status if status
        params[:customer] = customer if customer
        params[:subscription] = subscription if subscription

        invoices = Stripe::Invoice.list(params)

        if invoices.data.empty?
          puts 'No invoices found'
          return
        end

        puts format('%-22s %-22s %-12s %-10s %s',
          'ID', 'CUSTOMER', 'AMOUNT', 'STATUS', 'CREATED')
        puts '-' * 80

        invoices.data.each do |invoice|
          puts format_invoice_row(invoice)
        end

        puts "\nTotal: #{invoices.data.size} invoice(s)"
        puts "\nStatuses: draft, open, paid, uncollectible, void"
      rescue Stripe::StripeError => e
        puts "Error fetching invoices: #{e.message}"
      end
    end

    # View recent Stripe events
    class BillingEventsCommand < Command
      include BillingHelpers

      desc 'View recent Stripe events'

      option :type, type: :string, desc: 'Filter by event type (e.g., customer.created, invoice.paid)'
      option :limit, type: :integer, default: 20, desc: 'Maximum results to return'

      def call(type: nil, limit: 20, **)
        boot_application!

        return unless stripe_configured?

        puts 'Fetching recent events from Stripe...'
        params = { limit: limit }
        params[:type] = type if type

        events = Stripe::Event.list(params)

        if events.data.empty?
          puts 'No events found'
          return
        end

        puts format('%-22s %-35s %s',
          'ID', 'TYPE', 'CREATED')
        puts '-' * 70

        events.data.each do |event|
          puts format_event_row(event)
        end

        puts "\nTotal: #{events.data.size} event(s)"
        puts "\nCommon types: customer.created, customer.updated, invoice.paid,"
        puts "              subscription.created, subscription.updated, payment_intent.succeeded"
      rescue Stripe::StripeError => e
        puts "Error fetching events: #{e.message}"
      end
    end

    # Cancel subscription
    class BillingSubscriptionsCancelCommand < Command
      include BillingHelpers

      desc 'Cancel a subscription'

      argument :subscription_id, required: true, desc: 'Subscription ID (sub_xxx)'

      option :immediately, type: :boolean, default: false,
        desc: 'Cancel immediately instead of at period end'
      option :yes, type: :boolean, default: false,
        desc: 'Assume yes to prompts'

      def call(subscription_id:, immediately: false, yes: false, **)
        boot_application!

        return unless stripe_configured?

        # Retrieve subscription
        subscription = Stripe::Subscription.retrieve(subscription_id)

        # Display current status
        puts "Subscription: #{subscription.id}"
        puts "Customer: #{subscription.customer}"
        puts "Status: #{subscription.status}"
        puts "Current period end: #{format_timestamp(subscription.current_period_end)}"
        puts

        if immediately
          puts "⚠️  Will cancel IMMEDIATELY"
        else
          puts "Will cancel at period end: #{format_timestamp(subscription.current_period_end)}"
        end

        unless yes
          print '\nProceed? (y/n): '
          return unless $stdin.gets.chomp.downcase == 'y'
        end

        # Cancel subscription
        canceled = if immediately
          Stripe::Subscription.cancel(subscription_id)
        else
          Stripe::Subscription.update(subscription_id, {
            cancel_at_period_end: true
          })
        end

        puts "\nSubscription canceled successfully"
        puts "Status: #{canceled.status}"
        puts "Canceled at: #{format_timestamp(canceled.canceled_at)}" if canceled.canceled_at
        if canceled.cancel_at_period_end
          puts "Will end at: #{format_timestamp(canceled.current_period_end)}"
        end

      rescue Stripe::StripeError => e
        puts "Error canceling subscription: #{e.message}"
      end
    end

    # Create customer
    class BillingCustomersCreateCommand < Command
      include BillingHelpers

      desc 'Create a new Stripe customer'

      option :email, type: :string, desc: 'Customer email'
      option :name, type: :string, desc: 'Customer name'
      option :interactive, type: :boolean, default: false,
        desc: 'Interactive mode - prompt for fields'

      def call(email: nil, name: nil, interactive: false, **)
        boot_application!

        return unless stripe_configured?

        if interactive || email.nil?
          print 'Email: '
          email = $stdin.gets.chomp
          print 'Name (optional): '
          name = $stdin.gets.chomp
        end

        if email.to_s.strip.empty?
          puts 'Error: Email is required'
          return
        end

        puts "\nCreating customer:"
        puts "  Email: #{email}"
        puts "  Name: #{name}" if name && !name.empty?

        print '\nProceed? (y/n): '
        return unless $stdin.gets.chomp.downcase == 'y'

        customer_params = { email: email }
        customer_params[:name] = name if name && !name.empty?

        customer = Stripe::Customer.create(customer_params)

        puts "\nCustomer created successfully:"
        puts "  ID: #{customer.id}"
        puts "  Email: #{customer.email}"
        puts "  Name: #{customer.name}" if customer.name

      rescue Stripe::StripeError => e
        puts "Error creating customer: #{e.message}"
      end
    end

    # Create test customer with payment method
    class BillingTestCreateCustomerCommand < Command
      include BillingHelpers

      desc 'Create test customer with payment method (test mode only)'

      option :with_card, type: :boolean, default: true,
        desc: 'Attach test card payment method'

      def call(with_card: true, **)
        boot_application!

        return unless stripe_configured?

        unless Stripe.api_key.start_with?('sk_test_')
          puts 'Error: Can only create test customers with test API keys'
          puts 'Current key appears to be for live mode'
          return
        end

        require 'securerandom'
        email = "test-#{SecureRandom.hex(4)}@example.com"

        puts "Creating test customer:"
        puts "  Email: #{email}"

        customer = Stripe::Customer.create({
          email: email,
          name: "Test Customer",
          description: "CLI test customer - #{Time.now}"
        })

        puts "\nCustomer created:"
        puts "  ID: #{customer.id}"
        puts "  Email: #{customer.email}"

        if with_card
          # Attach test card
          pm = Stripe::PaymentMethod.create({
            type: 'card',
            card: {
              number: '4242424242424242',
              exp_month: 12,
              exp_year: Time.now.year + 2,
              cvc: '123'
            }
          })

          Stripe::PaymentMethod.attach(pm.id, { customer: customer.id })

          Stripe::Customer.update(customer.id, {
            invoice_settings: {
              default_payment_method: pm.id
            }
          })

          puts "\nTest card attached:"
          puts "  Payment method: #{pm.id}"
          puts "  Card: Visa ****4242"
          puts "  Expiry: 12/#{Time.now.year + 2}"
        end

        puts "\nTest customer ready for use!"
        puts "\nNext steps:"
        puts "  bin/ots billing subscriptions create --customer #{customer.id}"

      rescue Stripe::StripeError => e
        puts "Error creating test customer: #{e.message}"
      end
    end

    # Pause subscription
    class BillingSubscriptionsPauseCommand < Command
      include BillingHelpers

      desc 'Pause a subscription'

      argument :subscription_id, required: true, desc: 'Subscription ID (sub_xxx)'

      option :yes, type: :boolean, default: false,
        desc: 'Assume yes to prompts'

      def call(subscription_id:, yes: false, **)
        boot_application!

        return unless stripe_configured?

        subscription = Stripe::Subscription.retrieve(subscription_id)

        if subscription.pause_collection
          puts "Subscription is already paused"
          return
        end

        puts "Subscription: #{subscription.id}"
        puts "Customer: #{subscription.customer}"
        puts "Status: #{subscription.status}"
        puts

        unless yes
          print 'Pause subscription? (y/n): '
          return unless $stdin.gets.chomp.downcase == 'y'
        end

        updated = Stripe::Subscription.update(subscription_id, {
          pause_collection: { behavior: 'void' }
        })

        puts "\nSubscription paused successfully"
        puts "Status: #{updated.status}"
        puts "Paused: Billing paused, access continues"

      rescue Stripe::StripeError => e
        puts "Error pausing subscription: #{e.message}"
      end
    end

    # Resume subscription
    class BillingSubscriptionsResumeCommand < Command
      include BillingHelpers

      desc 'Resume a paused subscription'

      argument :subscription_id, required: true, desc: 'Subscription ID (sub_xxx)'

      option :yes, type: :boolean, default: false,
        desc: 'Assume yes to prompts'

      def call(subscription_id:, yes: false, **)
        boot_application!

        return unless stripe_configured?

        subscription = Stripe::Subscription.retrieve(subscription_id)

        unless subscription.pause_collection
          puts "Subscription is not paused"
          return
        end

        puts "Subscription: #{subscription.id}"
        puts "Customer: #{subscription.customer}"
        puts "Status: #{subscription.status}"
        puts "Currently paused: Yes"
        puts

        unless yes
          print 'Resume subscription? (y/n): '
          return unless $stdin.gets.chomp.downcase == 'y'
        end

        updated = Stripe::Subscription.update(subscription_id, {
          pause_collection: nil
        })

        puts "\nSubscription resumed successfully"
        puts "Status: #{updated.status}"
        puts "Billing will resume on next period"

      rescue Stripe::StripeError => e
        puts "Error resuming subscription: #{e.message}"
      end
    end

    # Show customer details with payment methods
    class BillingCustomersShowCommand < Command
      include BillingHelpers

      desc 'Show detailed customer information'

      argument :customer_id, required: true, desc: 'Customer ID (cus_xxx)'

      def call(customer_id:, **)
        boot_application!

        return unless stripe_configured?

        customer = Stripe::Customer.retrieve(customer_id)

        puts "Customer Details:"
        puts "  ID: #{customer.id}"
        puts "  Email: #{customer.email}"
        puts "  Name: #{customer.name}" if customer.name
        puts "  Created: #{format_timestamp(customer.created)}"
        puts "  Currency: #{customer.currency}" if customer.currency
        puts "  Balance: #{format_amount(customer.balance, customer.currency || 'usd')}"
        puts

        # Payment methods
        payment_methods = Stripe::PaymentMethod.list({
          customer: customer_id,
          limit: 10
        })

        puts "Payment Methods:"
        if payment_methods.data.empty?
          puts "  None"
        else
          default_pm = customer.invoice_settings&.default_payment_method

          payment_methods.data.each do |pm|
            default_marker = pm.id == default_pm ? ' (default)' : ''
            puts "  #{pm.id} - #{pm.type}#{default_marker}"

            case pm.type
            when 'card'
              puts "    Card: #{pm.card.brand} ****#{pm.card.last4} (#{pm.card.exp_month}/#{pm.card.exp_year})"
            when 'bank_account'
              puts "    Bank: ****#{pm.bank_account.last4}"
            end
          end
        end
        puts

        # Subscriptions
        subscriptions = Stripe::Subscription.list({
          customer: customer_id,
          limit: 10
        })

        puts "Subscriptions:"
        if subscriptions.data.empty?
          puts "  None"
        else
          subscriptions.data.each do |sub|
            status_marker = sub.pause_collection ? ' (paused)' : ''
            puts "  #{sub.id} - #{sub.status}#{status_marker}"
            puts "    Period: #{format_timestamp(sub.current_period_start)} to #{format_timestamp(sub.current_period_end)}"
          end
        end

      rescue Stripe::StripeError => e
        puts "Error retrieving customer: #{e.message}"
      end
    end

    # Update subscription price or quantity
    class BillingSubscriptionsUpdateCommand < Command
      include BillingHelpers

      desc 'Update subscription price or quantity'

      argument :subscription_id, required: true, desc: 'Subscription ID (sub_xxx)'

      option :price, type: :string, desc: 'New price ID (price_xxx)'
      option :quantity, type: :integer, desc: 'New quantity'
      option :prorate, type: :boolean, default: true, desc: 'Prorate charges'

      def call(subscription_id:, price: nil, quantity: nil, prorate: true, **)
        boot_application!
        return unless stripe_configured?

        if price.nil? && quantity.nil?
          puts "Error: Must specify --price or --quantity"
          return
        end

        subscription = Stripe::Subscription.retrieve(subscription_id)
        current_item = subscription.items.data.first

        puts "Current subscription:"
        puts "  Subscription: #{subscription.id}"
        puts "  Current price: #{current_item.price.id}"
        puts "  Current quantity: #{current_item.quantity}"
        puts "  Amount: #{format_amount(current_item.price.unit_amount, current_item.price.currency)}"
        puts

        puts "New configuration:"
        puts "  New price: #{price || current_item.price.id}"
        puts "  New quantity: #{quantity || current_item.quantity}"
        puts "  Prorate: #{prorate}"

        print "\nProceed? (y/n): "
        return unless $stdin.gets.chomp.downcase == 'y'

        update_params = {
          items: [{
            id: current_item.id,
            price: price || current_item.price.id,
            quantity: quantity || current_item.quantity
          }],
          proration_behavior: prorate ? 'create_prorations' : 'none'
        }

        updated = Stripe::Subscription.update(subscription_id, update_params)

        puts "\nSubscription updated successfully"
        puts "Status: #{updated.status}"

      rescue Stripe::StripeError => e
        puts "Error updating subscription: #{e.message}"
      end
    end

    # Delete customer with safety checks
    class BillingCustomersDeleteCommand < Command
      include BillingHelpers

      desc 'Delete a Stripe customer'

      argument :customer_id, required: true, desc: 'Customer ID (cus_xxx)'

      option :yes, type: :boolean, default: false,
        desc: 'Assume yes to prompts'

      def call(customer_id:, yes: false, **)
        boot_application!
        return unless stripe_configured?

        customer = Stripe::Customer.retrieve(customer_id)

        # Check for active subscriptions
        subscriptions = Stripe::Subscription.list({
          customer: customer_id,
          status: 'active',
          limit: 1
        })

        if subscriptions.data.any?
          puts "⚠️  Customer has active subscriptions!"
          puts "Cancel subscriptions first or use --yes"
          return unless yes
        end

        puts "Customer: #{customer.id}"
        puts "Email: #{customer.email}"

        unless yes
          print "\n⚠️  Delete customer permanently? (y/n): "
          return unless $stdin.gets.chomp.downcase == 'y'
        end

        deleted = Stripe::Customer.delete(customer_id)

        if deleted.deleted
          puts "\nCustomer deleted successfully"
        else
          puts "\nFailed to delete customer"
        end

      rescue Stripe::StripeError => e
        puts "Error deleting customer: #{e.message}"
      end
    end

    # Set default payment method for customer
    class BillingPaymentMethodsSetDefaultCommand < Command
      include BillingHelpers

      desc 'Set default payment method'

      argument :payment_method_id, required: true, desc: 'Payment method ID (pm_xxx)'

      option :customer, type: :string, required: true, desc: 'Customer ID (cus_xxx)'

      def call(payment_method_id:, customer:, **)
        boot_application!
        return unless stripe_configured?

        # Verify payment method belongs to customer
        pm = Stripe::PaymentMethod.retrieve(payment_method_id)

        unless pm.customer == customer
          puts "Error: Payment method does not belong to customer"
          return
        end

        puts "Payment method: #{payment_method_id}"
        puts "Customer: #{customer}"

        print "\nSet as default? (y/n): "
        return unless $stdin.gets.chomp.downcase == 'y'

        updated = Stripe::Customer.update(customer, {
          invoice_settings: {
            default_payment_method: payment_method_id
          }
        })

        puts "\nDefault payment method updated successfully"
        puts "Default: #{updated.invoice_settings.default_payment_method}"

      rescue Stripe::StripeError => e
        puts "Error setting default payment method: #{e.message}"
      end
    end

    # List refunds
    class BillingRefundsCommand < Command
      include BillingHelpers

      desc 'List Stripe refunds'

      option :charge, type: :string, desc: 'Filter by charge ID'
      option :limit, type: :integer, default: 100, desc: 'Maximum results to return'

      def call(charge: nil, limit: 100, **)
        boot_application!

        return unless stripe_configured?

        puts 'Fetching refunds from Stripe...'
        params = { limit: limit }
        params[:charge] = charge if charge

        refunds = Stripe::Refund.list(params)

        if refunds.data.empty?
          puts 'No refunds found'
          return
        end

        puts format('%-22s %-22s %-12s %-10s %s',
          'ID', 'CHARGE', 'AMOUNT', 'STATUS', 'CREATED')
        puts '-' * 90

        refunds.data.each do |refund|
          amount = format_amount(refund.amount, refund.currency)
          created = format_timestamp(refund.created)

          puts format('%-22s %-22s %-12s %-10s %s',
            refund.id[0..21],
            refund.charge[0..21],
            amount[0..11],
            refund.status[0..9],
            created)
        end

        puts "\nTotal: #{refunds.data.size} refund(s)"

      rescue Stripe::StripeError => e
        puts "Error fetching refunds: #{e.message}"
      end
    end

    # Create refund
    class BillingRefundsCreateCommand < Command
      include BillingHelpers

      desc 'Create a refund for a charge'

      option :charge, type: :string, required: true,
        desc: 'Charge ID (ch_xxx)'
      option :amount, type: :integer,
        desc: 'Amount in cents (leave empty for full refund)'
      option :reason, type: :string,
        desc: 'Reason: duplicate, fraudulent, requested_by_customer'
      option :yes, type: :boolean, default: false,
        desc: 'Assume yes to prompts'

      def call(charge:, amount: nil, reason: nil, yes: false, **)
        boot_application!

        return unless stripe_configured?

        charge_obj = Stripe::Charge.retrieve(charge)

        puts "Charge: #{charge_obj.id}"
        puts "Amount: #{format_amount(charge_obj.amount, charge_obj.currency)}"
        puts "Customer: #{charge_obj.customer}"
        puts

        refund_amount = amount || charge_obj.amount
        puts "Refund amount: #{format_amount(refund_amount, charge_obj.currency)}"
        puts "Reason: #{reason}" if reason

        unless yes
          print '\nCreate refund? (y/n): '
          return unless $stdin.gets.chomp.downcase == 'y'
        end

        refund_params = { charge: charge }
        refund_params[:amount] = amount if amount
        refund_params[:reason] = reason if reason

        refund = Stripe::Refund.create(refund_params)

        puts "\nRefund created successfully:"
        puts "  ID: #{refund.id}"
        puts "  Amount: #{format_amount(refund.amount, refund.currency)}"
        puts "  Status: #{refund.status}"

      rescue Stripe::StripeError => e
        puts "Error creating refund: #{e.message}"
      end
    end

    # Trigger test webhook
    class BillingTestTriggerWebhookCommand < Command
      include BillingHelpers

      desc 'Trigger a test webhook event (requires Stripe CLI)'

      argument :event_type, required: true,
        desc: 'Event type (e.g., customer.subscription.updated)'

      option :subscription, type: :string,
        desc: 'Subscription ID for subscription events'
      option :customer, type: :string,
        desc: 'Customer ID for customer events'

      def call(event_type:, subscription: nil, customer: nil, **)
        boot_application!

        return unless stripe_configured?

        unless Stripe.api_key.start_with?('sk_test_')
          puts 'Error: Can only trigger test events with test API keys'
          return
        end

        puts "Triggering test webhook: #{event_type}"

        # Build stripe CLI command
        cmd = "stripe trigger #{event_type}"
        cmd += " --subscription #{subscription}" if subscription
        cmd += " --customer #{customer}" if customer

        puts "Command: #{cmd}"
        puts

        # Check if stripe CLI is available
        unless system('which stripe > /dev/null 2>&1')
          puts 'Error: Stripe CLI not found'
          puts 'Install from: https://stripe.com/docs/stripe-cli'
          return
        end

        # Execute command
        system(cmd)

      rescue StandardError => e
        puts "Error: #{e.message}"
        puts "\nNote: Requires Stripe CLI installed (stripe.com/docs/stripe-cli)"
      end
    end

    # Sigma parent command (show help)
    class BillingSigmaCommand < Command
      include BillingHelpers

      desc 'Stripe Sigma analytics commands'

      def call(**)
        puts <<~HELP
          Stripe Sigma Analytics:

            bin/ots billing sigma queries      List Sigma queries
            bin/ots billing sigma run          Execute Sigma query

          Examples:

            # List available queries
            bin/ots billing sigma queries

            # Execute a query
            bin/ots billing sigma run sqa_ABC123xyz

            # Export query results to CSV
            bin/ots billing sigma run sqa_ABC123xyz --format csv --output report.csv

          Note: Sigma is only available on paid Stripe plans.
          See: https://stripe.com/docs/sigma
        HELP
      end
    end

    # List Sigma queries
    class BillingSigmaQueriesCommand < Command
      include BillingHelpers

      desc 'List Stripe Sigma queries'

      option :limit, type: :integer, default: 100, desc: 'Maximum results to return'

      def call(limit: 100, **)
        boot_application!

        return unless stripe_configured?

        puts 'Fetching Sigma queries from Stripe...'

        queries = Stripe::Sigma::ScheduledQueryRun.list({ limit: limit })

        if queries.data.empty?
          puts 'No Sigma queries found'
          puts 'Note: Sigma is only available on paid Stripe plans'
          return
        end

        puts format('%-22s %-40s %s',
          'ID', 'SQL', 'CREATED')
        puts '-' * 80

        queries.data.each do |query|
          sql_preview = query.sql&.[](0..39) || 'N/A'
          created = format_timestamp(query.created)

          puts format('%-22s %-40s %s',
            query.id[0..21],
            sql_preview,
            created)
        end

        puts "\nTotal: #{queries.data.size} query/queries"

      rescue Stripe::StripeError => e
        if e.message.include?('This feature is not available')
          puts "Error: Sigma is not available on your Stripe plan"
          puts "Sigma requires a paid Stripe plan. See: https://stripe.com/docs/sigma"
        else
          puts "Error fetching Sigma queries: #{e.message}"
        end
      end
    end

    # Execute Sigma query
    class BillingSigmaRunCommand < Command
      include BillingHelpers

      desc 'Execute a Sigma query'

      argument :query_id, required: true, desc: 'Sigma query ID (sqa_xxx)'

      option :format, type: :string, default: 'table',
        desc: 'Output format: table, csv, json'
      option :output, type: :string, desc: 'Output file path'

      def call(query_id:, format: 'table', output: nil, **)
        boot_application!

        return unless stripe_configured?

        unless %w[table csv json].include?(format)
          puts 'Error: Format must be one of: table, csv, json'
          return
        end

        puts "Executing Sigma query: #{query_id}"

        query_run = Stripe::Sigma::ScheduledQueryRun.retrieve(query_id)

        puts "Query: #{query_run.sql[0..100]}..."
        puts

        # Note: Actual execution and result retrieval requires the query to be run
        # This is a simplified implementation
        puts "Status: #{query_run.status}"

        if query_run.result_available_until
          puts "Results available until: #{format_timestamp(query_run.result_available_until)}"
        end

        # In a real implementation, you would fetch and format the actual results
        # For now, show query details
        case format
        when 'json'
          require 'json'
          result = {
            id: query_run.id,
            sql: query_run.sql,
            status: query_run.status,
            created: query_run.created
          }
          output_str = JSON.pretty_generate(result)
        when 'csv'
          output_str = "ID,SQL,STATUS,CREATED\n#{query_run.id},\"#{query_run.sql}\",#{query_run.status},#{query_run.created}"
        else
          output_str = "Query execution complete. Use Stripe Dashboard to view full results."
        end

        if output
          File.write(output, output_str)
          puts "Results saved to: #{output}"
        else
          puts output_str
        end

      rescue Stripe::StripeError => e
        puts "Error executing Sigma query: #{e.message}"
      end
    end

    # List payment links
    class BillingPaymentLinksCommand < Command
      include BillingHelpers

      desc 'List Stripe payment links'

      option :active_only, type: :boolean, default: true,
        desc: 'Show only active links'
      option :limit, type: :integer, default: 100, desc: 'Maximum results to return'

      def call(active_only: true, limit: 100, **)
        boot_application!

        return unless stripe_configured?

        puts 'Fetching payment links from Stripe...'
        params = { limit: limit }
        params[:active] = true if active_only

        links = Stripe::PaymentLink.list(params)

        if links.data.empty?
          puts 'No payment links found'
          return
        end

        puts format('%-30s %-30s %-12s %-10s %s',
          'ID', 'PRODUCT/PRICE', 'AMOUNT', 'INTERVAL', 'ACTIVE')
        puts '-' * 100

        links.data.each do |link|
          active = link.active ? 'yes' : 'no'
          product_name = 'N/A'
          amount = 'N/A'
          interval = 'N/A'

          begin
            # Retrieve with line_items expanded for each link
            link_expanded = Stripe::PaymentLink.retrieve(link.id, expand: ['line_items'])

            if link_expanded.line_items && link_expanded.line_items.data.any?
              line_item = link_expanded.line_items.data.first

              # Get price ID - handle both string and object
              price_id = line_item.price.is_a?(String) ? line_item.price : line_item.price.id
              price = Stripe::Price.retrieve(price_id)

              # Get product ID - handle both string and object
              product_id = price.product.is_a?(String) ? price.product : price.product.id
              product = Stripe::Product.retrieve(product_id)

              product_name = product.name[0..29]
              amount = format_amount(price.unit_amount, price.currency)
              interval = price.recurring&.interval || 'one-time'
            end
          rescue StandardError => e
            # Continue with N/A values if we can't fetch details
            OT.logger.debug { "Failed to fetch details for #{link.id}: #{e.message}" }
          end

          puts format('%-30s %-30s %-12s %-10s %s',
            link.id,
            product_name,
            amount[0..11],
            interval[0..9],
            active)
        end

        puts "\nTotal: #{links.data.size} payment link(s)"
        puts "\nUse 'bin/ots billing payment-links show <id>' for full details including URL"

      rescue Stripe::StripeError => e
        puts "Error fetching payment links: #{e.message}"
      rescue StandardError => e
        puts "Error: #{e.message}"
        puts e.backtrace.first(5).join("\n") if OT.debug?
      end
    end

    # Create payment link
    class BillingPaymentLinksCreateCommand < Command
      include BillingHelpers

      desc 'Create a new payment link'

      option :price, type: :string, required: true, desc: 'Price ID (price_xxx)'
      option :quantity, type: :integer, default: 1, desc: 'Fixed quantity'
      option :allow_quantity, type: :boolean, default: false,
        desc: 'Allow customer to adjust quantity'
      option :after_completion, type: :string,
        desc: 'Redirect URL after successful payment'

      def call(price:, quantity: 1, allow_quantity: false, after_completion: nil, **)
        boot_application!

        return unless stripe_configured?

        # Retrieve price to show details
        price_obj = Stripe::Price.retrieve(price)
        product = Stripe::Product.retrieve(price_obj.product)

        puts "Price: #{price}"
        puts "Product: #{product.name}"
        puts "Amount: #{format_amount(price_obj.unit_amount, price_obj.currency)}/#{price_obj.recurring&.interval || 'one-time'}"
        puts

        puts "Creating payment link..."

        link_params = {
          line_items: [{
            price: price,
            quantity: quantity,
            adjustable_quantity: allow_quantity ? { enabled: true } : nil
          }.compact]
        }

        if after_completion
          link_params[:after_completion] = {
            type: 'redirect',
            redirect: { url: after_completion }
          }
        end

        link = Stripe::PaymentLink.create(link_params)

        puts "\nPayment link created successfully:"
        puts "  ID: #{link.id}"
        puts "  URL: #{link.url}"
        puts "\nShare this link with customers!"

      rescue Stripe::StripeError => e
        puts "Error creating payment link: #{e.message}"
      end
    end

    # Update payment link
    class BillingPaymentLinksUpdateCommand < Command
      include BillingHelpers

      desc 'Update a payment link'

      argument :link_id, required: true, desc: 'Payment link ID (plink_xxx)'

      option :active, type: :boolean, desc: 'Activate or deactivate link'

      def call(link_id:, active: nil, **)
        boot_application!

        return unless stripe_configured?

        link = Stripe::PaymentLink.retrieve(link_id)

        puts "Payment link: #{link.id}"
        puts "Current status: #{link.active ? 'active' : 'inactive'}"
        puts

        if active.nil?
          puts 'Error: Must specify --active true or --active false'
          return
        end

        status_word = active ? 'active' : 'inactive'
        print "Update status to #{status_word}? (y/n): "
        return unless $stdin.gets.chomp.downcase == 'y'

        updated = Stripe::PaymentLink.update(link_id, { active: active })

        puts "\nPayment link updated successfully"
        puts "Status: #{updated.active ? 'active' : 'inactive'}"

      rescue Stripe::StripeError => e
        puts "Error updating payment link: #{e.message}"
      end
    end

    # Show payment link details
    class BillingPaymentLinksShowCommand < Command
      include BillingHelpers

      desc 'Show payment link details'

      argument :link_id, required: true, desc: 'Payment link ID (plink_xxx)'

      def call(link_id:, **)
        boot_application!

        return unless stripe_configured?

        # Ensure link_id is a string
        link_id = link_id.to_s.strip if link_id.respond_to?(:strip)
        link_id = link_id.first.to_s.strip if link_id.is_a?(Array)

        # Retrieve the payment link
        link = Stripe::PaymentLink.retrieve(link_id)

        puts "Payment Link Details:"
        puts "  ID: #{link.id}"
        puts "  URL: #{link.url}"
        puts "  Active: #{link.active ? 'yes' : 'no'}"
        puts

        # Try to get line items - Stripe requires expand parameter
        begin
          link_with_items = Stripe::PaymentLink.retrieve(link_id, expand: ['line_items'])

          if link_with_items.line_items && link_with_items.line_items.data.any?
            line_item = link_with_items.line_items.data.first

            # Get price ID - handle both string and object
            price_id = line_item.price.is_a?(String) ? line_item.price : line_item.price.id
            price = Stripe::Price.retrieve(price_id)

            # Get product ID - handle both string and object
            product_id = price.product.is_a?(String) ? price.product : price.product.id
            product = Stripe::Product.retrieve(product_id)

            puts "Product:"
            puts "  ID: #{product.id}"
            puts "  Name: #{product.name}"
            puts

            puts "Price:"
            puts "  ID: #{price.id}"
            puts "  Amount: #{format_amount(price.unit_amount, price.currency)}"
            puts "  Interval: #{price.recurring&.interval || 'one-time'}"
            puts

            puts "Configuration:"
            quantity_text = line_item.adjustable_quantity&.enabled ? '(adjustable)' : '(fixed)'
            puts "  Quantity: #{line_item.quantity} #{quantity_text}"

            if link.after_completion && link.after_completion.redirect
              puts "  After completion: #{link.after_completion.redirect.url}"
            end
          else
            puts "Line Items:"
            puts "  (none configured)"
          end
        rescue StandardError => e
          puts "Line Items:"
          puts "  Error retrieving: #{e.message}"
          OT.logger.debug { "Line items error for #{link_id}: #{e.message}\n#{e.backtrace.first(5).join("\n")}" }
        end

      rescue Stripe::StripeError => e
        puts "Error retrieving payment link: #{e.message}"
      rescue StandardError => e
        puts "Error: #{e.message}"
        puts e.backtrace.first(5).join("\n") if OT.debug?
      end
    end

    # Archive payment link
    class BillingPaymentLinksArchiveCommand < Command
      include BillingHelpers

      desc 'Archive a payment link'

      argument :link_id, required: true, desc: 'Payment link ID (plink_xxx)'

      option :yes, type: :boolean, default: false,
        desc: 'Assume yes to prompts'

      def call(link_id:, yes: false, **)
        boot_application!

        return unless stripe_configured?

        link = Stripe::PaymentLink.retrieve(link_id)

        puts "Payment link: #{link.id}"
        puts "URL: #{link.url}"
        puts "Status: #{link.active ? 'active' : 'inactive'}"
        puts

        unless yes
          print 'Archive this payment link? (y/n): '
          return unless $stdin.gets.chomp.downcase == 'y'
        end

        updated = Stripe::PaymentLink.update(link_id, { active: false })

        puts "\nPayment link archived successfully"
        puts "Status: inactive"
        puts "URL no longer accepts payments"

      rescue Stripe::StripeError => e
        puts "Error archiving payment link: #{e.message}"
      end
    end
  end
end

# Register commands
Onetime::CLI.register 'billing', Onetime::CLI::BillingCommand
Onetime::CLI.register 'billing catalog', Onetime::CLI::BillingCatalogCommand
Onetime::CLI.register 'billing products', Onetime::CLI::BillingProductsCommand
Onetime::CLI.register 'billing products create', Onetime::CLI::BillingProductsCreateCommand
Onetime::CLI.register 'billing products show', Onetime::CLI::BillingProductsShowCommand
Onetime::CLI.register 'billing products update', Onetime::CLI::BillingProductsUpdateCommand
Onetime::CLI.register 'billing prices', Onetime::CLI::BillingPricesCommand
Onetime::CLI.register 'billing prices create', Onetime::CLI::BillingPricesCreateCommand
Onetime::CLI.register 'billing subscriptions', Onetime::CLI::BillingSubscriptionsCommand
Onetime::CLI.register 'billing subscriptions cancel', Onetime::CLI::BillingSubscriptionsCancelCommand
Onetime::CLI.register 'billing subscriptions pause', Onetime::CLI::BillingSubscriptionsPauseCommand
Onetime::CLI.register 'billing subscriptions resume', Onetime::CLI::BillingSubscriptionsResumeCommand
Onetime::CLI.register 'billing subscriptions update', Onetime::CLI::BillingSubscriptionsUpdateCommand
Onetime::CLI.register 'billing customers', Onetime::CLI::BillingCustomersCommand
Onetime::CLI.register 'billing customers create', Onetime::CLI::BillingCustomersCreateCommand
Onetime::CLI.register 'billing customers show', Onetime::CLI::BillingCustomersShowCommand
Onetime::CLI.register 'billing customers delete', Onetime::CLI::BillingCustomersDeleteCommand
Onetime::CLI.register 'billing payment-methods set-default', Onetime::CLI::BillingPaymentMethodsSetDefaultCommand
Onetime::CLI.register 'billing invoices', Onetime::CLI::BillingInvoicesCommand
Onetime::CLI.register 'billing refunds', Onetime::CLI::BillingRefundsCommand
Onetime::CLI.register 'billing refunds create', Onetime::CLI::BillingRefundsCreateCommand
Onetime::CLI.register 'billing events', Onetime::CLI::BillingEventsCommand
Onetime::CLI.register 'billing test create-customer', Onetime::CLI::BillingTestCreateCustomerCommand
Onetime::CLI.register 'billing test trigger-webhook', Onetime::CLI::BillingTestTriggerWebhookCommand
Onetime::CLI.register 'billing sigma', Onetime::CLI::BillingSigmaCommand
Onetime::CLI.register 'billing sigma queries', Onetime::CLI::BillingSigmaQueriesCommand
Onetime::CLI.register 'billing sigma run', Onetime::CLI::BillingSigmaRunCommand
Onetime::CLI.register 'billing payment-links', Onetime::CLI::BillingPaymentLinksCommand
Onetime::CLI.register 'billing payment-links create', Onetime::CLI::BillingPaymentLinksCreateCommand
Onetime::CLI.register 'billing payment-links update', Onetime::CLI::BillingPaymentLinksUpdateCommand
Onetime::CLI.register 'billing payment-links show', Onetime::CLI::BillingPaymentLinksShowCommand
Onetime::CLI.register 'billing payment-links archive', Onetime::CLI::BillingPaymentLinksArchiveCommand
Onetime::CLI.register 'billing sync', Onetime::CLI::BillingSyncCommand
Onetime::CLI.register 'billing validate', Onetime::CLI::BillingValidateCommand
