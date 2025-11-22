# apps/web/billing/cli/test_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Test utilities for billing
    class BillingTestCommand < Command
      include BillingHelpers

      desc 'Testing utilities for billing integration'

      def call(**)
        puts <<~HELP
          Billing Test Utilities

          Usage:
            bin/ots billing test SUBCOMMAND

          Subcommands:
            create-customer    Create test customer with payment method
            trigger-webhook    Trigger test webhook event

          Examples:
            # Create test customer
            bin/ots billing test create-customer

            # Trigger webhook event
            bin/ots billing test trigger-webhook customer.subscription.updated --subscription sub_xxx

        HELP
      end
    end
  end
end

Onetime::CLI.register 'billing test', Onetime::CLI::BillingTestCommand
