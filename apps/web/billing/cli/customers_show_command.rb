# apps/web/billing/cli/customers_show_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Show customer details with payment methods
    class BillingCustomersShowCommand < Command
      include BillingHelpers

      desc 'Show detailed customer information'

      argument :customer_id, required: true, desc: 'Customer ID (cus_xxx)'

      def call(customer_id:, **)
        boot_application!

        return unless stripe_configured?

        customer = Stripe::Customer.retrieve(customer_id)

        puts 'Customer Details:'
        puts "  ID: #{customer.id}"
        puts "  Email: #{customer.email}"
        puts "  Name: #{customer.name}" if customer.name
        puts "  Created: #{format_timestamp(customer.created)}"
        puts "  Currency: #{customer.currency}" if customer.currency
        puts "  Balance: #{format_amount(customer.balance, customer.currency || 'usd')}"
        puts

        # Payment methods
        payment_methods = Stripe::PaymentMethod.list({
          customer: customer_id,
          limit: 10,
        },
                                                    )

        puts 'Payment Methods:'
        if payment_methods.data.empty?
          puts '  None'
        else
          default_pm = customer.invoice_settings&.default_payment_method

          payment_methods.data.each do |pm|
            default_marker = pm.id == default_pm ? ' (default)' : ''
            puts "  #{pm.id} - #{pm.type}#{default_marker}"

            case pm.type
            when 'card'
              puts "    Card: #{pm.card.brand} ****#{pm.card.last4} (#{pm.card.exp_month}/#{pm.card.exp_year})"
            when 'bank_account'
              puts "    Bank: ****#{pm.bank_account.last4}"
            end
          end
        end
        puts

        # Subscriptions
        subscriptions = Stripe::Subscription.list({
          customer: customer_id,
          limit: 10,
        },
                                                 )

        puts 'Subscriptions:'
        if subscriptions.data.empty?
          puts '  None'
        else
          subscriptions.data.each do |sub|
            status_marker = sub.pause_collection ? ' (paused)' : ''
            puts "  #{sub.id} - #{sub.status}#{status_marker}"
            # Note: current_period_* is now at the subscription item level in Stripe API 2025-11-17.clover
            item = sub.items&.data&.first
            if item&.current_period_start && item&.current_period_end
              puts "    Period: #{format_timestamp(item.current_period_start)} to #{format_timestamp(item.current_period_end)}"
            end
          end
        end
      rescue Stripe::StripeError => ex
        puts "Error retrieving customer: #{ex.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing customers show', Onetime::CLI::BillingCustomersShowCommand
