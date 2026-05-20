# apps/web/billing/operations/grant_probono_entitlements.rb
#
# frozen_string_literal: true

require_relative 'apply_subscription_to_org'

module Billing
  module Operations
    # Result of GrantProbonoEntitlements.call
    #
    # @!attribute status [Symbol] One of :granted, :would_grant,
    #   :skipped_no_org, :skipped_already_complimentary
    # @!attribute customer_extid [String]
    # @!attribute org_extid [String, nil] nil only when status is :skipped_no_org
    # @!attribute reason [String, nil]
    GrantProbonoResult = Data.define(:status, :customer_extid, :org_extid, :reason) do
      def granted?     = status == :granted
      def would_grant? = status == :would_grant
      def skipped?     = %i[skipped_no_org skipped_already_complimentary].include?(status)
    end

    # GrantProbonoEntitlements — Apply pro-bono entitlements to one
    # legacy identity-plan customer without a Stripe round-trip.
    #
    # Legacy pro-bono accounts carry `customer.planid='identity'` from
    # before org-level subscriptions existed. With materialized
    # entitlements and the 'identity' plan in the catalog, the modern
    # expression of "this customer's org gets the identity plan for
    # free" is three local writes: org.planid, org.complimentary, and
    # materialized entitlements.
    #
    # Usage:
    #   result = Billing::Operations::GrantProbonoEntitlements.call(customer)
    #   result.granted?  # => true
    #
    #   # Dry-run (no writes, returns :would_grant)
    #   result = Billing::Operations::GrantProbonoEntitlements.call(customer, dry_run: true)
    #
    #   # Re-materialize an already-complimentary org
    #   result = Billing::Operations::GrantProbonoEntitlements.call(customer, force: true)
    #
    # Also exposes the helpers a batch caller needs:
    #   GrantProbonoEntitlements.find_eligible_customers { |scanned, total| ... }
    #   GrantProbonoEntitlements.default_org_for(customer)
    #
    # @see https://github.com/onetimesecret/onetimesecret/issues/3161
    class GrantProbonoEntitlements
      # Legacy planid values on Customer that mark a pro-bono account.
      # Listed as a constant so the scanner and the filter agree.
      LEGACY_PROBONO_PLANIDS = %w[identity].freeze

      # Planid applied to the customer's default org during the grant.
      # Matches a catalog plan; entitlements are materialized from it.
      TARGET_PLANID = 'identity'

      # Batch size for find_eligible_customers' load_multi calls.
      DEFAULT_BATCH_SIZE = 100

      # Grant pro-bono entitlements to one customer.
      #
      # @param customer [Onetime::Customer]
      # @param dry_run [Boolean] When true, return :would_grant without writes
      # @param force [Boolean] When true, re-materialize already-complimentary orgs
      # @return [GrantProbonoResult]
      # @raise [Billing::PlanCacheMissError] if the target plan is missing
      #   from both the cache and config (propagated from materialize_entitlements_for_org)
      def self.call(customer, dry_run: false, force: false)
        new(customer, dry_run: dry_run, force: force).call
      end

      # Scan all customers and return those eligible for the grant.
      #
      # @param batch_size [Integer] How many IDs to load per round-trip
      # @yieldparam scanned [Integer] Cumulative count of IDs processed
      # @yieldparam total [Integer] Total IDs to process
      # @return [Array<Onetime::Customer>]
      def self.find_eligible_customers(batch_size: DEFAULT_BATCH_SIZE)
        all_ids  = Onetime::Customer.instances.all
        total    = all_ids.size
        eligible = []

        all_ids.each_slice(batch_size).with_index do |batch_ids, batch_idx|
          customers = Onetime::Customer.load_multi(batch_ids).compact
          eligible.concat(filter_eligible(customers))
          yield [(batch_idx + 1) * batch_size, total].min, total if block_given?
        end

        eligible
      end

      # Filter a batch of customers down to the legacy pro-bono ones.
      # Pure — callers can use this without invoking the full scan.
      #
      # @param customers [Array<Onetime::Customer>]
      # @return [Array<Onetime::Customer>]
      def self.filter_eligible(customers)
        customers.select { |cust| LEGACY_PROBONO_PLANIDS.include?(cust.planid.to_s) }
      end

      # Pick the customer's default org using the same priority as
      # OrganizationLoader: explicit default_org_id, then is_default flag,
      # then first org. Skips the loader's session and domain-based paths.
      #
      # @param customer [Onetime::Customer]
      # @return [Onetime::Organization, nil]
      def self.default_org_for(customer)
        orgs = customer.organization_instances.to_a
        return nil if orgs.empty?

        if customer.default_org_id.to_s.length.positive?
          explicit = orgs.find { |o| o.objid == customer.default_org_id }
          return explicit if explicit
        end

        orgs.find { |o| o.is_default } || orgs.first
      end

      def initialize(customer, dry_run:, force:)
        @customer = customer
        @dry_run  = dry_run
        @force    = force
      end

      def call
        org = self.class.default_org_for(@customer)
        return no_org_result unless org
        return already_complimentary_result(org) if blocked_by_complimentary?(org)
        return would_grant_result(org) if @dry_run

        execute_grant(org)
        granted_result(org)
      end

      private

      def blocked_by_complimentary?(org)
        !@force && org.complimentary.to_s == 'true'
      end

      # Order matters: org fields first (so materialize reads the new
      # planid), then materialize, then clear customer.planid last so a
      # mid-flight failure leaves the legacy marker visible for retry.
      def execute_grant(org)
        org.planid        = TARGET_PLANID
        org.complimentary = 'true'
        org.save

        ApplySubscriptionToOrg.materialize_entitlements_for_org(org, raise_on_miss: true)

        @customer.planid = nil
        @customer.save
      end

      def no_org_result
        GrantProbonoResult.new(
          status: :skipped_no_org,
          customer_extid: @customer.extid,
          org_extid: nil,
          reason: 'Customer has no organization',
        )
      end

      def already_complimentary_result(org)
        GrantProbonoResult.new(
          status: :skipped_already_complimentary,
          customer_extid: @customer.extid,
          org_extid: org.extid,
          reason: 'Organization already marked complimentary',
        )
      end

      def would_grant_result(org)
        GrantProbonoResult.new(
          status: :would_grant,
          customer_extid: @customer.extid,
          org_extid: org.extid,
          reason: nil,
        )
      end

      def granted_result(org)
        GrantProbonoResult.new(
          status: :granted,
          customer_extid: @customer.extid,
          org_extid: org.extid,
          reason: nil,
        )
      end
    end
  end
end
