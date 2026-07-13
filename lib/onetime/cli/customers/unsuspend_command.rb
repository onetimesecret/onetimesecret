# lib/onetime/cli/customers/unsuspend_command.rb
#
# frozen_string_literal: true

# Unsuspend (reinstate) a previously suspended customer account.
#
# Usage:
#   bin/ots customers unsuspend user@example.com        # confirm, then unsuspend
#   bin/ots customers unsuspend ur1234567890abcdef --yes  # skip confirmation
#   bin/ots customers unsuspend 123 --json              # machine output
#
# Unsuspending clears the suspended flag + who/when/why stamps; it destroys no
# data. The mutation + admin audit event is performed by the shared
# Auth::Operations::Customers::SetSuspension op (the single implementation).
# This command owns only CLI concerns. Gated behind a confirmation prompt for
# parity with `suspend` even though it is the low-risk (reinstating) direction.
# The CLI runs outside the auth app's autoloader, so require the op explicitly.
require 'json'
require 'auth/operations/customers/set_suspension'

module Onetime
  module CLI
    class CustomersUnsuspendCommand < Command
      include Customers::Shared

      desc 'Unsuspend (reinstate) a suspended customer account'

      argument :identifier,
        type: :string,
        required: true,
        desc: 'Email, extid, or Rodauth account ID of the customer'

      option :yes,
        type: :boolean,
        default: false,
        aliases: ['-y', '-f'],
        desc: 'Skip confirmation prompt'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(identifier:, yes: false, json: false, **)
        boot_application!

        customer = resolve_target(identifier, json: json)
        obscured = customer.obscure_email

        unless yes
          if json
            error_exit('Refusing to unsuspend without --yes in --json mode', json: true)
          end

          print "Unsuspend #{obscured}? [y/N] "
          response = $stdin.gets&.strip&.downcase
          unless response == 'y'
            puts 'Aborted.'
            return
          end
        end

        result = Auth::Operations::Customers::SetSuspension.new(
          customer: customer,
          suspended: false,
          actor: Customers::Shared::CLI_ACTOR,
        ).call

        OT.info "[cli-customers-unsuspend] #{obscured} status=#{result.status}"

        if json
          output_json(result)
        else
          output_text(result, obscured)
        end
      end

      private

      def output_text(result, obscured)
        if result.status == :no_change
          puts "#{obscured} is not suspended"
          return
        end

        puts "Unsuspended: #{obscured}"
      end

      def output_json(result)
        puts JSON.pretty_generate(
          status: result.status,
          extid: result.customer.extid,
          email: result.customer.obscure_email,
          suspended: result.suspended,
        )
      end

      # Resolve to a mutable, non-anonymous Customer or exit non-zero with a
      # json-aware error. resolve_customer is the shared identifier resolver
      # (email / extid / numeric Rodauth account id).
      def resolve_target(identifier, json:)
        error_exit('Identifier is required', json: json) if identifier.to_s.strip.empty?

        customer = resolve_customer(identifier)
        error_exit("Customer not found: #{identifier}", json: json) unless customer
        error_exit('Cannot unsuspend anonymous customer', json: json) if customer.anonymous?

        customer
      end

      def error_exit(message, json:)
        if json
          puts JSON.generate({ error: message })
        else
          puts "Error: #{message}"
        end
        exit 1
      end
    end

    register 'customers unsuspend', CustomersUnsuspendCommand
  end
end
