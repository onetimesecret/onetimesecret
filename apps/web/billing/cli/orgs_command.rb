# apps/web/billing/cli/orgs_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Parent help command for `billing orgs` subcommands.
    class BillingOrgsCommand < Command
      include BillingHelpers

      desc 'Inspect organization billing state'

      def call(**)
        puts <<~HELP
          Organization Billing Commands:

            bin/ots billing orgs validate   Detect orgs with plan IDs that don't resolve

          Examples:
            # Scan all orgs for unresolvable plan IDs
            bin/ots billing orgs validate

            # Same scan, JSON output for tooling
            bin/ots billing orgs validate --json

            # Show per-org details as the scan runs
            bin/ots billing orgs validate --verbose

        HELP
      end
    end
  end
end

Onetime::CLI.register 'billing orgs', Onetime::CLI::BillingOrgsCommand
