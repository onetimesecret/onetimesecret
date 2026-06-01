# apps/web/billing/cli/catalog_sync_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require_relative '../operations/catalog/push'
require_relative '../operations/catalog/pull'
require_relative '../operations/materialize_plans'

module Onetime
  module CLI
    # Full catalog sync: push to Stripe, pull to Redis, materialize entitlements
    #
    # Composes three operations in sequence:
    #   1. catalog push  — sync YAML catalog to Stripe
    #   2. catalog pull  — pull Stripe products/prices into Redis cache
    #   3. plans materialize — materialize entitlements on organizations
    #
    # Aborts on first failure so downstream steps never run against stale data.
    #
    class BillingCatalogSyncCommand < Command
      include BillingHelpers

      desc 'Full catalog sync: push to Stripe, pull to cache, materialize plans'

      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'Preview all steps without making changes'

      option :force,
        type: :boolean,
        default: false,
        desc: 'Skip confirmation prompts'

      option :plan,
        type: :string,
        desc: 'Limit to a specific plan (e.g., identity_plus_v1)'

      option :skip_prices,
        type: :boolean,
        default: false,
        desc: 'Skip price creation during push'

      option :include_memberships,
        type: :boolean,
        default: false,
        desc: 'Cascade materialization to active memberships'

      option :verbose,
        type: :boolean,
        default: false,
        aliases: ['v'],
        desc: 'Show per-membership detail during materialization'

      option :quiet,
        type: :boolean,
        default: false,
        aliases: ['q'],
        desc: 'Suppress per-org progress during materialization'

      def call(dry_run: false, force: false, plan: nil, skip_prices: false, include_memberships: false, verbose: false, quiet: false, **)
        boot_application!
        return unless stripe_configured?

        puts "Billing Catalog Sync#{' (DRY RUN)' if dry_run}"
        puts '=' * 60
        puts
        puts 'This command runs three steps in sequence:'
        puts '  1. Push catalog to Stripe'
        puts '  2. Pull from Stripe to Redis cache'
        puts '  3. Materialize entitlements on organizations'
        puts

        return unless step_push(dry_run: dry_run, force: force, plan: plan, skip_prices: skip_prices)
        return unless step_pull(dry_run: dry_run)
        step_materialize(dry_run: dry_run, plan: plan, include_memberships: include_memberships,
                         verbose: verbose, quiet: quiet)

        puts
        puts '=' * 60
        puts "Catalog sync #{dry_run ? 'preview' : ''} complete!"
      end

      private

      def step_push(dry_run:, force:, plan:, skip_prices:)
        print_step_header(1, 'Catalog Push')

        preview = Billing::Operations::Catalog::Push.call(
          dry_run: true,
          plan_filter: plan,
          skip_prices: skip_prices,
          progress: method(:show_progress),
        )

        unless preview.success
          preview.errors.each { |e| puts "  Error: #{e}" }
          puts "\nAborting sync: catalog push preview failed."
          return false
        end

        if preview.no_changes
          puts '  No changes needed — Stripe is in sync with catalog.'
          return true
        end

        puts "  Would create #{preview.products_created} product(s)" if preview.products_created > 0
        puts "  Would update #{preview.products_updated} product(s)" if preview.products_updated > 0
        puts "  Would create #{preview.prices_created} price(s)" if preview.prices_created > 0

        return true if dry_run

        unless force
          print "\n  Proceed with catalog push? (y/n): "
          response = $stdin.gets
          unless response&.chomp&.downcase == 'y'
            puts "\nAborted by user."
            return false
          end
        end

        result = Billing::Operations::Catalog::Push.call(
          dry_run: false,
          plan_filter: plan,
          skip_prices: skip_prices,
          progress: method(:show_progress),
        )

        unless result.success
          result.errors.each { |e| puts "  Error: #{e}" }
          puts "\nAborting sync: catalog push failed."
          return false
        end

        puts "  Created #{result.products_created} product(s)" if result.products_created > 0
        puts "  Updated #{result.products_updated} product(s)" if result.products_updated > 0
        puts "  Created #{result.prices_created} price(s)" if result.prices_created > 0
        true
      end

      def step_pull(dry_run:)
        print_step_header(2, 'Catalog Pull')

        if dry_run
          puts '  Skipped (dry run) — would pull products/prices from Stripe to Redis.'
          return true
        end

        result = Billing::Operations::Catalog::Pull.call(
          clear_cache: false,
          progress: method(:show_pull_progress),
        )

        puts

        unless result.success
          result.errors.each { |e| puts "  Error: #{e}" }
          puts "\nAborting sync: catalog pull failed."
          return false
        end

        puts "  Pulled #{result.plans_synced} plan(s) from Stripe."
        puts "  Upserted #{result.config_plans_loaded} config-only plan(s)." if result.config_plans_loaded > 0
        true
      end

      def step_materialize(dry_run:, plan:, include_memberships:, verbose:, quiet:)
        print_step_header(3, 'Plans Materialize')

        total = Onetime::Organization.instances.element_count

        if total.zero?
          puts '  No organizations found — nothing to materialize.'
          return true
        end

        scope = plan ? "organizations on plan '#{plan}'" : 'all organizations'
        scope += ' + memberships cascade' if include_memberships

        if dry_run
          puts "  Dry run: would materialize #{scope}."
        else
          puts "  Materializing #{scope}..."
        end

        verbosity = resolve_verbosity(verbose: verbose, quiet: quiet)
        renderer  = MaterializeStepRenderer.new(total: total, verbosity: verbosity,
                                                dry_run: dry_run,
                                                include_memberships: include_memberships)

        result = ::Billing::Operations::MaterializePlans.call(
          plan_filter: plan,
          include_memberships: include_memberships,
          dry_run: dry_run,
        ) { |event| renderer.render(event) }

        puts
        puts "  Scanned: #{result.scanned}"
        puts "  Succeeded: #{result.succeeded}"
        puts "  Failed: #{result.failed}" if result.failed > 0
        puts "  Skipped (no plan): #{result.skipped_no_plan}" if result.skipped_no_plan > 0
        puts "  Skipped (plan filter): #{result.skipped_plan_filter}" if result.skipped_plan_filter > 0

        if include_memberships && !dry_run
          puts "  Memberships materialized: #{result.memberships_succeeded}"
          puts "  Memberships failed: #{result.memberships_failed}" if result.memberships_failed > 0
        end

        unless result.errors.empty?
          puts "\n  Errors:"
          result.errors.each { |err| puts "    - #{err[:org_extid]}: #{err[:reason]}" }
        end

        true
      end

      def resolve_verbosity(verbose:, quiet:)
        return :quiet if quiet
        return :verbose if verbose

        :default
      end

      def print_step_header(number, name)
        puts
        puts "Step #{number}: #{name}"
        puts '-' * 40
      end

      def show_progress(message)
        puts "  #{message}"
      end

      def show_pull_progress(message)
        print "\r  #{message}"
        $stdout.flush
      end

      # Compact progress renderer for the materialize step.
      class MaterializeStepRenderer
        def initialize(total:, verbosity:, dry_run:, include_memberships:)
          @total               = total
          @verbosity           = verbosity
          @dry_run             = dry_run
          @include_memberships = include_memberships
          @processed           = 0
        end

        def render(event)
          @processed += 1
          return if @verbosity == :quiet

          puts "    [#{@processed}/#{@total}] #{describe(event)}"
          render_membership_detail(event) if @verbosity == :verbose
        end

        private

        def render_membership_detail(event)
          details = event.cascade && event.cascade[:details]
          return if details.nil? || details.empty?

          details.each do |m|
            status = m[:status] == :ok ? "#{m[:entitlements_count]} entitlements" : "FAILED — #{m[:error]}"
            puts "        -> #{m[:objid]} (role=#{m[:role]}): #{status}"
          end
        end

        def describe(event)
          case event.event
          when :materialized
            cascade = event.cascade ? " + cascaded #{event.cascade[:success]}/#{event.cascade[:total]} memberships" : ''
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
            cascade = event.cascade ? " (#{event.cascade[:success]}/#{event.cascade[:total]} succeeded)" : ''
            "Error: cascade failed for #{event.org_extid}: #{event.reason}#{cascade}"
          else
            "[#{event.event}] #{event.org_extid}"
          end
        end
      end
    end
  end
end

Onetime::CLI.register 'billing catalog sync', Onetime::CLI::BillingCatalogSyncCommand
