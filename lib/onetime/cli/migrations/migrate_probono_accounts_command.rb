# lib/onetime/cli/migrations/migrate_probono_accounts_command.rb
#
# frozen_string_literal: true

# Migrate legacy pro-bono accounts to $0 complimentary subscriptions.
#
# Legacy pro-bono accounts have customer.planid='identity' but no
# corresponding organization-level subscription. This command:
#
# 1. Finds customers with planid='identity'
# 2. Locates each customer's default organization
# 3. Creates a Stripe Customer (if needed)
# 4. Creates a $0 subscription on the identity_plus product
# 5. Sets org.planid='identity_plus_v1', subscription_status='active',
#    and complimentary='true'
# 6. Clears the legacy customer.planid field
#
# Usage:
#   bin/ots migrations migrate-probono-accounts                    # Dry run
#   bin/ots migrations migrate-probono-accounts --run              # Execute
#   bin/ots migrations migrate-probono-accounts --run --verbose    # Verbose
#
# Prerequisites:
#   - STRIPE_API_KEY must be set
#   - A $0 Stripe Price must exist (pass via --price-id)
#
# @see https://github.com/onetimesecret/onetimesecret/issues/2657

module Onetime
  module CLI
    class MigrateProbonoAccountsCommand < Command
      desc 'Migrate legacy pro-bono accounts (customer.planid=identity) to $0 subscriptions'

      # Conservative rate limit for Stripe API calls
      BATCH_DELAY_SECONDS    = 0.2
      MAX_RATE_LIMIT_RETRIES = 3

      # Legacy planid values that indicate pro-bono accounts
      LEGACY_PROBONO_PLANIDS = %w[identity].freeze

      # Target plan for migrated accounts
      TARGET_PLANID = 'identity_plus_v1'

      option :run,
        type: :boolean,
        default: false,
        desc: 'Execute migration (default is dry-run)'

      option :verbose,
        type: :boolean,
        default: false,
        aliases: ['v'],
        desc: 'Show detailed progress for each account'

      option :price_id,
        type: :string,
        default: nil,
        desc: 'Stripe Price ID for the $0 complimentary plan (required for --run)'

      option :help,
        type: :boolean,
        default: false,
        aliases: ['h'],
        desc: 'Show help message'

      def call(run: false, verbose: false, price_id: nil, help: false, **)
        return show_usage_help if help

        boot_application!

        puts "\nPro-Bono Account Migration"
        puts '=' * 60

        dry_run = !run

        if !dry_run && price_id.to_s.empty?
          puts "\nError: --price-id is required when using --run"
          puts 'This should be a $0 Stripe Price ID on the identity_plus product.'
          puts 'Create one in Stripe Dashboard or via API first.'
          return
        end

        return unless verify_stripe_configured! unless dry_run

        customers = find_probono_customers
        return if customers.empty?

        print_mode_banner(dry_run)

        stats = {
          total: 0,
          migrated: 0,
          skipped_no_org: 0,
          skipped_has_subscription: 0,
          skipped_already_migrated: 0,
          errors: [],
        }

        customers.each_with_index do |cust, idx|
          process_customer(cust, idx, customers.size, stats, dry_run, verbose, price_id)
        end

        print_results(stats, dry_run)
        print_next_steps(dry_run, stats[:migrated])
      end

      private

      def verify_stripe_configured!
        return true if defined?(Stripe) && !Stripe.api_key.to_s.empty?

        puts "\nStripe API not configured. Please set STRIPE_API_KEY."
        false
      end

      def find_probono_customers
        puts "\nScanning customers for legacy pro-bono planid values..."

        all_ids   = Onetime::Customer.instances.all
        total     = all_ids.size
        probono   = []

        # Process in batches to avoid memory issues
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

      def print_mode_banner(dry_run)
        if dry_run
          puts "\nDRY RUN MODE - No changes will be made"
          puts "To execute migration, run with --run --price-id <price_id>\n"
        else
          puts "\nLIVE MODE - Creating Stripe subscriptions"
          puts "Rate limit: #{(1 / BATCH_DELAY_SECONDS).to_i} requests/second\n"
        end
      end

      def process_customer(cust, idx, total, stats, dry_run, verbose, price_id)
        stats[:total] += 1
        label = "[#{idx + 1}/#{total}]"

        # Find default organization
        orgs = cust.organization_instances.to_a
        org  = orgs.find(&:is_default) || orgs.first

        unless org
          stats[:skipped_no_org] += 1
          puts "  #{label} Skipping #{cust.extid} (no organization)" if verbose
          return
        end

        # Skip if org already has an active subscription
        if org.active_subscription? && !org.planid.to_s.empty? && org.planid != 'free_v1'
          stats[:skipped_has_subscription] += 1
          puts "  #{label} Skipping #{cust.extid} (org already has subscription: #{org.planid})" if verbose
          return
        end

        # Skip if already migrated (complimentary marker set)
        if org.complimentary.to_s == 'true'
          stats[:skipped_already_migrated] += 1
          puts "  #{label} Skipping #{cust.extid} (already migrated)" if verbose
          return
        end

        if dry_run
          puts "  #{label} Would migrate: #{cust.extid} (#{cust.email}) -> org #{org.extid}"
          stats[:migrated] += 1
          return
        end

        # Live migration
        migrate_account!(cust, org, price_id, label, stats, verbose)
      rescue StandardError => ex
        stats[:errors] << "#{cust.extid}: #{ex.message}"
        puts "  #{label} Error: #{ex.message}"
        OT.le "[MigrateProBono] Error for #{cust.extid}: #{ex.message}"
      end

      def migrate_account!(cust, org, price_id, label, stats, verbose)
        rate_limit_retries = 0

        begin
          # Step 1: Get or create Stripe Customer
          stripe_customer = get_or_create_stripe_customer(org, cust)

          # Step 2: Create $0 subscription with complimentary metadata
          subscription = Stripe::Subscription.create(
            customer: stripe_customer.id,
            items: [{ price: price_id }],
            metadata: {
              Billing::Metadata::FIELD_COMPLIMENTARY => 'true',
              Billing::Metadata::FIELD_PLAN_ID => TARGET_PLANID,
              'migrated_from' => 'probono',
              'migrated_at' => Time.now.utc.iso8601,
              'legacy_planid' => cust.planid.to_s,
            },
          )

          # Step 3: Update organization via shared operation
          # Uses planid_override because the $0 complimentary price may
          # not be in the plan catalog yet.
          require 'billing/operations/apply_subscription_to_org'
          Billing::Operations::ApplySubscriptionToOrg.call(
            org, subscription,
            owner: true,
            planid_override: TARGET_PLANID
          )

          # Step 4: Clear legacy customer.planid
          cust.planid = nil
          cust.save

          stats[:migrated] += 1
          puts "  #{label} Migrated: #{cust.extid} -> sub #{subscription.id}" if verbose

          sleep(BATCH_DELAY_SECONDS)
        rescue Stripe::RateLimitError => ex
          rate_limit_retries += 1
          if rate_limit_retries <= MAX_RATE_LIMIT_RETRIES
            backoff = 5 * rate_limit_retries
            puts "  #{label} Rate limited (attempt #{rate_limit_retries}/#{MAX_RATE_LIMIT_RETRIES}), waiting #{backoff}s..."
            sleep(backoff)
            retry
          else
            raise
          end
        end
      end

      # Find existing Stripe customer or create a new one
      def get_or_create_stripe_customer(org, cust)
        # Try existing org stripe_customer_id first
        unless org.stripe_customer_id.to_s.empty?
          begin
            return Stripe::Customer.retrieve(org.stripe_customer_id)
          rescue Stripe::InvalidRequestError
            OT.lw "[MigrateProBono] Stripe customer not found: #{org.stripe_customer_id}"
          end
        end

        # Try finding by email
        email = [org.billing_email, org.contact_email, cust.email].find do |e|
          !e.to_s.empty?
        end

        if email
          existing = Stripe::Customer.list(email: email, limit: 1)
          return existing.data.first unless existing.data.empty?
        end

        # Create new Stripe customer
        Stripe::Customer.create(
          email: email,
          metadata: {
            'org_extid' => org.extid,
            'migrated_from' => 'probono',
            'migrated_at' => Time.now.utc.iso8601,
          },
        )
      end

      def print_results(stats, dry_run)
        puts "\n" + ('=' * 60)
        puts "Migration #{dry_run ? 'Preview' : 'Complete'}"
        puts '=' * 60
        puts "\nStatistics:"
        puts '  Total pro-bono accounts:'.ljust(35) + stats[:total].to_s
        puts '  Migrated:'.ljust(35) + stats[:migrated].to_s
        puts '  Skipped (no organization):'.ljust(35) + stats[:skipped_no_org].to_s
        puts '  Skipped (has subscription):'.ljust(35) + stats[:skipped_has_subscription].to_s
        puts '  Skipped (already migrated):'.ljust(35) + stats[:skipped_already_migrated].to_s

        return unless stats[:errors].any?

        puts "\n  Errors:".ljust(35) + stats[:errors].size.to_s
        stats[:errors].each { |err| puts "    - #{err}" }
      end

      def print_next_steps(dry_run, migrated_count)
        return unless dry_run && migrated_count > 0

        puts <<~MESSAGE

          To execute migration, run:
            bin/ots migrations migrate-probono-accounts --run --price-id <PRICE_ID>

          Prerequisites:
            1. Create a $0 CAD recurring price on the identity_plus product in Stripe
            2. Set metadata: complimentary=true on the price
            3. Use that price ID with --price-id

        MESSAGE
      end

      def show_usage_help
        puts <<~USAGE

          Pro-Bono Account Migration

          Usage:
            bin/ots migrations migrate-probono-accounts [options]

          Description:
            Migrates legacy pro-bono accounts (customer.planid='identity') to
            $0 complimentary Stripe subscriptions on the identity_plus_v1 plan.

            This ensures pro-bono accounts are visible to the modern organization-
            based billing infrastructure and can use the canonical paid? and
            complimentary? methods.

          Options:
            --run                 Execute migration (default is dry-run)
            --price-id <ID>       Stripe Price ID for $0 complimentary plan (required with --run)
            --verbose, -v         Show detailed progress for each account
            --help, -h            Show this help message

          Examples:
            # Preview migration (dry run)
            bin/ots migrations migrate-probono-accounts

            # Execute migration
            bin/ots migrations migrate-probono-accounts --run --price-id price_0ABC123

            # Verbose dry run
            bin/ots migrations migrate-probono-accounts --verbose

          What This Does:
            For each customer with planid='identity':
            1. Finds their default organization
            2. Creates a Stripe Customer (if needed)
            3. Creates a $0 subscription with complimentary metadata
            4. Sets org: planid=identity_plus_v1, subscription_status=active,
               complimentary=true
            5. Clears the legacy customer.planid field

          Notes:
            - Command is idempotent (safe to run multiple times)
            - Skips accounts that already have active subscriptions
            - Skips accounts already marked complimentary
            - Rate limited for Stripe API safety
            - Requires STRIPE_API_KEY and --price-id

        USAGE
        true
      end
    end

    register 'migrations migrate-probono-accounts', MigrateProbonoAccountsCommand
  end
end
