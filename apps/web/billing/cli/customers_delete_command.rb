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

      option :yes,
        type: :boolean,
        default: false,
        desc: 'Assume yes to prompts'

      def call(customer_id:, yes: false, **)
        boot_application!
        return unless stripe_configured?

        customer = Stripe::Customer.retrieve(customer_id)

        # Check for active subscriptions
        subscriptions = Stripe::Subscription.list(
          {
            customer: customer_id,
            status: 'active',
            limit: 1,
          },
        )

        if subscriptions.data.any?
          puts '⚠️  Customer has active subscriptions!'
          if yes
            puts 'Cancelling all active subscriptions before deleting customer...'
            all_subscriptions = Stripe::Subscription.list(
              {
                customer: customer_id,
                status: 'active',
              },
            )
            all_subscriptions.auto_paging_each do |subscription|
                Stripe::Subscription.update(subscription.id, { cancel_at_period_end: false })
                Stripe::Subscription.cancel(subscription.id)
                puts "  Cancelled subscription #{subscription.id}"
            rescue Stripe::StripeError => ex
                puts "  Failed to cancel subscription #{subscription.id}: #{ex.message}"
            end
          else
            puts 'Cancel subscriptions first or use --yes to force deletion with cancellation'
            return
          end
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
      rescue Stripe::StripeError => ex
        puts "Error deleting customer: #{ex.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing customers delete', Onetime::CLI::BillingCustomersDeleteCommand
