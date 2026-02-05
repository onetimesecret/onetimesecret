# apps/api/organizations/cli/sync_billing_email_command.rb
#
# frozen_string_literal: true

# CLI command for syncing Organization billing_email from Stripe customer records.
#
# Use case: When billing emails are manually updated in Stripe Dashboard,
# this command pulls those changes back to the Organization model.
#
# Usage:
#   bin/ots organizations sync-billing-email              # Dry run (show changes)
#   bin/ots organizations sync-billing-email --apply      # Apply billing_email changes
#   bin/ots organizations sync-billing-email --apply --update-contact-email  # Also update contact_email
#   bin/ots organizations sync-billing-email --customer cus_xxx  # Sync specific customer
#   bin/ots organizations sync-billing-email --sleep 100  # Throttle API calls (100ms between calls)
#

require_relative '../../../../apps/web/billing/cli/helpers'

module Onetime
  module CLI
    # Sync Organization billing_email from Stripe customer email
    class OrganizationsSyncBillingEmailCommand < Command
      include BillingHelpers

      desc 'Sync organization billing emails from Stripe customer records'

      option :apply,
        type: :boolean,
        default: false,
        desc: 'Apply changes (default is dry-run)'

      option :customer,
        type: :string,
        default: nil,
        desc: 'Sync only the organization linked to this Stripe customer ID (cus_xxx)'

      option :update_contact_email,
        type: :boolean,
        default: false,
        desc: 'Also update contact_email (default: only update billing_email)'

      option :sleep,
        type: :numeric,
        default: 50,
        desc: 'Milliseconds to sleep between Stripe API calls (default: 50, prevents rate limiting)'

      def call(apply: false, customer: nil, update_contact_email: false, sleep: 50, **)
        boot_application!

        return unless stripe_configured?

        # Convert sleep from milliseconds to seconds for Kernel.sleep
        @sleep_interval = sleep / 1000.0

        if customer
          sync_single_organization(customer, apply: apply, update_contact_email: update_contact_email)
        else
          sync_all_organizations(apply: apply, update_contact_email: update_contact_email)
        end
      end

      private

      def sync_single_organization(stripe_customer_id, apply:, update_contact_email:)
        org = Onetime::Organization.find_by_stripe_customer_id(stripe_customer_id)

        if org.nil?
          puts "No organization found with Stripe customer: #{stripe_customer_id}"
          return
        end

        sync_organization(org, stripe_customer_id, apply: apply, update_contact_email: update_contact_email)
      end

      def sync_all_organizations(apply:, update_contact_email:)
        index = Onetime::Organization.stripe_customer_id_index
        total = index.size

        puts "Found #{total} organizations with Stripe customers"
        puts apply ? 'Mode: APPLY changes' : 'Mode: DRY RUN (use --apply to commit)'
        puts "Update contact_email: #{update_contact_email ? 'YES' : 'NO'}"
        puts "API throttle: #{(@sleep_interval * 1000).to_i}ms between calls"
        puts
        puts format(
          '%-32s %-30s %-30s %s',
          'Org ExtID',
          'Current Billing Email',
          'Stripe Email',
          'Status',
        )
        puts '-' * 110

        stats = { unchanged: 0, updated: 0, errors: 0 }

        # NOTE: index.all uses HGETALL which loads all entries into memory.
        # For large datasets, consider using hscan_each if Familia adds support.
        # Current usage is admin CLI with ~hundreds of orgs, so acceptable.
        index.all.each do |stripe_customer_id, org_objid|
          org = Onetime::Organization.load(org_objid)

          if org.nil?
            puts format(
              '%-32s %-30s %-30s %s',
              "(orphaned: #{org_objid[0..15]}...)",
              '-',
              stripe_customer_id,
              'ERROR: org not found',
            )
            stats[:errors] += 1
            next
          end

          result         = sync_organization(org, stripe_customer_id, apply: apply, update_contact_email: update_contact_email)
          stats[result] += 1
        end

        puts
        puts 'Summary:'
        puts "  Unchanged: #{stats[:unchanged]}"
        puts "  Updated:   #{stats[:updated]}"
        puts "  Errors:    #{stats[:errors]}"
        puts
        puts 'Run with --apply to commit changes' unless apply
      end

      def sync_organization(org, stripe_customer_id, apply:, update_contact_email:)
        stripe_customer = with_stripe_retry { Stripe::Customer.retrieve(stripe_customer_id) }

        # Proactive throttling to avoid Stripe rate limits
        sleep(@sleep_interval) if @sleep_interval.positive?

        current_billing_email = org.billing_email.to_s
        stripe_email          = stripe_customer.email.to_s

        # Determine status
        status = if stripe_email.empty?
                   'SKIP: no Stripe email'
                 elsif current_billing_email == stripe_email
                   'unchanged'
                 elsif apply
                   apply_billing_email_update(org, stripe_email, update_contact_email: update_contact_email)
                 else
                   update_contact_email ? 'would update (both)' : 'would update'
                 end

        # Print row
        puts format(
          '%-32s %-30s %-30s %s',
          org.extid,
          truncate_email(current_billing_email),
          truncate_email(stripe_email),
          status,
        )

        # Return status symbol for stats
        case status
        when 'unchanged', /^SKIP/
          :unchanged
        when /^UPDATED/, /^would update/
          :updated
        else
          :errors  # CONFLICT and other errors
        end
      rescue Stripe::InvalidRequestError => ex
        puts format(
          '%-32s %-30s %-30s %s',
          org.extid,
          truncate_email(org.billing_email.to_s),
          "(#{stripe_customer_id[0..26]})",
          "ERROR: #{ex.message[0..25]}",
        )
        :errors
      end

      # Apply billing_email update with optional contact_email sync
      #
      # @param org [Onetime::Organization] Organization to update
      # @param stripe_email [String] Email from Stripe customer
      # @param update_contact_email [Boolean] Also update contact_email
      # @return [String] Status message
      def apply_billing_email_update(org, stripe_email, update_contact_email:)
        # Check billing_email uniqueness
        existing_billing = Onetime::Organization.find_by_billing_email(stripe_email)
        if existing_billing && existing_billing.objid != org.objid
          return "CONFLICT: billing_email used by #{existing_billing.extid[0..10]}..."
        end

        org.billing_email = stripe_email
        status            = 'UPDATED'

        # Optionally update contact_email
        if update_contact_email
          existing_contact = Onetime::Organization.find_by_contact_email(stripe_email)
          if existing_contact && existing_contact.objid != org.objid
            # billing_email updated but contact_email conflict
            status = 'UPDATED (billing only - contact conflict)'
          else
            org.contact_email = stripe_email
            status            = 'UPDATED (both)'
          end
        end

        org.save
        status
      end

      def truncate_email(email)
        return '-' if email.nil? || email.empty?

        email.length > 28 ? "#{email[0..25]}..." : email
      end
    end
  end
end

Onetime::CLI.register 'organizations sync-billing-email', Onetime::CLI::OrganizationsSyncBillingEmailCommand
