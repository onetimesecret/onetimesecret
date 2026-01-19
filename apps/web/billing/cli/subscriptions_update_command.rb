# apps/web/billing/cli/subscriptions_update_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Update subscription price, quantity, or reactivate cancelled subscriptions
    class BillingSubscriptionsUpdateCommand < Command
      include BillingHelpers

      desc 'Update subscription price or quantity'

      argument :subscription_id, required: true, desc: 'Subscription ID (sub_xyz)'

      option :price, type: :string, desc: 'New price ID (price_xxx)'
      option :quantity, type: :integer, desc: 'New quantity'
      option :prorate, type: :boolean, default: true, desc: 'Prorate charges'
      option :reactivate,
        type: :boolean,
        default: false,
        desc: 'Clear cancel_at_period_end flag to reactivate subscription'

      def call(subscription_id:, price: nil, quantity: nil, prorate: true, reactivate: false, **)
        boot_application!
        return unless stripe_configured?

        # Reactivate mode - just clear the cancellation flag
        if reactivate
          reactivate_subscription(subscription_id)
          return
        end

        if price.nil? && quantity.nil?
          puts 'Error: Must specify --price, --quantity, or --reactivate'
          return
        end

        subscription = Stripe::Subscription.retrieve(subscription_id)
        current_item = subscription.items.data.first

        puts 'Current subscription:'
        puts "  Subscription: #{subscription.id}"
        puts "  Current price: #{current_item.price.id}"
        puts "  Current quantity: #{current_item.quantity}"
        puts "  Amount: #{format_amount(current_item.price.unit_amount, current_item.price.currency)}"
        puts

        puts 'New configuration:'
        puts "  New price: #{price || current_item.price.id}"
        puts "  New quantity: #{quantity || current_item.quantity}"
        puts "  Prorate: #{prorate}"

        print "\nProceed? (y/n): "
        return unless $stdin.gets.chomp.downcase == 'y'

        update_params = {
          items: [{
            id: current_item.id,
            price: price || current_item.price.id,
            quantity: quantity || current_item.quantity,
          }],
          proration_behavior: prorate ? 'create_prorations' : 'none',
        }

        updated = Stripe::Subscription.update(subscription_id, update_params)

        puts "\nSubscription updated successfully"
        puts "Status: #{updated.status}"
      rescue Stripe::StripeError => ex
        puts "Error updating subscription: #{ex.message}"
      end

      private

      def reactivate_subscription(subscription_id)
        subscription = Stripe::Subscription.retrieve(subscription_id)

        puts 'Current subscription:'
        puts "  Subscription: #{subscription.id}"
        puts "  Status: #{subscription.status}"
        puts "  Cancel at period end: #{subscription.cancel_at_period_end}"

        if subscription.cancel_at
          cancel_date = Time.at(subscription.cancel_at).strftime('%Y-%m-%d')
          puts "  Scheduled cancellation: #{cancel_date}"
        end

        unless subscription.cancel_at_period_end
          puts "\nSubscription is not scheduled for cancellation. Nothing to do."
          return
        end

        print "\nReactivate this subscription? (y/n): "
        return unless $stdin.gets.chomp.downcase == 'y'

        updated = Stripe::Subscription.update(subscription_id, { cancel_at_period_end: false })

        puts "\nSubscription reactivated successfully"
        puts "  Status: #{updated.status}"
        puts "  Cancel at period end: #{updated.cancel_at_period_end}"
      rescue Stripe::StripeError => ex
        puts "Error reactivating subscription: #{ex.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing subscriptions update', Onetime::CLI::BillingSubscriptionsUpdateCommand
