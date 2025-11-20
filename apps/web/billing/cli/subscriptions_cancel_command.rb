# apps/web/billing/cli/subscriptions_cancel_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
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
          print "\nProceed? (y/n): "
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
  end
end

Onetime::CLI.register 'billing subscriptions cancel', Onetime::CLI::BillingSubscriptionsCancelCommand
