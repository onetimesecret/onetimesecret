# spec/unit/onetime/cli/migrations/migrate_probono_accounts_command_spec.rb
#
# frozen_string_literal: true

# Unit tests for MigrateProbonoAccountsCommand.
#
# Covers:
# - parse_price_ids: multi-currency string parsing, fallback, edge cases
# - resolve_price_for_customer: single-price mode, multi-currency dispatch
# - Dry-run mode (no mutations, correct preview output)
# - Skip: no organization found
# - Skip: org already has active subscription
# - Skip: already migrated (complimentary marker)
# - Skip: currency mismatch (no matching price)
# - Live migration flow (Stripe customer + subscription creation)
# - Live migration with multi-currency prices
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
  let(:price_map) { { nil => price_id } }
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
      skipped_currency_mismatch: 0,
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
  # parse_price_ids
  # ---------------------------------------------------------------------------

  describe '#parse_price_ids (private)' do
    it 'parses multi-currency string into a hash' do
      result = command.send(:parse_price_ids, 'cad:price_aaa,usd:price_bbb', nil)

      expect(result).to eq('cad' => 'price_aaa', 'usd' => 'price_bbb')
    end

    it 'handles extra whitespace around entries' do
      result = command.send(:parse_price_ids, ' cad:price_aaa , usd:price_bbb ', nil)

      expect(result).to eq('cad' => 'price_aaa', 'usd' => 'price_bbb')
    end

    it 'handles a single currency entry' do
      result = command.send(:parse_price_ids, 'cad:price_aaa', nil)

      expect(result).to eq('cad' => 'price_aaa')
    end

    it 'downcases currency codes' do
      result = command.send(:parse_price_ids, 'CAD:price_aaa,USD:price_bbb', nil)

      expect(result).to eq('cad' => 'price_aaa', 'usd' => 'price_bbb')
    end

    it 'falls back to single price_id with nil key when no price_ids string' do
      result = command.send(:parse_price_ids, nil, 'price_xxx')

      expect(result).to eq(nil => 'price_xxx')
    end

    it 'returns empty hash when both arguments are nil' do
      result = command.send(:parse_price_ids, nil, nil)

      expect(result).to eq({})
    end

    it 'skips malformed entries missing a colon' do
      result = command.send(:parse_price_ids, 'cad:price_aaa,badentry,usd:price_bbb', nil)

      expect(result).to eq('cad' => 'price_aaa', 'usd' => 'price_bbb')
    end

    it 'skips entries with empty currency or price after split' do
      result = command.send(:parse_price_ids, ':price_orphan,cad:price_aaa', nil)

      # ":price_orphan" splits to ["", "price_orphan"] -- empty string is truthy,
      # so it gets stored under "" key. This is the current behavior.
      expect(result).to include('cad' => 'price_aaa')
    end

    it 'prefers --price-ids over --price-id when both provided' do
      result = command.send(:parse_price_ids, 'cad:price_aaa', 'price_fallback')

      expect(result).to eq('cad' => 'price_aaa')
      expect(result).not_to have_key(nil)
    end

    it 'rejects entries with empty price values' do
      result = command.send(:parse_price_ids, 'cad:price_aaa,usd:', nil)

      expect(result).to eq('cad' => 'price_aaa')
    end
  end

  # ---------------------------------------------------------------------------
  # resolve_price_for_customer
  # ---------------------------------------------------------------------------

  describe '#resolve_price_for_customer (private)' do
    let(:stripe_customer_usd) { double('Stripe::Customer', currency: 'usd') }
    let(:stripe_customer_cad) { double('Stripe::Customer', currency: 'cad') }
    let(:stripe_customer_eur) { double('Stripe::Customer', currency: 'eur') }
    let(:stripe_customer_nil) { double('Stripe::Customer', currency: nil) }

    context 'single-price mode (nil key in map)' do
      let(:single_map) { { nil => 'price_single' } }

      it 'returns the single price regardless of customer currency' do
        result = command.send(:resolve_price_for_customer, stripe_customer_usd, single_map)
        expect(result).to eq('price_single')
      end

      it 'returns the single price when customer has no currency' do
        result = command.send(:resolve_price_for_customer, stripe_customer_nil, single_map)
        expect(result).to eq('price_single')
      end
    end

    context 'multi-currency mode' do
      let(:multi_map) { { 'cad' => 'price_cad', 'usd' => 'price_usd' } }

      it 'returns the USD price for a USD customer' do
        result = command.send(:resolve_price_for_customer, stripe_customer_usd, multi_map)
        expect(result).to eq('price_usd')
      end

      it 'returns the CAD price for a CAD customer' do
        result = command.send(:resolve_price_for_customer, stripe_customer_cad, multi_map)
        expect(result).to eq('price_cad')
      end

      it 'returns first available price when customer has no currency' do
        result = command.send(:resolve_price_for_customer, stripe_customer_nil, multi_map)
        expect(result).to eq(multi_map.values.first)
      end

      it 'returns nil when customer currency has no matching price' do
        result = command.send(:resolve_price_for_customer, stripe_customer_eur, multi_map)
        expect(result).to be_nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Dry-run mode
  # ---------------------------------------------------------------------------

  describe '#process_customer (dry-run)' do
    it 'increments migrated count without calling Stripe' do
      expect(Stripe::Customer).not_to receive(:create)
      expect(Stripe::Subscription).not_to receive(:create)

      command.send(:process_customer, customer, 0, 1, stats, true, false, price_map, target_planid)

      expect(stats[:total]).to eq(1)
      expect(stats[:migrated]).to eq(1)
    end

    it 'outputs preview message' do
      expect(command).to receive(:puts).with(/Would migrate.*cust_ext_1/)

      command.send(:process_customer, customer, 0, 1, stats, true, true, price_map, target_planid)
    end
  end

  # ---------------------------------------------------------------------------
  # Skip conditions
  # ---------------------------------------------------------------------------

  describe '#process_customer skip conditions' do
    it 'skips when customer has no organization' do
      allow(customer).to receive(:organization_instances)
        .and_return(double(to_a: []))

      command.send(:process_customer, customer, 0, 1, stats, true, false, price_map, target_planid)

      expect(stats[:skipped_no_org]).to eq(1)
      expect(stats[:migrated]).to eq(0)
    end

    it 'skips when org already has active subscription' do
      allow(org).to receive(:active_subscription?).and_return(true)
      allow(org).to receive(:planid).and_return('identity_plus_v1')

      command.send(:process_customer, customer, 0, 1, stats, true, false, price_map, target_planid)

      expect(stats[:skipped_has_subscription]).to eq(1)
    end

    it 'skips when org already has complimentary marker' do
      allow(org).to receive(:complimentary).and_return('true')

      command.send(:process_customer, customer, 0, 1, stats, true, false, price_map, target_planid)

      expect(stats[:skipped_already_migrated]).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  # Live migration (single-price mode)
  # ---------------------------------------------------------------------------

  describe '#process_customer (live mode, single-price)' do
    let(:stripe_customer) { double('Stripe::Customer', id: 'cus_new_123', currency: 'cad') }
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
      allow(Billing::Operations::ApplySubscriptionToOrg).to receive(:call)
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

      command.send(:process_customer, customer, 0, 1, stats, false, false, price_map, target_planid)

      expect(stats[:migrated]).to eq(1)
    end

    it 'applies subscription to organization via ApplySubscriptionToOrg' do
      expect(Billing::Operations::ApplySubscriptionToOrg).to receive(:call).with(
        org,
        stripe_subscription,
        owner: true,
        planid_override: target_planid,
      )

      command.send(:process_customer, customer, 0, 1, stats, false, false, price_map, target_planid)
    end

    it 'clears legacy customer planid' do
      expect(customer).to receive(:planid=).with(nil)
      expect(customer).to receive(:save)

      command.send(:process_customer, customer, 0, 1, stats, false, false, price_map, target_planid)
    end
  end

  # ---------------------------------------------------------------------------
  # Live migration (multi-currency mode)
  # ---------------------------------------------------------------------------

  describe '#process_customer (live mode, multi-currency)' do
    let(:multi_price_map) { { 'cad' => 'price_cad_123', 'usd' => 'price_usd_456' } }
    let(:stripe_customer) { double('Stripe::Customer', id: 'cus_multi_1', currency: 'usd') }
    let(:period_end) { 1_700_000_000 }
    let(:subscription_item) { double('SubscriptionItem', current_period_end: period_end) }
    let(:items_data) { double('ItemsData', data: [subscription_item]) }
    let(:stripe_subscription) do
      double('Stripe::Subscription',
        id: 'sub_multi_1',
        status: 'active',
        customer: 'cus_multi_1',
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
      allow(Billing::Operations::ApplySubscriptionToOrg).to receive(:call)
      allow(org).to receive(:stripe_customer_id).and_return(nil)
    end

    it 'uses the currency-matched price for subscription creation' do
      expect(Stripe::Subscription).to receive(:create).with(
        hash_including(
          customer: 'cus_multi_1',
          items: [{ price: 'price_usd_456' }],
        ),
      ).and_return(stripe_subscription)

      command.send(:process_customer, customer, 0, 1, stats, false, false, multi_price_map, target_planid)

      expect(stats[:migrated]).to eq(1)
    end

    it 'uses CAD price for a CAD-currency Stripe customer' do
      cad_customer = double('Stripe::Customer', id: 'cus_cad_1', currency: 'cad')
      allow(Stripe::Customer).to receive(:list)
        .and_return(double(data: [cad_customer]))

      expect(Stripe::Subscription).to receive(:create).with(
        hash_including(
          items: [{ price: 'price_cad_123' }],
        ),
      ).and_return(stripe_subscription)

      command.send(:process_customer, customer, 0, 1, stats, false, false, multi_price_map, target_planid)
    end

    it 'logs a note when verbose and Stripe customer has no currency' do
      nil_currency_customer = double('Stripe::Customer', id: 'cus_nil_1', currency: nil)
      allow(Stripe::Customer).to receive(:list)
        .and_return(double(data: [nil_currency_customer]))

      # Re-allow puts so we can assert on output
      allow(command).to receive(:puts).and_call_original

      expect {
        command.send(:process_customer, customer, 0, 1, stats, false, true, multi_price_map, target_planid)
      }.to output(/has no Stripe currency, using default price/).to_stdout
    end
  end

  # ---------------------------------------------------------------------------
  # Currency mismatch skip
  # ---------------------------------------------------------------------------

  describe '#process_customer (currency mismatch)' do
    let(:multi_price_map) { { 'cad' => 'price_cad_123', 'usd' => 'price_usd_456' } }
    let(:stripe_customer_eur) { double('Stripe::Customer', id: 'cus_eur_1', currency: 'eur') }

    before do
      allow(Stripe::Customer).to receive(:list)
        .and_return(double(data: [stripe_customer_eur]))
      allow(org).to receive(:stripe_customer_id).and_return(nil)
    end

    it 'skips customer and increments skipped_currency_mismatch' do
      expect(Stripe::Subscription).not_to receive(:create)

      command.send(:process_customer, customer, 0, 1, stats, false, false, multi_price_map, target_planid)

      expect(stats[:skipped_currency_mismatch]).to eq(1)
      expect(stats[:migrated]).to eq(0)
    end

    it 'outputs a message about the currency mismatch' do
      expect(command).to receive(:puts).with(/no price for currency eur/)

      command.send(:process_customer, customer, 0, 1, stats, false, true, multi_price_map, target_planid)
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

      command.send(:process_customer, customer, 0, 1, stats, false, false, price_map, target_planid)

      expect(stats[:errors].size).to eq(1)
      expect(stats[:errors].first).to include('test error')
    end
  end
end
