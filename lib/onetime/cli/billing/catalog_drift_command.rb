# lib/onetime/cli/billing/catalog_drift_command.rb
#
# frozen_string_literal: true

# Show config-vs-live billing catalog drift.
#
# This is the CLI peer of `GET /api/colonel/billing/catalog`. Both adapters call
# the same read op (Onetime::Operations::Billing::CatalogDrift), so the console
# and the shell can never disagree about what "in sync" means.
#
# Distinct from the neighbouring catalog commands:
#   validate — JSON-schema checks on billing.yaml (structure only)
#   push / pull / sync — MOVE data between billing.yaml, Stripe and Redis
#   drift  — READ-ONLY comparison; changes nothing
#
# Usage:
#   bin/ots billing catalog drift
#   bin/ots billing catalog drift --json
#   bin/ots billing catalog drift --verbose    # list every plan on both sides
#
# Exit status is 0 when the two sides agree, 1 when they drift — so it can gate
# a deploy step.

require 'json'
require 'onetime/operations/billing/catalog_drift'

module Onetime
  module CLI
    class BillingCatalogDriftCommand < Command
      desc 'Compare the configured plan catalog against the live Stripe cache'

      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'
      option :verbose,
        type: :boolean,
        default: false,
        desc: 'List every plan on both sides, not just the differences'

      def call(json: false, verbose: false, **)
        boot_application!

        result = Onetime::Operations::Billing::CatalogDrift.new.call

        json ? output_json(result) : output_text(result, verbose: verbose)

        exit 1 unless result.drift[:in_sync]
      end

      private

      def output_json(result)
        puts JSON.pretty_generate(
          source: result.source,
          stripe_configured: result.stripe_configured,
          billing_enabled: result.billing_enabled,
          config_plans: result.config_plans,
          live_plans: result.live_plans,
          drift: result.drift,
        )
      end

      def output_text(result, verbose:)
        unless result.billing_enabled
          puts 'Billing is not enabled in this deployment — nothing to compare.'
          return
        end

        puts "Source:     #{result.source}"
        puts "Config:     #{result.config_plans.size} plans (billing.yaml)"
        puts "Live:       #{result.live_plans.size} plans (Stripe-synced cache)"

        if result.source == 'local_config'
          puts
          puts 'WARNING: the live cache is empty, so drift cannot be evaluated.'
          puts '         Run `bin/ots billing catalog pull` first.'
        end

        drift = result.drift
        puts
        if drift[:in_sync]
          puts 'In sync: config and live catalogs match.'
        else
          print_drift(drift)
        end

        return unless verbose

        puts
        print_plan_table('Config plans', result.config_plans)
        puts
        print_plan_table('Live plans', result.live_plans)
      end

      def print_drift(drift)
        puts 'DRIFT DETECTED'
        puts '-' * 60

        if drift[:only_in_config].any?
          puts "  Only in config (#{drift[:only_in_config].size}):"
          drift[:only_in_config].each { |planid| puts "    #{planid}" }
        end

        if drift[:only_in_live].any?
          puts "  Only in live (#{drift[:only_in_live].size}):"
          drift[:only_in_live].each { |planid| puts "    #{planid}" }
        end

        return unless drift[:changed].any?

        puts "  Changed (#{drift[:changed].size}):"
        drift[:changed].each do |change|
          puts format('    %-32s %s', change[:planid], change[:fields].join(', '))
        end
      end

      def print_plan_table(title, plans)
        puts "#{title} (#{plans.size})"
        puts format('  %-32s %-20s %-10s %s', 'PLANID', 'NAME', 'TIER', 'ENTITLEMENTS')
        plans.each do |plan|
          puts format(
            '  %-32s %-20s %-10s %s',
            plan[:planid].to_s[0, 31],
            plan[:name].to_s[0, 19],
            plan[:tier].to_s[0, 9],
            plan[:entitlements].size,
          )
        end
      end
    end

    register 'billing catalog drift', BillingCatalogDriftCommand
  end
end
