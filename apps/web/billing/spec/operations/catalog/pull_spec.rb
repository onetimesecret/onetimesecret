# apps/web/billing/spec/operations/catalog/pull_spec.rb
#
# frozen_string_literal: true

require_relative '../../support/billing_spec_helper'
require_relative '../../../operations/catalog/pull'
require_relative '../../../operations/catalog/stripe_reader'
require_relative '../../../operations/catalog/plan_persister'
require_relative '../../../operations/catalog/config_loader'
require_relative '../../../operations/catalog/data_extractor'

RSpec.describe Billing::Operations::Catalog::Pull, :billing do
  describe '.call' do
    let(:progress_messages) { [] }
    let(:progress_proc) { ->(msg) { progress_messages << msg } }

    let(:mock_product) do
      double(
        'Stripe::Product',
        id: 'prod_test123',
        name: 'Test Plan',
        description: 'A test plan',
        updated: 1700000000,
        marketing_features: [],
        metadata: {
          'app' => 'onetimesecret',
          'plan_id' => 'test_plan_v1',
          'tier' => 'test',
          'region' => 'US',
          'currency' => 'usd',
          'plan_code' => 'test',
          'entitlements' => '',
          'display_order' => '1',
          'tenancy' => 'multi',
          'show_on_plans_page' => 'true',
        },
      )
    end

    let(:mock_price) do
      double(
        'Stripe::Price',
        id: 'price_test123',
        product: 'prod_test123',
        type: 'recurring',
        active: true,
        currency: 'usd',
        unit_amount: 999,
        billing_scheme: 'per_unit',
        nickname: nil,
        recurring: double(interval: 'month', usage_type: 'licensed', trial_period_days: nil),
      )
    end

    let(:mock_plan) do
      instance_double(Billing::Plan, plan_id: 'test_plan_v1', exists?: true)
    end

    before do
      # Stub billing config
      allow(Onetime).to receive(:billing_config).and_return(
        double(
          stripe_key: 'sk_test_xxx',
          region: 'US',
          currency: 'usd',
          plans: {},
        ),
      )

      # Stub StripeReader
      allow(Billing::Operations::Catalog::StripeReader).to receive(:fetch_products)
        .and_return({ 'test_plan_v1' => mock_product })
      allow(Billing::Operations::Catalog::StripeReader).to receive(:fetch_prices)
        .and_return({ 'test_plan_v1' => [mock_price] })

      # Stub Plan validation method
      allow(Billing::Plan).to receive(:validate_product_metadata)
        .and_return({ missing: [], blank: [] })

      # Stub DataExtractor
      allow(Billing::Operations::Catalog::DataExtractor).to receive(:call).and_return({
        plan_id: 'test_plan_v1',
        stripe_product_id: 'prod_test123',
        stripe_updated_at: '1700000000',
        name: 'Test Plan',
        tier: 'test',
        currency: 'usd',
        region: 'US',
        tenancy: 'multi',
        display_order: '1',
        show_on_plans_page: 'true',
        description: 'A test plan',
        plan_code: 'test',
        is_popular: 'false',
        plan_name_label: nil,
        includes_plan: nil,
        active: 'true',
        entitlements: [],
        features: [],
        limits: {},
        stripe_snapshot: { product: {}, prices: { month: {} } },
        prices: { month: {} },
      })
      # Stub PlanPersister methods (extracted from Plan)
      allow(Billing::Operations::Catalog::PlanPersister).to receive(:upsert_from_stripe_data).and_return(mock_plan)
      allow(Billing::Operations::Catalog::PlanPersister).to receive(:prune_stale_plans).and_return(0)
      allow(Billing::Operations::Catalog::PlanPersister).to receive(:rebuild_stripe_price_id_cache)
      allow(Billing::Operations::Catalog::PlanPersister).to receive(:update_catalog_sync_timestamp)

      # Stub ConfigLoader methods (extracted from Plan)
      allow(Billing::Operations::Catalog::ConfigLoader).to receive(:upsert_config_only_plans).and_return(1)

      # Stub remaining Plan methods
      allow(Billing::Plan).to receive(:instances).and_return(double(member?: true))
      allow(Billing::Plan).to receive(:clear_cache)
    end

    context 'successful pull' do
      subject(:result) { described_class.call(progress: progress_proc) }

      it 'returns success result' do
        expect(result.success).to be true
      end

      it 'reports plans synced count' do
        expect(result.plans_synced).to eq(1)
      end

      it 'reports config plans loaded' do
        expect(result.config_plans_loaded).to eq(1)
      end

      it 'calls progress with status messages' do
        result
        expect(progress_messages).to include('Pulling from Stripe to Redis cache...')
      end

      it 'fetches products via StripeReader' do
        expect(Billing::Operations::Catalog::StripeReader).to receive(:fetch_products)
          .with(app_identifier: 'onetimesecret', region_filter: 'US')
        result
      end

      it 'fetches prices via StripeReader' do
        expect(Billing::Operations::Catalog::StripeReader).to receive(:fetch_prices)
        result
      end

      it 'upserts plans to Redis' do
        expect(Billing::Operations::Catalog::PlanPersister).to receive(:upsert_from_stripe_data)
        result
      end

      it 'prunes stale plans' do
        expect(Billing::Operations::Catalog::PlanPersister).to receive(:prune_stale_plans).with(['test_plan_v1'])
        result
      end

      it 'rebuilds price ID cache' do
        expect(Billing::Operations::Catalog::PlanPersister).to receive(:rebuild_stripe_price_id_cache)
        result
      end

      it 'updates catalog sync timestamp' do
        expect(Billing::Operations::Catalog::PlanPersister).to receive(:update_catalog_sync_timestamp)
        result
      end
    end

    context 'with clear_cache option' do
      subject(:result) { described_class.call(clear_cache: true, progress: progress_proc) }

      it 'clears cache before pulling' do
        expect(Billing::Plan).to receive(:clear_cache).ordered
        expect(Billing::Operations::Catalog::StripeReader).to receive(:fetch_products).ordered
        result
      end

      it 'sets cache_cleared flag' do
        expect(result.cache_cleared).to be true
      end

      it 'reports cache clearing in progress' do
        result
        expect(progress_messages).to include('Clearing existing plan cache...')
        expect(progress_messages).to include('Cache cleared')
      end
    end

    context 'without clear_cache option' do
      subject(:result) { described_class.call }

      it 'cache_cleared is false' do
        expect(result.cache_cleared).to be false
      end
    end

    context 'no Stripe API key configured' do
      before do
        allow(Onetime).to receive(:billing_config).and_return(
          double(stripe_key: '', region: nil, currency: 'usd', plans: {}),
        )
      end

      subject(:result) { described_class.call }

      it 'returns success with zero plans synced' do
        expect(result.success).to be true
        expect(result.plans_synced).to eq(0)
      end

      it 'still loads config-only plans' do
        expect(Billing::Operations::Catalog::ConfigLoader).to receive(:upsert_config_only_plans)
        result
      end
    end

    context 'no products found' do
      before do
        allow(Billing::Operations::Catalog::StripeReader).to receive(:fetch_products)
          .and_return({})
      end

      subject(:result) { described_class.call }

      it 'returns success with zero plans synced' do
        expect(result.success).to be true
        expect(result.plans_synced).to eq(0)
      end
    end

    context 'Stripe error' do
      before do
        allow(Billing::Operations::Catalog::StripeReader).to receive(:fetch_products)
          .and_raise(Stripe::APIError.new('API key invalid'))
      end

      subject(:result) { described_class.call }

      it 'returns failure result' do
        expect(result.success).to be false
      end

      it 'includes error message' do
        expect(result.errors).to include(match(/Stripe error/))
      end
    end

    context 'validation error' do
      let(:invalid_product) do
        double(
          'Stripe::Product',
          id: 'prod_invalid',
          name: 'Invalid Plan',
          description: 'Missing required metadata',
          updated: 1700000000,
          marketing_features: [],
          metadata: {
            'app' => 'onetimesecret',
            'region' => 'US',
            # Missing: plan_id, tier, currency, plan_code
          },
        )
      end

      before do
        allow(Billing::Operations::Catalog::StripeReader).to receive(:fetch_products)
          .and_return({ 'invalid_key' => invalid_product })
        allow(Billing::Operations::Catalog::StripeReader).to receive(:fetch_prices)
          .and_return({ 'invalid_key' => [mock_price] })
      end

      subject(:result) { described_class.call }

      it 'returns failure result' do
        expect(result.success).to be false
      end

      it 'includes validation error message' do
        expect(result.errors.first).to include('failed metadata validation')
      end
    end

    context 'unexpected error' do
      before do
        allow(Billing::Operations::Catalog::StripeReader).to receive(:fetch_products)
          .and_raise(StandardError.new('Network timeout'))
      end

      subject(:result) { described_class.call }

      it 'returns failure result' do
        expect(result.success).to be false
      end

      it 'includes error class and message' do
        expect(result.errors.first).to include('StandardError')
        expect(result.errors.first).to include('Network timeout')
      end
    end
  end

  describe 'Result struct' do
    it 'has expected fields' do
      result = described_class::Result.new(success: true)
      expect(result).to respond_to(:success, :plans_synced,
                                   :config_plans_loaded, :cache_cleared, :errors)
    end

    it 'has sensible defaults' do
      result = described_class::Result.new(success: true)
      expect(result.plans_synced).to eq(0)
      expect(result.errors).to eq([])
    end
  end
end
