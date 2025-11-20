# apps/web/billing/cli/customers_delete_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
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
          puts '⚠️  Customer has active subscriptions!'
          puts 'Cancel subscriptions first or use --yes'
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
  end
end

Onetime::CLI.register 'billing customers delete', Onetime::CLI::BillingCustomersDeleteCommand
