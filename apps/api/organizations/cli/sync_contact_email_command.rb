# apps/api/organizations/cli/sync_contact_email_command.rb
#
# frozen_string_literal: true

# CLI command for syncing Organization contact_email from Stripe customer records.
#
# Use case: When billing emails are manually updated in Stripe Dashboard,
# this command pulls those changes back to the Organization model.
#
# Usage:
#   bin/ots organizations sync-contact-email              # Dry run (show changes)
#   bin/ots organizations sync-contact-email --apply      # Apply changes
#   bin/ots organizations sync-contact-email --customer cus_xxx  # Sync specific customer
#

require_relative '../../../../apps/web/billing/cli/helpers'

module Onetime
  module CLI
    # Sync Organization contact_email from Stripe customer email
    class OrganizationsSyncContactEmailCommand < Command
      include BillingHelpers

      desc 'Sync organization contact emails from Stripe customer records'

      option :apply,
        type: :boolean,
        default: false,
        desc: 'Apply changes (default is dry-run)'

      option :customer,
        type: :string,
        default: nil,
        desc: 'Sync only the organization linked to this Stripe customer ID (cus_xxx)'

      def call(apply: false, customer: nil, **)
        boot_application!

        return unless stripe_configured?

        if customer
          sync_single_organization(customer, apply: apply)
        else
          sync_all_organizations(apply: apply)
        end
      end

      private

      def sync_single_organization(stripe_customer_id, apply:)
        org = Onetime::Organization.find_by_stripe_customer_id(stripe_customer_id)

        if org.nil?
          puts "No organization found with Stripe customer: #{stripe_customer_id}"
          exit 1
        end

        sync_organization(org, stripe_customer_id, apply: apply)
      end

      def sync_all_organizations(apply:)
        index = Onetime::Organization.stripe_customer_id_index
        total = index.size

        puts "Found #{total} organizations with Stripe customers"
        puts apply ? 'Mode: APPLY changes' : 'Mode: DRY RUN (use --apply to commit)'
        puts
        puts format(
          '%-32s %-30s %-30s %s',
          'Org ExtID',
          'Current Email',
          'Stripe Email',
          'Status',
        )
        puts '-' * 110

        stats = { unchanged: 0, updated: 0, errors: 0 }

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

          result         = sync_organization(org, stripe_customer_id, apply: apply)
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

      def sync_organization(org, stripe_customer_id, apply:)
        stripe_customer = with_stripe_retry { Stripe::Customer.retrieve(stripe_customer_id) }

        current_email = org.contact_email.to_s
        stripe_email  = stripe_customer.email.to_s

        # Determine status
        status = if stripe_email.empty?
                   'SKIP: no Stripe email'
                 elsif current_email == stripe_email
                   'unchanged'
                 elsif apply
                   # Check for uniqueness conflict before updating
                   existing = Onetime::Organization.find_by_contact_email(stripe_email)
                   if existing && existing.objid != org.objid
                     "CONFLICT: email used by #{existing.extid[0..10]}..."
                   else
                     org.contact_email = stripe_email
                     org.save
                     'UPDATED'
                   end
                 else
                   'would update'
                 end

        # Print row
        puts format(
          '%-32s %-30s %-30s %s',
          org.extid,
          truncate_email(current_email),
          truncate_email(stripe_email),
          status,
        )

        # Return status symbol for stats
        case status
        when 'unchanged', /^SKIP/
          :unchanged
        when 'UPDATED', 'would update'
          :updated
        else
          :errors  # CONFLICT and other errors
        end
      rescue Stripe::InvalidRequestError => ex
        puts format(
          '%-32s %-30s %-30s %s',
          org.extid,
          truncate_email(org.contact_email.to_s),
          "(#{stripe_customer_id[0..26]})",
          "ERROR: #{ex.message[0..25]}",
        )
        :errors
      end

      def truncate_email(email)
        return '-' if email.nil? || email.empty?

        email.length > 28 ? "#{email[0..25]}..." : email
      end
    end
  end
end

Onetime::CLI.register 'organizations sync-contact-email', Onetime::CLI::OrganizationsSyncContactEmailCommand
