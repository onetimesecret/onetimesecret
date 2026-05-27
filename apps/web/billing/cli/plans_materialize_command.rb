# apps/web/billing/cli/plans_materialize_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require_relative '../operations/materialize_plans'

module Onetime
  module CLI
    # Materialize entitlements on organizations
    #
    # Thin wrapper over Billing::Operations::MaterializePlans. Owns option
    # parsing and human-readable output; the operation owns iteration,
    # accounting, logging, and cascade semantics so non-CLI callers can
    # use the same logic.
    #
    # Use cases:
    # - Initial migration: materialize all orgs so legacy Plan.load fallback can be removed
    # - Catalog refresh: re-materialize orgs on a specific plan after plan definition changes
    # - Membership consistency: cascade after plan catalog changes
    #
    # Usage:
    #   bin/ots billing plans materialize --all                              # Dry run all orgs
    #   bin/ots billing plans materialize --all --run                        # Execute on all orgs
    #   bin/ots billing plans materialize --plan=identity_plus_v1 --run      # Specific plan
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

      def call(all: false, plan: nil, include_memberships: false, run: false, verbose: false, help: false, **)
        return show_usage_help if help

        boot_application!

        unless all || plan
          puts 'Error: Must specify --all or --plan=<plan_id>'
          puts 'Run with --help for usage information.'
          return
        end

        dry_run = !run
        total   = Onetime::Organization.instances.element_count

        puts "\nEntitlement Materialization"
        puts '=' * 60

        if total.zero?
          puts 'No organizations found.'
          return
        end

        print_mode_banner(dry_run: dry_run, all: all, plan: plan,
                          include_memberships: include_memberships)

        progress_interval = [total / 10, 1].max
        renderer          = ProgressRenderer.new(total: total, verbose: verbose,
                                                 progress_interval: progress_interval,
                                                 dry_run: dry_run,
                                                 include_memberships: include_memberships)

        result = ::Billing::Operations::MaterializePlans.call(
          plan_filter: plan,
          include_memberships: include_memberships,
          dry_run: dry_run,
        ) { |event| renderer.render(event) }

        renderer.finish
        print_results(result, dry_run, verbose, include_memberships)
        print_next_steps(dry_run, result.succeeded, all, plan, include_memberships)
      end

      private

      def print_mode_banner(dry_run:, all:, plan:, include_memberships:)
        scope  = all ? 'all organizations' : "organizations on plan '#{plan}'"
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

      def print_results(result, dry_run, verbose, include_memberships)
        puts "\n" + ('=' * 60)
        puts "Materialization #{dry_run ? 'Preview' : 'Complete'}"
        puts '=' * 60
        puts "\nStatistics:"
        puts '  Total scanned:'.ljust(30) + result.scanned.to_s
        puts '  Succeeded:'.ljust(30) + result.succeeded.to_s
        puts '  Failed:'.ljust(30) + result.failed.to_s if result.failed > 0
        puts '  Skipped (plan filter):'.ljust(30) + result.skipped_plan_filter.to_s if result.skipped_plan_filter > 0
        puts '  Skipped (no plan):'.ljust(30) + result.skipped_no_plan.to_s

        if include_memberships && !dry_run
          puts '  Orgs cascaded:'.ljust(30) + result.orgs_cascaded.to_s
          puts '  Memberships materialized:'.ljust(30) + result.memberships_succeeded.to_s
          puts '  Memberships failed:'.ljust(30) + result.memberships_failed.to_s if result.memberships_failed > 0
        end

        return if result.errors.empty?

        puts "\n  Errors:".ljust(30) + result.errors.size.to_s
        return unless verbose

        puts "\n  Error details:"
        result.errors.each { |err| puts "    - #{err[:org_extid]}: #{err[:reason]}" }
      end

      def print_next_steps(dry_run, succeeded_count, all, plan, include_memberships)
        return unless dry_run && succeeded_count > 0

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

            # Re-materialize all orgs AND cascade to their active memberships
            bin/ots billing plans materialize --all --include-memberships --run

          Notes:
            - Command is idempotent (safe to run multiple times). Every in-scope
              org has its entitlements re-written from the plan definition; there
              is no "skip if already up-to-date" optimization because the perf
              gain is minor and pairing it with --include-memberships caused
              cascades to be silently skipped for up-to-date orgs.
            - Plans are preloaded before iteration (no Redis reads in loop).
            - --include-memberships cascades for every in-scope org, including
              orgs whose entitlement set hasn't changed — memberships can drift
              independently of the org plan.
            - Cascade failures count the org as FAILED (not succeeded). Partial
              membership materialization is reported in the errors list.

        USAGE
        true
      end

      # Renders streaming progress events to stdout.
      #
      # Verbose mode prints one line per org; non-verbose prints a periodic
      # one-line progress indicator. Decoupled from the operation so other
      # callers (jobs, future UIs) can plug in their own renderers.
      class ProgressRenderer
        def initialize(total:, verbose:, progress_interval:, dry_run:, include_memberships:)
          @total               = total
          @verbose             = verbose
          @progress_interval   = progress_interval
          @dry_run             = dry_run
          @include_memberships = include_memberships
          @processed           = 0
        end

        def render(event)
          @processed += 1
          render_verbose(event) if @verbose
          render_compact unless @verbose
        end

        def finish
          # Clear the progress line if we were rendering one.
          print "\r" + (' ' * 80) + "\r" unless @verbose
        end

        private

        def render_verbose(event)
          line = "  [#{@processed}/#{@total}] #{describe(event)}"
          puts line
        end

        def render_compact
          return unless (@processed % @progress_interval).zero? || @processed == @total

          print "\r  Progress: #{@processed}/#{@total} organizations processed"
        end

        def describe(event)
          case event.event
          when :materialized
            cascade = event.cascade ? " (+#{event.cascade[:success]} memberships)" : ''
            "Materialized: #{event.org_extid} (#{event.planid}, #{event.entitlements_count} entitlements)#{cascade}"
          when :would_materialize
            cascade_hint = @include_memberships ? ' (+memberships cascade)' : ''
            "Would materialize: #{event.org_extid} (#{event.planid}, #{event.entitlements_count} entitlements)#{cascade_hint}"
          when :skipped_plan_filter
            "Skipping (plan filter): #{event.org_extid}"
          when :skipped_no_plan
            "Skipping (no planid): #{event.org_extid}"
          when :failed_plan_not_found
            "Error: #{event.reason} (#{event.org_extid})"
          when :failed_org_write
            "Error: org write failed for #{event.org_extid}: #{event.reason}"
          when :failed_cascade
            "Error: cascade failed for #{event.org_extid}: #{event.reason}"
          else
            "[#{event.event}] #{event.org_extid}"
          end
        end
      end
    end
  end
end

Onetime::CLI.register 'billing plans materialize', Onetime::CLI::BillingPlansMaterializeCommand
