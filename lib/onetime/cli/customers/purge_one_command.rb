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
# inactivity sweep (`--older-than 3y`). Both commands use the same safe,
# audited purge lifecycle; use this command for a single deliberate deletion.
#
# Guards (kept in lockstep with the colonel endpoint):
#   - refuses an anonymous customer
#   - requires an explicit confirmation (interactive y/N, or --yes)
#
# Discovery depth is the one deliberate difference: this command passes
# `deep: true` (the global registry sweep, run twice per purge); the colonel
# endpoint stays shallow because a request path cannot afford that sweep.
#
# Usage:
#   bin/ots customers purge-one user@example.com          # confirm, then purge
#   bin/ots customers purge-one user@example.com --reason "GDPR erasure #123"
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

      # OPTIONAL operator-supplied why (#4338), recorded in the audit detail
      # of the event this command's op writes. Same flag, same wording and same
      # blank-means-absent handling as every other destructive CLI verb.
      option :reason,
        type: :string,
        default: nil,
        desc: 'Operator-supplied reason (recorded in the admin audit trail)'
      option :yes,
        type: :boolean,
        default: false,
        aliases: ['-y', '-f'],
        desc: 'Skip confirmation prompt (preflight still runs and may refuse)'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(identifier:, reason: nil, yes: false, json: false, **)
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

          puts 'The purge first runs a read-only organization preflight.'
          puts 'Blockers refuse the purge without mutation. If preflight passes,'
          puts 'the customer and approved references are permanently removed.'
          puts 'A failure after mutation starts is reported as partial; it does not imply rollback.'
          puts
          note     = reason.to_s.strip.empty? ? '' : " (reason: #{reason})"
          print "Purge #{obscured} (#{extid})#{note}? [y/N] "
          response = $stdin.gets&.strip&.downcase
          unless response == 'y'
            puts 'Aborted.'
            return
          end
        end

        result = Auth::Operations::Customers::Purge.new(
          customer: customer,
          actor: Customers::Shared::CLI_ACTOR,
          reason: reason,
          deep: true, # single-account operator action; see Purge#initialize
        ).call

        OT.info "[cli-customers-purge-one] extid=#{extid} status=#{result.status}"

        output_result(result, email: obscured, json: json)

        exit_for_result(result)
      end

      private

      def output_result(result, email:, json:)
        if json
          puts JSON.pretty_generate(purge_result_payload(result, email: email))
          return
        end

        case result.status
        when :success
          puts "Purged #{email} (#{result.extid})"
        when :refused
          puts "Purge refused for #{email} (#{result.extid}); no mutation occurred."
          print_lifecycle_details(result)
        when :partial
          puts "Purge partially completed for #{email} (#{result.extid}); mutation began."
          print_lifecycle_details(result)
        when :not_found
          puts "Nothing to delete for #{email} (#{result.extid})"
          print_lifecycle_details(result)
        else
          puts "Purge failed for #{email} (#{result.extid}): unknown status #{result.status.inspect}"
          print_lifecycle_details(result)
        end
      end

      def purge_result_payload(result, email:)
        {
          status: result.status,
          deleted: result.status == :success,
          extid: result.extid,
          custid: result.custid,
          email: email,
          blockers: result.blockers,
          actions: result.actions,
          planned_actions: result.planned_actions,
          stage: result.stage,
          completed_stages: result.completed_stages,
        }
      end

      def print_lifecycle_details(result)
        puts "  Stage: #{result.stage || 'none'}"
        puts "  Completed stages: #{result.completed_stages.join(', ')}"
        puts '  Completed actions:'
        result.actions.each { |action| puts "    #{JSON.generate(action)}" }
        puts '  Blockers:'
        result.blockers.each { |blocker| puts "    #{JSON.generate(blocker)}" }
      end

      def exit_for_result(result)
        exit 1 unless result.status == :success
      end

      def error_exit(message, json:)
        puts(json ? JSON.generate({ error: message }) : "Error: #{message}")
        exit 1
      end
    end

    register 'customers purge-one', CustomersPurgeOneCommand
  end
end
