# apps/web/billing/cli/catalog_sync_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require_relative '../lib/materialize_progress_renderer'
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

        materialize_ok = step_materialize(
          dry_run: dry_run,
          plan: plan,
          include_memberships: include_memberships,
          verbose: verbose,
          quiet: quiet,
        )

        puts
        puts '=' * 60
        if materialize_ok
          puts "Catalog sync #{'preview ' if dry_run}complete!"
        else
          puts "Catalog sync #{'preview ' if dry_run}finished with materialization errors."
          puts 'Review the errors above. Push and pull succeeded.'
        end
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

        scope  = plan ? "organizations on plan '#{plan}'" : 'all organizations'
        scope += ' + memberships cascade' if include_memberships

        if dry_run
          puts "  Dry run: would materialize #{scope}."
        else
          puts "  Materializing #{scope}..."
        end

        verbosity = resolve_verbosity(verbose: verbose, quiet: quiet)
        renderer  = Billing::MaterializeProgressRenderer.new(
          total: total,
          verbosity: verbosity,
          include_memberships: include_memberships,
          indent: 4,
        )

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

        result.errors.empty?
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
        print "\r  #{message}\e[K"
        $stdout.flush
      end
    end
  end
end

Onetime::CLI.register 'billing catalog sync', Onetime::CLI::BillingCatalogSyncCommand
