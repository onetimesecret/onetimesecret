# apps/web/billing/spec/lib/plan_validator_spec.rb
#
# frozen_string_literal: true

# Unit tests for Billing::PlanValidator module
#
# Tests catalog-first plan_id resolution with fail-closed behavior.
# Run: pnpm run test:rspec apps/web/billing/spec/lib/plan_validator_spec.rb

require_relative '../support/billing_spec_helper'
require_relative '../../lib/plan_validator'
require_relative '../../models/plan'

RSpec.describe Billing::PlanValidator, type: :billing do
  before do
    Billing::Plan.clear_cache
  end

  after do
    Billing::Plan.clear_cache
  end

  describe '.resolve_plan_id' do
    context 'when price_id exists in catalog' do
      let(:mock_plan) do
        Billing::Plan.new(
          plan_id: 'identity_plus_v1_monthly',
          stripe_price_id: 'price_live_abc123',
          stripe_product_id: 'prod_xyz',
          tier: 'single_team',
          interval: 'month',
          amount: '1499',
          currency: 'usd',
        )
      end

      before do
        allow(Billing::Plan).to receive(:find_by_stripe_price_id)
          .with('price_live_abc123')
          .and_return(mock_plan)
      end

      it 'returns the plan_id from catalog' do
        expect(described_class.resolve_plan_id('price_live_abc123')).to eq('identity_plus_v1_monthly')
      end
    end

    context 'when price_id is not in catalog' do
      before do
        allow(Billing::Plan).to receive(:find_by_stripe_price_id)
          .with('price_unknown_999')
          .and_return(nil)
      end

      it 'raises CatalogMissError' do
        expect {
          described_class.resolve_plan_id('price_unknown_999')
        }.to raise_error(Billing::CatalogMissError, /price_unknown_999/)
      end
    end

    context 'when price_id is nil' do
      it 'raises ArgumentError' do
        expect {
          described_class.resolve_plan_id(nil)
        }.to raise_error(ArgumentError, /price_id is required/)
      end
    end

    context 'when price_id is empty string' do
      it 'raises ArgumentError' do
        expect {
          described_class.resolve_plan_id('')
        }.to raise_error(ArgumentError, /price_id is required/)
      end
    end
  end

  describe '.valid_plan_id?' do
    context 'when plan_id exists in catalog (via Plan.load)' do
      let(:mock_plan) do
        instance_double(Billing::Plan, plan_id: 'identity_plus_v1_monthly')
      end

      before do
        allow(Billing::Plan).to receive(:load)
          .with('identity_plus_v1_monthly')
          .and_return(mock_plan)
        allow(mock_plan).to receive(:exists?).and_return(true)
      end

      it 'returns true' do
        expect(described_class.valid_plan_id?('identity_plus_v1_monthly')).to be true
      end
    end

    context 'when plan_id exists in static config' do
      before do
        allow(Billing::Plan).to receive(:load).with('legacy_plan').and_return(nil)
        allow(Billing::Config).to receive(:load_plans).and_return({
          'legacy_plan' => { 'tier' => 'legacy' },
        })
      end

      it 'returns true for config-defined plans' do
        expect(described_class.valid_plan_id?('legacy_plan')).to be true
      end
    end

    context 'when plan_id does not exist anywhere' do
      before do
        allow(Billing::Plan).to receive(:load).with('nonexistent_plan').and_return(nil)
        allow(Billing::Config).to receive(:load_plans).and_return({})
      end

      it 'returns false' do
        expect(described_class.valid_plan_id?('nonexistent_plan')).to be false
      end
    end

    context 'when plan_id is nil' do
      it 'returns false' do
        expect(described_class.valid_plan_id?(nil)).to be false
      end
    end

    context 'when plan_id is empty string' do
      it 'returns false' do
        expect(described_class.valid_plan_id?('')).to be false
      end
    end
  end

  describe '.available_plan_ids' do
    before do
      plan1 = instance_double(Billing::Plan, plan_id: 'identity_plus_v1_monthly')
      plan2 = instance_double(Billing::Plan, plan_id: 'multi_team_v1_yearly')
      allow(Billing::Plan).to receive(:list_plans).and_return([plan1, plan2])

      allow(Billing::Config).to receive(:load_plans).and_return({
        'legacy_v1' => { 'tier' => 'legacy' },
      })
    end

    it 'includes plan_ids from Stripe catalog' do
      result = described_class.available_plan_ids
      expect(result).to include('identity_plus_v1_monthly', 'multi_team_v1_yearly')
    end

    it 'includes plan_ids from static config' do
      result = described_class.available_plan_ids
      expect(result).to include('legacy_v1')
    end

    it 'returns a unique sorted list' do
      result = described_class.available_plan_ids
      expect(result).to eq(result.uniq.sort)
    end
  end

  describe '.detect_drift' do
    let(:mock_plan) do
      Billing::Plan.new(
        plan_id: 'identity_plus_v1_monthly',
        stripe_price_id: 'price_live_abc123',
        tier: 'single_team',
        interval: 'month',
      )
    end

    before do
      allow(Billing::Plan).to receive(:find_by_stripe_price_id)
        .with('price_live_abc123')
        .and_return(mock_plan)
    end

    context 'when metadata matches catalog' do
      it 'returns nil (no drift)' do
        result = described_class.detect_drift(
          price_id: 'price_live_abc123',
          metadata_plan_id: 'identity_plus_v1_monthly'
        )
        expect(result).to be_nil
      end
    end

    context 'when metadata differs from catalog' do
      it 'returns drift info hash' do
        result = described_class.detect_drift(
          price_id: 'price_live_abc123',
          metadata_plan_id: 'identity_plus' # stale/wrong value
        )

        expect(result).to eq({
          catalog_plan_id: 'identity_plus_v1_monthly',
          metadata_plan_id: 'identity_plus',
          price_id: 'price_live_abc123',
        })
      end

      it 'logs warning about drift' do
        logger = instance_double(SemanticLogger::Logger)
        allow(Onetime).to receive(:get_logger).with('Billing').and_return(logger)
        allow(logger).to receive(:warn)

        expect(logger).to receive(:warn).with(
          '[PlanValidator] Drift detected: metadata differs from catalog',
          hash_including(
            catalog_plan_id: 'identity_plus_v1_monthly',
            metadata_plan_id: 'identity_plus',
            price_id: 'price_live_abc123'
          )
        )

        described_class.detect_drift(
          price_id: 'price_live_abc123',
          metadata_plan_id: 'identity_plus'
        )
      end
    end

    context 'when metadata_plan_id is nil' do
      it 'returns drift info (nil vs catalog value)' do
        result = described_class.detect_drift(
          price_id: 'price_live_abc123',
          metadata_plan_id: nil
        )

        expect(result).to eq({
          catalog_plan_id: 'identity_plus_v1_monthly',
          metadata_plan_id: nil,
          price_id: 'price_live_abc123',
        })
      end
    end

    context 'when price_id is not in catalog' do
      before do
        allow(Billing::Plan).to receive(:find_by_stripe_price_id)
          .with('price_unknown')
          .and_return(nil)
      end

      it 'raises CatalogMissError' do
        expect {
          described_class.detect_drift(
            price_id: 'price_unknown',
            metadata_plan_id: 'some_plan'
          )
        }.to raise_error(Billing::CatalogMissError)
      end
    end
  end
end

RSpec.describe Billing::CatalogMissError, type: :billing do
  it 'is defined in Billing module' do
    expect(defined?(Billing::CatalogMissError)).to eq('constant')
  end

  it 'inherits from Billing::OpsProblem' do
    expect(Billing::CatalogMissError.superclass).to eq(Billing::OpsProblem)
  end

  it 'can be instantiated with a message' do
    error = Billing::CatalogMissError.new('Price price_xyz not found in catalog')
    expect(error.message).to include('price_xyz')
  end

  it 'stores the price_id for programmatic access' do
    error = Billing::CatalogMissError.new('Not found', price_id: 'price_123')
    expect(error.price_id).to eq('price_123')
  end
end
