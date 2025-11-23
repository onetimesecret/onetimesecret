# apps/web/billing/cli/billing_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Main billing command (show help)
    class BillingCommand < Command
      include BillingHelpers

      desc 'Manage billing, products, and prices'

      def call(**)
        puts <<~HELP
          Billing Management Commands:

          Plans & Products:
            bin/ots billing plans              List billing plans from Redis
            bin/ots billing plans --refresh    Refresh cache from Stripe
            bin/ots billing products           List all Stripe products
            bin/ots billing products create    Create new product
            bin/ots billing products show      Show product details
            bin/ots billing products update    Update product metadata
            bin/ots billing products events    Show product-related events
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
            bin/ots billing connection         Show Stripe connection info (masked)

          Examples:

            # List all products
            bin/ots billing products

            # List active subscriptions
            bin/ots billing subscriptions --status active

            # Cancel subscription at period end
            bin/ots billing subscriptions cancel sub_xyz

            # Cancel subscription immediately
            bin/ots billing subscriptions cancel sub_xyz --immediately

            # Pause and resume subscriptions
            bin/ots billing subscriptions pause sub_xyz
            bin/ots billing subscriptions resume sub_xyz

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
            bin/ots billing test trigger-webhook customer.subscription.updated --subscription sub_xyz

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
  end
end

Onetime::CLI.register 'billing', Onetime::CLI::BillingCommand
