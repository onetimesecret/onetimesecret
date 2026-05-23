# lib/onetime/cli/customers/verify_command.rb
#
# frozen_string_literal: true

# Mark an existing customer as verified.
#
# Use when a customer self-registered but never completed email
# confirmation, and you want to verify them manually (e.g., after
# out-of-band identity check). For new customers, use `customers create`
# with `--verified` instead.
#
# Usage:
#   bin/ots customers verify user@example.com      # Lookup by email
#   bin/ots customers verify ur1234567890abcdef    # Lookup by extid

# The auth app's operations autoloader (apps/web/auth/operations.rb)
# only runs when the auth Rack app boots for HTTP serving; CLI runs
# don't go through that path. Load the op explicitly so the call site
# resolves at runtime.
require 'auth/operations/set_customer_verification'

module Onetime
  module CLI
    class CustomersVerifyCommand < Command
      desc 'Mark an existing customer account as verified'

      argument :identifier,
        type: :string,
        required: true,
        desc: 'Email address or extid of the customer'

      def call(identifier:, **)
        boot_application!

        normalized = OT::Utils.normalize_email(identifier)
        if normalized.empty?
          puts 'Error: Identifier is required'
          exit 1
        end

        customer = Onetime::Customer.load_by_extid_or_email(normalized)
        unless customer
          puts "Error: Customer not found: #{identifier}"
          exit 1
        end

        if customer.anonymous?
          puts 'Error: Cannot verify anonymous customer'
          exit 1
        end

        obscured = OT::Utils.obscure_email(customer.email)

        result = Auth::Operations::SetCustomerVerification.new(
          customer: customer,
          verified: true,
          verified_by: 'cli_provision',
        ).call

        case result
        when :no_change
          puts "#{obscured} is already verified"
        when :success
          puts "Verified: #{obscured}"
        end
      rescue Auth::Operations::SetCustomerVerification::NoAuthDatabase => ex
        puts "Error: #{ex.message}. Check AUTH_DATABASE_URL."
        exit 1
      rescue Auth::Operations::SetCustomerVerification::AccountNotFound => ex
        puts "Error: #{ex.message}. " \
          'Run `bin/ots customers sync-auth-accounts` to reconcile.'
        exit 1
      end
    end

    register 'customers verify', CustomersVerifyCommand
  end
end
