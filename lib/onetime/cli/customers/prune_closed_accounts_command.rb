# lib/onetime/cli/customers/prune_closed_accounts_command.rb
#
# frozen_string_literal: true

# Delete the Rodauth `accounts` rows that account closures left behind, with
# their authentication audit logs (#4819).
#
# Until #4819, closing an account kept its accounts row (status Closed) and
# every account_authentication_audit_logs row for it, with no expiry: the
# plaintext email and a per-event record of client IP and user agent for an
# account whose Customer record was already deleted. Closure now deletes the
# row and its audit log in the same transaction. This command removes the
# rows that predate the change. Run it once after upgrading; re-running is a
# no-op.
#
# Usage:
#   bin/ots customers prune-closed-accounts             # Dry run (default)
#   bin/ots customers prune-closed-accounts --confirm   # Delete
#   bin/ots customers prune-closed-accounts --json      # Machine-readable
#
# The deletion is owned by Auth::Operations::Customers::PruneClosedAccounts.
# This command owns only CLI concerns: flags, rendering, exit codes.
#
# @see https://github.com/onetimesecret/onetimesecret/issues/4819

require 'json'
require 'sequel'

# The CLI runs outside the auth app's autoloader, so the op is required
# explicitly (its own requires cover the auth DB).
require 'auth/operations/customers/prune_closed_accounts'

module Onetime
  module CLI
    class CustomersPruneClosedAccountsCommand < Command
      desc 'Delete closed Rodauth account rows and their audit logs (#4819)'

      option :confirm,
        type: :boolean,
        default: false,
        desc: 'Delete the rows (WITHOUT this flag the run is forced dry-run)'

      option :json,
        type: :boolean,
        default: false,
        desc: 'JSON output: {dry_run, accounts, rows, marked} and nothing else'

      option :help,
        type: :boolean,
        default: false,
        aliases: ['h'],
        desc: 'Show help message'

      def call(confirm: false, json: false, help: false, **)
        return show_usage_help if help

        boot_application!

        dry_run = !confirm
        op      = build_operation(dry_run, json)
        result  = run_operation(op, json)

        if json
          output_json(result)
        else
          print_report(result)
        end
      end

      private

      def build_operation(dry_run, json)
        Auth::Operations::Customers::PruneClosedAccounts.new(dry_run: dry_run)
      rescue Onetime::Problem => ex
        fail_with("Cannot prune: #{ex.message}", json)
      end

      # The op connects lazily, so an unreachable database surfaces here, on
      # the first query, not in build_operation. Rendered the same way: a JSON
      # error document under --json, otherwise a line on stderr, exit 1. The
      # live run also writes closure markers to Redis (see the op), so an
      # unreachable Redis is rendered the same way; nothing is deleted then.
      def run_operation(op, json)
        op.call
      rescue Sequel::Error, Redis::BaseError => ex
        fail_with("Pruning failed: #{ex.message}", json)
      end

      def fail_with(message, json)
        if json
          puts JSON.generate(error: message)
        else
          warn message
        end
        exit 1
      end

      def print_report(result)
        verb = result.dry_run ? 'Would delete' : 'Deleted'

        puts "\nClosed Account Pruning (#4819)"
        puts '=' * 60
        puts "  Mode: #{result.dry_run ? 'DRY RUN (re-run with --confirm to delete)' : 'LIVE'}"
        puts
        puts format('  %-50s %d', "#{verb} closed accounts rows:", result.accounts)
        result.rows.each do |table, count|
          puts format('  %-50s %d', "#{verb} #{table} rows:", count)
        end
        marking = result.dry_run ? 'Would mark' : 'Marked'
        puts format('  %-50s %d', "#{marking} customer records as closing:", result.marked)

        puts
        if result.marked.positive?
          puts 'Some closed rows still name a customer record: a closure before #4819 that'
          puts 'stopped before the record was deleted. Those records are marked as closing'
          puts 'before their rows go; finish them afterwards with:'
          puts '  bin/ots customers finish-closures --confirm'
          puts
        end
        if result.accounts.zero? && result.rows.empty?
          puts 'Nothing to prune: no closed accounts rows remain.'
        elsif result.dry_run
          puts 'Review the counts above, then run:'
          puts '  bin/ots customers prune-closed-accounts --confirm'
        else
          puts 'Pruning complete. Re-running reports nothing to prune.'
        end
      end

      def output_json(result)
        puts JSON.pretty_generate(
          dry_run: result.dry_run,
          accounts: result.accounts,
          rows: result.rows,
          marked: result.marked,
        )
      end

      def show_usage_help
        puts <<~USAGE

          Closed Account Pruning

          Usage:
            bin/ots customers prune-closed-accounts [options]

          Description:
            Before #4819, closing an account (self-service or administrative)
            kept its Rodauth accounts row with status Closed and every
            account_authentication_audit_logs row for it, with no expiry: the
            plaintext email plus a per-event record of client IP and user
            agent, for an account whose customer record was already deleted.
            Closure now deletes the row and its audit log in the same
            transaction.

            This command deletes the closed rows that predate that change,
            together with every row that still references them (the audit
            log, and any credential row an interrupted closure left behind).
            A closed row has no product use: sign-up ignores it. A closed
            row that still names a customer record belongs to a closure
            that stopped before the record was deleted; that record is
            marked as closing before the row goes, and
            `bin/ots customers finish-closures` finishes it. Run the command
            once after upgrading. Re-running is a no-op.

          Options:
            --confirm               Delete the rows (default is dry-run)
            --json                  JSON output: {dry_run, accounts, rows, marked}
            --help, -h              Show this help message

          Examples:
            # Preview (dry run): counts only, nothing written
            bin/ots customers prune-closed-accounts

            # Delete
            bin/ots customers prune-closed-accounts --confirm

          Safety:
            - Default mode is dry-run and writes nothing
            - The live run deletes inside one transaction; a failure leaves
              every row in place. Customer records a closed row still points
              at may already be marked as closing, which they are
            - Works on PostgreSQL and SQLite
            - Export the audit rows first if a compliance requirement needs
              them; nothing keeps them after this run

        USAGE
        true
      end
    end

    register 'customers prune-closed-accounts', CustomersPruneClosedAccountsCommand
  end
end
