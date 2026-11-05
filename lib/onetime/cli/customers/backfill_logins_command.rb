# lib/onetime/cli/customers/backfill_logins_command.rb
#
# frozen_string_literal: true

# Give every Rodauth `accounts` row its internal `login` and the contact-email
# verification columns migration 015 added (ADR-051, SSO email-less accounts
# Phase 2, step "Backfill op" in
# docs/specs/sso/email-less-accounts-account-model.md §7).
#
# Usage:
#   bin/ots customers backfill-logins                 # Dry run (default)
#   bin/ots customers backfill-logins --confirm       # Execute
#   bin/ots customers backfill-logins --limit 500     # First 500 rows without a login
#   bin/ots customers backfill-logins --after-id 900  # Rows with account id > 900
#   bin/ots customers backfill-logins --mint-missing  # Also mint logins for rows with no Customer
#   bin/ots customers backfill-logins --json          # Machine-readable
#
# The per-row rules live in Auth::Operations::BackfillAccountLogins. This
# command owns only CLI concerns: flags, rendering, exit codes. Exit code is
# 1 when any row ended as `error`, after the full report is printed.

require 'json'

# The CLI runs outside the auth app's autoloader, so the op is required
# explicitly (its own requires cover the auth DB).
require 'auth/operations/backfill_account_logins'

module Onetime
  module CLI
    class CustomersBackfillLoginsCommand < Command
      desc 'Backfill accounts.login and the email verification columns (ADR-051)'

      option :confirm,
        type: :boolean,
        default: false,
        desc: 'Execute changes (WITHOUT this flag the run is forced dry-run)'

      option :limit,
        type: :string,
        default: nil,
        desc: 'Process at most N rows without a login (lowest account id first)'

      option :after_id,
        type: :string,
        default: nil,
        desc: 'Only process accounts rows with id > N (resume a --limit run)'

      option :mint_missing,
        type: :boolean,
        default: false,
        desc: 'Mint a fresh login for rows with no resolvable Customer (only once every ' \
              'process materialises Customers from login)'

      option :json,
        type: :boolean,
        default: false,
        desc: 'JSON output: {dry_run, stats, rows, last_account_id} and nothing else'

      option :help,
        type: :boolean,
        default: false,
        aliases: ['h'],
        desc: 'Show help message'

      def call(confirm: false, limit: nil, after_id: nil, mint_missing: false, json: false, help: false, **)
        return show_usage_help if help

        boot_application!

        dry_run  = !confirm
        limit    = parse_limit(limit, json)
        after_id = parse_after_id(after_id, json)
        op       = build_operation(dry_run, limit, after_id, mint_missing, json)
        result   = op.call

        if json
          output_json(result)
        else
          print_header(dry_run, limit, after_id, mint_missing)
          print_results(result)
          print_next_steps(result, limit, after_id, mint_missing)
        end

        exit 1 if result.stats[:error].positive?
      end

      private

      def parse_limit(limit, json)
        return nil if limit.nil? || limit.to_s.strip.empty?

        value = Integer(limit.to_s, 10)
        raise ArgumentError, 'must be positive' unless value.positive?

        value
      rescue ArgumentError
        fail_with("--limit must be a positive integer (got #{limit.inspect})", json)
      end

      def parse_after_id(after_id, json)
        return nil if after_id.nil? || after_id.to_s.strip.empty?

        value = Integer(after_id.to_s, 10)
        raise ArgumentError, 'must not be negative' if value.negative?

        value
      rescue ArgumentError
        fail_with("--after-id must be a non-negative integer (got #{after_id.inspect})", json)
      end

      def build_operation(dry_run, limit, after_id, mint_missing, json)
        Auth::Operations::BackfillAccountLogins.new(
          dry_run: dry_run,
          limit: limit,
          after_id: after_id,
          mint_missing: mint_missing,
        )
      rescue Onetime::Problem => ex
        fail_with("Cannot backfill: #{ex.message}", json)
      end

      def fail_with(message, json)
        if json
          puts JSON.generate(error: message)
        else
          warn message
        end
        exit 1
      end

      def print_header(dry_run, limit, after_id, mint_missing)
        puts "\nAccount Login Backfill (ADR-051)"
        puts '=' * 60
        puts "  Mode:         #{dry_run ? 'DRY RUN (re-run with --confirm to apply)' : 'LIVE'}"
        puts "  Mint missing: #{mint_missing ? 'yes' : 'no'}"
        puts "  Limit:        #{limit}" if limit
        puts "  After id:     #{after_id}" if after_id
      end

      def print_results(result)
        stats = result.stats
        rows  = result.rows

        puts "\nScanned #{stats[:scanned]} account row(s) without a login"

        if rows.any?
          puts
          puts format('  %-36s %-10s %-16s %s', 'OUTCOME', 'ACCOUNT', 'BRANCH', 'EMAIL')
          puts '  ' + ('-' * 76)
          rows.each do |row|
            puts format('  %-36s %-10s %-16s %s', row[:outcome], row[:account_id], row[:branch] || '-', row[:email])
            puts "      #{row[:detail]}" if row[:detail]
          end
        end

        puts "\n" + ('=' * 60)
        puts "Backfill #{result.dry_run ? 'Preview' : 'Complete'}"
        puts '=' * 60
        puts format('  %-40s %d', result.dry_run ? 'Would backfill:' : 'Backfilled:', stats[:backfilled])
        puts format('  %-40s %d', '  via external_id:', stats[:by_external_id])
        puts format('  %-40s %d', '  via email:', stats[:by_email])
        puts format('  %-40s %d', '  minted:', stats[:minted])
        puts format('  %-40s %d', 'Skipped (dangling external_id):', stats[:skipped_dangling_external_id])
        puts format('  %-40s %d', 'Skipped (ambiguous customer):', stats[:skipped_ambiguous_customer])
        puts format('  %-40s %d', 'Skipped (customer linked elsewhere):', stats[:skipped_customer_linked_elsewhere])
        puts format('  %-40s %d', 'Skipped (address mismatch):', stats[:skipped_email_mismatch])
        puts format('  %-40s %d', 'Skipped (unknown verified_by):', stats[:skipped_unknown_verified_by])
        puts format('  %-40s %d', 'Skipped (no customer):', stats[:skipped_no_customer])
        puts format('  %-40s %d', 'Errors:', stats[:error])
      end

      def print_next_steps(result, limit, after_id, mint_missing)
        stats = result.stats
        lines = []

        # The apply suggestion keeps the preview's --limit and --after-id, so
        # it selects the rows just reviewed rather than every candidate from
        # the lowest id.
        if result.dry_run && stats[:backfilled].positive?
          lines << 'Review the rows above, then apply the same selection:'
          lines << "  #{command_line(limit: limit, after_id: after_id, mint_missing: mint_missing, confirm: true)}"
        end

        if stats[:skipped_no_customer].positive?
          lines << 'Rows with no Customer are left without a login. Once every process reads the'
          lines << 'Customer by external_id and creates a missing one from `login`, re-run with'
          lines << '--mint-missing to give them one.'
        end

        if (stats[:skipped_dangling_external_id] + stats[:skipped_ambiguous_customer] +
            stats[:skipped_customer_linked_elsewhere] + stats[:skipped_email_mismatch] +
            stats[:skipped_unknown_verified_by]).positive?
          lines << 'Skipped rows are never resolved automatically. The detail under each one says'
          lines << 'what to settle first (a dangling external_id, for one, is settled from the'
          lines << 'accounts row, not by `customers doctor`). Re-run once it is settled.'
        end

        if stats[:error].positive?
          lines << 'Error rows wrote nothing and are selected again on the next run once the'
          lines << 'cause is fixed.'
        end

        if limit && result.last_account_id
          resume = command_line(
            limit: limit, after_id: result.last_account_id, mint_missing: mint_missing, confirm: !result.dry_run
          )
          lines << 'Resume with:'
          lines << "  #{resume}"
        end

        return if lines.empty?

        puts
        lines.each { |line| puts line }
      end

      # A backfill-logins invocation over one selection, flags in a fixed
      # order.
      def command_line(limit:, after_id:, mint_missing:, confirm:)
        parts  = ['bin/ots customers backfill-logins']
        parts << "--limit #{limit}" if limit
        parts << "--after-id #{after_id}" if after_id
        parts << '--mint-missing' if mint_missing
        parts << '--confirm' if confirm
        parts.join(' ')
      end

      def output_json(result)
        puts JSON.pretty_generate(
          dry_run: result.dry_run,
          stats: result.stats,
          rows: result.rows,
          last_account_id: result.last_account_id,
        )
      end

      def show_usage_help
        puts <<~USAGE

          Account Login Backfill (ADR-051)

          Usage:
            bin/ots customers backfill-logins [options]

          Description:
            Migration 015 added `accounts.login` (the opaque internal Rodauth login,
            equal to the account's Customer objid) and the contact-email
            verification columns `email_verified_at`, `email_verified_by` and
            `email_verification_hold`. Rows written before it carry NULLs. This
            command fills them, one row at a time, and never merges two accounts
            onto one Customer or rewrites an existing external_id.

            Per row:
              external_id present and its Customer exists   -> login = that Customer
              external_id blank, exactly one Customer holds
              the address and no other row links it         -> login = that Customer,
                                                               external_id = its extid
              external_id names a missing Customer          -> skipped_dangling_external_id
                                                               (the row detail says what
                                                               settles it)
              two Customers hold the address                -> skipped_ambiguous_customer
              another row already links that Customer       -> skipped_customer_linked_elsewhere
              that Customer holds a different address       -> skipped_email_mismatch
              its verified_by is not a known provenance     -> skipped_unknown_verified_by
              no Customer at all                            -> skipped_no_customer
                                                               (--mint-missing: fresh login)
            Verification columns copy the Customer mirror: verified -> email_verified_at
            (now) and email_verified_by (the Customer's provenance, or 'legacy');
            a verification hold is copied as email_verification_hold. A minted row
            has no Customer and gets none of them. Whether a copied provenance is
            mailbox proof is Onetime::Customer::MAILBOX_VERIFIED_BY's call, as it is
            for the Customer.

          Options:
            --confirm               Execute changes (default is dry-run)
            --limit N               Process at most N rows without a login
            --after-id N            Only process accounts rows with id > N
            --mint-missing          Mint a fresh login for rows with no Customer. Safe only
                                    once every process materialises a missing Customer from
                                    `login` (the current binary would re-link such a row by
                                    email on its next sign-in)
            --json                  JSON output: {dry_run, stats, rows, last_account_id}
            --help, -h              Show this help message

          Examples:
            bin/ots customers backfill-logins
            bin/ots customers backfill-logins --confirm
            bin/ots customers backfill-logins --limit 1000 --confirm
            bin/ots customers backfill-logins --limit 1000 --after-id 4821 --confirm

          Safety:
            - Default mode is dry-run (writes nothing)
            - Backfilled rows are not selected again. Skipped and errored rows are
              reported on every run until fixed, so a --limit run without
              --after-id keeps returning the same low-id rows.
            - The SQL write is compare-and-set on the row as scanned (`login IS NULL`
              and its external_id, email and status_id), so a row another process
              filled, re-linked, moved or closed in between is reported (as an error,
              so the run exits 1) and left alone; re-run to pick it up
            - The login value itself is never printed or logged

        USAGE
        true
      end
    end

    register 'customers backfill-logins', CustomersBackfillLoginsCommand
  end
end
