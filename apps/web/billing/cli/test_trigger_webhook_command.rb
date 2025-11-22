# apps/web/billing/cli/test_trigger_webhook_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
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
        cmd  = "stripe trigger #{event_type}"
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
      rescue StandardError => ex
        puts "Error: #{ex.message}"
        puts "\nNote: Requires Stripe CLI installed (stripe.com/docs/stripe-cli)"
      end
    end
  end
end

Onetime::CLI.register 'billing test trigger-webhook', Onetime::CLI::BillingTestTriggerWebhookCommand
