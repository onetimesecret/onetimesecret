# lib/onetime/cli/customers/suspend_command.rb
#
# frozen_string_literal: true

# Suspend a customer account — the trust & safety "pause button".
#
# Usage:
#   bin/ots customers suspend user@example.com                    # confirm, then suspend
#   bin/ots customers suspend ur1234567890abcdef --reason "spam"  # with a reason
#   bin/ots customers suspend 123 --yes                           # skip confirmation
#   bin/ots customers suspend user@example.com --json             # machine output
#
# The actual mutation + session sweep + admin audit event is performed by the
# shared Auth::Operations::Customers::SetSuspension op (the single
# implementation; the colonel SuspendUser Logic class is the other adapter).
# This command owns only CLI concerns (identifier parsing, confirmation prompt,
# output). The CLI runs outside the auth app's autoloader, so require the op
# explicitly.
require 'json'
require 'auth/operations/customers/set_suspension'

module Onetime
  module CLI
    class CustomersSuspendCommand < Command
      include Customers::Shared

      desc 'Suspend a customer account (trust & safety pause)'

      argument :identifier,
        type: :string,
        required: true,
        desc: 'Email, extid, or Rodauth account ID of the customer'

      option :reason,
        type: :string,
        default: nil,
        desc: 'Operator-supplied reason (stored on the customer and audit event)'
      option :yes,
        type: :boolean,
        default: false,
        aliases: ['-y', '-f'],
        desc: 'Skip confirmation prompt'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(identifier:, reason: nil, yes: false, json: false, **)
        boot_application!

        customer = resolve_target(identifier, json: json)
        obscured = customer.obscure_email

        unless yes
          if json
            error_exit('Refusing to suspend without --yes in --json mode', json: true)
          end

          reason_note = reason.to_s.strip.empty? ? '' : " (reason: #{reason})"
          print "Suspend #{obscured}#{reason_note}? [y/N] "
          response    = $stdin.gets&.strip&.downcase
          unless response == 'y'
            puts 'Aborted.'
            return
          end
        end

        result = Auth::Operations::Customers::SetSuspension.new(
          customer: customer,
          suspended: true,
          actor: Customers::Shared::CLI_ACTOR,
          reason: reason,
        ).call

        OT.info "[cli-customers-suspend] #{obscured} status=#{result.status} " \
                "sessions_revoked=#{result.sessions_revoked}"

        if json
          output_json(result)
        else
          output_text(result, obscured)
        end
      rescue Auth::Operations::Customers::SetSuspension::PrivilegedAccount => ex
        error_exit(ex.message, json: json)
      end

      private

      def output_text(result, obscured)
        if result.status == :no_change
          puts "#{obscured} is already suspended"
          return
        end

        puts "Suspended: #{obscured}"
        puts "  sessions revoked: #{result.sessions_revoked}"
      end

      def output_json(result)
        puts JSON.pretty_generate(
          status: result.status,
          extid: result.customer.extid,
          email: result.customer.obscure_email,
          suspended: result.suspended,
          sessions_revoked: result.sessions_revoked,
        )
      end

      # Resolve to a mutable, non-anonymous Customer or exit non-zero with a
      # json-aware error. resolve_customer is the shared identifier resolver
      # (email / extid / numeric Rodauth account id).
      def resolve_target(identifier, json:)
        error_exit('Identifier is required', json: json) if identifier.to_s.strip.empty?

        customer = resolve_customer(identifier)
        error_exit("Customer not found: #{identifier}", json: json) unless customer
        error_exit('Cannot suspend anonymous customer', json: json) if customer.anonymous?

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

    register 'customers suspend', CustomersSuspendCommand
  end
end
