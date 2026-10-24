# lib/onetime/cli/customers/role_reconcile_command.rb
#
# frozen_string_literal: true

# Reconcile customer:role_index:* against each customer's `role` field (#3974).
#
# Usage:
#   bin/ots customers role reconcile                  # Report role-index drift (dry run)
#   bin/ots customers role reconcile --apply          # Repair the index
#   bin/ots customers role reconcile --apply --json   # Repair, machine-readable
#
# The check + repair lives in the shared
# Auth::Operations::Customers::ReconcileRoleIndex op; this command owns only
# the write gate, output and exit codes. The CLI runs outside the auth app's
# autoloader, so require the op explicitly.
#
# A subcommand of `customers role` rather than one of its actions, so the
# gate's --apply and --dry-run are declared on reconcile alone. promote and
# demote write after a y/N prompt; a --dry-run they accepted and ignored would
# write while the operator expected a preview.
#
# `-f`/`--force` are a no-op here, not --apply aliases: before the gate they
# skipped the prompt that --apply also needed, so a bare `--force` was a dry
# run. `-y`/`--yes` were never accepted, so they alias --apply as on every
# other gated verb.
require 'json'
require 'auth/operations/customers/reconcile_role_index'
require 'onetime/cli/customers/shared'
require 'onetime/cli/write_gate'

module Onetime
  module CLI
    class CustomersRoleReconcileCommand < Command
      include WriteGate

      desc 'Report role-index drift (dry run unless --apply)'

      write_gate_options 'Write the repair', aliases: APPLY_ALIASES - ['-f']
      option :force,
        type: :boolean,
        default: false,
        aliases: ['-f'],
        desc: 'No effect; --apply repairs. Accepted so --apply --force scripts still run'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(apply: false, dry_run: false, json: false, **)
        boot_application!

        reconcile_role_index(apply: apply, dry_run: dry_run, json: json)
      end

      private

      # Reconcile customer:role_index:* against the authoritative `role` field
      # (#3974). The index drifts through two familia-2.12 mechanisms — the
      # ADD-ONLY multi_index maintenance on targeted writers (save_fields et
      # al. never clear the previous value's bucket) and customer hashes whose
      # right-to-be-forgotten TTL expired while their index members persist.
      # See the ReconcileRoleIndex op for the full mechanism; this method owns
      # only the write gate, output and exit codes.
      #
      # Default is a report-only dry run (WriteGate); --apply repairs, with no
      # prompt.
      def reconcile_role_index(apply:, json:, dry_run: false)
        dry_run = dry_run_unless_applied(apply: apply, dry_run: dry_run, json: json)

        result = Auth::Operations::Customers::ReconcileRoleIndex.new(
          apply: !dry_run,
          # Never fabricate a Customer for the shell (ADR-023) — the audit
          # trail records the shared CLI sentinel. Only attributed when the
          # run can actually mutate.
          actor: dry_run ? nil : Customers::Shared::CLI_ACTOR,
        ).call

        OT.info "[cli-customers-role-reconcile] status=#{result.status} " \
                "scanned=#{result.scanned} additions=#{result.additions.size} " \
                "removals=#{result.removals.size} skipped=#{result.skipped.size} " \
                "dry_run=#{result.dry_run}"

        json ? reconcile_output_json(result) : reconcile_output_text(result)

        # A dry run that FOUND drift exits non-zero so scripts and monitoring
        # can detect it (customers doctor precedent); a clean or repaired run
        # exits zero.
        exit 1 if result.status == :drift
      rescue StandardError => ex
        OT.le "[cli-customers-role-reconcile] failed: #{ex.class}: #{ex.message}"
        if json
          puts JSON.pretty_generate(error: "#{ex.class}: #{ex.message}")
        else
          puts "Error: reconcile failed: #{ex.message}"
        end
        exit 1
      end

      def reconcile_output_text(result)
        dry_run_header if result.dry_run
        puts "Customers scanned: #{result.scanned}"
        puts "Status:            #{result.status}"

        if result.buckets.any?
          puts
          puts format('%-20s %8s %8s %8s', 'Bucket', 'Members', 'Stale', 'Missing')
          result.buckets.each do |role, stats|
            puts format('%-20s %8d %8d %8d', role, stats[:members], stats[:stale], stats[:missing])
          end
        end

        return if result.status == :clean

        puts
        verb = result.dry_run ? 'Would remove' : 'Removed'
        result.removals.each { |entry| puts "#{verb} #{entry[:objid]} from role_index:#{entry[:role]}" }
        verb = result.dry_run ? 'Would add' : 'Added'
        result.additions.each { |entry| puts "#{verb} #{entry[:objid]} to role_index:#{entry[:role]}" }

        # Entries whose premise no longer held when the applied run revalidated
        # them (concurrent role change) — nothing was written; rerun to
        # re-evaluate from fresh snapshots.
        result.skipped.each do |entry|
          puts "Skipped #{entry[:action]} of #{entry[:objid]} in role_index:#{entry[:role]} (#{entry[:reason]})"
        end
        if result.skipped.any?
          puts
          puts "#{result.skipped.size} entr#{result.skipped.size == 1 ? 'y' : 'ies'} skipped after revalidation; rerun reconcile to re-check."
        end

        return unless result.dry_run

        puts
        dry_run_footer('repair')
      end

      def reconcile_output_json(result)
        puts JSON.pretty_generate(
          status: result.status,
          dry_run: result.dry_run,
          scanned: result.scanned,
          buckets: result.buckets,
          additions: result.additions,
          removals: result.removals,
          skipped: result.skipped,
        )
      end
    end

    register 'customers role reconcile', CustomersRoleReconcileCommand
  end
end
