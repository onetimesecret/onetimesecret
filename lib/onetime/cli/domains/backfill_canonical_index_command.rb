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
# After --apply the report describes the index as the writes left it (the
# audit runs again) and lists the outcome of every write. --apply writes
# nothing while any record cannot be loaded.
#
# Exit status: 0 when no record needs an operator; 1 when there are
# collisions, conflicts, unreadable records or a write that did not land,
# when entries are still missing or stale after --apply, or on refusal
# (declined prompt, --apply --json without --yes).
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

      # Planned writes listed in a text dry run; --json lists every one, and
      # so does the text report of an apply.
      TEXT_ACTION_LIMIT = 20

      RUNBOOK = 'docs/runbooks/custom-domain-canonical-index-backfill.md'

      desc 'Audit and backfill the custom-domain canonical name index (stop the app before --apply)'

      option :apply,
        type: :boolean,
        default: false,
        desc: 'Write the planned changes (default: dry run). Run only while the application is stopped'
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

        OT.info "[cli-domains-backfill-canonical-index] dry_run=#{result.dry_run} refusal=#{result.refusal.inspect} " \
                "counts=#{result.report_audit.counts} changes=#{result.changes.size} failures=#{result.failures.size}"

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
        audit = result.report_audit

        puts 'Custom domain canonical index'
        puts '=' * 40
        puts "Mode: #{mode_label(result)}"
        puts "Records scanned: #{audit.rows.size}"
        puts
        puts counts_heading(result)
        print_counts(audit)
        print_actions(result)
        print_collisions(audit)
        print_rows('Conflicts (the entry names another live record)', audit.rows_in(:conflict))
        print_entries('Entries naming a live record under a name it does not have', audit.entries_in(:conflict))
        print_rows('Unconvertible (no A-label form; not indexed)', audit.rows_in(:unconvertible))
        print_errors(audit)
        print_next_steps(result)
      end

      def mode_label(result)
        return 'DRY RUN (nothing written)' if result.dry_run
        return 'APPLY REFUSED (nothing written)' if result.refusal

        'APPLY'
      end

      def counts_heading(result)
        return 'Counts:' unless result.applied?
        return "Counts before the writes (the audit after them failed: #{result.recheck_error}):" if result.recheck_error

        'Counts after the writes:'
      end

      def print_counts(audit)
        counts = audit.counts
        Onetime::Operations::Domains::CanonicalIndexAudit::CATEGORIES.each do |category|
          puts format('  %-14s %d', category, counts[category])
        end
        puts format('  %-14s %d', 'unreadable', audit.errors.size)
        puts
      end

      # An apply lists every write with its outcome; a plan lists the first
      # TEXT_ACTION_LIMIT.
      def print_actions(result)
        actions = result.actions
        return if actions.empty?

        puts actions_heading(result)
        shown     = result.applied? ? actions : actions.first(TEXT_ACTION_LIMIT)
        shown.each do |action|
          target = action.domain_id ? "#{action.domain_id} #{spelled(action.display_domain)}" : "(was #{action.stale_id})"
          detail = action.detail ? " - #{action.detail}" : ''
          puts format('  %-8s %-12s %s -> %s%s', action.kind, action.outcome, action.canonical, target, detail)
        end
        remaining = actions.size - shown.size
        puts "  ... and #{remaining} more (--json lists all)" if remaining.positive?
        puts
      end

      def actions_heading(result)
        return 'Planned writes:' if result.dry_run
        return 'Planned writes (not applied):' if result.refusal

        'Writes:'
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

        puts 'Records that exist but could not be loaded (--apply writes nothing while any remain):'
        audit.errors.each { |error| puts "  #{error.domain_id}: #{error.message}" }
        puts
      end

      def print_next_steps(result)
        if result.attention?
          print_attention(result)
          puts "See #{RUNBOOK}."
        elsif result.dry_run && result.changes.any?
          puts 'With the application stopped, apply with:'
          puts '  bin/ots domains backfill-canonical-index --apply'
        else
          puts 'The canonical index agrees with every record.'
        end
      end

      def print_attention(result)
        audit = result.report_audit

        if audit.errors.any?
          lead = result.refusal ? 'Nothing was written. ' : ''
          puts "#{lead}#{audit.errors.size} records could not be loaded; --apply writes nothing while"
          puts 'they remain. Inspect them with `bin/ots domains doctor --all --familia-audit`,'
          puts 'repair or remove them, then run this command again.'
        end
        if result.recheck_error
          puts 'The writes ran, but the audit after them failed. Run this command without'
          puts '--apply to see the current state.'
        end
        if result.failures.any?
          puts "#{result.failures.size} writes did not land (outcome refused, unverified or error)."
          puts 'With the application stopped, run this command again.'
        end
        if result.applied? && (audit.count(:missing) + audit.count(:stale)).positive?
          puts 'Entries are still missing or stale after the writes. With the application'
          puts 'stopped, run this command again.'
        end
        return unless Onetime::Operations::Domains::CanonicalIndexAudit::ATTENTION_CATEGORIES.any? { |cat| audit.count(cat).positive? }

        puts 'For each collision group keep the record whose organization has proven DNS'
        puts 'ownership, remove the others by extid with `bin/ots domains remove <extid>`,'
        puts 'then run this command again. Resolve conflicts by hand.'
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

      # counts, rows, entries and unreadable describe report_audit: the index
      # after the writes for an apply. counts_before is the audit the writes
      # were planned from, present only for an apply.
      def output_json(result)
        audit  = result.report_audit
        report = {
          dry_run: result.dry_run,
          applied: result.applied?,
          refusal: result.refusal,
          recheck_error: result.recheck_error,
          attention: result.attention?,
          counts: counts_with_unreadable(audit),
        }

        report[:counts_before] = counts_with_unreadable(result.audit) if result.applied?
        puts JSON.pretty_generate(
          report.merge(
            collision_groups: audit.collision_groups.transform_values { |rows| rows.map(&:domain_id) },
            rows: audit.rows.reject { |row| row.category == :ok }.map(&:to_h),
            entries: audit.entries.map(&:to_h),
            unreadable: audit.errors.map(&:to_h),
            actions: result.actions.map(&:to_h),
          ),
        )
      end

      def counts_with_unreadable(audit)
        audit.counts.merge(unreadable: audit.errors.size)
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
            reported and never written. A second --apply changes nothing. After
            the writes it audits the index again and reports that state, with the
            outcome of every write. --apply writes nothing while any record cannot
            be loaded.

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
            1  collisions, conflicts, unreadable records or a failed write; entries
               still missing or stale after --apply; or the run was refused
               (declined prompt, --apply --json without --yes)

        USAGE
        true
      end
    end

    register 'domains backfill-canonical-index', DomainsBackfillCanonicalIndexCommand
  end
end
