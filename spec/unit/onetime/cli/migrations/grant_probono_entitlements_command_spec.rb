# spec/unit/onetime/cli/migrations/grant_probono_entitlements_command_spec.rb
#
# frozen_string_literal: true

# Unit tests for GrantProbonoEntitlementsCommand.
#
# Covers:
# - default_org_for: prioritizes default_org_id, then is_default, then first
# - Dry-run mode (no mutations, correct preview output)
# - Skip: no organization found
# - Skip: org already complimentary (unless --force)
# - Live grant flow (planid, complimentary, materialize, clear customer.planid)
# - --force re-materializes on already-complimentary orgs
# - Error handling (records error and continues)
#
# Run: pnpm run test:rspec spec/unit/onetime/cli/migrations/grant_probono_entitlements_command_spec.rb

require 'spec_helper'
require 'onetime/cli'
require 'billing/operations/apply_subscription_to_org'

RSpec.describe Onetime::CLI::GrantProbonoEntitlementsCommand do
  subject(:command) { described_class.new }

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

  let(:org_instances) { double('instances', to_a: [org]) }

  let(:materialize_result) do
    Billing::Operations::MaterializeResult.new(
      status: :materialized,
      planid: 'identity',
      entitlements_count: 5,
      source: :config,
      reason: nil,
    )
  end

  let(:stats) do
    {
      total: 0,
      granted: 0,
      skipped_no_org: 0,
      skipped_already_complimentary: 0,
      errors: [],
    }
  end

  before do
    allow(command).to receive(:puts)
    allow(command).to receive(:print)
    allow(OT).to receive(:le)
    allow(OT).to receive(:lw)
    allow(OT).to receive(:info)
    allow(customer).to receive(:organization_instances).and_return(org_instances)
    allow(Billing::Operations::ApplySubscriptionToOrg)
      .to receive(:materialize_entitlements_for_org).and_return(materialize_result)
  end

  # ---------------------------------------------------------------------------
  # default_org_for (private)
  # ---------------------------------------------------------------------------

  describe '#default_org_for (private)' do
    let(:org_a) { double('OrgA', objid: 'a', is_default: false) }
    let(:org_b) { double('OrgB', objid: 'b', is_default: true) }
    let(:org_c) { double('OrgC', objid: 'c', is_default: false) }

    it 'returns nil when customer has no organizations' do
      allow(customer).to receive(:organization_instances)
        .and_return(double(to_a: []))

      expect(command.send(:default_org_for, customer)).to be_nil
    end

    it 'returns the org matching customer.default_org_id when set' do
      allow(customer).to receive(:default_org_id).and_return('c')
      allow(customer).to receive(:organization_instances)
        .and_return(double(to_a: [org_a, org_b, org_c]))

      expect(command.send(:default_org_for, customer)).to eq(org_c)
    end

    it 'falls back to is_default org when default_org_id is unset' do
      allow(customer).to receive(:default_org_id).and_return(nil)
      allow(customer).to receive(:organization_instances)
        .and_return(double(to_a: [org_a, org_b, org_c]))

      expect(command.send(:default_org_for, customer)).to eq(org_b)
    end

    it 'falls back to first org when no is_default flag is set' do
      allow(customer).to receive(:default_org_id).and_return(nil)
      allow(customer).to receive(:organization_instances)
        .and_return(double(to_a: [org_a, org_c]))

      expect(command.send(:default_org_for, customer)).to eq(org_a)
    end

    it 'falls back through default_org_id when it points at a non-member org' do
      allow(customer).to receive(:default_org_id).and_return('missing')
      allow(customer).to receive(:organization_instances)
        .and_return(double(to_a: [org_a, org_b]))

      expect(command.send(:default_org_for, customer)).to eq(org_b)
    end
  end

  # ---------------------------------------------------------------------------
  # Dry-run mode
  # ---------------------------------------------------------------------------

  describe '#process_customer (dry-run)' do
    it 'increments granted count without mutating org or customer' do
      expect(org).not_to receive(:planid=)
      expect(org).not_to receive(:complimentary=)
      expect(org).not_to receive(:save)
      expect(customer).not_to receive(:planid=)
      expect(Billing::Operations::ApplySubscriptionToOrg)
        .not_to receive(:materialize_entitlements_for_org)

      command.send(:process_customer, customer, 0, 1, stats, true, false, false)

      expect(stats[:total]).to eq(1)
      expect(stats[:granted]).to eq(1)
    end

    it 'outputs a preview message in verbose mode' do
      expect(command).to receive(:puts).with(/Would grant.*cust_ext_1/)

      command.send(:process_customer, customer, 0, 1, stats, true, true, false)
    end
  end

  # ---------------------------------------------------------------------------
  # Skip conditions
  # ---------------------------------------------------------------------------

  describe '#process_customer skip conditions' do
    it 'skips when customer has no organization' do
      allow(customer).to receive(:organization_instances)
        .and_return(double(to_a: []))

      command.send(:process_customer, customer, 0, 1, stats, true, false, false)

      expect(stats[:skipped_no_org]).to eq(1)
      expect(stats[:granted]).to eq(0)
    end

    it 'skips when org already complimentary and force is false' do
      allow(org).to receive(:complimentary).and_return('true')

      command.send(:process_customer, customer, 0, 1, stats, true, false, false)

      expect(stats[:skipped_already_complimentary]).to eq(1)
      expect(stats[:granted]).to eq(0)
    end

    it 'does not skip when org is complimentary and force is true' do
      allow(org).to receive(:complimentary).and_return('true')

      command.send(:process_customer, customer, 0, 1, stats, true, false, true)

      expect(stats[:skipped_already_complimentary]).to eq(0)
      expect(stats[:granted]).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  # Live grant
  # ---------------------------------------------------------------------------

  describe '#process_customer (live mode)' do
    it 'sets planid=identity and complimentary=true on the org' do
      expect(org).to receive(:planid=).with('identity')
      expect(org).to receive(:complimentary=).with('true')
      expect(org).to receive(:save)

      command.send(:process_customer, customer, 0, 1, stats, false, false, false)

      expect(stats[:granted]).to eq(1)
    end

    it 'materializes entitlements for the org' do
      expect(Billing::Operations::ApplySubscriptionToOrg)
        .to receive(:materialize_entitlements_for_org)
        .with(org, raise_on_miss: true)
        .and_return(materialize_result)

      command.send(:process_customer, customer, 0, 1, stats, false, false, false)
    end

    it 'clears legacy customer.planid after materialization' do
      expect(customer).to receive(:planid=).with(nil)
      expect(customer).to receive(:save)

      command.send(:process_customer, customer, 0, 1, stats, false, false, false)
    end

    it 'still grants when --force re-materializes an already-complimentary org' do
      allow(org).to receive(:complimentary).and_return('true')

      expect(Billing::Operations::ApplySubscriptionToOrg)
        .to receive(:materialize_entitlements_for_org)
        .with(org, raise_on_miss: true)
        .and_return(materialize_result)

      command.send(:process_customer, customer, 0, 1, stats, false, false, true)

      expect(stats[:granted]).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  # Error handling
  # ---------------------------------------------------------------------------

  describe '#process_customer error handling' do
    it 'records error and continues on exception' do
      allow(customer).to receive(:organization_instances).and_raise(
        StandardError.new('test error')
      )

      command.send(:process_customer, customer, 0, 1, stats, false, false, false)

      expect(stats[:errors].size).to eq(1)
      expect(stats[:errors].first).to include('test error')
      expect(stats[:granted]).to eq(0)
    end

    it 'records error when materialize_entitlements_for_org raises' do
      allow(Billing::Operations::ApplySubscriptionToOrg)
        .to receive(:materialize_entitlements_for_org)
        .and_raise(Billing::PlanCacheMissError.new('plan missing', plan_id: 'identity'))

      command.send(:process_customer, customer, 0, 1, stats, false, false, false)

      expect(stats[:errors].size).to eq(1)
      expect(stats[:errors].first).to include('plan missing')
    end
  end
end
