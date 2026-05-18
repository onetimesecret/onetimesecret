# apps/web/billing/cli/plans_materialize_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Materialize entitlements on organizations
    #
    # Use cases:
    # - Initial migration: materialize all orgs so legacy Plan.load fallback can be removed
    # - Catalog refresh: re-materialize orgs on a specific plan after plan definition changes
    #
    # Usage:
    #   bin/ots billing plans materialize --all                 # Dry run all orgs
    #   bin/ots billing plans materialize --all --run           # Execute on all orgs
    #   bin/ots billing plans materialize --plan=identity_plus_v1 --run  # Specific plan
    #   bin/ots billing plans materialize --stale --run         # Only stale orgs
    #
    class BillingPlansMaterializeCommand < Command
      include BillingHelpers

      desc 'Materialize entitlements on organizations from plan definitions'

      option :all,
        type: :boolean,
        default: false,
        desc: 'Materialize all organizations (migration mode)'

      option :plan,
        type: :string,
        default: nil,
        desc: 'Materialize only organizations on this plan ID'

      option :stale,
        type: :boolean,
        default: false,
        desc: 'Only materialize orgs where entitlements are stale vs current plan'

      option :run,
        type: :boolean,
        default: false,
        desc: 'Execute materialization (default is dry-run)'

      option :verbose,
        type: :boolean,
        default: false,
        aliases: ['v'],
        desc: 'Show detailed progress for each organization'

      option :help,
        type: :boolean,
        default: false,
        aliases: ['h'],
        desc: 'Show help message'

      def call(all: false, plan: nil, stale: false, run: false, verbose: false, help: false, **)
        return show_usage_help if help

        boot_application!

        unless all || plan
          puts 'Error: Must specify --all or --plan=<plan_id>'
          puts 'Run with --help for usage information.'
          return
        end

        puts "\nEntitlement Materialization"
        puts '=' * 60

        orgs    = find_target_orgs(all, plan, stale)
        dry_run = !run

        return if orgs.empty?

        print_mode_banner(dry_run, all, plan, stale)

        stats             = { total: 0, materialized: 0, skipped_no_plan: 0, skipped_up_to_date: 0, errors: [] }
        progress_interval = [orgs.size / 10, 1].max

        orgs.each_with_index do |org, idx|
          process_org(org, idx, orgs.size, stats, dry_run, verbose, stale, progress_interval)
        end

        print_results(stats, dry_run, verbose)
        print_next_steps(dry_run, stats[:materialized], all, plan)
      end

      private

      def find_target_orgs(all, plan_filter, stale_only)
        puts "\nDiscovering organizations..."

        orgs = if all
                 load_all_orgs
               else
                 load_orgs_by_plan(plan_filter)
               end

        if stale_only && !orgs.empty?
          orgs = filter_stale_orgs(orgs)
        end

        puts "Found #{orgs.size} organizations to process"
        orgs
      end

      def load_all_orgs
        all_org_ids = Onetime::Organization.instances.all
        Onetime::Organization.load_multi(all_org_ids).compact
      end

      def load_orgs_by_plan(plan_id)
        all_org_ids = Onetime::Organization.instances.all
        Onetime::Organization.load_multi(all_org_ids).compact.select do |org|
          org.planid.to_s == plan_id
        end
      end

      def filter_stale_orgs(orgs)
        orgs.select do |org|
          next true unless org.entitlements_materialized?

          plan = load_plan_for_org(org)
          next false unless plan

          org.entitlements_stale?(plan)
        end
      end

      def load_plan_for_org(org)
        return nil if org.planid.to_s.empty?

        result = ::Billing::Plan.load_with_fallback(org.planid)
        result[:plan] || result[:config]
      end

      def print_mode_banner(dry_run, all, plan, stale)
        scope  = if all
                  'all organizations'
                else
                  "organizations on plan '#{plan}'"
                end
        scope += ' (stale only)' if stale

        if dry_run
          puts "\nDRY RUN MODE - No changes will be made"
          puts "Scope: #{scope}"
          puts "To execute, run with --run flag\n"
        else
          puts "\nExecuting materialization"
          puts "Scope: #{scope}\n"
        end
      end

      def process_org(org, idx, total, stats, dry_run, verbose, stale_only, progress_interval)
        stats[:total] += 1

        if org.planid.to_s.empty?
          stats[:skipped_no_plan] += 1
          puts "  [#{idx + 1}/#{total}] Skipping (no planid): #{org.extid}" if verbose
          print_progress(stats[:total], total, verbose, progress_interval)
          return
        end

        plan_result = ::Billing::Plan.load_with_fallback(org.planid)
        plan        = plan_result[:plan]
        config      = plan_result[:config]

        unless plan || config
          stats[:errors] << "#{org.extid}: Plan '#{org.planid}' not found"
          puts "  [#{idx + 1}/#{total}] Error: Plan not found for #{org.extid}" if verbose
          print_progress(stats[:total], total, verbose, progress_interval)
          return
        end

        if !stale_only && org.entitlements_materialized?
          already_current = plan ? !org.entitlements_stale?(plan) : false
          if already_current
            stats[:skipped_up_to_date] += 1
            puts "  [#{idx + 1}/#{total}] Skipping (up to date): #{org.extid}" if verbose
            print_progress(stats[:total], total, verbose, progress_interval)
            return
          end
        end

        if dry_run
          ent_count = plan ? plan.entitlements.size : (config[:entitlements] || []).size
          puts "  [#{idx + 1}/#{total}] Would materialize: #{org.extid} (#{org.planid}, #{ent_count} entitlements)"
        else
          begin
            if plan
              org.materialize_entitlements_from_plan(plan)
            else
              org.materialize_entitlements_from_config(config)
            end
            puts "  [#{idx + 1}/#{total}] Materialized: #{org.extid}" if verbose
          rescue StandardError => ex
            stats[:errors] << "#{org.extid}: #{ex.message}"
            puts "  [#{idx + 1}/#{total}] Error: #{ex.message}" if verbose
            print_progress(stats[:total], total, verbose, progress_interval)
            return
          end
        end

        stats[:materialized] += 1
        print_progress(stats[:total], total, verbose, progress_interval)
      end

      def print_progress(current, total, verbose, interval)
        return if verbose
        return unless (current % interval).zero? || current == total

        print "\r  Progress: #{current}/#{total} organizations processed"
      end

      def print_results(stats, dry_run, verbose)
        print "\r" + (' ' * 80) + "\r" unless verbose

        puts "\n" + ('=' * 60)
        puts "Materialization #{dry_run ? 'Preview' : 'Complete'}"
        puts '=' * 60
        puts "\nStatistics:"
        puts '  Total organizations:'.ljust(30) + stats[:total].to_s
        puts '  Materialized:'.ljust(30) + stats[:materialized].to_s
        puts '  Skipped (no plan):'.ljust(30) + stats[:skipped_no_plan].to_s
        puts '  Skipped (up to date):'.ljust(30) + stats[:skipped_up_to_date].to_s

        return unless stats[:errors].any?

        puts "\n  Errors:".ljust(30) + stats[:errors].size.to_s
        return unless verbose

        puts "\n  Error details:"
        stats[:errors].each { |err| puts "    - #{err}" }
      end

      def print_next_steps(dry_run, materialized_count, all, plan)
        return unless dry_run && materialized_count > 0

        cmd = if all
                'bin/ots billing plans materialize --all --run'
              else
                "bin/ots billing plans materialize --plan=#{plan} --run"
              end

        puts <<~MESSAGE

          To execute materialization, run:
            #{cmd}

        MESSAGE
      end

      def show_usage_help
        puts <<~USAGE

          Entitlement Materialization

          Usage:
            bin/ots billing plans materialize [options]

          Description:
            Materializes entitlements from plan definitions onto organizations.
            After materialization, orgs read entitlements from local storage
            instead of calling Plan.load on every request.

          Options:
            --all                 Materialize all organizations (migration mode)
            --plan=<plan_id>      Materialize only organizations on this plan
            --stale               Only materialize orgs where entitlements are stale
            --run                 Execute materialization (default is dry-run)
            --verbose, -v         Show detailed progress for each organization
            --help, -h            Show this help message

          Examples:
            # Preview migration (all orgs, dry run)
            bin/ots billing plans materialize --all

            # Execute migration (all orgs)
            bin/ots billing plans materialize --all --run

            # Re-materialize after plan definition change
            bin/ots billing plans materialize --plan=identity_plus_v1 --run

            # Only update stale orgs (efficient for large deployments)
            bin/ots billing plans materialize --all --stale --run

          Notes:
            - Command is idempotent (safe to run multiple times)
            - Skips orgs already up-to-date unless --stale is used
            - Uses Plan.load_with_fallback for config-only plans (free_v1)
            - After full migration, legacy Plan.load fallback can be removed

        USAGE
        true
      end
    end
  end
end

Onetime::CLI.register 'billing plans materialize', Onetime::CLI::BillingPlansMaterializeCommand
