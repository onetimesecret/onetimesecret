# apps/web/billing/cli/catalog_push_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require_relative '../operations/catalog/push'

module Onetime
  module CLI
    # Push catalog to Stripe
    #
    # Syncs the YAML billing catalog to Stripe, creating or updating
    # products as needed. Prices are NEVER updated - only created when
    # all required fields are provided.
    #
    class BillingCatalogPushCommand < Command
      include BillingHelpers

      desc 'Push billing catalog to Stripe (create/update products)'

      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'Preview changes without making them'

      option :force,
        type: :boolean,
        default: false,
        desc: 'Skip confirmation prompts'

      option :plan,
        type: :string,
        desc: 'Push only a specific plan (e.g., identity_plus_v1)'

      option :skip_prices,
        type: :boolean,
        default: false,
        desc: 'Skip price creation, only push products'

      def call(dry_run: false, force: false, plan: nil, skip_prices: false, **)
        boot_application!
        return unless stripe_configured?

        puts "Billing Catalog Push#{' (DRY RUN)' if dry_run}"
        puts '=' * 50

        # Always run preview first to show what would happen
        preview = Billing::Operations::Catalog::Push.call(
          dry_run: true,
          plan_filter: plan,
          skip_prices: skip_prices,
          progress: method(:show_progress),
        )

        unless preview.success
          preview.errors.each { |e| puts "Error: #{e}" }
          exit 1
        end

        puts
        display_success(preview, true)

        # If no changes or already in dry-run mode, we're done
        return if dry_run || preview.no_changes

        # Confirmation unless --force
        unless force
          print "\nProceed with catalog push? (y/n): "
          response = $stdin.gets
          return unless response&.chomp&.downcase == 'y'
        end

        puts

        result = Billing::Operations::Catalog::Push.call(
          dry_run: false,
          plan_filter: plan,
          skip_prices: skip_prices,
          progress: method(:show_progress),
        )

        puts

        if result.success
          display_success(result, false)
        else
          result.errors.each { |e| puts "Error: #{e}" }
          exit 1
        end
      end

      private

      def show_progress(message)
        puts message
      end

      def display_success(result, dry_run)
        prefix = dry_run ? '[DRY RUN] Would' : 'Completed:'

        if result.no_changes
          puts 'No changes needed - Stripe is in sync with catalog'
          return
        end

        puts "#{prefix} create #{result.products_created} product(s)" if result.products_created > 0
        puts "#{prefix} update #{result.products_updated} product(s)" if result.products_updated > 0
        puts "#{prefix} create #{result.prices_created} price(s)" if result.prices_created > 0

        unless dry_run
          puts "\nCatalog push complete!"
          puts 'Run `bin/ots billing catalog pull` to sync to Redis cache'
        end
      end
    end
  end
end

Onetime::CLI.register 'billing catalog push', Onetime::CLI::BillingCatalogPushCommand
