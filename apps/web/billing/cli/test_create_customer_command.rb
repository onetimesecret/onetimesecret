# apps/web/billing/cli/test_create_customer_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Create test customer with payment method
    class BillingTestCreateCustomerCommand < Command
      include BillingHelpers

      desc 'Create test customer with payment method (test mode only)'

      option :with_card, type: :boolean, default: true,
        desc: 'Attach test card payment method'

      def call(with_card: true, **)
        boot_application!

        return unless stripe_configured?

        unless Stripe.api_key.start_with?('sk_test_')
          puts 'Error: Can only create test customers with test API keys'
          puts 'Current key appears to be for live mode'
          return
        end

        require 'securerandom'
        email = "test-#{SecureRandom.hex(4)}@example.com"

        puts 'Creating test customer:'
        puts "  Email: #{email}"

        customer = Stripe::Customer.create({
          email: email,
          name: 'Test Customer',
          description: "CLI test customer - #{Time.now}",
        },
                                          )

        puts "\nCustomer created:"
        puts "  ID: #{customer.id}"
        puts "  Email: #{customer.email}"

        if with_card
          # Use Stripe's pre-defined test payment method token
          # See: https://stripe.com/docs/testing#cards
          pm = Stripe::PaymentMethod.attach('pm_card_visa', { customer: customer.id })

          Stripe::Customer.update(customer.id, {
            invoice_settings: {
              default_payment_method: pm.id,
            },
          }
          )

          puts "\nTest card attached:"
          puts "  Payment method: #{pm.id}"
          puts '  Card: Visa ****4242'
          puts "  Expiry: 12/#{Time.now.year + 2}"
        end

        puts "\nTest customer ready for use!"
        puts "\nNext steps:"
        puts "  bin/ots billing subscriptions create --customer #{customer.id}"
      rescue Stripe::StripeError => ex
        puts "Error creating test customer: #{ex.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing test create-customer', Onetime::CLI::BillingTestCreateCustomerCommand
