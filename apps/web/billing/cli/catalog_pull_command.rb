# apps/web/billing/cli/catalog_pull_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require_relative '../operations/catalog/pull'

module Onetime
  module CLI
    # Pull from Stripe to Redis cache
    class BillingCatalogPullCommand < Command
      include BillingHelpers

      desc 'Pull products and prices from Stripe to Redis cache'

      option :clear,
        type: :boolean,
        default: false,
        desc: 'Clear existing cache before pulling'

      def call(clear: false, **)
        boot_application!
        return unless stripe_configured?

        result = Billing::Operations::Catalog::Pull.call(
          clear_cache: clear,
          progress: method(:show_progress),
        )

        puts "\n"

        if result.success
          puts "Successfully pulled #{result.plans_synced} plan(s) from Stripe"
          puts "Upserted #{result.config_plans_loaded} config-only plan(s)" if result.config_plans_loaded > 0
          puts "\nTo view cached plans:"
          puts '  bin/ots billing plans'
        else
          result.errors.each { |e| puts "Error: #{e}" }
          exit 1
        end
      end

      private

      def show_progress(message)
        print "\r#{message}"
        $stdout.flush
      end
    end
  end
end

Onetime::CLI.register 'billing catalog pull', Onetime::CLI::BillingCatalogPullCommand
