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

      def call(**)
        boot_application!

        return unless stripe_configured?

        puts 'Syncing from Stripe to Redis cache...'
        puts

        count = Billing::Plan.refresh_from_stripe

        puts "Successfully synced #{count} plan(s) to cache"
        puts "\nTo view cached plans:"
        puts "  bin/ots billing plans"
      rescue StandardError => e
        puts "Error during sync: #{e.message}"
        puts e.backtrace.first(5).join("\n") if OT.debug?
      end
    end
  end
end

Onetime::CLI.register 'billing sync', Onetime::CLI::BillingSyncCommand
