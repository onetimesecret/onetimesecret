# lib/onetime/cli/customers/normalize_emails_command.rb
#
# frozen_string_literal: true

# Bring mixed-case `accounts.email` rows to their canonical (lowercase, NFC)
# form so every exact email lookup finds the row's Customer again (#4726).
#
# SSO sign-ins before PR #4730 stored the identity provider's casing in the
# Rodauth accounts row while the Redis customer email index was keyed by the
# normalized address. Readers that look the Customer up by the stored SQL
# address (new-login alerts, MFA, active sessions, account teardown, re-auth
# offers) miss it for those rows. This command repairs the stored rows; new
# sign-ins are already canonical.
#
# Usage:
#   bin/ots customers normalize-emails                # Dry run (default)
#   bin/ots customers normalize-emails --confirm      # Execute
#   bin/ots customers normalize-emails --limit 50     # First 50 mixed-case rows
#   bin/ots customers normalize-emails --json         # Machine-readable
#
# The per-row mutation and its audit event are owned by
# Auth::Operations::Customers::ChangeEmail (via NormalizeAccountEmails). This
# command owns only CLI concerns: flags, rendering, exit codes.
#
# @see https://github.com/onetimesecret/onetimesecret/issues/4726

require 'json'

# The CLI runs outside the auth app's autoloader, so the op is required
# explicitly (its own requires cover the auth DB and ChangeEmail).
require 'auth/operations/customers/normalize_account_emails'

module Onetime
  module CLI
    class CustomersNormalizeEmailsCommand < Command
      desc 'Bring mixed-case account emails to their canonical form (#4726)'

      option :confirm,
        type: :boolean,
        default: false,
        desc: 'Execute changes (WITHOUT this flag the run is forced dry-run)'

      option :limit,
        type: :string,
        default: nil,
        desc: 'Process at most N mixed-case rows (lowest account id first)'

      option :json,
        type: :boolean,
        default: false,
        desc: 'JSON output: {dry_run, stats, rows} and nothing else'

      option :help,
        type: :boolean,
        default: false,
        aliases: ['h'],
        desc: 'Show help message'

      def call(confirm: false, limit: nil, json: false, help: false, **)
        return show_usage_help if help

        boot_application!

        dry_run = !confirm
        op      = build_operation(dry_run, parse_limit(limit, json), json)
        result  = op.call

        if json
          output_json(result)
        else
          print_header(dry_run, limit)
          print_results(result)
          print_next_steps(result)
        end
      end

      private

      # dry-cli does not coerce option types; a non-integer --limit is an
      # operator error, not a silent "process everything".
      def parse_limit(limit, json)
        return nil if limit.nil? || limit.to_s.strip.empty?

        value = Integer(limit.to_s, 10)
        raise ArgumentError, 'must be positive' unless value.positive?

        value
      rescue ArgumentError
        fail_with("--limit must be a positive integer (got #{limit.inspect})", json)
      end

      def build_operation(dry_run, limit, json)
        Auth::Operations::Customers::NormalizeAccountEmails.new(dry_run: dry_run, limit: limit)
      rescue Onetime::Problem => ex
        fail_with("Cannot normalize: #{ex.message}", json)
      end

      def fail_with(message, json)
        if json
          puts JSON.generate(error: message)
        else
          warn message
        end
        exit 1
      end

      def print_header(dry_run, limit)
        puts "\nAccount Email Normalization (#4726)"
        puts '=' * 60
        puts "  Mode:   #{dry_run ? 'DRY RUN (re-run with --confirm to apply)' : 'LIVE'}"
        puts "  Limit:  #{limit}" if limit
      end

      def print_results(result)
        stats = result.stats
        rows  = result.rows

        puts "\nScanned #{stats[:scanned]} mixed-case account row(s)"

        if rows.any?
          puts
          puts format('  %-24s %-10s %s', 'OUTCOME', 'ACCOUNT', 'FROM -> TO')
          puts '  ' + ('-' * 70)
          rows.each do |row|
            puts format('  %-24s %-10s %s -> %s', row[:outcome], row[:account_id], row[:from], row[:to])
            puts "      #{row[:detail]}" if row[:detail]
          end
        end

        puts "\n" + ('=' * 60)
        puts "Normalization #{result.dry_run ? 'Preview' : 'Complete'}"
        puts '=' * 60
        puts format('  %-34s %d', result.dry_run ? 'Would normalize:' : 'Normalized:', stats[:normalized])
        puts format('  %-34s %d', 'Skipped (fold-unstable):', stats[:skipped_fold_unstable])
        puts format('  %-34s %d', 'Skipped (SQL collision):', stats[:skipped_sql_collision])
        puts format('  %-34s %d', 'Skipped (index collision):', stats[:skipped_index_collision])
        puts format('  %-34s %d', 'Skipped (no customer):', stats[:skipped_no_customer])
        puts format('  %-34s %d', 'Errors:', stats[:error])
      end

      def print_next_steps(result)
        stats = result.stats
        lines = []

        if result.dry_run && stats[:normalized].positive?
          lines << 'Review the rows above, then run:'
          lines << '  bin/ots customers normalize-emails --confirm'
        end

        if (stats[:skipped_sql_collision] + stats[:skipped_index_collision]).positive?
          lines << 'Collisions are never merged automatically. Decide which account keeps the'
          lines << 'address, then use `bin/ots customers change-email` on the other one'
          lines << '(`--allow-closed-account-reuse` when the holder is a closed account).'
        end

        if stats[:error].positive?
          lines << 'Rows marked error were left untouched; fix the cause named in the detail'
          lines << 'line (`customers sync-auth-accounts`, `customers doctor`) and re-run.'
        end

        return if lines.empty?

        puts
        lines.each { |line| puts line }
      end

      def output_json(result)
        puts JSON.pretty_generate(
          dry_run: result.dry_run,
          stats: result.stats,
          rows: result.rows,
        )
      end

      def show_usage_help
        puts <<~USAGE

          Account Email Normalization

          Usage:
            bin/ots customers normalize-emails [options]

          Description:
            SSO sign-ins before PR #4730 stored the identity provider's casing in
            the Rodauth accounts row (Jane.Doe@Example.COM) while the Redis customer
            email index was keyed by the lowercase address. Every exact lookup of
            the Customer by the stored SQL address misses for those rows: new-login
            alerts, MFA, active sessions, account teardown, re-auth offers.

            This command rewrites each such row to its canonical form (trimmed,
            NFC, lowercase) through the one change-email operation, with the
            user-facing follow-ups off: no verification reset, no session
            revocation, no notification mail. One `customer.change_email` audit
            event is recorded per normalized row.

            Rows are REFUSED, never merged, when:
              - the lowercase form is not the same address (case folding would
                rewrite it, e.g. ß -> ss)                -> skipped_fold_unstable
              - another accounts row (live or closed) holds the canonical
                address                                  -> skipped_sql_collision
              - no Customer resolves from external_id, the stored address or
                the canonical address                    -> skipped_no_customer
              - the Redis email index already maps the canonical address to a
                different Customer                       -> skipped_index_collision
            Any other failure is reported per row as `error`; the run continues.

          Options:
            --confirm               Execute changes (default is dry-run)
            --limit N               Process at most N mixed-case rows
            --json                  JSON output: {dry_run, stats, rows}
            --help, -h              Show this help message

          Examples:
            # Preview (dry run)
            bin/ots customers normalize-emails

            # Execute
            bin/ots customers normalize-emails --confirm

            # Execute in batches
            bin/ots customers normalize-emails --limit 100 --confirm

          Safety:
            - Default mode is dry-run (writes nothing, not even an audit preview)
            - Idempotent: a second run finds nothing to do
            - The SQL write is compare-and-set on the scanned address, so a row
              that changed in between is reported and left alone
            - Collisions and drift are reported, never auto-resolved

        USAGE
        true
      end
    end

    register 'customers normalize-emails', CustomersNormalizeEmailsCommand
  end
end
