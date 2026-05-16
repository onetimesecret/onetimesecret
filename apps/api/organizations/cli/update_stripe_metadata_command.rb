# apps/api/organizations/cli/update_stripe_metadata_command.rb
#
# frozen_string_literal: true

# CLI command for region-scoped bulk update of Stripe customer metadata.
#
# Iterates the per-region Familia stripe_customer_id_index so writes are
# guaranteed to stay within this region's organizations — never touching
# customers owned by sibling regions (US/EU/etc.) that share a Stripe account.
#
# Usage:
#   bin/ots organizations update-stripe-metadata --key KEY --value VALUE
#   bin/ots organizations update-stripe-metadata --key KEY --value VALUE --apply
#   bin/ots organizations update-stripe-metadata --key region --value us-east --apply
#   bin/ots organizations update-stripe-metadata --key tier --value pro --org ORG_EXTID
#   bin/ots organizations update-stripe-metadata --key KEY --unset --apply
#   bin/ots organizations update-stripe-metadata --key KEY --value VALUE --sleep 100
#

require_relative '../../../../apps/web/billing/cli/helpers'

module Onetime
  module CLI
    # Bulk-update Stripe customer metadata for organizations in this region
    class OrganizationsUpdateStripeMetadataCommand < Command
      include BillingHelpers

      desc 'Bulk update a Stripe customer metadata key for orgs in this region'

      option :key,
        type: :string,
        default: nil,
        desc: 'Metadata key to update (required)'

      option :value,
        type: :string,
        default: nil,
        desc: 'New value for the metadata key (required unless --unset)'

      option :unset,
        type: :boolean,
        default: false,
        desc: 'Remove the metadata key instead of setting a value (mutually exclusive with --value)'

      option :apply,
        type: :boolean,
        default: false,
        desc: 'Apply changes (default is dry-run)'

      option :org,
        type: :string,
        default: nil,
        desc: 'Update only this organization (extid). Skips iteration over the index.'

      option :sleep,
        type: :numeric,
        default: 50,
        desc: 'Milliseconds to sleep between Stripe API calls (default: 50)'

      def call(key: nil, value: nil, unset: false, apply: false, org: nil, sleep: 50, **)
        boot_application!

        return unless stripe_configured?
        return unless validate_options!(key: key, value: value, unset: unset)

        @sleep_interval = sleep / 1000.0

        if org
          update_single_organization(org, key: key, value: value, unset: unset, apply: apply)
        else
          update_all_organizations(key: key, value: value, unset: unset, apply: apply)
        end
      end

      private

      def validate_options!(key:, value:, unset:)
        if key.nil? || key.to_s.strip.empty?
          puts 'Error: --key is required'
          return false
        end

        if unset && !value.nil?
          puts 'Error: --unset is mutually exclusive with --value'
          return false
        end

        if !unset && value.nil?
          puts 'Error: --value is required (or use --unset to remove the key)'
          return false
        end

        true
      end

      def update_single_organization(org_extid, key:, value:, unset:, apply:)
        org = Onetime::Organization.find_by_extid(org_extid)

        if org.nil?
          puts "No organization found with extid: #{org_extid}"
          return
        end

        stripe_customer_id = org.stripe_customer_id.to_s
        if stripe_customer_id.empty?
          puts "Organization #{org.extid} has no Stripe customer linked"
          return
        end

        print_header(key: key, value: value, unset: unset, apply: apply, total: 1)
        update_one(org, stripe_customer_id, key: key, value: value, unset: unset, apply: apply)
        puts
        puts 'Run with --apply to commit changes' unless apply
      end

      def update_all_organizations(key:, value:, unset:, apply:)
        index = Onetime::Organization.stripe_customer_id_index
        total = index.size

        print_header(key: key, value: value, unset: unset, apply: apply, total: total)

        stats = { unchanged: 0, updated: 0, errors: 0, orphaned: 0 }

        # NOTE: index.all uses HGETALL — fine for admin-scale (hundreds of orgs).
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
            stats[:orphaned] += 1
            next
          end

          result         = update_one(org, stripe_customer_id, key: key, value: value, unset: unset, apply: apply)
          stats[result] += 1
        end

        puts
        puts 'Summary:'
        puts "  Unchanged: #{stats[:unchanged]}"
        puts "  Updated:   #{stats[:updated]}"
        puts "  Errors:    #{stats[:errors]}"
        puts "  Orphaned:  #{stats[:orphaned]}"
        puts
        puts 'Run with --apply to commit changes' unless apply
      end

      def print_header(key:, value:, unset:, apply:, total:)
        action = unset ? "UNSET #{key}" : "SET #{key}=#{value}"
        puts "Found #{total} organizations with Stripe customers"
        puts apply ? 'Mode: APPLY changes' : 'Mode: DRY RUN (use --apply to commit)'
        puts "Action: #{action}"
        puts "API throttle: #{(@sleep_interval * 1000).to_i}ms between calls"
        puts
        puts format(
          '%-32s %-28s %-22s %-22s %s',
          'Org ExtID',
          'Stripe Customer',
          'Current Value',
          'Target Value',
          'Status',
        )
        puts '-' * 120
      end

      # Compare current Stripe metadata against target and (optionally) apply update.
      # @return [Symbol] :unchanged, :updated, or :errors
      def update_one(org, stripe_customer_id, key:, value:, unset:, apply:)
        stripe_customer = with_stripe_retry { Stripe::Customer.retrieve(stripe_customer_id) }
        sleep(@sleep_interval) if @sleep_interval.positive?

        # Stripe returns metadata as a hash with string keys
        current_value = stripe_customer.metadata[key]
        target_value  = unset ? nil : value
        target_label  = unset ? '(unset)' : value.to_s

        already_matches = unset ? current_value.nil? : current_value.to_s == value.to_s

        status, result = if already_matches
                           ['unchanged', :unchanged]
                         elsif apply
                           apply_update(stripe_customer_id, key: key, value: target_value, unset: unset)
                         else
                           [unset ? 'would unset' : 'would update', :updated]
                         end

        puts format(
          '%-32s %-28s %-22s %-22s %s',
          org.extid,
          stripe_customer_id,
          truncate(current_value.to_s),
          truncate(target_label),
          status,
        )

        result
      rescue Stripe::StripeError => ex
        puts format(
          '%-32s %-28s %-22s %-22s %s',
          org.extid,
          stripe_customer_id,
          '-',
          unset ? '(unset)' : value.to_s,
          "ERROR: #{format_stripe_error('retrieve', ex)[0..40]}",
        )
        :errors
      end

      # Apply the metadata update via Stripe::Customer.update.
      # Stripe merges metadata: keys not present in the update hash are preserved.
      # Setting a key to '' (empty string) removes it.
      # Throttling lives in update_one so each row sleeps exactly once.
      def apply_update(stripe_customer_id, key:, value:, unset:)
        metadata_param = unset ? { key => '' } : { key => value.to_s }

        with_stripe_retry do
          Stripe::Customer.update(stripe_customer_id, metadata: metadata_param)
        end

        [unset ? 'UNSET' : 'UPDATED', :updated]
      rescue Stripe::StripeError => ex
        ["ERROR: #{format_stripe_error('update', ex)[0..40]}", :errors]
      end

      def truncate(str, length: 20)
        return '-' if str.nil? || str.empty?

        str.length > length ? "#{str[0..(length - 3)]}..." : str
      end
    end
  end
end

Onetime::CLI.register 'organizations update-stripe-metadata', Onetime::CLI::OrganizationsUpdateStripeMetadataCommand
