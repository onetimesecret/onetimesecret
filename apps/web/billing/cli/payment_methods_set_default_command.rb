# apps/web/billing/cli/payment_methods_set_default_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Set default payment method for customer
    class BillingPaymentMethodsSetDefaultCommand < Command
      include BillingHelpers

      desc 'Set default payment method'

      argument :payment_method_id, required: true, desc: 'Payment method ID (pm_xxx)'

      option :customer, type: :string, required: true, desc: 'Customer ID (cus_xxx)'

      def call(payment_method_id:, customer:, **)
        boot_application!
        return unless stripe_configured?

        # Verify payment method belongs to customer
        pm = Stripe::PaymentMethod.retrieve(payment_method_id)

        unless pm.customer == customer
          puts "Error: Payment method does not belong to customer"
          return
        end

        puts "Payment method: #{payment_method_id}"
        puts "Customer: #{customer}"

        print "\nSet as default? (y/n): "
        return unless $stdin.gets.chomp.downcase == 'y'

        updated = Stripe::Customer.update(customer, {
          invoice_settings: {
            default_payment_method: payment_method_id
          }
        })

        puts "\nDefault payment method updated successfully"
        puts "Default: #{updated.invoice_settings.default_payment_method}"

      rescue Stripe::StripeError => e
        puts "Error setting default payment method: #{e.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing payment-methods set-default', Onetime::CLI::BillingPaymentMethodsSetDefaultCommand
