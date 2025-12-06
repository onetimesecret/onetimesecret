# apps/web/billing/cli/subscriptions_pause_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Pause subscription
    class BillingSubscriptionsPauseCommand < Command
      include BillingHelpers

      desc 'Pause a subscription'

      argument :subscription_id, required: true, desc: 'Subscription ID (sub_xyz)'

      option :yes, type: :boolean, default: false,
        desc: 'Assume yes to prompts'

      def call(subscription_id:, yes: false, **)
        boot_application!

        return unless stripe_configured?

        subscription = Stripe::Subscription.retrieve(subscription_id)

        if subscription.pause_collection
          puts 'Subscription is already paused'
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
          pause_collection: { behavior: 'void' },
        }
        )

        puts "\nSubscription paused successfully"
        puts "Status: #{updated.status}"
        puts 'Paused: Billing paused, access continues'
      rescue Stripe::StripeError => ex
        puts "Error pausing subscription: #{ex.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing subscriptions pause', Onetime::CLI::BillingSubscriptionsPauseCommand
