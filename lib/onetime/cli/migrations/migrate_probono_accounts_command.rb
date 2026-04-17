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

      # Default target plan for migrated accounts
      DEFAULT_TARGET_PLANID = 'identity_plus_v1'

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
        desc: 'Stripe Price ID for the $0 complimentary plan (required for --run unless --price-ids used)'

      option :price_ids,
        type: :string,
        default: nil,
        desc: 'Currency-specific prices, e.g. "cad:price_xxx,usd:price_yyy" (overrides --price-id)'

      option :target_planid,
        type: :string,
        default: DEFAULT_TARGET_PLANID,
        desc: "Target plan ID for migrated accounts (default: #{DEFAULT_TARGET_PLANID})"

      option :help,
        type: :boolean,
        default: false,
        aliases: ['h'],
        desc: 'Show help message'

      def call(run: false, verbose: false, price_id: nil, price_ids: nil, target_planid: DEFAULT_TARGET_PLANID, help: false, **)
        return show_usage_help if help

        boot_application!
        require 'billing/operations/apply_subscription_to_org'

        puts "\nPro-Bono Account Migration"
        puts '=' * 60

        dry_run = !run

        # Build currency -> price_id map
        price_map = parse_price_ids(price_ids, price_id)

        if !dry_run && price_map.empty?
          puts "\nError: --price-id or --price-ids is required when using --run"
          puts 'Examples:'
          puts '  --price-id price_xxx                        (single currency)'
          puts '  --price-ids "cad:price_xxx,usd:price_yyy"   (multi-currency)'
          return
        end

        unless dry_run || price_map.empty?
          puts "\nPrice mapping:"
          price_map.each { |cur, pid| puts "  #{(cur || 'default').upcase}: #{pid}" }
        end

        return unless dry_run || verify_stripe_configured!

        customers = find_probono_customers
        return if customers.empty?

        print_mode_banner(dry_run)

        stats = {
          total: 0,
          migrated: 0,
          skipped_no_org: 0,
          skipped_has_subscription: 0,
          skipped_already_migrated: 0,
          skipped_currency_mismatch: 0,
          errors: [],
        }

        customers.each_with_index do |cust, idx|
          process_customer(cust, idx, customers.size, stats, dry_run, verbose, price_map, target_planid)
        end

        print_results(stats, dry_run)
        print_next_steps(dry_run, stats[:migrated])
      end

      private

      # Parse --price-ids "cad:price_xxx,usd:price_yyy" into { "cad" => "price_xxx", "usd" => "price_yyy" }.
      # Falls back to --price-id as a single-entry map (currency determined at subscription time).
      def parse_price_ids(price_ids_str, single_price_id)
        if price_ids_str
          price_ids_str.split(',').each_with_object({}) do |pair, map|
            currency, pid          = pair.strip.split(':', 2)
            currency               = currency&.strip
            pid                    = pid&.strip
            map[currency.downcase] = pid if currency && !currency.empty? && pid && !pid.empty?
          end
        elsif single_price_id
          # No explicit currency — stored under nil key, used as default
          { nil => single_price_id }
        else
          {}
        end
      end

      # Pick the right price ID for a Stripe customer's currency.
      # Returns nil if no matching price is available.
      def resolve_price_for_customer(stripe_customer, price_map)
        # Single-price mode (--price-id without --price-ids)
        return price_map[nil] if price_map.key?(nil)

        customer_currency = stripe_customer.currency&.downcase
        # WARNING: When a Stripe customer has no currency set (no prior invoices)
        # and the price_map has multiple entries, we arbitrarily pick the first
        # one. If it doesn't match the currency Stripe eventually locks to this
        # customer, Stripe will reject the subscription create call and the
        # account will be logged as an error and skipped. This is acceptable for
        # this one-shot legacy pro-bono migration because: (a) with a single-
        # entry map the "first" is the only sensible choice, and (b) with a
        # multi-entry map the downstream rescue in #migrate_account! catches
        # and reports the mismatch so no silent bad data is written. Operators
        # can re-run with corrected --price-ids after investigating.
        return price_map.values.first if customer_currency.nil?

        price_map[customer_currency]
      end

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

      def process_customer(cust, idx, total, stats, dry_run, verbose, price_map, target_planid)
        stats[:total] += 1
        label          = "[#{idx + 1}/#{total}]"

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
        migrate_account!(cust, org, price_map, target_planid, label, stats, verbose)
      rescue StandardError => ex
        stats[:errors] << "#{cust.extid}: #{ex.message}"
        puts "  #{label} Error: #{ex.message}"
        OT.le "[MigrateProBono] Error for #{cust.extid}: #{ex.message}"
      end

      def migrate_account!(cust, org, price_map, target_planid, label, stats, verbose)
        rate_limit_retries = 0

        begin
          # Step 1: Get or create Stripe Customer
          stripe_customer = get_or_create_stripe_customer(org, cust)

          # Step 2: Resolve the correct price for this customer's currency
          price_id = resolve_price_for_customer(stripe_customer, price_map)
          unless price_id
            customer_currency                  = stripe_customer.currency || 'none'
            stats[:skipped_currency_mismatch] += 1
            puts "  #{label} Skipping #{cust.extid}: no price for currency #{customer_currency} (available: #{price_map.keys.join(', ')})"
            return
          end

          if stripe_customer.currency.nil? && !price_map.key?(nil) && verbose
            puts "  #{label} Note: #{cust.extid} has no Stripe currency, using default price #{price_id}"
          end

          # Step 3: Create $0 subscription with complimentary metadata
          subscription = Stripe::Subscription.create(
            customer: stripe_customer.id,
            items: [{ price: price_id }],
            metadata: {
              Billing::Metadata::FIELD_COMPLIMENTARY => 'true',
              Billing::Metadata::FIELD_PLAN_ID => target_planid,
              'migrated_from' => 'probono',
              'migrated_at' => Time.now.utc.iso8601,
              'legacy_planid' => cust.planid.to_s,
            },
          )

          # Step 4: Update organization via shared operation
          # Uses planid_override because the $0 complimentary price may
          # not be in the plan catalog yet.
          Billing::Operations::ApplySubscriptionToOrg.call(
            org,
            subscription,
            owner: true,
            planid_override: target_planid,
          )

          # Step 5: Clear legacy customer.planid
          cust.planid = nil
          cust.save

          stats[:migrated] += 1
          puts "  #{label} Migrated: #{cust.extid} -> sub #{subscription.id}" if verbose

          sleep(BATCH_DELAY_SECONDS)
        rescue Stripe::RateLimitError
          rate_limit_retries += 1
          raise unless rate_limit_retries <= MAX_RATE_LIMIT_RETRIES

          backoff = 5 * rate_limit_retries
          puts "  #{label} Rate limited (attempt #{rate_limit_retries}/#{MAX_RATE_LIMIT_RETRIES}), waiting #{backoff}s..."
          sleep(backoff)
          retry
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
        puts '  Skipped (currency mismatch):'.ljust(35) + stats[:skipped_currency_mismatch].to_s if stats[:skipped_currency_mismatch] > 0

        return unless stats[:errors].any?

        puts "\n  Errors:".ljust(35) + stats[:errors].size.to_s
        stats[:errors].each { |err| puts "    - #{err}" }
      end

      def print_next_steps(dry_run, migrated_count)
        return unless dry_run && migrated_count > 0

        puts <<~MESSAGE

          To execute migration, run:
            bin/ots migrations migrate-probono-accounts --run --price-id <PRICE_ID>

          For customers with mixed currencies (CAD/USD):
            bin/ots migrations migrate-probono-accounts --run --price-ids "cad:<CAD_PRICE>,usd:<USD_PRICE>"

          Prerequisites:
            1. Create a $0 recurring price on the identity_plus product in Stripe
               (one per currency if customers have mixed currencies)
            2. Set metadata: complimentary=true on each price
            3. Use the price ID(s) with --price-id or --price-ids

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
            --run                   Execute migration (default is dry-run)
            --price-id <ID>         Stripe Price ID for $0 complimentary plan (single currency)
            --price-ids <MAP>       Currency-specific prices: "cad:price_xxx,usd:price_yyy"
            --target-planid <ID>    Target plan ID (default: identity_plus_v1)
            --verbose, -v           Show detailed progress for each account
            --help, -h              Show this help message

          Examples:
            # Preview migration (dry run)
            bin/ots migrations migrate-probono-accounts

            # Execute with single price
            bin/ots migrations migrate-probono-accounts --run --price-id price_0ABC123

            # Execute with multi-currency prices
            bin/ots migrations migrate-probono-accounts --run --price-ids "cad:price_CAD,usd:price_USD"

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
