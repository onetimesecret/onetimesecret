# apps/web/billing/spec/operations/grant_probono_entitlements_spec.rb
#
# frozen_string_literal: true

# Unit tests for GrantProbonoEntitlements operation.
#
# Covers:
# - default_org_for: prioritizes default_org_id, then is_default, then first
# - filter_eligible: keeps only LEGACY_PROBONO_PLANIDS customers
# - find_eligible_customers: yields progress, returns filtered array
# - .call with no org: returns :skipped_no_org without writes
# - .call with complimentary org: returns :skipped_already_complimentary
# - .call with --force on complimentary org: bypasses the skip
# - .call dry_run: returns :would_grant without writes
# - .call live: writes planid + complimentary, materializes, clears
#   customer.planid (and verifies the ordering invariant)
# - .call propagates PlanCacheMissError from materialize_entitlements_for_org
#
# Run: pnpm run test:rspec apps/web/billing/spec/operations/grant_probono_entitlements_spec.rb

require 'spec_helper'
require 'billing/operations/grant_probono_entitlements'

RSpec.describe Billing::Operations::GrantProbonoEntitlements do
  let(:customer_email) { 'probono@example.com' }

  let(:customer) do
    double('Customer',
      extid: 'cust_ext_1',
      email: customer_email,
      planid: 'identity',
      default_org_id: nil,
      :planid= => nil,
      save: true,
    )
  end

  let(:org) do
    double('Organization',
      extid: 'org_ext_1',
      objid: 'org_obj_1',
      is_default: true,
      planid: 'free_v1',
      complimentary: nil,
      :planid= => nil,
      :complimentary= => nil,
      save: true,
    )
  end

  let(:materialize_result) do
    Billing::Operations::MaterializeResult.new(
      status: :materialized,
      planid: 'identity',
      entitlements_count: 5,
      source: :config,
      reason: nil,
    )
  end

  before do
    allow(customer).to receive(:organization_instances)
      .and_return(double(to_a: [org]))
    allow(Billing::Operations::ApplySubscriptionToOrg)
      .to receive(:materialize_entitlements_for_org).and_return(materialize_result)
    allow(OT).to receive(:le)
    allow(OT).to receive(:lw)
    allow(OT).to receive(:info)
  end

  # ---------------------------------------------------------------------------
  # .default_org_for (class method)
  # ---------------------------------------------------------------------------

  describe '.default_org_for' do
    let(:org_a) { double('OrgA', objid: 'a', is_default: false) }
    let(:org_b) { double('OrgB', objid: 'b', is_default: true) }
    let(:org_c) { double('OrgC', objid: 'c', is_default: false) }

    it 'returns nil when customer has no organizations' do
      allow(customer).to receive(:organization_instances)
        .and_return(double(to_a: []))

      expect(described_class.default_org_for(customer)).to be_nil
    end

    it 'returns the org matching customer.default_org_id when set' do
      allow(customer).to receive(:default_org_id).and_return('c')
      allow(customer).to receive(:organization_instances)
        .and_return(double(to_a: [org_a, org_b, org_c]))

      expect(described_class.default_org_for(customer)).to eq(org_c)
    end

    it 'falls back to is_default org when default_org_id is unset' do
      allow(customer).to receive(:default_org_id).and_return(nil)
      allow(customer).to receive(:organization_instances)
        .and_return(double(to_a: [org_a, org_b, org_c]))

      expect(described_class.default_org_for(customer)).to eq(org_b)
    end

    it 'falls back to first org when no is_default flag is set' do
      allow(customer).to receive(:default_org_id).and_return(nil)
      allow(customer).to receive(:organization_instances)
        .and_return(double(to_a: [org_a, org_c]))

      expect(described_class.default_org_for(customer)).to eq(org_a)
    end

    it 'falls back through default_org_id when it points at a non-member org' do
      allow(customer).to receive(:default_org_id).and_return('missing')
      allow(customer).to receive(:organization_instances)
        .and_return(double(to_a: [org_a, org_b]))

      expect(described_class.default_org_for(customer)).to eq(org_b)
    end
  end

  # ---------------------------------------------------------------------------
  # .filter_eligible (class method)
  # ---------------------------------------------------------------------------

  describe '.filter_eligible' do
    let(:identity_cust)  { double('Customer', planid: 'identity') }
    let(:paid_cust)      { double('Customer', planid: 'identity_plus_v1') }
    let(:no_planid_cust) { double('Customer', planid: nil) }
    let(:empty_cust)     { double('Customer', planid: '') }

    it 'keeps only customers with planid == "identity"' do
      result = described_class.filter_eligible(
        [identity_cust, paid_cust, no_planid_cust, empty_cust],
      )

      expect(result).to eq([identity_cust])
    end

    it 'returns empty when no customer matches' do
      result = described_class.filter_eligible([paid_cust, no_planid_cust])
      expect(result).to be_empty
    end

    it 'handles non-string planids via to_s' do
      sym_cust = double('Customer', planid: :identity)
      result   = described_class.filter_eligible([sym_cust])
      expect(result).to eq([sym_cust])
    end
  end

  # ---------------------------------------------------------------------------
  # .find_eligible_customers (class method)
  # ---------------------------------------------------------------------------

  describe '.find_eligible_customers' do
    let(:cust_eligible)   { double('Customer', planid: 'identity') }
    let(:cust_ineligible) { double('Customer', planid: 'identity_plus_v1') }

    before do
      allow(Onetime::Customer).to receive(:instances)
        .and_return(double(all: %w[c1 c2 c3]))
      allow(Onetime::Customer).to receive(:load_multi)
        .with(%w[c1 c2 c3])
        .and_return([cust_eligible, cust_ineligible, cust_eligible])
    end

    it 'returns only eligible customers' do
      result = described_class.find_eligible_customers

      expect(result).to eq([cust_eligible, cust_eligible])
    end

    it 'yields progress for each batch' do
      progress = []
      described_class.find_eligible_customers do |scanned, total|
        progress << [scanned, total]
      end

      expect(progress).to eq([[3, 3]])
    end

    it 'caps scanned count at total when batch overshoots' do
      allow(Onetime::Customer).to receive(:instances)
        .and_return(double(all: %w[c1 c2]))
      allow(Onetime::Customer).to receive(:load_multi)
        .with(%w[c1 c2])
        .and_return([cust_eligible, cust_eligible])

      progress = []
      described_class.find_eligible_customers(batch_size: 5) do |scanned, total|
        progress << [scanned, total]
      end

      expect(progress).to eq([[2, 2]])
    end

    it 'compacts nil entries from load_multi' do
      allow(Onetime::Customer).to receive(:load_multi)
        .and_return([cust_eligible, nil, cust_eligible])

      result = described_class.find_eligible_customers
      expect(result).to eq([cust_eligible, cust_eligible])
    end
  end

  # ---------------------------------------------------------------------------
  # .call — skip paths
  # ---------------------------------------------------------------------------

  describe '.call skip paths' do
    it 'returns :skipped_no_org without writes when customer has no org' do
      allow(customer).to receive(:organization_instances)
        .and_return(double(to_a: []))

      expect(org).not_to receive(:planid=)
      expect(customer).not_to receive(:planid=)
      expect(Billing::Operations::ApplySubscriptionToOrg)
        .not_to receive(:materialize_entitlements_for_org)

      result = described_class.call(customer)

      expect(result.status).to eq(:skipped_no_org)
      expect(result.customer_extid).to eq('cust_ext_1')
      expect(result.org_extid).to be_nil
      expect(result.skipped?).to be true
    end

    it 'returns :skipped_already_complimentary when org is complimentary and force is false' do
      allow(org).to receive(:complimentary).and_return('true')

      expect(org).not_to receive(:planid=)
      expect(customer).not_to receive(:planid=)
      expect(Billing::Operations::ApplySubscriptionToOrg)
        .not_to receive(:materialize_entitlements_for_org)

      result = described_class.call(customer)

      expect(result.status).to eq(:skipped_already_complimentary)
      expect(result.org_extid).to eq('org_ext_1')
      expect(result.skipped?).to be true
    end

    it 'does not skip a complimentary org when force is true' do
      allow(org).to receive(:complimentary).and_return('true')

      result = described_class.call(customer, force: true)

      expect(result.status).to eq(:granted)
      expect(result.granted?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # .call — dry-run
  # ---------------------------------------------------------------------------

  describe '.call dry_run' do
    it 'returns :would_grant without mutating org or customer' do
      expect(org).not_to receive(:planid=)
      expect(org).not_to receive(:complimentary=)
      expect(org).not_to receive(:save)
      expect(customer).not_to receive(:planid=)
      expect(Billing::Operations::ApplySubscriptionToOrg)
        .not_to receive(:materialize_entitlements_for_org)

      result = described_class.call(customer, dry_run: true)

      expect(result.status).to eq(:would_grant)
      expect(result.would_grant?).to be true
      expect(result.customer_extid).to eq('cust_ext_1')
      expect(result.org_extid).to eq('org_ext_1')
    end
  end

  # ---------------------------------------------------------------------------
  # .call — live grant
  # ---------------------------------------------------------------------------

  describe '.call live grant' do
    it 'sets org.planid to the target plan' do
      expect(org).to receive(:planid=).with('identity')

      described_class.call(customer)
    end

    it 'marks org complimentary' do
      expect(org).to receive(:complimentary=).with('true')
      expect(org).to receive(:save)

      described_class.call(customer)
    end

    it 'materializes entitlements with raise_on_miss: true' do
      expect(Billing::Operations::ApplySubscriptionToOrg)
        .to receive(:materialize_entitlements_for_org)
        .with(org, raise_on_miss: true)
        .and_return(materialize_result)

      described_class.call(customer)
    end

    it 'clears customer.planid only after materialize succeeds' do
      call_order = []
      allow(org).to receive(:save) { call_order << :org_save }
      allow(Billing::Operations::ApplySubscriptionToOrg)
        .to receive(:materialize_entitlements_for_org) do
          call_order << :materialize
          materialize_result
        end
      allow(customer).to receive(:planid=) { |_| call_order << :clear_customer_planid }
      allow(customer).to receive(:save) { call_order << :customer_save }

      described_class.call(customer)

      expect(call_order).to eq(%i[org_save materialize clear_customer_planid customer_save])
    end

    it 'leaves customer.planid untouched when materialize raises' do
      allow(Billing::Operations::ApplySubscriptionToOrg)
        .to receive(:materialize_entitlements_for_org)
        .and_raise(Billing::PlanCacheMissError.new('plan missing', plan_id: 'identity'))

      expect(customer).not_to receive(:planid=)
      expect(customer).not_to receive(:save)

      expect {
        described_class.call(customer)
      }.to raise_error(Billing::PlanCacheMissError)
    end

    it 'returns :granted with both extids on success' do
      result = described_class.call(customer)

      expect(result.status).to eq(:granted)
      expect(result.customer_extid).to eq('cust_ext_1')
      expect(result.org_extid).to eq('org_ext_1')
      expect(result.reason).to be_nil
    end
  end
end
