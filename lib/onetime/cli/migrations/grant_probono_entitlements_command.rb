# lib/onetime/cli/migrations/grant_probono_entitlements_command.rb
#
# frozen_string_literal: true

# Grant pro-bono entitlements directly to legacy identity-plan customers.
#
# Legacy pro-bono accounts have customer.planid='identity' but no
# corresponding organization-level entitlements. With materialized
# entitlements and the 'identity' plan in the catalog, the modern
# billing system no longer requires a Stripe subscription to express
# this state. This command:
#
# 1. Finds customers with planid='identity'
# 2. Locates each customer's default organization
# 3. Sets org.planid='identity', org.complimentary='true'
# 4. Materializes the org's entitlements from the 'identity' plan
# 5. Clears the legacy customer.planid field
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

      LEGACY_PROBONO_PLANIDS = %w[identity].freeze
      TARGET_PLANID          = 'identity'

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
        require 'billing/operations/apply_subscription_to_org'

        puts "\nPro-Bono Entitlement Grant"
        puts '=' * 60

        dry_run = !run

        customers = find_probono_customers
        return if customers.empty?

        print_mode_banner(dry_run, force)

        stats = {
          total: 0,
          granted: 0,
          skipped_no_org: 0,
          skipped_already_complimentary: 0,
          errors: [],
        }

        customers.each_with_index do |cust, idx|
          process_customer(cust, idx, customers.size, stats, dry_run, verbose, force)
        end

        print_results(stats, dry_run)
        print_next_steps(dry_run, stats[:granted])
      end

      private

      def find_probono_customers
        puts "\nScanning customers for legacy pro-bono planid values..."

        all_ids    = Onetime::Customer.instances.all
        total      = all_ids.size
        probono    = []
        batch_size = 100

        all_ids.each_slice(batch_size).with_index do |batch_ids, batch_idx|
          customers = Onetime::Customer.load_multi(batch_ids).compact
          customers.each do |cust|
            probono << cust if LEGACY_PROBONO_PLANIDS.include?(cust.planid.to_s)
          end
          processed = [(batch_idx + 1) * batch_size, total].min
          print "\r  Scanned #{processed}/#{total} customers..." unless total < 100
        end
        print "\r" + (' ' * 60) + "\r" unless total < 100

        if probono.empty?
          puts "\nNo legacy pro-bono accounts found (planid in #{LEGACY_PROBONO_PLANIDS})."
        else
          puts "\nDiscovered #{probono.size} legacy pro-bono accounts"
        end

        probono
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

      def process_customer(cust, idx, total, stats, dry_run, verbose, force)
        stats[:total] += 1
        label          = "[#{idx + 1}/#{total}]"

        org = default_org_for(cust)
        unless org
          stats[:skipped_no_org] += 1
          puts "  #{label} Skipping #{cust.extid} (no organization)" if verbose
          return
        end

        if !force && org.complimentary.to_s == 'true'
          stats[:skipped_already_complimentary] += 1
          puts "  #{label} Skipping #{cust.extid} (org already complimentary)" if verbose
          return
        end

        if dry_run
          puts "  #{label} Would grant: #{cust.extid} (#{cust.email}) -> org #{org.extid}"
          stats[:granted] += 1
          return
        end

        grant_account!(cust, org)
        stats[:granted] += 1
        puts "  #{label} Granted: #{cust.extid} -> org #{org.extid}" if verbose
      rescue StandardError => ex
        stats[:errors] << "#{cust.extid}: #{ex.message}"
        puts "  #{label} Error: #{ex.message}"
        OT.le "[GrantProBonoEntitlements] Error for #{cust.extid}: #{ex.message}"
      end

      # Pick the customer's default org using the same priority as
      # OrganizationLoader: explicit default_org_id, then is_default flag,
      # then first org. Avoids importing the loader's session-aware logic.
      def default_org_for(cust)
        orgs = cust.organization_instances.to_a
        return nil if orgs.empty?

        if cust.default_org_id.to_s.length.positive?
          explicit = orgs.find { |o| o.objid == cust.default_org_id }
          return explicit if explicit
        end

        orgs.find { |o| o.is_default } || orgs.first
      end

      def grant_account!(cust, org)
        org.planid        = TARGET_PLANID
        org.complimentary = 'true'
        org.save

        result = Billing::Operations::ApplySubscriptionToOrg
          .materialize_entitlements_for_org(org, raise_on_miss: true)

        cust.planid = nil
        cust.save

        result
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

        USAGE
        true
      end
    end

    register 'migrations grant-probono-entitlements', GrantProbonoEntitlementsCommand
  end
end
