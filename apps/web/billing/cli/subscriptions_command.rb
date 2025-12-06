# apps/web/billing/cli/subscriptions_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
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
        params            = { limit: limit }
        params[:status]   = status if status
        params[:customer] = customer if customer

        subscriptions = Stripe::Subscription.list(params)

        if subscriptions.data.empty?
          puts 'No subscriptions found'
          return
        end

        puts format('%-22s %-22s %-12s %s',
          'ID', 'CUSTOMER', 'STATUS', 'PERIOD END'
        )
        puts '-' * 70

        subscriptions.data.each do |subscription|
          puts format_subscription_row(subscription)
        end

        puts "\nTotal: #{subscriptions.data.size} subscription(s)"
        puts "\nStatuses: active, past_due, canceled, incomplete, trialing, unpaid"
      rescue Stripe::StripeError => ex
        puts "Error fetching subscriptions: #{ex.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing subscriptions', Onetime::CLI::BillingSubscriptionsCommand
