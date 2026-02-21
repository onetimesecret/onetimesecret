# lib/onetime/cli/migrations/backfill_subscription_status_command.rb
#
# frozen_string_literal: true

# Backfill subscription_status and subscription_period_end for organizations
# from Stripe subscription data.
#
# The v0.24.0 migration creates organizations with stripe_subscription_id but
# omits subscription_status and subscription_period_end (these cannot be derived
# from the v1 source data). This command reconciles by fetching current state
# from Stripe.
#
# Usage:
#   bin/ots migrations backfill-subscription-status           # Dry run (default)
#   bin/ots migrations backfill-subscription-status --run     # Execute backfill
#   bin/ots migrations backfill-subscription-status --verbose # Show each org
#
# @see scripts/upgrades/v0.24.0/02-organization/generate.rb

module Onetime
  module CLI
    class BackfillSubscriptionStatusCommand < Command
      desc 'Backfill subscription_status and subscription_period_end from Stripe'

      # Conservative rate limit: 10 requests/second (100ms delay)
      # Stripe allows 100 req/sec in live mode, but we're conservative for safety
      BATCH_DELAY_SECONDS    = 0.1
      MAX_RATE_LIMIT_RETRIES = 3

      option :run,
        type: :boolean,
        default: false,
        desc: 'Execute backfill (default is dry-run)'

      option :verbose,
        type: :boolean,
        default: false,
        aliases: ['v'],
        desc: 'Show detailed progress for each organization'

      option :help,
        type: :boolean,
        default: false,
        aliases: ['h'],
        desc: 'Show help message'

      def call(run: false, verbose: false, help: false, **)
        return show_usage_help if help

        boot_application!

        puts "\nSubscription Status Backfill"
        puts '=' * 60

        return unless verify_stripe_configured!

        orgs = find_orgs_with_subscription
        return if orgs.empty?

        total_orgs = orgs.size
        dry_run    = !run
        print_mode_banner(dry_run)

        stats = { total: 0, updated: 0, skipped_has_status: 0, skipped_deleted: 0, errors: [] }

        orgs.each_with_index do |org, idx|
          process_org(org, idx, total_orgs, stats, dry_run, verbose)
        end

        print_results(stats, dry_run, verbose)
        print_next_steps(dry_run, stats[:updated])
      end

      private

      def verify_stripe_configured!
        return true if defined?(Stripe) && !Stripe.api_key.to_s.empty?

        puts "\nStripe API not configured. Please set STRIPE_API_KEY."
        false
      end

      def find_orgs_with_subscription
        all_org_ids = Onetime::Organization.instances.all
        orgs        = all_org_ids.filter_map do |objid|
          org = Onetime::Organization.load(objid)
          org if org && !org.stripe_subscription_id.to_s.empty?
        end

        if orgs.empty?
          puts "\nNo organizations with Stripe subscription IDs found."
        else
          puts "\nDiscovered #{orgs.size} organizations with Stripe subscriptions"
        end

        orgs
      end

      def print_mode_banner(dry_run)
        if dry_run
          puts "\nDRY RUN MODE - No changes will be made"
          puts "To execute backfill, run with --run flag\n"
        else
          puts "\nRate limit: #{(1 / BATCH_DELAY_SECONDS).to_i} requests/second"
        end
      end

      def process_org(org, idx, total_orgs, stats, dry_run, verbose)
        stats[:total]     += 1
        rate_limit_retries = 0

        # Skip orgs that already have subscription_status (idempotent)
        unless org.subscription_status.to_s.empty?
          stats[:skipped_has_status] += 1
          puts "  [#{idx + 1}/#{total_orgs}] Skipping (has status '#{org.subscription_status}'): #{org.extid}" if verbose
          print_progress(stats[:total], total_orgs, verbose, 10)
          return
        end

        begin
          subscription = Stripe::Subscription.retrieve(org.stripe_subscription_id)

          status     = subscription.status
          period_end = subscription.items.data.first&.current_period_end

          if dry_run
            puts "  [#{idx + 1}/#{total_orgs}] Would update: #{org.extid} -> status=#{status}, period_end=#{period_end}"
          else
            org.subscription_status     = status
            org.subscription_period_end = period_end.to_s if period_end
            org.save
            sleep(BATCH_DELAY_SECONDS)
            puts "  [#{idx + 1}/#{total_orgs}] Updated: #{org.extid} -> status=#{status}" if verbose
          end

          stats[:updated] += 1
          print_progress(stats[:total], total_orgs, verbose, 10)
        rescue Stripe::InvalidRequestError => ex
          if ex.code == 'resource_missing'
            stats[:skipped_deleted] += 1
            puts "  [#{idx + 1}/#{total_orgs}] Skipping (subscription not found in Stripe): #{org.stripe_subscription_id}" if verbose
            OT.lw "[BackfillSubscriptionStatus] Subscription not found: #{org.stripe_subscription_id} for org #{org.extid}"
          else
            record_stripe_error(org, ex, idx, total_orgs, stats)
          end
        rescue Stripe::RateLimitError => ex
          rate_limit_retries += 1
          if rate_limit_retries <= MAX_RATE_LIMIT_RETRIES
            backoff = 5 * rate_limit_retries
            puts "  [#{idx + 1}/#{total_orgs}] Rate limited (attempt #{rate_limit_retries}/#{MAX_RATE_LIMIT_RETRIES}), waiting #{backoff}s..."
            sleep(backoff)
            retry
          else
            record_stripe_error(org, ex, idx, total_orgs, stats)
          end
        rescue Stripe::StripeError => ex
          record_stripe_error(org, ex, idx, total_orgs, stats)
        rescue StandardError => ex
          record_general_error(org, ex, idx, total_orgs, stats)
        end
      end

      def record_stripe_error(org, ex, idx, total_orgs, stats)
        error_msg = "#{org.stripe_subscription_id}: #{ex.message}"
        stats[:errors] << error_msg
        puts "  [#{idx + 1}/#{total_orgs}] Stripe error: #{error_msg}"
        OT.le "[BackfillSubscriptionStatus] Stripe error for #{org.stripe_subscription_id}: #{ex.message}"
      end

      def record_general_error(org, ex, idx, total_orgs, stats)
        error_msg = "#{org.extid}: #{ex.message}"
        stats[:errors] << error_msg
        puts "  [#{idx + 1}/#{total_orgs}] Error: #{error_msg}"
        OT.le "[BackfillSubscriptionStatus] Error for #{org.extid}: #{ex.message}"
      end

      def print_progress(current, total, verbose, interval)
        return if verbose
        return unless (current % interval).zero?

        print "\r  Progress: #{current}/#{total} organizations processed"
      end

      def print_results(stats, dry_run, verbose)
        print "\r" + (' ' * 80) + "\r" unless verbose

        puts "\n" + ('=' * 60)
        puts "Backfill #{dry_run ? 'Preview' : 'Complete'}"
        puts '=' * 60
        puts "\nStatistics:"
        puts '  Total organizations:'.ljust(30) + stats[:total].to_s
        puts '  Updated:'.ljust(30) + stats[:updated].to_s
        puts '  Skipped (has status):'.ljust(30) + stats[:skipped_has_status].to_s
        puts '  Skipped (deleted in Stripe):'.ljust(30) + stats[:skipped_deleted].to_s

        return unless stats[:errors].any?

        puts "\n  Errors:".ljust(30) + stats[:errors].size.to_s
        return unless verbose

        puts "\n  Error details:"
        stats[:errors].each { |err| puts "    - #{err}" }
      end

      def print_next_steps(dry_run, updated_count)
        return unless dry_run && updated_count > 0

        puts <<~MESSAGE

          To execute backfill, run:
            bin/ots migrations backfill-subscription-status --run

        MESSAGE
      end

      def show_usage_help
        puts <<~USAGE

          Subscription Status Backfill

          Usage:
            bin/ots migrations backfill-subscription-status [options]

          Description:
            Backfills subscription_status and subscription_period_end for
            organizations that have a stripe_subscription_id but are missing
            these fields (typically after v0.24.0 migration).

          Options:
            --run                 Execute backfill (default is dry-run)
            --verbose, -v         Show detailed progress for each organization
            --help, -h            Show this help message

          Examples:
            # Preview backfill (dry run)
            bin/ots migrations backfill-subscription-status

            # Execute backfill
            bin/ots migrations backfill-subscription-status --run

            # Execute with verbose output
            bin/ots migrations backfill-subscription-status --run --verbose

          Fields Updated:
            - subscription_status:      Stripe subscription status (active, past_due, canceled, etc.)
            - subscription_period_end:  Unix timestamp when current billing period ends

          Notes:
            - Command is idempotent (safe to run multiple times)
            - Skips organizations that already have subscription_status
            - Skips subscriptions deleted in Stripe (logs warning)
            - Rate limited to ~10 requests/second for safety
            - Requires STRIPE_API_KEY

        USAGE
        true
      end
    end

    register 'migrations backfill-subscription-status', BackfillSubscriptionStatusCommand
  end
end
