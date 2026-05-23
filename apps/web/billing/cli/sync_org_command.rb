# apps/web/billing/cli/sync_org_command.rb
#
# frozen_string_literal: true

# CLI command for syncing Organization subscription state from Stripe.
#
# Usage:
#   bin/ots billing sync-org on8q30gih2uxu2cw77jzh7caq07  # Single org by extid
#   bin/ots billing sync-org --all                         # All orgs with subscriptions
#   bin/ots billing sync-org --all --dry-run               # Preview changes

require_relative 'helpers'

module Onetime
  module CLI
    # Sync Organization subscription state from Stripe
    class BillingSyncOrgCommand < Command
      include BillingHelpers

      desc 'Sync organization subscription state from Stripe'

      argument :extid,
        type: :string,
        required: false,
        desc: 'Organization external ID (e.g., on8q30gih2uxu2cw77jzh7caq07)'

      option :all,
        type: :boolean,
        default: false,
        desc: 'Sync all organizations with stripe_subscription_id'

      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'Preview changes without applying'

      def call(extid: nil, all: false, dry_run: false, **)
        boot_application!
        return unless stripe_configured?

        if all
          sync_all_organizations(dry_run: dry_run)
        elsif extid
          sync_single_organization(extid, dry_run: dry_run)
        else
          puts 'Error: Provide an extid or use --all'
        end
      end

      private

      def sync_single_organization(extid, dry_run:)
        org = Onetime::Organization.find_by_extid(extid)
        unless org
          puts "Error: Organization not found: #{extid}"
          return
        end

        if org.stripe_subscription_id.to_s.empty?
          puts 'Skipped: Organization has no stripe_subscription_id'
          puts "  Customer ID: #{org.stripe_customer_id.to_s.empty? ? '(none)' : org.stripe_customer_id}"
          return
        end

        sync_organization(org, dry_run: dry_run)
      end

      def sync_all_organizations(dry_run:)
        stats = { synced: 0, skipped: 0, errors: 0 }

        Onetime::Organization.instances.each_record(batch_size: 100) do |org|
          if org.stripe_subscription_id.to_s.empty?
            puts "Skipped #{truncate_extid(org.extid)}: no stripe_subscription_id"
            stats[:skipped] += 1
            next
          end

          result         = sync_organization(org, dry_run: dry_run)
          stats[result] += 1
        end

        puts
        puts "Summary: #{stats[:synced]} synced, #{stats[:skipped]} skipped, #{stats[:errors]} error"
      end

      def sync_organization(org, dry_run:)
        sub_id       = org.stripe_subscription_id
        subscription = with_stripe_retry { Stripe::Subscription.retrieve(sub_id) }
        price_id     = subscription.items.data.first&.price&.id
        new_planid   = Billing::PlanValidator.resolve_plan_id(price_id)
        old_planid   = org.planid.to_s.empty? ? '(none)' : org.planid

        if dry_run
          puts "[DRY RUN] Would sync #{truncate_extid(org.extid)}: #{old_planid} -> #{new_planid}"
        else
          Billing::Operations::ApplySubscriptionToOrg.call(org, subscription, owner: true)
          puts "Synced #{truncate_extid(org.extid)}: #{old_planid} -> #{new_planid}"
        end

        :synced
      rescue Stripe::InvalidRequestError => ex
        puts "Error #{truncate_extid(org.extid)}: #{ex.message}"
        :errors
      rescue Billing::CatalogMissError => ex
        puts "Error #{truncate_extid(org.extid)}: price not in catalog (#{ex.price_id})"
        :errors
      end

      def truncate_extid(extid)
        extid.to_s[0..10] + '...'
      end
    end
  end
end

Onetime::CLI.register 'billing sync-org', Onetime::CLI::BillingSyncOrgCommand
