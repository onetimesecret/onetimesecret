# apps/web/billing/cli/checkout_links_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Landing command for `billing checkout-links` so the intermediate node
    # exists (dry-cli renders `--help` from a registered command; a bare
    # prefix with only nested subcommands leaves a nil node behind).
    class BillingCheckoutLinksCommand < Command
      include BillingHelpers

      desc 'Manage support-issued Stripe Checkout links'

      def call(**)
        puts 'Usage: bin/ots billing checkout-links create <email-or-extid> --plan <plan_id> [options]'
        puts
        puts "Run 'bin/ots billing checkout-links create --help' for options."
      end
    end
  end
end

Onetime::CLI.register 'billing checkout-links', Onetime::CLI::BillingCheckoutLinksCommand
