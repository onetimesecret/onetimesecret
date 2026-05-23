# apps/web/billing/cli/orgs_validate_command.rb
#
# frozen_string_literal: true

require 'json'

require_relative 'helpers'
require_relative 'validation_helpers'

module Onetime
  module CLI
    # Detect organizations whose `planid` cannot be resolved against the
    # Redis plan cache or billing.yaml config.
    #
    # Since PR #3097 (issue #3089), billing fails closed on plan cache
    # misses: an org with an unresolvable planid raises
    # `Billing::PlanCacheMissError` instead of silently falling back to
    # free tier. This command lets operators scan production for orgs
    # that would break before rolling out a change.
    #
    # Usage:
    #   bin/ots billing orgs validate
    #   bin/ots billing orgs validate --verbose
    #   bin/ots billing orgs validate --json
    #
    # Exits non-zero when at least one org has an unresolvable planid,
    # so the command is safe to gate deploys on.
    #
    # @see https://github.com/onetimesecret/onetimesecret/issues/3099
    class BillingOrgsValidateCommand < Command
      include BillingHelpers
      include ValidationHelpers

      desc "Detect orgs whose planid doesn't resolve in cache or config"

      option :verbose,
        type: :boolean,
        default: false,
        aliases: ['v'],
        desc: 'Print each invalid org as it is detected'

      option :json,
        type: :boolean,
        default: false,
        desc: 'Emit machine-readable JSON instead of a text report'

      def call(verbose: false, json: false, **)
        boot_application!

        unless billing_enabled?
          warn 'Billing is not enabled; nothing to validate.'
          exit 0
        end

        stats        = init_stats
        invalid_orgs = []

        total             = Onetime::Organization.instances.element_count
        progress_interval = [total / 10, 1].max
        show_progress     = !json && !verbose

        Onetime::Organization.instances.each_record(batch_size: 100) do |org|
          process_org(org, stats, invalid_orgs, verbose: verbose && !json)
          print_progress(stats[:total], total, progress_interval, label: 'organizations scanned') if show_progress
        end

        clear_progress_line if show_progress

        report = build_report(stats, invalid_orgs)

        if json
          puts JSON.pretty_generate(report)
        else
          print_text_report(report)
        end

        exit(invalid_orgs.empty? ? 0 : 1)
      end

      private

      def billing_enabled?
        return false unless defined?(Onetime::BillingConfig)
        return false unless Onetime::BillingConfig.instance.enabled?
        return false unless defined?(::Billing::Plan) && ::Billing::Plan.respond_to?(:load_with_fallback)

        true
      end

      def init_stats
        {
          total: 0,
          skipped_no_planid: 0,
          valid_stripe: 0,
          valid_config: 0,
          invalid: 0,
        }
      end

      def process_org(org, stats, invalid_orgs, verbose:)
        stats[:total] += 1
        planid         = org.planid.to_s

        if planid.empty?
          stats[:skipped_no_planid] += 1
          return
        end

        result = ::Billing::Plan.load_with_fallback(planid)

        case result[:source]
        when 'stripe'
          stats[:valid_stripe] += 1
        when 'local_config'
          stats[:valid_config] += 1
        else
          stats[:invalid] += 1
          entry           = build_invalid_entry(org, planid)
          invalid_orgs << entry
          puts format_verbose_line(entry) if verbose
        end
      end

      def build_invalid_entry(org, planid)
        {
          extid: org.extid,
          display_name: org.display_name.to_s,
          planid: planid,
          stripe_customer_id: org.stripe_customer_id.to_s,
          stripe_subscription_id: org.stripe_subscription_id.to_s,
          subscription_status: org.subscription_status.to_s,
        }
      end

      def format_verbose_line(entry)
        sub_state = entry[:subscription_status].empty? ? '(no sub)' : entry[:subscription_status]
        "  invalid: #{entry[:extid]}  planid=#{entry[:planid]}  sub=#{sub_state}"
      end

      def build_report(stats, invalid_orgs)
        {
          stats: stats,
          invalid_orgs: invalid_orgs,
          invalid_by_planid: group_by_planid(invalid_orgs),
        }
      end

      def group_by_planid(invalid_orgs)
        grouped = invalid_orgs.group_by { |o| o[:planid] }
        # Sort by descending count so the worst offenders surface first.
        grouped.sort_by { |_planid, orgs| -orgs.size }.to_h
      end

      def print_text_report(report)
        stats        = report[:stats]
        invalid_orgs = report[:invalid_orgs]
        grouped      = report[:invalid_by_planid]

        puts
        puts 'Organization Plan ID Validation'
        print_separator(60, '=')
        puts "  Total orgs scanned:       #{stats[:total]}"
        puts "  Skipped (no planid):      #{stats[:skipped_no_planid]}"
        puts "  Valid (Redis cache):      #{stats[:valid_stripe]}"
        puts "  Valid (billing.yaml):     #{stats[:valid_config]}"
        puts "  Invalid plan IDs:         #{stats[:invalid]}"
        puts

        if invalid_orgs.empty?
          puts 'All organizations have resolvable plan IDs.'
          return
        end

        print_invalid_groups(grouped)
        print_resolution_hints
      end

      def print_invalid_groups(grouped)
        puts 'INVALID PLAN IDS'
        print_separator(60, '-')

        grouped.each do |planid, orgs|
          puts
          puts "  #{planid} (#{orgs.size} #{orgs.size == 1 ? 'org' : 'orgs'}):"
          orgs.each do |org|
            name      = org[:display_name].empty? ? '(no name)' : org[:display_name]
            sub_state = org[:subscription_status].empty? ? 'no sub' : org[:subscription_status]
            puts "    - #{org[:extid]}  #{name}  [#{sub_state}]"
          end
        end
        puts
      end

      def print_resolution_hints
        print_resolution_section(
          [
            'Update org.planid to a value in the catalog or billing.yaml',
            'Or add the missing plan to billing.yaml / Stripe catalog',
            'Refresh the plan cache: bin/ots billing catalog pull',
            'Inspect a specific org:  bin/ots billing diagnose --org <extid>',
          ],
        )
      end
    end
  end
end

Onetime::CLI.register 'billing orgs validate', Onetime::CLI::BillingOrgsValidateCommand
