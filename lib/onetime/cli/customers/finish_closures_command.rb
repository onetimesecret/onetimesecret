# lib/onetime/cli/customers/finish_closures_command.rb
#
# frozen_string_literal: true

# Finish the account closures that stopped before the customer record was
# deleted (#4830).
#
# A closure marks the customer record just before it removes the sign-in,
# and a completed closure deletes the record. A record still marked, with no
# open auth account, belongs to a closure that stopped part-way: its owner
# asked for the account to be deleted, and `customers diagnose` / `customers
# doctor` report it as an interrupted closure. This command finds every such
# record and purges it, so nobody has to know the IDs.
#
# Usage:
#   bin/ots customers finish-closures                      # Dry run (default)
#   bin/ots customers finish-closures --confirm            # Purge them
#   bin/ots customers finish-closures --confirm --reason "Ticket 123"
#   bin/ots customers finish-closures --json               # Machine-readable
#
# The selection and the purges are owned by
# Auth::Operations::Customers::FinishClosures. This command owns only CLI
# concerns: flags, rendering, exit codes.
#
# @see https://github.com/onetimesecret/onetimesecret/issues/4830

require 'json'
require 'sequel'

# The CLI runs outside the auth app's autoloader, so the op is required
# explicitly (its own requires cover the auth DB and Purge).
require 'auth/operations/customers/finish_closures'

# Customers::Shared must exist before `include Customers::Shared` below.
require_relative 'shared'

module Onetime
  module CLI
    class CustomersFinishClosuresCommand < Command
      include Customers::Shared

      desc 'Finish account closures that stopped before the customer record was deleted (#4830)'

      option :confirm,
        type: :boolean,
        default: false,
        desc: 'Purge the records (WITHOUT this flag the run is forced dry-run)'

      # Same flag and wording as every other destructive CLI verb (#4338).
      option :reason,
        type: :string,
        default: nil,
        desc: 'Operator-supplied reason (recorded in the admin audit trail)'

      option :json,
        type: :boolean,
        default: false,
        desc: 'JSON output: {dry_run, candidates, results} and nothing else'

      option :help,
        type: :boolean,
        default: false,
        aliases: ['h'],
        desc: 'Show help message'

      def call(confirm: false, reason: nil, json: false, help: false, **)
        return show_usage_help if help

        boot_application!

        op     = Auth::Operations::Customers::FinishClosures.new(
          dry_run: !confirm,
          actor: Customers::Shared::CLI_ACTOR,
          reason: reason,
        )
        result = run_operation(op, json)

        if json
          output_json(result)
        else
          print_report(result)
        end

        exit 1 if result.results.any? { |entry| entry[:status] != :success }
      end

      private

      # Without the auth database an open account cannot be ruled out, so the
      # op raises before it purges anything. Rendered as a JSON error document
      # under --json, otherwise a line on stderr; exit 1 either way.
      def run_operation(op, json)
        op.call
      rescue Sequel::Error => ex
        fail_with("Cannot finish closures: #{ex.message}", json)
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
        puts "\nInterrupted Account Closures (#4830)"
        puts '=' * 60
        puts "  Mode: #{result.dry_run ? 'DRY RUN (re-run with --confirm to purge)' : 'LIVE'}"
        puts

        if result.candidates.empty?
          puts 'Nothing to finish: no customer record is left from a closure that stopped part-way.'
          return
        end

        outcomes = result.results.to_h { |entry| [entry[:extid], entry] }
        result.candidates.each do |candidate|
          started = Time.at(candidate[:closure_started_at]).utc.strftime('%Y-%m-%d %H:%M UTC')
          line    = format('  %-28s %-28s closing since %s', candidate[:extid], candidate[:email], started)
          outcome = outcomes[candidate[:extid]]
          line   += "  -> #{outcome[:status]}" if outcome
          puts line
          next unless outcome && outcome[:status] != :success

          puts "      stage: #{outcome[:stage] || 'none'}"
          outcome[:blockers].each { |blocker| puts "      blocker: #{JSON.generate(blocker)}" }
        end

        puts
        if result.dry_run
          puts "#{result.candidates.size} record(s) would be purged. Review the list above, then run:"
          puts '  bin/ots customers finish-closures --confirm'
        else
          finished = result.results.count { |entry| entry[:status] == :success }
          puts "Purged #{finished} of #{result.candidates.size} record(s)."
          if finished < result.candidates.size
            puts 'Resolve the blockers shown, then re-run, or purge one with: bin/ots customers purge ID'
          end
        end
      end

      def output_json(result)
        puts JSON.pretty_generate(
          dry_run: result.dry_run,
          candidates: result.candidates,
          results: result.results,
        )
      end

      def show_usage_help
        puts <<~USAGE

          Interrupted Account Closures

          Usage:
            bin/ots customers finish-closures [options]

          Description:
            Closing an account marks the customer record just before the
            sign-in is removed, and deletes the record when the closure
            completes. A record that is still marked and has no open auth
            account belongs to a closure that stopped part-way: the owner
            asked for the account to be deleted, and it was not.

            This command lists every such record and, with --confirm,
            purges each one through the same audited lifecycle as
            `bin/ots customers purge ID`. Records whose closure started in
            the last 15 minutes are left out, since that closure may still
            be running. A marked record with an open auth account is a
            closure that rolled back and is never purged here;
            `bin/ots customers doctor --repair` clears its marker.

          Options:
            --confirm               Purge the records (default is dry-run)
            --reason TEXT           Recorded in the admin audit trail
            --json                  JSON output: {dry_run, candidates, results}
            --help, -h              Show this help message

          Examples:
            # Preview (dry run): lists the records, writes nothing
            bin/ots customers finish-closures

            # Purge them
            bin/ots customers finish-closures --confirm

          Safety:
            - Default mode is dry-run and writes nothing
            - Each purge runs the purge preflight; a record with blockers
              is refused and left as it is
            - Exits 1 if any purge did not complete

        USAGE
        true
      end
    end

    register 'customers finish-closures', CustomersFinishClosuresCommand
  end
end
