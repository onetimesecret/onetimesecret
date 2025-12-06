# apps/web/billing/cli/subscriptions_resume_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Resume subscription
    class BillingSubscriptionsResumeCommand < Command
      include BillingHelpers

      desc 'Resume a paused subscription'

      argument :subscription_id, required: true, desc: 'Subscription ID (sub_xyz)'

      option :yes, type: :boolean, default: false,
        desc: 'Assume yes to prompts'

      def call(subscription_id:, yes: false, **)
        boot_application!

        return unless stripe_configured?

        subscription = Stripe::Subscription.retrieve(subscription_id)

        unless subscription.pause_collection
          puts 'Subscription is not paused'
          return
        end

        puts "Subscription: #{subscription.id}"
        puts "Customer: #{subscription.customer}"
        puts "Status: #{subscription.status}"
        puts 'Currently paused: Yes'
        puts

        unless yes
          print 'Resume subscription? (y/n): '
          return unless $stdin.gets.chomp.downcase == 'y'
        end

        updated = Stripe::Subscription.update(subscription_id, {
          pause_collection: nil,
        }
        )

        puts "\nSubscription resumed successfully"
        puts "Status: #{updated.status}"
        puts 'Billing will resume on next period'
      rescue Stripe::StripeError => ex
        puts "Error resuming subscription: #{ex.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing subscriptions resume', Onetime::CLI::BillingSubscriptionsResumeCommand
