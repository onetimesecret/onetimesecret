# lib/onetime/cli/migrations/backfill_secret_counts_command.rb
#
# frozen_string_literal: true

# Backfill (and on-demand reconcile) per-customer `secrets_active` counters.
#
# Populates every customer's live-secret counter from the true datastore state
# (issue #60). Run once at rollout to seed counters for existing customers; safe
# to re-run any time as a manual reconcile / safety valve (the nightly
# SecretCountReconcileJob does the same recount automatically).
#
# The heavy lifting is the SHARED reconciliation — this command is a thin CLI
# adapter over SecretCountReconcileJob.reconcile so backfill and the scheduled
# job are one implementation, never two.
#
# Usage:
#   bin/ots migrations backfill-secret-counts            # Dry run (default)
#   bin/ots migrations backfill-secret-counts --run      # Execute recount
#
# @see https://github.com/onetimesecret/onetimesecret/issues/60
# @see #2211 (closed) — colonel API blocking Redis KEYS; prior art for moving
#   the enumeration off the request path.

require_relative '../../jobs/scheduled/maintenance/secret_count_reconcile_job'

module Onetime
  module CLI
    class BackfillSecretCountsCommand < Command
      desc 'Backfill per-customer live-secret counters (secrets_active)'

      option :run,
        type: :boolean,
        default: false,
        desc: 'Execute the recount (default is dry-run)'

      option :help,
        type: :boolean,
        default: false,
        aliases: ['h'],
        desc: 'Show help message'

      def call(run: false, help: false, **)
        return show_usage_help if help

        boot_application!

        puts "\nPer-Customer Secret Count Backfill"
        puts '=' * 60

        dry_run = !run
        if dry_run
          puts "\nDRY RUN MODE - No counters will be written"
          puts "To execute the recount, run with --run flag\n"
        end

        report = Onetime::Jobs::Scheduled::Maintenance::SecretCountReconcileJob.reconcile(dry_run: dry_run)

        print_results(report, dry_run)
      end

      private

      def print_results(report, dry_run)
        puts "\n" + ('=' * 60)
        puts "Backfill #{dry_run ? 'Preview' : 'Complete'}"
        puts '=' * 60
        puts "\nStatistics:"
        puts "  Secret keys scanned:        #{report[:secrets_scanned]}"
        puts "  Owners with live secrets:   #{report[:owners_with_live_secrets]}"
        puts "  Customers processed:        #{report[:customers_processed]}"
        puts "  Customers #{dry_run ? 'to correct' : 'corrected'}:      #{report[:customers_corrected]}"

        return unless dry_run && report[:customers_corrected].to_i > 0

        puts <<~MESSAGE

          To execute the recount, run:
            bin/ots migrations backfill-secret-counts --run

        MESSAGE
      end

      def show_usage_help
        puts <<~USAGE

          Per-Customer Secret Count Backfill

          Usage:
            bin/ots migrations backfill-secret-counts [options]

          Description:
            Recomputes each customer's secrets_active counter (the live-secret
            count shown in the colonel users list) from the true datastore state
            and writes back any that have drifted. Uses a single bounded,
            non-blocking cursor SCAN off the request path.

            Run once at rollout to seed counters for existing customers. Safe to
            re-run at any time; the nightly SecretCountReconcileJob performs the
            identical recount automatically.

          Options:
            --run                 Execute the recount (default is dry-run)
            --help, -h            Show this help message

          Examples:
            # Preview (dry run)
            bin/ots migrations backfill-secret-counts

            # Execute the backfill
            bin/ots migrations backfill-secret-counts --run

          Notes:
            - Idempotent (safe to run multiple times)
            - Anonymous / ownerless secrets are not counted
            - Correct beyond 10k secrets per owner (no SCAN cap)

        USAGE
        true
      end
    end

    register 'migrations backfill-secret-counts', BackfillSecretCountsCommand
  end
end
