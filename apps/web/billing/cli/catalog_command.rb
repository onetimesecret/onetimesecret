# apps/web/billing/cli/catalog_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # List catalog cache
    class BillingCatalogCommand < Command
      include BillingHelpers

      desc 'List product catalog cache from Redis'

      option :refresh, type: :boolean, default: false,
        desc: 'Refresh cache from Stripe before listing'

      def call(refresh: false, **)
        boot_application!

        return unless stripe_configured?

        if refresh
          puts 'Refreshing catalog from Stripe...'
          count = Billing::Models::CatalogCache.refresh_from_stripe
          puts "Refreshed #{count} catalog entries"
          puts
        end

        catalog = Billing::Models::CatalogCache.list_catalog
        if catalog.empty?
          puts 'No catalog entries found. Run with --refresh to sync from Stripe.'
          return
        end

        puts format('%-20s %-18s %-10s %-10s %-12s %s',
          'CATALOG ID', 'TIER', 'INTERVAL', 'AMOUNT', 'REGION', 'CAPS')
        puts '-' * 90

        catalog.each do |entry|
          puts format_plan_row(entry)
        end

        puts "
Total: #{catalog.size} catalog entries"
      end
    end
  end
end

Onetime::CLI.register 'billing catalog', Onetime::CLI::BillingCatalogCommand
