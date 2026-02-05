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

        return unless verify_stripe_configured!
        return unless verify_federation_configured!

        orgs_with_stripe = find_orgs_with_stripe
        return if orgs_with_stripe.empty?

        total_orgs = orgs_with_stripe.size
        dry_run    = !run
        print_mode_banner(dry_run)

        stats = { total: 0, updated: 0, skipped_no_email: 0, skipped_has_hash: 0, errors: [] }

        orgs_with_stripe.each_with_index do |org, idx|
          process_stripe_customer(org, idx, total_orgs, stats, dry_run, verbose)
        end

        print_results(stats, dry_run, verbose, 'Stripe customers')
        print_next_steps(dry_run, stats[:updated], 'backfill-stripe-email-hash')
      end

      private

      def verify_stripe_configured!
        return true if defined?(Stripe) && !Stripe.api_key.to_s.empty?

        puts "\nStripe API not configured. Please set STRIPE_SECRET_KEY."
        false
      end

      def verify_federation_configured!
        Onetime::Utils::EmailHash.compute('test@example.com')
        true
      rescue Onetime::Problem => ex
        puts "\nConfiguration Error: #{ex.message}"
        puts "\nTo configure, set FEDERATION_HMAC_SECRET in your environment"
        puts 'or add site.federation_hmac_secret to your config file.'
        false
      end

      def find_orgs_with_stripe
        all_org_ids = Onetime::Organization.instances.all
        orgs        = all_org_ids.filter_map do |objid|
          org = Onetime::Organization.load(objid)
          org if org && !org.stripe_customer_id.to_s.empty?
        end

        if orgs.empty?
          puts "\nNo organizations with Stripe customer IDs found."
        else
          puts "\nDiscovered #{orgs.size} organizations with Stripe customers"
        end

        orgs
      end

      def print_mode_banner(dry_run)
        if dry_run
          puts "\nDRY RUN MODE - No changes will be made to Stripe"
          puts "To execute backfill, run with --run flag\n"
        else
          puts "\nRate limit: #{(1 / BATCH_DELAY_SECONDS).to_i} requests/second"
        end
      end

      def process_stripe_customer(org, idx, total_orgs, stats, dry_run, verbose)
        stats[:total] += 1
        customer       = Stripe::Customer.retrieve(org.stripe_customer_id)

        if customer_has_hash?(customer, org, idx, total_orgs, stats, verbose)
          return
        end

        email_hash = compute_org_email_hash(org, idx, total_orgs, stats, verbose)
        return unless email_hash

        update_stripe_customer(org, customer, email_hash, idx, total_orgs, dry_run, verbose)
        stats[:updated] += 1
        print_progress(stats[:total], total_orgs, verbose, 10, 'customers')
      rescue Stripe::RateLimitError
        puts "  [#{idx + 1}/#{total_orgs}] Rate limited, waiting 5 seconds..."
        sleep(5)
        retry
      rescue Stripe::StripeError => ex
        record_stripe_error(org, ex, idx, total_orgs, stats)
      rescue StandardError => ex
        record_general_error(org, ex, idx, total_orgs, stats)
      end

      def customer_has_hash?(customer, org, idx, total_orgs, stats, verbose)
        return false if customer.metadata['email_hash'].to_s.empty?

        stats[:skipped_has_hash] += 1
        puts "  [#{idx + 1}/#{total_orgs}] Skipping (has hash): #{org.stripe_customer_id}" if verbose
        true
      end

      def compute_org_email_hash(org, idx, total_orgs, stats, verbose)
        email_hash = Onetime::Utils::EmailHash.compute(org.billing_email)
        return email_hash if email_hash

        stats[:skipped_no_email] += 1
        puts "  [#{idx + 1}/#{total_orgs}] Skipping (no billing_email): #{org.extid}" if verbose
        nil
      end

      def update_stripe_customer(org, customer, email_hash, idx, total_orgs, dry_run, verbose)
        region          = OT.conf.dig(:site, :region) || 'default'
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
          sleep(BATCH_DELAY_SECONDS)
          puts "  [#{idx + 1}/#{total_orgs}] Updated: #{org.stripe_customer_id} -> #{email_hash[0..7]}..." if verbose
        end
      end

      def record_stripe_error(org, ex, idx, total_orgs, stats)
        error_msg = "#{org.stripe_customer_id}: #{ex.message}"
        stats[:errors] << error_msg
        puts "  [#{idx + 1}/#{total_orgs}] Stripe error: #{error_msg}"
        OT.le "[BackfillStripeEmailHash] Stripe error for #{org.stripe_customer_id}: #{ex.message}"
      end

      def record_general_error(org, ex, idx, total_orgs, stats)
        error_msg = "#{org.extid}: #{ex.message}"
        stats[:errors] << error_msg
        puts "  [#{idx + 1}/#{total_orgs}] Error: #{error_msg}"
        OT.le "[BackfillStripeEmailHash] Error for #{org.extid}: #{ex.message}"
      end

      def print_progress(current, total, verbose, interval, label)
        return if verbose
        return unless (current % interval).zero?

        print "\r  Progress: #{current}/#{total} #{label} processed"
      end

      def print_results(stats, dry_run, verbose, label)
        print "\r" + (' ' * 80) + "\r" unless verbose

        puts "\n" + ('=' * 60)
        puts "Backfill #{dry_run ? 'Preview' : 'Complete'}"
        puts '=' * 60
        puts "\nStatistics:"
        puts "  Total #{label}:".ljust(30) + stats[:total].to_s
        puts '  Updated:'.ljust(30) + stats[:updated].to_s
        puts '  Skipped (no billing_email):'.ljust(30) + stats[:skipped_no_email].to_s
        puts '  Skipped (already has hash):'.ljust(30) + stats[:skipped_has_hash].to_s

        return unless stats[:errors].any?

        puts "\n  Errors:".ljust(30) + stats[:errors].size.to_s
        return unless verbose

        puts "\n  Error details:"
        stats[:errors].each { |err| puts "    - #{err}" }
      end

      def print_next_steps(dry_run, updated_count, command_name)
        return unless dry_run && updated_count > 0

        puts <<~MESSAGE

          To execute backfill, run:
            bin/ots migrations #{command_name} --run

        MESSAGE
      end

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
