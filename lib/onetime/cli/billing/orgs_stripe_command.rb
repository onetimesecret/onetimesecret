# lib/onetime/cli/billing/orgs_stripe_command.rb
#
# frozen_string_literal: true

# List organizations that carry a Stripe customer id.
#
# This is the CLI peer of `GET /api/colonel/billing/stripe-organizations`. Both
# adapters call the same read op
# (Onetime::Operations::Billing::StripeOrganizations), which reads the EXISTING
# `organization:stripe_customer_id_index` — HLEN for the count, HSCAN for the
# entries — and hydrates only the requested page. It never enumerates
# Organization.instances.
#
# Distinct from `bin/ots billing orgs validate`, which scans for unresolvable
# plan ids. This one answers "which tenants are actually billed?".
#
# Usage:
#   bin/ots billing orgs stripe
#   bin/ots billing orgs stripe --search cus_ABC        # substring on the Stripe id
#   bin/ots billing orgs stripe --page 2 --per-page 100
#   bin/ots billing orgs stripe --json

require 'json'
require 'onetime/operations/billing/stripe_organizations'

module Onetime
  module CLI
    class BillingOrgsStripeCommand < Command
      desc 'List organizations that have a Stripe customer id (index-backed)'

      # No `type:` on the numeric options: dry-cli 1.4.1 special-cases only
      # :boolean/:flag/:array, so `type: :integer` is a silent no-op that would
      # falsely advertise coercion. The op re-coerces with #to_i.
      option :page,
        default: 1,
        desc: 'Page number (1-based)'
      option :per_page,
        default: 50,
        desc: 'Rows per page (max 100)'
      option :search,
        type: :string,
        default: nil,
        desc: 'Filter on the Stripe customer id (substring, or a * / ? glob)'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(page: 1, per_page: 50, search: nil, json: false, **)
        boot_application!

        result = Onetime::Operations::Billing::StripeOrganizations.new(
          page: page,
          per_page: per_page,
          search: search,
        ).call

        json ? output_json(result) : output_text(result)
      end

      private

      def output_json(result)
        puts JSON.pretty_generate(
          organizations: result.organizations,
          pagination: {
            page: result.page,
            per_page: result.per_page,
            total_count: result.total_count,
            total_pages: result.total_pages,
          },
          filters: { search: result.search },
          capped: result.capped,
          stale_count: result.stale_count,
          indexed_total: result.indexed_total,
        )
      end

      def output_text(result)
        puts "Indexed organizations with a Stripe customer: #{result.indexed_total}"
        puts "Filter: #{result.search}" unless result.search.to_s.empty?
        if result.capped
          puts "WARNING: scan stopped at #{Onetime::Operations::Billing::StripeOrganizations::MAX_INDEX_ENTRIES} " \
               'entries — the counts below understate the population.'
        end
        puts

        if result.organizations.empty?
          puts 'No matching organizations.'
          return
        end

        puts format(
          '%-24s %-28s %-22s %-14s %s',
          'ORG EXTID',
          'NAME',
          'STRIPE CUSTOMER',
          'PLAN',
          'STATUS',
        )
        puts '-' * 100

        result.organizations.each do |row|
          puts format(
            '%-24s %-28s %-22s %-14s %s',
            row[:extid].to_s[0, 23],
            row[:display_name].to_s[0, 27],
            row[:stripe_customer_id].to_s[0, 21],
            row[:planid].to_s[0, 13],
            row[:subscription_status].to_s,
          )
        end

        puts
        puts format(
          'Page %d/%d (%d matching entries, %d rows shown)',
          result.page,
          [result.total_pages, 1].max,
          result.total_count,
          result.organizations.size,
        )
        return unless result.stale_count.positive?

        puts "Stale index entries on this page (org no longer loads): #{result.stale_count}"
      end
    end

    register 'billing orgs stripe', BillingOrgsStripeCommand
  end
end
