# apps/web/billing/cli/payment_methods_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Payment methods management
    class BillingPaymentMethodsCommand < Command
      include BillingHelpers

      desc 'Manage customer payment methods'

      def call(**)
        puts <<~HELP
          Payment Methods Management

          Usage:
            bin/ots billing payment-methods SUBCOMMAND

          Subcommands:
            set-default    Set default payment method for customer

          Examples:
            # Set default payment method
            bin/ots billing payment-methods set-default --customer cus_xxx --payment-method pm_xxx

        HELP
      end
    end
  end
end

Onetime::CLI.register 'billing payment-methods', Onetime::CLI::BillingPaymentMethodsCommand
