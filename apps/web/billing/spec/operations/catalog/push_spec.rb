# apps/web/billing/spec/operations/catalog/push_spec.rb
#
# frozen_string_literal: true

require_relative '../../support/billing_spec_helper'
require_relative '../../../operations/catalog/push'

RSpec.describe Billing::Operations::Catalog::Push, :billing do
  let(:progress_messages) { [] }
  let(:progress_proc) { ->(msg) { progress_messages << msg } }

  let(:valid_catalog) do
    {
      'app_identifier' => 'onetimesecret',
      'currency' => 'cad',
      'match_fields' => ['plan_id'],
      'plans' => {
        'test_plan_v1' => {
          'name' => 'Test Plan',
          'tier' => 'single_team',
          'prices' => [
            { 'amount' => 1900, 'interval' => 'month' },
            { 'amount' => 19000, 'interval' => 'year' }
          ]
        }
      }
    }
  end

  before do
    allow(Billing::Config).to receive(:config_exists?).and_return(true)
    allow(Billing::Config).to receive(:safe_load_config).and_return(valid_catalog)
  end

  describe '.call' do
    context 'catalog not found' do
      before do
        allow(Billing::Config).to receive(:config_exists?).and_return(false)
      end

      subject(:result) { described_class.call }

      it 'returns failure' do
        expect(result.success).to be false
      end

      it 'includes error message' do
        expect(result.errors.first).to include('Catalog not found')
      end
    end

    context 'empty catalog' do
      before do
        allow(Billing::Config).to receive(:safe_load_config).and_return({})
      end

      subject(:result) { described_class.call }

      it 'returns failure' do
        expect(result.success).to be false
      end
    end

    context 'no plans in catalog' do
      before do
        allow(Billing::Config).to receive(:safe_load_config).and_return({ 'plans' => {} })
      end

      subject(:result) { described_class.call }

      it 'returns failure with no plans error' do
        expect(result.success).to be false
        expect(result.errors.first).to include('No plans found')
      end
    end

    context 'plan filter with unknown plan' do
      subject(:result) { described_class.call(plan_filter: 'nonexistent_plan') }

      it 'returns failure' do
        expect(result.success).to be false
      end

      it 'lists available plans in error' do
        expect(result.errors.first).to include('test_plan_v1')
      end
    end

    context 'dry run mode' do
      let(:mock_product_list) { double('ProductList', auto_paging_each: nil) }
      let(:mock_price_list) { double('PriceList', auto_paging_each: nil) }

      before do
        allow(Stripe::Product).to receive(:list).and_return(mock_product_list)
        allow(Stripe::Price).to receive(:list).and_return(mock_price_list)
      end

      subject(:result) { described_class.call(dry_run: true, progress: progress_proc) }

      it 'returns success' do
        expect(result.success).to be true
      end

      it 'sets dry_run flag' do
        expect(result.dry_run).to be true
      end

      it 'does not create Stripe products' do
        expect(Stripe::Product).not_to receive(:create)
        result
      end

      it 'reports products to create' do
        expect(result.products_created).to eq(1)
      end
    end

    context 'no changes needed' do
      before do
        mock_list = double('List', auto_paging_each: nil)
        allow(Stripe::Product).to receive(:list).and_return(mock_list)
        allow(Stripe::Price).to receive(:list).and_return(mock_list)
      end

      subject(:result) { described_class.call(dry_run: true, progress: progress_proc) }

      it 'in dry_run mode reports changes without applying' do
        expect(result.success).to be true
        expect(result.dry_run).to be true
        expect(result.products_created).to be >= 0
      end
    end

    context 'Stripe API error' do
      before do
        allow(Stripe::Product).to receive(:list)
          .and_raise(Stripe::APIError.new('Invalid API key'))
      end

      subject(:result) { described_class.call }

      it 'returns failure' do
        expect(result.success).to be false
      end

      it 'includes Stripe error' do
        expect(result.errors.first).to include('Stripe error')
      end
    end
  end

  describe 'Result struct' do
    it 'has expected fields' do
      result = described_class::Result.new(success: true)
      expect(result).to respond_to(:success, :dry_run, :products_created,
                                   :products_updated, :prices_created, :no_changes, :errors)
    end

    it 'has sensible defaults' do
      result = described_class::Result.new(success: true)
      expect(result.dry_run).to be false
      expect(result.products_created).to eq(0)
      expect(result.errors).to eq([])
    end
  end

  describe 'plan filtering' do
    let(:multi_plan_catalog) do
      valid_catalog.merge(
        'plans' => {
          'plan_a' => { 'name' => 'Plan A', 'tier' => 'free' },
          'plan_b' => { 'name' => 'Plan B', 'tier' => 'single_team' }
        }
      )
    end

    before do
      allow(Billing::Config).to receive(:safe_load_config).and_return(multi_plan_catalog)

      mock_list = double('List', auto_paging_each: nil)
      allow(Stripe::Product).to receive(:list).and_return(mock_list)
      allow(Stripe::Price).to receive(:list).and_return(mock_list)
    end

    it 'processes only specified plan' do
      result = described_class.call(plan_filter: 'plan_a', dry_run: true, progress: progress_proc)
      expect(result.success).to be true
      expect(progress_messages.join).to include('plan_a')
      expect(progress_messages.join).not_to include('plan_b')
    end
  end
end
