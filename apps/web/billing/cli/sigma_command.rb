# apps/web/billing/cli/sigma_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Sigma parent command (show help)
    class BillingSigmaCommand < Command
      include BillingHelpers

      desc 'Stripe Sigma analytics commands'

      def call(**)
        puts <<~HELP
          Stripe Sigma Analytics:

            bin/ots billing sigma queries      List Sigma queries
            bin/ots billing sigma run          Execute Sigma query

          Examples:

            # List available queries
            bin/ots billing sigma queries

            # Execute a query
            bin/ots billing sigma run sqa_ABC123xyz

            # Export query results to CSV
            bin/ots billing sigma run sqa_ABC123xyz --format csv --output report.csv

          Note: Sigma is only available on paid Stripe plans.
          See: https://stripe.com/docs/sigma
        HELP
      end
    end
  end
end

Onetime::CLI.register 'billing sigma', Onetime::CLI::BillingSigmaCommand
