# lib/onetime/cli/customers/unverify_command.rb
#
# frozen_string_literal: true

# Mark an existing customer as unverified.
#
# Reverses a prior verification. Symmetric with `customers verify`.
# Useful for QA, admin reset, and recovering from incorrect manual
# verification. Clears `verified_by`; provenance is captured in logs.
#
# Usage:
#   bin/ots customers unverify user@example.com      # Lookup by email
#   bin/ots customers unverify ur1234567890abcdef    # Lookup by extid
#   bin/ots customers unverify 123                   # Lookup by Rodauth account ID (full mode)

# The auth app's operations autoloader (apps/web/auth/operations.rb)
# only runs when the auth Rack app boots for HTTP serving; CLI runs
# don't go through that path. Load the op explicitly so the call site
# resolves at runtime.
require 'auth/operations/set_customer_verification'

module Onetime
  module CLI
    class CustomersUnverifyCommand < Command
      include Customers::Shared

      desc 'Mark an existing customer account as unverified'

      argument :identifier,
        type: :string,
        required: true,
        desc: 'Email, extid, or Rodauth account ID of the customer'

      def call(identifier:, **)
        boot_application!

        if identifier.to_s.strip.empty?
          puts 'Error: Identifier is required'
          exit 1
        end

        customer = resolve_customer(identifier)
        unless customer
          puts "Error: Customer not found: #{identifier}"
          exit 1
        end

        if customer.anonymous?
          puts 'Error: Cannot unverify anonymous customer'
          exit 1
        end

        obscured = OT::Utils.obscure_email(customer.email)

        result = Auth::Operations::SetCustomerVerification.new(
          customer: customer,
          verified: false,
          verified_by: nil,
        ).call

        case result
        when :no_change
          puts "#{obscured} is already unverified"
        when :success
          puts "Unverified: #{obscured}"
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

    register 'customers unverify', CustomersUnverifyCommand
  end
end
