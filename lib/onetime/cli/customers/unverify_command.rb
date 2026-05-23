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

module Onetime
  module CLI
    class CustomersUnverifyCommand < Command
      desc 'Mark an existing customer account as unverified'

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
