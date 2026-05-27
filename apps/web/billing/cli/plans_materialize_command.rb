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
    #   bin/ots billing plans materialize --all --include-memberships --run  # Cascade to memberships
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

      option :force,
        type: :boolean,
        default: false,
        desc: 'Force re-materialization even if entitlements are up to date'

      option :include_memberships,
        type: :boolean,
        default: false,
        desc: 'Cascade re-materialization to all active memberships after each org'

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

      def call(all: false, plan: nil, stale: false, force: false, include_memberships: false, run: false, verbose: false, help: false, **)
        return show_usage_help if help

        boot_application!

        unless all || plan
          puts 'Error: Must specify --all or --plan=<plan_id>'
          puts 'Run with --help for usage information.'
          return
        end

        puts "\nEntitlement Materialization"
        puts '=' * 60

        dry_run = !run
        total   = Onetime::Organization.instances.element_count

        if total.zero?
          puts 'No organizations found.'
          return
        end

        print_mode_banner(dry_run, all, plan, stale, force, include_memberships)

        stats             = {
          total: 0,
          materialized: 0,
          skipped_no_plan: 0,
          skipped_up_to_date: 0,
          skipped_plan_filter: 0,
          orgs_cascaded: 0,
          memberships_materialized: 0,
          memberships_failed: 0,
          errors: [],
        }
        progress_interval = [total / 10, 1].max

        # Preload all plans (only ~5) so no Redis reads happen inside the loop.
        # This allows both reads and writes to be batched via pipelining.
        # Includes both Stripe-synced and config-only plans (via upsert_config_only_plans).
        plans_cache = ::Billing::Plan.list_plans.to_h { |p| [p.plan_id, p] }

        Onetime::Organization.instances.each_record(batch_size: 100) do |org|
          process_org(org, stats, total, dry_run, verbose, stale, force, plan, include_memberships, progress_interval, plans_cache)
        end

        print_results(stats, dry_run, verbose, include_memberships)
        print_next_steps(dry_run, stats[:materialized], all, plan, include_memberships)
      end

      private

      def skip_for_plan_filter?(org, plan_filter)
        return false unless plan_filter

        org.planid.to_s != plan_filter
      end

      def skip_for_stale_filter?(org, stale_only, force, plans_cache)
        return false if force
        return false unless stale_only
        return false unless org.entitlements_materialized?

        plan = plans_cache[org.planid]
        return true unless plan

        !org.entitlements_stale?(plan)
      end

      def print_mode_banner(dry_run, all, plan, stale, force, include_memberships)
        scope  = if all
                  'all organizations'
                else
                  "organizations on plan '#{plan}'"
                end
        scope += ' (stale only)' if stale
        scope += ' (force)' if force
        scope += ' + memberships cascade' if include_memberships

        if dry_run
          puts "\nDRY RUN MODE - No changes will be made"
          puts "Scope: #{scope}"
          puts "To execute, run with --run flag\n"
        else
          puts "\nExecuting materialization"
          puts "Scope: #{scope}\n"
        end
      end

      # rubocop:disable Metrics/PerceivedComplexity
      def process_org(org, stats, total, dry_run, verbose, stale_only, force, plan_filter, include_memberships, progress_interval, plans_cache)
        stats[:total] += 1
        idx            = stats[:total]

        if skip_for_plan_filter?(org, plan_filter)
          stats[:skipped_plan_filter] += 1
          print_progress(idx, total, verbose, progress_interval)
          return
        end

        if org.planid.to_s.empty?
          stats[:skipped_no_plan] += 1
          puts "  [#{idx}/#{total}] Skipping (no planid): #{org.extid}" if verbose
          print_progress(idx, total, verbose, progress_interval)
          return
        end

        if skip_for_stale_filter?(org, stale_only, force, plans_cache)
          stats[:skipped_up_to_date] += 1
          puts "  [#{idx}/#{total}] Skipping (up to date): #{org.extid}" if verbose
          print_progress(idx, total, verbose, progress_interval)
          return
        end

        plan = plans_cache[org.planid]

        unless plan
          stats[:errors] << "#{org.extid}: Plan '#{org.planid}' not found"
          puts "  [#{idx}/#{total}] Error: Plan not found for #{org.extid}" if verbose
          print_progress(idx, total, verbose, progress_interval)
          return
        end

        if !force && !stale_only && org.entitlements_materialized? && !org.entitlements_stale?(plan)
          stats[:skipped_up_to_date] += 1
          puts "  [#{idx}/#{total}] Skipping (up to date): #{org.extid}" if verbose
          print_progress(idx, total, verbose, progress_interval)
          return
        end

        if dry_run
          cascade_suffix = include_memberships ? ' (+memberships cascade)' : ''
          puts "  [#{idx}/#{total}] Would materialize: #{org.extid} (#{org.planid}, #{plan.entitlements.size} entitlements)#{cascade_suffix}"
        else
          begin
            org.materialize_entitlements_from_plan(plan)
            puts "  [#{idx}/#{total}] Materialized: #{org.extid}" if verbose
            cascade_memberships(org, stats, idx, total, verbose) if include_memberships
          rescue StandardError => ex
            stats[:errors] << "#{org.extid}: #{ex.message}"
            puts "  [#{idx}/#{total}] Error: #{ex.message}" if verbose
            print_progress(idx, total, verbose, progress_interval)
            return
          end
        end

        stats[:materialized] += 1
        print_progress(idx, total, verbose, progress_interval)
      end
      # rubocop:enable Metrics/PerceivedComplexity

      # Cascade re-materialization to active memberships of the org.
      # Mirrors the pattern in materialize_standalone_entitlements chore so that
      # memberships stay in sync after org-level plan changes.
      def cascade_memberships(org, stats, idx, total, verbose)
        result = org.rematerialize_all_memberships!
        stats[:orgs_cascaded]            += 1
        stats[:memberships_materialized] += result[:success]
        stats[:memberships_failed]       += result[:failed]

        if result[:failed] > 0
          stats[:errors] << "#{org.extid}: #{result[:failed]} membership(s) failed to materialize"
        end

        return unless verbose

        puts "  [#{idx}/#{total}] Cascaded to memberships: #{result[:success]}/#{result[:total]} succeeded"
      end

      def print_progress(current, total, verbose, interval)
        return if verbose
        return unless (current % interval).zero? || current == total

        print "\r  Progress: #{current}/#{total} organizations processed"
      end

      def print_results(stats, dry_run, verbose, include_memberships)
        print "\r" + (' ' * 80) + "\r" unless verbose

        puts "\n" + ('=' * 60)
        puts "Materialization #{dry_run ? 'Preview' : 'Complete'}"
        puts '=' * 60
        puts "\nStatistics:"
        puts '  Total scanned:'.ljust(30) + stats[:total].to_s
        puts '  Materialized:'.ljust(30) + stats[:materialized].to_s
        puts '  Skipped (plan filter):'.ljust(30) + stats[:skipped_plan_filter].to_s if stats[:skipped_plan_filter] > 0
        puts '  Skipped (no plan):'.ljust(30) + stats[:skipped_no_plan].to_s
        puts '  Skipped (up to date):'.ljust(30) + stats[:skipped_up_to_date].to_s

        if include_memberships && !dry_run
          puts '  Orgs cascaded:'.ljust(30) + stats[:orgs_cascaded].to_s
          puts '  Memberships materialized:'.ljust(30) + stats[:memberships_materialized].to_s
          puts '  Memberships failed:'.ljust(30) + stats[:memberships_failed].to_s if stats[:memberships_failed] > 0
        end

        return unless stats[:errors].any?

        puts "\n  Errors:".ljust(30) + stats[:errors].size.to_s
        return unless verbose

        puts "\n  Error details:"
        stats[:errors].each { |err| puts "    - #{err}" }
      end

      def print_next_steps(dry_run, materialized_count, all, plan, include_memberships)
        return unless dry_run && materialized_count > 0

        cmd = if all
                'bin/ots billing plans materialize --all --run'
              else
                "bin/ots billing plans materialize --plan=#{plan} --run"
              end
        cmd += ' --include-memberships' if include_memberships

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
            --all                   Materialize all organizations (migration mode)
            --plan=<plan_id>        Materialize only organizations on this plan
            --stale                 Only materialize orgs where entitlements are stale
            --force                 Force re-materialization even if up to date
            --include-memberships   Cascade re-materialization to all active memberships
            --run                   Execute materialization (default is dry-run)
            --verbose, -v           Show detailed progress for each organization
            --help, -h              Show this help message

          Examples:
            # Preview migration (all orgs, dry run)
            bin/ots billing plans materialize --all

            # Execute migration (all orgs)
            bin/ots billing plans materialize --all --run

            # Re-materialize after plan definition change
            bin/ots billing plans materialize --plan=identity_plus_v1 --run

            # Only update stale orgs (efficient for large deployments)
            bin/ots billing plans materialize --all --stale --run

            # Force re-materialize all orgs (ignore up-to-date checks)
            bin/ots billing plans materialize --all --force --run

            # Re-materialize all orgs AND cascade to their active memberships
            bin/ots billing plans materialize --all --include-memberships --run

          Notes:
            - Command is idempotent (safe to run multiple times)
            - Skips orgs already up-to-date unless --stale is used
            - Plans are preloaded before iteration (no Redis reads in loop)
            - Reports errors for orgs with invalid planid values
            - --include-memberships only cascades for orgs that were materialized
              this run; up-to-date orgs are not cascaded unless paired with --force

        USAGE
        true
      end
    end
  end
end

Onetime::CLI.register 'billing plans materialize', Onetime::CLI::BillingPlansMaterializeCommand
