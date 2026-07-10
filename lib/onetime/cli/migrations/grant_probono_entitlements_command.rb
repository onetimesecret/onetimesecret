# lib/onetime/cli/migrations/grant_probono_entitlements_command.rb
#
# frozen_string_literal: true

# Grant pro-bono entitlements directly to legacy identity-plan customers.
#
# Thin CLI wrapper around Billing::Operations::GrantProbonoEntitlements,
# which holds the business logic (default-org resolution, skip
# decisions, planid/complimentary writes, materialization, customer
# planid clearing).
#
# Usage:
#   bin/ots migrations grant-probono-entitlements           # Dry run
#   bin/ots migrations grant-probono-entitlements --run     # Execute
#   bin/ots migrations grant-probono-entitlements --run -v  # Verbose
#   bin/ots migrations grant-probono-entitlements --run --force  # Re-materialize
#
# @see https://github.com/onetimesecret/onetimesecret/issues/3161

module Onetime
  module CLI
    class GrantProbonoEntitlementsCommand < Command
      desc 'Grant pro-bono entitlements to legacy identity-plan customers'

      option :run,
        type: :boolean,
        default: false,
        desc: 'Execute changes (default is dry-run)'

      option :verbose,
        type: :boolean,
        default: false,
        aliases: ['v'],
        desc: 'Show detailed progress for each account'

      option :force,
        type: :boolean,
        default: false,
        desc: 'Re-materialize entitlements on orgs already marked complimentary'

      option :help,
        type: :boolean,
        default: false,
        aliases: ['h'],
        desc: 'Show help message'

      def call(run: false, verbose: false, force: false, help: false, **)
        return show_usage_help if help

        boot_application!
        require 'billing/operations/grant_probono_entitlements'

        puts "\nPro-Bono Entitlement Grant"
        puts '=' * 60

        dry_run   = !run
        customers = scan_for_customers
        return if customers.empty?

        print_mode_banner(dry_run, force)

        stats = init_stats
        customers.each_with_index do |cust, idx|
          process_customer(cust, idx, customers.size, stats, dry_run, verbose, force)
        end

        print_results(stats, dry_run)
        print_next_steps(dry_run, stats[:granted])
      end

      private

      def init_stats
        {
          total: 0,
          granted: 0,
          skipped_no_org: 0,
          skipped_already_complimentary: 0,
          errors: [],
        }
      end

      def scan_for_customers
        puts "\nScanning customers for legacy pro-bono planid values..."

        customers = Billing::Operations::GrantProbonoEntitlements
          .find_eligible_customers do |scanned, total|
            print "\r  Scanned #{scanned}/#{total} customers..." if total >= 100
          end
        print "\r" + (' ' * 60) + "\r"

        if customers.empty?
          legacy_planids = Billing::Operations::GrantProbonoEntitlements::LEGACY_PROBONO_PLANIDS
          puts "\nNo legacy pro-bono accounts found (planid in #{legacy_planids})."
        else
          puts "\nDiscovered #{customers.size} legacy pro-bono accounts"
        end

        customers
      end

      def process_customer(cust, idx, total, stats, dry_run, verbose, force)
        stats[:total] += 1
        label          = "[#{idx + 1}/#{total}]"

        result = Billing::Operations::GrantProbonoEntitlements.call(
          cust, dry_run: dry_run, force: force
        )

        update_stats(stats, result)
        report_result(result, label, verbose)
      rescue StandardError => ex
        stats[:errors] << "#{cust.extid}: #{ex.message}"
        puts "  #{label} Error: #{ex.message}"
        # Include backtrace in the structured log so unexpected
        # failures across large batches are diagnosable; keep the
        # terminal output a single line for the operator.
        backtrace = (ex.backtrace || []).join("\n")
        OT.le "[GrantProBonoEntitlements] Error for #{cust.extid}: #{ex.message}\n#{backtrace}"
      end

      def update_stats(stats, result)
        case result.status
        when :granted, :would_grant         then stats[:granted]                       += 1
        when :skipped_no_org                then stats[:skipped_no_org]                += 1
        when :skipped_already_complimentary then stats[:skipped_already_complimentary] += 1
        end
      end

      def report_result(result, label, verbose)
        return unless verbose

        message = case result.status
                  when :would_grant
                    "Would grant: #{result.customer_extid} -> org #{result.org_extid}"
                  when :granted
                    "Granted: #{result.customer_extid} -> org #{result.org_extid}"
                  when :skipped_no_org
                    "Skipping #{result.customer_extid} (no organization)"
                  when :skipped_already_complimentary
                    "Skipping #{result.customer_extid} (org already complimentary)"
                  end
        puts "  #{label} #{message}" if message
      end

      def print_mode_banner(dry_run, force)
        if dry_run
          puts "\nDRY RUN MODE - No changes will be made"
          puts "To execute, run with --run\n"
        else
          puts "\nLIVE MODE - Granting entitlements"
          puts '  (--force: will re-materialize already-complimentary orgs)' if force
        end
      end

      def print_results(stats, dry_run)
        puts "\n" + ('=' * 60)
        puts "Grant #{dry_run ? 'Preview' : 'Complete'}"
        puts '=' * 60
        puts "\nStatistics:"
        puts '  Total pro-bono accounts:'.ljust(35) + stats[:total].to_s
        puts '  Granted:'.ljust(35) + stats[:granted].to_s
        puts '  Skipped (no organization):'.ljust(35) + stats[:skipped_no_org].to_s
        puts '  Skipped (already complimentary):'.ljust(35) + stats[:skipped_already_complimentary].to_s

        return unless stats[:errors].any?

        puts "\n  Errors:".ljust(35) + stats[:errors].size.to_s
        stats[:errors].each { |err| puts "    - #{err}" }
      end

      def print_next_steps(dry_run, granted_count)
        return unless dry_run && granted_count > 0

        puts <<~MESSAGE

          To execute, run:
            bin/ots migrations grant-probono-entitlements --run

        MESSAGE
      end

      def show_usage_help
        puts <<~USAGE

          Pro-Bono Entitlement Grant

          Usage:
            bin/ots migrations grant-probono-entitlements [options]

          Description:
            Grants pro-bono entitlements directly to legacy accounts where
            customer.planid='identity'. Sets the customer's default org to
            planid='identity', marks it complimentary, and materializes the
            org's entitlements from the catalog. Clears the legacy
            customer.planid afterward.

            This replaces the Stripe-based migrate-probono-accounts command.
            Now that entitlements are materialized at the org level and the
            'identity' plan lives in the catalog, no $0 Stripe subscription
            is required to express the pro-bono state.

          Options:
            --run                 Execute changes (default is dry-run)
            --force               Re-materialize entitlements on orgs already
                                  marked complimentary
            --verbose, -v         Show detailed progress for each account
            --help, -h            Show this help message

          Examples:
            # Preview (dry run)
            bin/ots migrations grant-probono-entitlements

            # Execute
            bin/ots migrations grant-probono-entitlements --run

            # Execute with verbose output
            bin/ots migrations grant-probono-entitlements --run --verbose

            # Force re-materialize on already-complimentary orgs
            bin/ots migrations grant-probono-entitlements --run --force

          What This Does:
            For each customer with planid='identity':
            1. Finds their default organization
            2. Sets org.planid='identity', org.complimentary='true'
            3. Materializes the org's entitlements from the 'identity' plan
            4. Clears the legacy customer.planid field

          Notes:
            - Command is idempotent (safe to run multiple times)
            - Skips orgs already marked complimentary unless --force
            - Requires the 'identity' plan to be defined in billing.yaml
            - Business logic lives in Billing::Operations::GrantProbonoEntitlements

        USAGE
        true
      end
    end

    register 'migrations grant-probono-entitlements', GrantProbonoEntitlementsCommand
  end
end
