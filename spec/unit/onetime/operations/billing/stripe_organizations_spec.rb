# spec/unit/onetime/operations/billing/stripe_organizations_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::Operations::Billing::StripeOrganizations' index scan.
#
# Fully mocked — NO datastore. The class-level index HashKey and
# Organization.load_multi are doubled, so these assert scan semantics only.
#
# The contract under test: HSCAN is at-least-once, so the same field can be
# yielded more than once (concurrent rehash) and the two yields can carry
# DIFFERENT values (concurrent write). The op must therefore
#
#   - collapse repeat yields on the INDEX FIELD (the stripe customer id),
#     first occurrence winning, so `total_count` and the page rows each see a
#     customer id exactly once; and
#   - spend MAX_INDEX_ENTRIES on UNIQUE ids. Deduping after the loop instead
#     would let repeat yields consume the budget, breaking the scan early and
#     dropping ids that were still scan-reachable.
#
# Run: pnpm run test:rspec spec/unit/onetime/operations/billing/stripe_organizations_spec.rb

require 'spec_helper'
require 'onetime/operations/billing/stripe_organizations'

RSpec.describe Onetime::Operations::Billing::StripeOrganizations do
  # Stands in for Organization.stripe_customer_id_index (a Familia HashKey).
  # `each` replays a fixed yield sequence, so a test can spell out exactly what
  # a rehashing HSCAN hands back.
  #
  # Plain, not verifying: the real collaborator's `each` takes driver-specific
  # keyword args (matching:, batch_size:), and pinning to that signature would
  # couple this spec to Familia's scan API rather than to the op.
  def index_double(yields, field_count: yields.size)
    double('stripe_customer_id_index').tap do |dbl| # rubocop:disable RSpec/VerifiedDoubles
      allow(dbl).to receive(:field_count).and_return(field_count)
      allow(dbl).to receive(:each) do |**_kwargs, &blk|
        yields.each { |field, value| blk.call(field, value) }
      end
    end
  end

  # One hydrated org per objid, carrying every reader `build_row` touches.
  def org_double(objid)
    double( # rubocop:disable RSpec/VerifiedDoubles
      "Organization<#{objid}>",
      objid: objid,
      extid: "org_ext_#{objid}",
      display_name: "Org #{objid}",
      owner: double('owner', email: "owner-#{objid}@example.com"), # rubocop:disable RSpec/VerifiedDoubles
      billing_email: "billing-#{objid}@example.com",
      planid: 'identity_month',
      stripe_subscription_id: "sub_#{objid}",
      subscription_status: 'active',
      subscription_period_end: 1_800_000_000,
      created: 1_700_000_000,
      updated: 1_700_000_001,
    )
  end

  before do
    allow(Onetime::Organization).to receive(:stripe_customer_id_index).and_return(index)
    allow(Onetime::Organization).to receive(:load_multi) do |objids|
      objids.map { |objid| org_double(objid.to_s) }
    end
    if defined?(Billing::BillingService)
      allow(Billing::BillingService).to receive(:compute_sync_status).and_return('ok')
    end
    allow(OT).to receive(:lw)
    allow(OT).to receive(:le)
  end

  describe 'duplicate yields from a rehashing HSCAN' do
    # Same field twice, second yield carrying a DIFFERENT objid.
    let(:index) do
      index_double(
        [
          %w[cus_a obj1],
          %w[cus_b obj2],
          %w[cus_a obj_reassigned],
          %w[cus_c obj3],
        ],
      )
    end

    it 'counts each stripe customer id exactly once' do
      result = described_class.new(page: 1, per_page: 50).call

      expect(result.total_count).to eq(3)
      expect(result.organizations.size).to eq(3)
    end

    it 'keeps the first value seen for a repeated field' do
      # obj_reassigned lost the race; obj1 was yielded first.
      expect(Onetime::Organization).to receive(:load_multi)
        .with(%w[obj1 obj2 obj3]).and_return([])

      described_class.new(page: 1, per_page: 50).call
    end
  end

  describe 'the MAX_INDEX_ENTRIES cap' do
    before { stub_const("#{described_class}::MAX_INDEX_ENTRIES", 3) }

    # Five yields, three unique ids: duplicates must not spend the budget.
    let(:index) do
      index_double(
        [
          %w[cus_a obj1],
          %w[cus_a obj1],
          %w[cus_b obj2],
          %w[cus_b obj2],
          %w[cus_c obj3],
        ],
      )
    end

    it 'spends the budget on unique ids, not on repeat yields' do
      result = described_class.new(page: 1, per_page: 50).call

      # Deduping after the loop would have broken at the 3rd yield (cus_a,
      # cus_a, cus_b) and returned only cus_a + cus_b.
      expect(result.total_count).to eq(3)
      expect(result.organizations.map { |row| row[:stripe_customer_id] })
        .to eq(%w[cus_a cus_b cus_c])
    end

    it 'still reports capped when unique ids reach the bound' do
      result = described_class.new(page: 1, per_page: 50).call

      expect(result.capped).to be(true)
    end
  end

  describe 'a scan that ends below the bound' do
    let(:index) { index_double([%w[cus_a obj1], %w[cus_b obj2]]) }

    it 'does not report capped' do
      result = described_class.new(page: 1, per_page: 50).call

      expect(result.capped).to be(false)
      expect(result.total_count).to eq(2)
    end
  end
end
