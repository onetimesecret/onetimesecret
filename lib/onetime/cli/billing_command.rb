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
            bin/ots billing products update    Update product metadata
            bin/ots billing prices             List all Stripe prices
            bin/ots billing prices create      Create price for product

          Customers & Subscriptions:
            bin/ots billing customers          List Stripe customers
            bin/ots billing subscriptions      List Stripe subscriptions
            bin/ots billing invoices           List Stripe invoices

          Sync & Validation:
            bin/ots billing sync               Full sync from Stripe to Redis
            bin/ots billing validate           Validate product metadata
            bin/ots billing events             View recent Stripe events

          Examples:

            # List all products
            bin/ots billing products

            # List active subscriptions
            bin/ots billing subscriptions --status active

            # Find customer by email
            bin/ots billing customers --email user@example.com

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

        catalog = Billing::Models::CatalogCache.list_catalogs
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
  end
end

# Register commands
Onetime::CLI.register 'billing', Onetime::CLI::BillingCommand
Onetime::CLI.register 'billing catalog', Onetime::CLI::BillingCatalogCommand
Onetime::CLI.register 'billing products', Onetime::CLI::BillingProductsCommand
Onetime::CLI.register 'billing products create', Onetime::CLI::BillingProductsCreateCommand
Onetime::CLI.register 'billing products update', Onetime::CLI::BillingProductsUpdateCommand
Onetime::CLI.register 'billing prices', Onetime::CLI::BillingPricesCommand
Onetime::CLI.register 'billing prices create', Onetime::CLI::BillingPricesCreateCommand
Onetime::CLI.register 'billing subscriptions', Onetime::CLI::BillingSubscriptionsCommand
Onetime::CLI.register 'billing customers', Onetime::CLI::BillingCustomersCommand
Onetime::CLI.register 'billing invoices', Onetime::CLI::BillingInvoicesCommand
Onetime::CLI.register 'billing events', Onetime::CLI::BillingEventsCommand
Onetime::CLI.register 'billing sync', Onetime::CLI::BillingSyncCommand
Onetime::CLI.register 'billing validate', Onetime::CLI::BillingValidateCommand
