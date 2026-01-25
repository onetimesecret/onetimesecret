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
          '%-20s %-18s %-10s %-10s %-12s %s',
          'PLAN ID',
          'TIER',
          'INTERVAL',
          'AMOUNT',
          'REGION',
          'CAPS',
        )
        puts '-' * 90

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
