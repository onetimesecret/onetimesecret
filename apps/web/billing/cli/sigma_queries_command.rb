# apps/web/billing/cli/sigma_queries_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # List Sigma queries
    class BillingSigmaQueriesCommand < Command
      include BillingHelpers

      desc 'List Stripe Sigma queries'

      option :limit, type: :integer, default: 100, desc: 'Maximum results to return'

      def call(limit: 100, **)
        boot_application!

        return unless stripe_configured?

        puts 'Fetching Sigma queries from Stripe...'

        queries = Stripe::Sigma::ScheduledQueryRun.list({ limit: limit })

        if queries.data.empty?
          puts 'No Sigma queries found'
          puts 'Note: Sigma is only available on paid Stripe plans'
          return
        end

        puts format('%-22s %-40s %s',
          'ID', 'SQL', 'CREATED')
        puts '-' * 80

        queries.data.each do |query|
          sql_preview = query.sql&.[](0..39) || 'N/A'
          created = format_timestamp(query.created)

          puts format('%-22s %-40s %s',
            query.id[0..21],
            sql_preview,
            created)
        end

        puts "\nTotal: #{queries.data.size} query/queries"

      rescue Stripe::StripeError => e
        if e.message.include?('This feature is not available')
          puts "Error: Sigma is not available on your Stripe plan"
          puts "Sigma requires a paid Stripe plan. See: https://stripe.com/docs/sigma"
        else
          puts "Error fetching Sigma queries: #{e.message}"
        end
      end
    end
  end
end

Onetime::CLI.register 'billing sigma queries', Onetime::CLI::BillingSigmaQueriesCommand
