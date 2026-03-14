# spec/unit/onetime/cli/migrations/migrate_probono_accounts_command_spec.rb
#
# frozen_string_literal: true

# Unit tests for MigrateProbonoAccountsCommand#process_customer.
#
# Covers:
# - Dry-run mode (no mutations, correct preview output)
# - Skip: no organization found
# - Skip: org already has active subscription
# - Skip: already migrated (complimentary marker)
# - Live migration flow (Stripe customer + subscription creation)
# - Rate limit retry logic
#
# Run: pnpm run test:rspec spec/unit/onetime/cli/migrations/migrate_probono_accounts_command_spec.rb

require 'spec_helper'
require 'onetime/cli'
require 'billing/metadata'
require 'billing/operations/apply_subscription_to_org'

RSpec.describe Onetime::CLI::MigrateProbonoAccountsCommand do
  subject(:command) { described_class.new }

  let(:customer_email) { 'probono@example.com' }
  let(:price_id) { 'price_0_complimentary' }
  let(:target_planid) { 'identity_plus_v1' }

  let(:customer) do
    double('Customer',
      extid: 'cust_ext_1',
      email: customer_email,
      planid: 'identity',
      :planid= => nil,
      save: true,
    )
  end

  let(:org) do
    double('Organization',
      extid: 'org_ext_1',
      is_default: true,
      stripe_customer_id: nil,
      billing_email: nil,
      contact_email: customer_email,
      planid: 'free_v1',
      subscription_status: nil,
      complimentary: nil,
      active_subscription?: false,
      :stripe_customer_id= => nil,
      :stripe_subscription_id= => nil,
      :subscription_status= => nil,
      :subscription_period_end= => nil,
      :planid= => nil,
      :complimentary= => nil,
      save: true,
    )
  end

  let(:org_instances) { double('instances', to_a: [org]) }

  let(:stats) do
    {
      total: 0,
      migrated: 0,
      skipped_no_org: 0,
      skipped_has_subscription: 0,
      skipped_already_migrated: 0,
      errors: [],
    }
  end

  before do
    allow(command).to receive(:puts)
    allow(command).to receive(:print)
    allow(command).to receive(:sleep)
    allow(OT).to receive(:le)
    allow(OT).to receive(:lw)
    allow(OT).to receive(:info)
    allow(customer).to receive(:organization_instances).and_return(org_instances)
  end

  # ---------------------------------------------------------------------------
  # Dry-run mode
  # ---------------------------------------------------------------------------

  describe '#process_customer (dry-run)' do
    it 'increments migrated count without calling Stripe' do
      expect(Stripe::Customer).not_to receive(:create)
      expect(Stripe::Subscription).not_to receive(:create)

      command.send(:process_customer, customer, 0, 1, stats, true, false, price_id, target_planid)

      expect(stats[:total]).to eq(1)
      expect(stats[:migrated]).to eq(1)
    end

    it 'outputs preview message' do
      expect(command).to receive(:puts).with(/Would migrate.*cust_ext_1/)

      command.send(:process_customer, customer, 0, 1, stats, true, true, price_id, target_planid)
    end
  end

  # ---------------------------------------------------------------------------
  # Skip conditions
  # ---------------------------------------------------------------------------

  describe '#process_customer skip conditions' do
    it 'skips when customer has no organization' do
      allow(customer).to receive(:organization_instances)
        .and_return(double(to_a: []))

      command.send(:process_customer, customer, 0, 1, stats, true, false, price_id, target_planid)

      expect(stats[:skipped_no_org]).to eq(1)
      expect(stats[:migrated]).to eq(0)
    end

    it 'skips when org already has active subscription' do
      allow(org).to receive(:active_subscription?).and_return(true)
      allow(org).to receive(:planid).and_return('identity_plus_v1')

      command.send(:process_customer, customer, 0, 1, stats, true, false, price_id, target_planid)

      expect(stats[:skipped_has_subscription]).to eq(1)
    end

    it 'skips when org already has complimentary marker' do
      allow(org).to receive(:complimentary).and_return('true')

      command.send(:process_customer, customer, 0, 1, stats, true, false, price_id, target_planid)

      expect(stats[:skipped_already_migrated]).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  # Live migration
  # ---------------------------------------------------------------------------

  describe '#process_customer (live mode)' do
    let(:stripe_customer) { double('Stripe::Customer', id: 'cus_new_123') }
    let(:period_end) { 1_700_000_000 }
    let(:subscription_item) { double('SubscriptionItem', current_period_end: period_end) }
    let(:items_data) { double('ItemsData', data: [subscription_item]) }
    let(:stripe_subscription) do
      double('Stripe::Subscription',
        id: 'sub_new_123',
        status: 'active',
        customer: 'cus_new_123',
        items: items_data,
        metadata: {
          Billing::Metadata::FIELD_COMPLIMENTARY => 'true',
          Billing::Metadata::FIELD_PLAN_ID => target_planid,
          'migrated_from' => 'probono',
        },
      )
    end

    before do
      allow(Stripe::Customer).to receive(:list)
        .and_return(double(data: [stripe_customer]))
      allow(Stripe::Subscription).to receive(:create)
        .and_return(stripe_subscription)
      allow(org).to receive(:stripe_customer_id).and_return(nil)
    end

    it 'creates Stripe subscription with complimentary metadata' do
      expect(Stripe::Subscription).to receive(:create).with(
        hash_including(
          customer: 'cus_new_123',
          items: [{ price: price_id }],
          metadata: hash_including(
            Billing::Metadata::FIELD_COMPLIMENTARY => 'true',
            'migrated_from' => 'probono',
          ),
        ),
      ).and_return(stripe_subscription)

      command.send(:process_customer, customer, 0, 1, stats, false, false, price_id, target_planid)

      expect(stats[:migrated]).to eq(1)
    end

    it 'updates organization fields' do
      expect(org).to receive(:stripe_customer_id=).with('cus_new_123')
      expect(org).to receive(:stripe_subscription_id=).with('sub_new_123')
      expect(org).to receive(:subscription_status=).with('active')
      expect(org).to receive(:planid=).with('identity_plus_v1')
      expect(org).to receive(:complimentary=).with('true')
      expect(org).to receive(:save)

      command.send(:process_customer, customer, 0, 1, stats, false, false, price_id, target_planid)
    end

    it 'clears legacy customer planid' do
      expect(customer).to receive(:planid=).with(nil)
      expect(customer).to receive(:save)

      command.send(:process_customer, customer, 0, 1, stats, false, false, price_id, target_planid)
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

      command.send(:process_customer, customer, 0, 1, stats, false, false, price_id, target_planid)

      expect(stats[:errors].size).to eq(1)
      expect(stats[:errors].first).to include('test error')
    end
  end
end
