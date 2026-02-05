# lib/onetime/cli/migrations/backfill_stripe_email_hash_command.rb
#
# frozen_string_literal: true

# Backfill email_hash metadata for existing Stripe customers.
#
# The email_hash in Stripe customer metadata enables cross-region subscription
# federation. This command updates Stripe customers that were created before
# the federation feature was added.
#
# Usage:
#   bin/ots migrations backfill-stripe-email-hash           # Dry run (default)
#   bin/ots migrations backfill-stripe-email-hash --run     # Execute backfill
#   bin/ots migrations backfill-stripe-email-hash --verbose # Show each customer
#
# @see https://github.com/onetimesecret/onetimesecret/issues/2471

require 'onetime/utils/email_hash'

module Onetime
  module CLI
    class BackfillStripeEmailHashCommand < Command
      desc 'Backfill email_hash metadata for Stripe customers'

      # Conservative rate limit: 10 requests/second (100ms delay)
      # Stripe allows 100 req/sec in live mode, but we're conservative for safety
      BATCH_DELAY_SECONDS = 0.1

      option :run,
        type: :boolean,
        default: false,
        desc: 'Execute backfill (default is dry-run)'

      option :verbose,
        type: :boolean,
        default: false,
        aliases: ['v'],
        desc: 'Show detailed progress for each customer'

      option :help,
        type: :boolean,
        default: false,
        aliases: ['h'],
        desc: 'Show help message'

      def call(run: false, verbose: false, help: false, **)
        return show_usage_help if help

        boot_application!

        puts "\nStripe Customer Email Hash Backfill"
        puts '=' * 60

        # Verify Stripe is configured
        unless defined?(Stripe) && !Stripe.api_key.to_s.empty?
          puts "\nStripe API not configured. Please set STRIPE_SECRET_KEY."
          return
        end

        # Verify FEDERATION_HMAC_SECRET is configured
        begin
          Onetime::Utils::EmailHash.compute('test@example.com')
        rescue Onetime::Problem => ex
          puts "\nConfiguration Error: #{ex.message}"
          puts "\nTo configure, set FEDERATION_HMAC_SECRET in your environment"
          puts 'or add site.federation_hmac_secret to your config file.'
          return
        end

        # Find organizations with stripe_customer_id
        all_org_ids      = Onetime::Organization.instances.all
        orgs_with_stripe = []

        all_org_ids.each do |objid|
          org = Onetime::Organization.load(objid)
          next unless org && !org.stripe_customer_id.to_s.empty?

          orgs_with_stripe << org
        end

        total_orgs = orgs_with_stripe.size

        if total_orgs.zero?
          puts "\nNo organizations with Stripe customer IDs found."
          return
        end

        puts "\nDiscovered #{total_orgs} organizations with Stripe customers"

        dry_run = !run
        if dry_run
          puts "\nDRY RUN MODE - No changes will be made to Stripe"
          puts "To execute backfill, run with --run flag\n"
        else
          puts "\nRate limit: #{(1 / BATCH_DELAY_SECONDS).to_i} requests/second"
        end

        stats = {
          total: 0,
          updated: 0,
          skipped_no_email: 0,
          skipped_has_hash: 0,
          errors: [],
        }

        region = OT.conf.dig(:site, :region) || 'default'

        orgs_with_stripe.each_with_index do |org, idx|
          stats[:total] += 1

          begin
            # Retrieve Stripe customer
            customer = Stripe::Customer.retrieve(org.stripe_customer_id)

            # Skip if already has email_hash in metadata
            unless customer.metadata['email_hash'].to_s.empty?
              stats[:skipped_has_hash] += 1
              if verbose
                puts "  [#{idx + 1}/#{total_orgs}] Skipping (has hash): #{org.stripe_customer_id}"
              end
              next
            end

            # Compute hash from org's billing_email (source of truth)
            email_hash = Onetime::Utils::EmailHash.compute(org.billing_email)
            if email_hash.nil?
              stats[:skipped_no_email] += 1
              if verbose
                puts "  [#{idx + 1}/#{total_orgs}] Skipping (no billing_email): #{org.extid}"
              end
              next
            end

            # Merge with existing metadata (preserve any existing fields)
            merged_metadata = customer.metadata.to_h.merge(
              'email_hash' => email_hash,
              'email_hash_created_at' => Time.now.to_i.to_s,
              'email_hash_migrated' => 'true',
              'home_region' => region,
            )

            if dry_run
              puts "  [#{idx + 1}/#{total_orgs}] Would update: #{org.stripe_customer_id} (#{OT::Utils.obscure_email(org.billing_email)})"
            else
              Stripe::Customer.update(org.stripe_customer_id, metadata: merged_metadata)
              sleep(BATCH_DELAY_SECONDS) # Rate limiting

              if verbose
                puts "  [#{idx + 1}/#{total_orgs}] Updated: #{org.stripe_customer_id} -> #{email_hash[0..7]}..."
              end
            end

            stats[:updated] += 1

            # Progress indicator for non-verbose mode
            if !verbose && (stats[:total] % 10).zero?
              print "\r  Progress: #{stats[:total]}/#{total_orgs} customers processed"
            end
          rescue Stripe::InvalidRequestError => ex
            # Customer may have been deleted in Stripe
            error_msg = "#{org.stripe_customer_id}: #{ex.message}"
            stats[:errors] << error_msg
            puts "  [#{idx + 1}/#{total_orgs}] Stripe error: #{error_msg}"
            OT.le "[BackfillStripeEmailHash] Stripe error for #{org.stripe_customer_id}: #{ex.message}"
          rescue Stripe::RateLimitError => ex
            # Back off and retry once
            error_msg = "#{org.stripe_customer_id}: Rate limited, backing off"
            puts "  [#{idx + 1}/#{total_orgs}] Rate limited, waiting 5 seconds..."
            sleep(5)
            retry
          rescue Stripe::StripeError => ex
            error_msg = "#{org.stripe_customer_id}: #{ex.message}"
            stats[:errors] << error_msg
            puts "  [#{idx + 1}/#{total_orgs}] Stripe error: #{error_msg}"
            OT.le "[BackfillStripeEmailHash] Stripe error for #{org.stripe_customer_id}: #{ex.message}"
          rescue StandardError => ex
            error_msg = "#{org.extid}: #{ex.message}"
            stats[:errors] << error_msg
            puts "  [#{idx + 1}/#{total_orgs}] Error: #{error_msg}"
            OT.le "[BackfillStripeEmailHash] Error for #{org.extid}: #{ex.message}"
          end
        end

        # Clear progress line
        print "\r" + (' ' * 80) + "\r" unless verbose

        # Report results
        puts "\n" + ('=' * 60)
        puts "Backfill #{dry_run ? 'Preview' : 'Complete'}"
        puts '=' * 60
        puts "\nStatistics:"
        puts "  Total Stripe customers:     #{stats[:total]}"
        puts "  Updated:                    #{stats[:updated]}"
        puts "  Skipped (no billing_email): #{stats[:skipped_no_email]}"
        puts "  Skipped (already has hash): #{stats[:skipped_has_hash]}"

        if stats[:errors].any?
          puts "\n  Errors:                     #{stats[:errors].size}"
          if verbose
            puts "\n  Error details:"
            stats[:errors].each { |err| puts "    - #{err}" }
          end
        end

        return unless dry_run && stats[:updated] > 0

        puts <<~MESSAGE

          To execute backfill, run:
            bin/ots migrations backfill-stripe-email-hash --run

        MESSAGE
      end

      private

      def show_usage_help
        puts <<~USAGE

          Stripe Customer Email Hash Backfill

          Usage:
            bin/ots migrations backfill-stripe-email-hash [options]

          Description:
            Backfills email_hash metadata for existing Stripe customers.
            The email_hash enables cross-region subscription federation by
            allowing regions to match customers without exposing email addresses.

          Options:
            --run                 Execute backfill (default is dry-run)
            --verbose, -v         Show detailed progress for each customer
            --help, -h            Show this help message

          Examples:
            # Preview backfill (dry run)
            bin/ots migrations backfill-stripe-email-hash

            # Execute backfill
            bin/ots migrations backfill-stripe-email-hash --run

            # Execute with verbose output
            bin/ots migrations backfill-stripe-email-hash --run --verbose

          Metadata Fields Added:
            - email_hash:            HMAC-SHA256 hash of billing_email (32 chars)
            - email_hash_created_at: Unix timestamp when hash was added
            - email_hash_migrated:   'true' flag indicating backfill (vs. creation-time)
            - home_region:           Region where org was created

          Notes:
            - Command is idempotent (safe to run multiple times)
            - Skips customers that already have email_hash metadata
            - Skips organizations without billing_email
            - Rate limited to ~10 requests/second for safety
            - Requires STRIPE_SECRET_KEY and FEDERATION_HMAC_SECRET

        USAGE
        true
      end
    end

    register 'migrations backfill-stripe-email-hash', BackfillStripeEmailHashCommand
  end
end
