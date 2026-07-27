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
# The mutation + the admin audit event are performed by the shared
# Onetime::Operations::Org::Reconcile op — 'billing sync-org' is a
# billing-namespace alias over the same op as 'org reconcile' (the CLI
# OrgReconcileCommand and the colonel ReconcileOrganization Logic class are
# the other adapters). The CLI runs outside the app autoloaders, so require
# the op explicitly. Customers::Shared is referenced by constant only
# (CLI_ACTOR), so it is required but NOT included — including it would drag
# its resolver methods into a command that resolves orgs, not customers.
require 'onetime/operations/org/reconcile'
require 'onetime/cli/customers/shared'

module Onetime
  module CLI
    # Sync Organization subscription state from Stripe.
    #
    # 'billing sync-org' is a billing-namespace alias over the same audited
    # Onetime::Operations::Org::Reconcile op as 'org reconcile' (#3903).
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
        result = Onetime::Operations::Org::Reconcile.new(
          org: org,
          # Never fabricate a Customer for the shell (ADR-023) — the audit
          # trail records the shared CLI sentinel.
          actor: Customers::Shared::CLI_ACTOR,
          dry_run: dry_run,
        ).call

        if Onetime::Operations::Org::Reconcile::OK_STATUSES.include?(result.status)
          print_outcome(org, result)
          :synced
        else
          # Includes :stripe_error — the op converts ::Stripe::StripeError
          # (e.g. InvalidRequestError) into that status instead of raising.
          detail = result.reason ? " (#{result.reason})" : nil
          puts "Error #{truncate_extid(org.extid)}: #{result.status}#{detail}"
          :errors
        end
      rescue Billing::OpsProblem => ex
        # OpsProblem subclasses (CatalogMissError from the catalog lookup,
        # PlanCacheMissError from entitlement materialization, ...) are NOT
        # Stripe::StripeError, so they escape Reconcile#call. Contain the
        # whole family per-org so a --all sweep keeps going. The class +
        # message is the operator hint (CatalogMissError's default message
        # already says to run `bin/ots billing catalog pull`).
        puts "Error #{truncate_extid(org.extid)}: #{ex.class}: #{ex.message}"
        :errors
      end

      # `result.after` is nil exactly when nothing was written (dry run; the
      # :stripe_error case never reaches here), so only print a planid diff
      # when it is present. `result.reason` rides along whenever the op set
      # one — for :standalone it is the ONLY carrier of the membership-cascade
      # outcome (including 'membership cascade failed (see logs)', D14), and
      # the planid diff alone reads like a no-op there.
      def print_outcome(org, result)
        label = truncate_extid(org.extid)
        if result.after
          detail = result.reason ? " (#{result.reason})" : nil
          puts "Synced #{label}: #{render(result.before[:planid])} -> #{render(result.after[:planid])}#{detail}"
        else
          puts "[DRY RUN] #{label}: #{result.status} — #{result.reason}"
        end
      end

      def render(value)
        value.to_s.empty? ? '(none)' : value.to_s
      end

      def truncate_extid(extid)
        extid.to_s[0..10] + '...'
      end
    end
  end
end

Onetime::CLI.register 'billing sync-org', Onetime::CLI::BillingSyncOrgCommand
