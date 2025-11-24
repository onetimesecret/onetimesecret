# apps/web/billing/cli/sync_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Sync from Stripe to Redis cache
    class BillingSyncCommand < Command
      include BillingHelpers

      desc 'Sync products and prices from Stripe to Redis cache'

      option :clear, type: :boolean, default: false,
        desc: 'Clear existing cache before syncing'

      def call(clear: false, **)
        boot_application!

        return unless stripe_configured?

        # Clear cache if requested
        if clear
          puts 'Clearing existing plan cache...'
          Billing::Plan.clear_cache
          puts '✓ Cache cleared'
          puts
        end

        puts 'Syncing from Stripe to Redis cache...'
        puts

        # Use retry wrapper for resilience against network errors
        count = with_stripe_retry do
          Billing::Plan.refresh_from_stripe(progress: method(:show_progress))
        end

        puts "\n\nSuccessfully synced #{count} plan(s) to cache"
        puts "\nTo view cached plans:"
        puts "  bin/ots billing plans"
      rescue Stripe::StripeError => e
        puts format_stripe_error('Sync failed', e)
        puts "\nTroubleshooting:"
        puts "  - Verify STRIPE_KEY is set correctly"
        puts "  - Check your internet connection"
        puts "  - Verify Stripe account has access to products"
      rescue StandardError => e
        puts "Error during sync: #{e.message}"
        puts e.backtrace.first(5).join("\n") if OT.debug?
      end

      private

      # Show progress during sync
      def show_progress(message)
        print "\r#{message}"
        $stdout.flush
      end
    end
  end
end

Onetime::CLI.register 'billing sync', Onetime::CLI::BillingSyncCommand
