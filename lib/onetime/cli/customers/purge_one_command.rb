# lib/onetime/cli/customers/purge_one_command.rb
#
# frozen_string_literal: true

# Purge (permanently delete) ONE customer account.
#
# This is the CLI peer of `DELETE /api/colonel/users/:user_id`. Both adapters
# call the same audited op (Auth::Operations::Customers::Purge), so a
# CLI-initiated deletion lands in the admin audit trail exactly like an
# operator-initiated one — the difference is only the actor
# (Customers::Shared::CLI_ACTOR).
#
# NOT the same command as `bin/ots customers purge`: that one is a BULK
# inactivity sweep (`--older-than 3y`) which deliberately uses the bare
# DeleteCustomer primitive and writes NO audit events, because a sweep would
# flood the 10k-capped audit set. Use this command for single, deliberate,
# accountable deletions.
#
# Guards (kept in lockstep with the colonel endpoint):
#   - refuses an anonymous customer
#   - requires an explicit confirmation (interactive y/N, or --yes)
#
# Usage:
#   bin/ots customers purge-one user@example.com          # confirm, then purge
#   bin/ots customers purge-one ur1234567890abcdef --yes
#   bin/ots customers purge-one 123 --yes --json          # Rodauth account ID

require 'json'
require 'auth/operations/customers/purge'

# Customers::Shared must exist before `include Customers::Shared` below.
# Required here (not only from the lib/onetime/cli.rb manifest) so this file
# cannot be loaded in a broken order.
require_relative 'shared'

module Onetime
  module CLI
    class CustomersPurgeOneCommand < Command
      include Customers::Shared

      desc 'Purge (permanently delete) a single customer account'

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

        if identifier.to_s.strip.empty?
          error_exit('Identifier is required', json: json)
        end

        customer = resolve_customer(identifier)
        error_exit("Customer not found: #{identifier}", json: json) unless customer
        error_exit('Cannot purge anonymous customer', json: json) if customer.anonymous?

        obscured = customer.obscure_email
        extid    = customer.extid

        unless yes
          # Never auto-confirm in --json mode: a machine-driven caller must be
          # explicit about an irreversible delete.
          error_exit('Refusing to purge without --yes in --json mode', json: true) if json

          puts 'This permanently destroys the customer record, its indexes and'
          puts 'its metadata. It is NOT reversible without a Redis backup.'
          puts
          print "Purge #{obscured} (#{extid})? [y/N] "
          response = $stdin.gets&.strip&.downcase
          unless response == 'y'
            puts 'Aborted.'
            return
          end
        end

        result = Auth::Operations::Customers::Purge.new(
          customer: customer,
          actor: Customers::Shared::CLI_ACTOR,
        ).call

        OT.info "[cli-customers-purge-one] extid=#{extid} status=#{result.status}"

        if json
          puts JSON.pretty_generate(
            status: result.status,
            extid: result.extid,
            email: obscured,
          )
        else
          case result.status
          when :success   then puts "Purged #{obscured} (#{extid})"
          when :not_found then puts "Nothing to delete for #{obscured} (#{extid})"
          end
        end

        exit 1 if result.status == :not_found
      end

      private

      def error_exit(message, json:)
        puts(json ? JSON.generate({ error: message }) : "Error: #{message}")
        exit 1
      end
    end

    register 'customers purge-one', CustomersPurgeOneCommand
  end
end
