# apps/web/billing/cli/plans_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # List plan cache
    class BillingPlansCommand < Command
      include BillingHelpers

      desc 'List product plan cache from Redis'

      option :refresh,
        type: :boolean,
        default: false,
        desc: 'Refresh cache from Stripe before listing'

      def call(refresh: false, **)
        boot_application!

        return unless stripe_configured?

        if refresh
          puts 'Refreshing plans from Stripe...'
          count = Billing::Plan.refresh_from_stripe
          puts "Refreshed #{count} plan entries"
          puts
        end

        plans = Billing::Plan.list_plans
        if plans.empty?
          puts 'No plan entries found. Run with --refresh to sync from Stripe.'
          return
        end

        puts format(
          '%-20s %-12s %-18s %-10s %-10s %-12s %-6s %-26s %s',
          'PLAN ID (*)',
          'APP (*)',
          'TIER',
          'INTERVAL',
          'AMOUNT',
          'REGION (*)',
          'CAPS',
          'STRIPE PRODUCT',
          'STRIPE PRICE',
        )
        puts '-' * 165

        plans.each do |entry|
          puts format_plan_row(entry)
        end

        puts "
Total: #{plans.size} plan entries"
      end
    end
  end
end

Onetime::CLI.register 'billing plans', Onetime::CLI::BillingPlansCommand
