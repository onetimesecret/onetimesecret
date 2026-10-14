# lib/onetime/cli/domains/backfill_canonical_index_command.rb
#
# frozen_string_literal: true

# Audit custom domain records against the canonical name index
# (CustomDomain.canonical_display_domain_index) and enter the records that are
# missing from it. Thin adapter over
# Onetime::Operations::Domains::CanonicalIndexBackfill, which owns the audit
# categories and the writes.
#
# Usage:
#   bin/ots domains backfill-canonical-index                 # dry run: report and plan
#   bin/ots domains backfill-canonical-index --json          # dry run, machine-readable
#   bin/ots domains backfill-canonical-index --apply         # confirm, then write
#   bin/ots domains backfill-canonical-index --apply --yes   # write without prompting
#
# STOP THE APPLICATION FIRST. The writes take no lock shared with the web,
# worker and scheduler processes; run --apply only while none of them is
# running. Runbook: docs/runbooks/custom-domain-canonical-index-backfill.md.
#
# Exit status: 0 when no record needs an operator; 1 when there are
# collisions, conflicts, unreadable records or a write that did not land, or
# on refusal (declined prompt, --apply --json without --yes).
#
# Why a command rather than a migration under migrations/: the result can
# need an operator (collision groups are reported, never resolved), and the
# runbook runs it again after they are resolved. A migration is recorded as
# applied once and `bin/ots migrate --run` applies every pending migration in
# one go, possibly with the application running.

require 'json'
require 'onetime/operations/domains/canonical_index_backfill'
require_relative 'shared'

module Onetime
  module CLI
    class DomainsBackfillCanonicalIndexCommand < Command
      include Domains::Shared

      # Planned claims listed in text mode; --json lists every one.
      TEXT_ACTION_LIMIT = 20

      RUNBOOK = 'docs/runbooks/custom-domain-canonical-index-backfill.md'

      desc 'Audit and backfill the custom-domain canonical name index (stop the app before --apply)'

      option :apply,
        type: :boolean,
        default: false,
        desc: 'Write only after a complete audit (default: dry run). Run only while the application is stopped'
      option :yes,
        type: :boolean,
        default: false,
        aliases: ['-y'],
        desc: 'With --apply: skip the confirmation prompt'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'
      option :help,
        type: :boolean,
        default: false,
        aliases: ['h'],
        desc: 'Show help message'

      def call(apply: false, yes: false, json: false, help: false, **)
        return show_usage_help if help

        boot_application!

        if apply && json && !yes
          error_exit('Refusing to --apply in --json mode without --yes', json: true)
        end

        confirm_stopped if apply && !yes

        result = run_backfill(dry_run: !apply, json: json)

        OT.info "[cli-domains-backfill-canonical-index] dry_run=#{result.dry_run} " \
                "counts=#{result.audit.counts} changes=#{result.changes.size} failures=#{result.failures.size}"

        json ? output_json(result) : output_text(result)
        exit 1 if result.attention?
      end

      private

      def run_backfill(dry_run:, json:)
        Onetime::Operations::Domains::CanonicalIndexBackfill.new(dry_run: dry_run).call
      rescue StandardError => ex
        error_exit("Backfill failed: #{ex.class}: #{ex.message}", json: json)
      end

      # Exits 1 unless the operator answers y.
      def confirm_stopped
        puts 'This writes to the canonical name index. The web, worker and scheduler'
        puts 'processes must be stopped, and the datastore snapshotted, before it runs.'
        print 'Is the application stopped? [y/N] '
        response = $stdin.gets&.strip&.downcase
        return if response == 'y'

        puts 'Aborted. Nothing was written.'
        exit 1
      end

      def output_text(result)
        audit = result.audit

        puts 'Custom domain canonical index'
        puts '=' * 40
        puts "Mode: #{result.dry_run ? 'DRY RUN (nothing written)' : 'APPLY'}"
        if audit.errors.any?
          puts 'Audit incomplete: unreadable records block all apply writes.'
          puts 'Nothing was written.' unless result.dry_run
        end
        puts "Records scanned: #{audit.rows.size}"
        puts
        print_counts(audit)
        print_actions(result)
        print_collisions(audit)
        print_rows('Conflicts (the entry names another live record)', audit.rows_in(:conflict))
        print_entries('Entries naming a live record under a name it does not have', audit.entries_in(:conflict))
        print_rows('Unconvertible (no A-label form; not indexed)', audit.rows_in(:unconvertible))
        print_errors(audit)
        print_next_steps(result)
      end

      def print_counts(audit)
        counts = audit.counts
        Onetime::Operations::Domains::CanonicalIndexAudit::CATEGORIES.each do |category|
          puts format('  %-14s %d', category, counts[category])
        end
        puts format('  %-14s %d', 'unreadable', audit.errors.size)
        puts
      end

      def print_actions(result)
        actions = result.actions
        return if actions.empty?

        puts result.dry_run ? 'Planned writes:' : 'Apply outcomes:'
        actions.first(TEXT_ACTION_LIMIT).each do |action|
          target = action.domain_id ? "#{action.domain_id} #{spelled(action.display_domain)}" : "(was #{action.stale_id})"
          detail = action.detail ? " - #{action.detail}" : ''
          puts format('  %-8s %-12s %s -> %s%s', action.kind, action.outcome, action.canonical, target, detail)
        end
        remaining = actions.size - TEXT_ACTION_LIMIT
        puts "  ... and #{remaining} more (--json lists all)" if remaining.positive?
        puts
      end

      def print_collisions(audit)
        groups = audit.collision_groups
        return if groups.empty?

        puts 'Collision groups (two or more records for one DNS name; resolve by hand):'
        groups.each do |canonical, rows|
          holder = rows.first.holder_id
          puts "  #{canonical}  (index entry: #{holder || 'none'})"
          rows.each { |row| puts "    #{describe_row(row)}" }
        end
        puts
      end

      def print_rows(title, rows)
        return if rows.empty?

        puts "#{title}:"
        rows.each do |row|
          puts "  #{describe_row(row)}"
          puts "    #{row.detail}" if row.detail
        end
        puts
      end

      def print_entries(title, entries)
        return if entries.empty?

        puts "#{title}:"
        entries.each { |entry| puts "  #{entry.canonical} -> #{entry.holder_id}" }
        puts
      end

      def print_errors(audit)
        return if audit.errors.empty?

        puts 'Records that exist but could not be loaded:'
        audit.errors.each { |error| puts "  #{error.domain_id}: #{error.message}" }
        puts
      end

      def print_next_steps(result)
        if result.audit.errors.any?
          puts 'Resolve the unreadable records and rerun this command before applying.'
          puts "See #{RUNBOOK}."
        elsif result.attention?
          puts 'Operator action needed. For each collision group keep the record whose'
          puts 'organization has proven DNS ownership, remove the others by extid with'
          puts '`bin/ots domains remove <extid>`, then run this command again.'
          puts "See #{RUNBOOK}."
        elsif result.dry_run && result.changes.any?
          puts 'With the application stopped, apply with:'
          puts '  bin/ots domains backfill-canonical-index --apply'
        else
          puts 'The canonical index agrees with every record.'
        end
      end

      def describe_row(row)
        verified = row.verified_confirmed_at ? "dns-confirmed #{format_time(row.verified_confirmed_at)}" : 'no dns confirmation'
        # Row fields are plain booleans, not model reads.
        override = row.verified_by_override ? ' override' : '' # boolean_field native
        [
          row.extid || row.domain_id,
          spelled(row.display_domain),
          "org=#{row.org_id || '(none)'}",
          "#{row.verification_state} (#{verified}#{override})",
          "created #{format_time(row.created)}",
        ].join('  ')
      end

      # Show non-ASCII names escaped as well: decomposed and composed
      # spellings print alike.
      def spelled(name)
        return name.to_s if name.to_s.ascii_only?

        "#{name} #{name.dump}"
      end

      def format_time(epoch)
        return 'unknown' unless epoch

        Time.at(epoch.to_i).utc.strftime('%Y-%m-%d')
      rescue StandardError
        'invalid'
      end

      def output_json(result)
        audit = result.audit
        puts JSON.pretty_generate(
          dry_run: result.dry_run,
          attention: result.attention?,
          counts: audit.counts.merge(unreadable: audit.errors.size),
          collision_groups: audit.collision_groups.transform_values { |rows| rows.map(&:domain_id) },
          rows: audit.rows.reject { |row| row.category == :ok }.map(&:to_h),
          entries: audit.entries.map(&:to_h),
          unreadable: audit.errors.map(&:to_h),
          actions: result.actions.map(&:to_h),
        )
      end

      def show_usage_help
        puts <<~USAGE

          Custom domain canonical index: audit and backfill

          Usage:
            bin/ots domains backfill-canonical-index [--apply [--yes]] [--json]

          Description:
            Compares every custom domain record with the canonical name index (one
            entry per DNS name, keyed by its A-label) and reports each record as ok,
            missing, collision, conflict, stale or unconvertible.

            With --apply it claims the missing entries, re-claims entries that name
            deleted records, and releases entries that no record accounts for.
            Collisions (two or more records for one DNS name) and conflicts are
            reported and never written. If any record cannot be loaded, all apply
            writes are blocked and planned actions are reported as skipped. Resolve
            unreadable records and rerun before applying. Dry runs never write.
            A second --apply changes nothing.

          STOP THE APPLICATION BEFORE --apply. The writes take no lock shared with
          the web, worker and scheduler processes. Snapshot the datastore first.
          Runbook: #{RUNBOOK}

          Options:
            --apply      Write the planned changes (default: dry run)
            --yes, -y    With --apply: skip the confirmation prompt
            --json       JSON output (--apply --json requires --yes)
            --help, -h   Show this help

          Exit status:
            0  nothing needs an operator
            1  collisions, conflicts, unreadable records or a failed write; or the
               run was refused (declined prompt, --apply --json without --yes)

        USAGE
        true
      end
    end

    register 'domains backfill-canonical-index', DomainsBackfillCanonicalIndexCommand
  end
end
