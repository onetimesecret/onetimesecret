# apps/web/billing/spec/operations/catalog/stripe_reader_spec.rb
#
# frozen_string_literal: true

require_relative '../../support/billing_spec_helper'
require_relative '../../../operations/catalog/stripe_reader'

RSpec.describe Billing::Operations::Catalog::StripeReader, :billing do
  let(:app_identifier) { 'onetimesecret' }
  let(:match_fields) { ['plan_id'] }

  def mock_product(id:, metadata:)
    instance_double(
      Stripe::Product,
      id: id,
      metadata: metadata,
    )
  end

  def mock_price(id:, product_id:, amount:, currency:, interval:)
    recurring = instance_double('Recurring', interval: interval)
    instance_double(
      Stripe::Price,
      id: id,
      product: product_id,
      unit_amount: amount,
      currency: currency,
      recurring: recurring,
    )
  end

  describe '.fetch_products' do
    let(:product_list) { instance_double('ProductList') }

    before do
      allow(Stripe::Product).to receive(:list).and_return(product_list)
    end

    context 'with matching app_identifier' do
      let(:matching_product) do
        mock_product(
          id: 'prod_123',
          metadata: { 'app' => app_identifier, 'plan_id' => 'basic_v1' },
        )
      end

      let(:non_matching_product) do
        mock_product(
          id: 'prod_456',
          metadata: { 'app' => 'other_app', 'plan_id' => 'other_plan' },
        )
      end

      before do
        allow(product_list).to receive(:auto_paging_each)
          .and_yield(matching_product)
          .and_yield(non_matching_product)
      end

      it 'returns only products matching app_identifier' do
        result = described_class.fetch_products(app_identifier: app_identifier)
        expect(result.keys).to eq(['basic_v1'])
        expect(result['basic_v1']).to eq(matching_product)
      end
    end

    context 'with region_filter' do
      let(:us_product) do
        mock_product(
          id: 'prod_us',
          metadata: { 'app' => app_identifier, 'plan_id' => 'basic_us', 'region' => 'US' },
        )
      end

      let(:ca_product) do
        mock_product(
          id: 'prod_ca',
          metadata: { 'app' => app_identifier, 'plan_id' => 'basic_ca', 'region' => 'CA' },
        )
      end

      before do
        allow(product_list).to receive(:auto_paging_each)
          .and_yield(us_product)
          .and_yield(ca_product)
        allow(Billing::RegionNormalizer).to receive(:match?).and_call_original
      end

      it 'filters products by region' do
        allow(Billing::RegionNormalizer).to receive(:match?).with('US', 'US').and_return(true)
        allow(Billing::RegionNormalizer).to receive(:match?).with('CA', 'US').and_return(false)

        result = described_class.fetch_products(
          app_identifier: app_identifier,
          region_filter: 'US',
        )
        expect(result.keys).to eq(['basic_us'])
      end
    end

    context 'with override_product_ids' do
      let(:app_product) do
        mock_product(
          id: 'prod_app',
          metadata: { 'app' => app_identifier, 'plan_id' => 'basic_v1' },
        )
      end

      let(:override_product) do
        mock_product(
          id: 'prod_override',
          metadata: { 'app' => 'different_app', 'plan_id' => 'legacy_plan' },
        )
      end

      before do
        allow(product_list).to receive(:auto_paging_each)
          .and_yield(app_product)
          .and_yield(override_product)
      end

      it 'includes override products regardless of app match' do
        result = described_class.fetch_products(
          app_identifier: app_identifier,
          override_product_ids: Set.new(['prod_override']),
        )
        expect(result.keys).to contain_exactly('basic_v1', 'legacy_plan')
      end

      it 'uses __id__ prefix when override product has no match key' do
        override_no_key = mock_product(
          id: 'prod_no_key',
          metadata: { 'app' => 'other' },
        )
        allow(product_list).to receive(:auto_paging_each)
          .and_yield(override_no_key)

        result = described_class.fetch_products(
          app_identifier: app_identifier,
          override_product_ids: Set.new(['prod_no_key']),
        )
        expect(result.keys).to eq(['__id__prod_no_key'])
      end
    end

    context 'with custom match_fields' do
      let(:multi_field_product) do
        mock_product(
          id: 'prod_multi',
          metadata: {
            'app' => app_identifier,
            'plan_id' => 'pro_v1',
            'region' => 'US',
          },
        )
      end

      before do
        allow(product_list).to receive(:auto_paging_each)
          .and_yield(multi_field_product)
      end

      it 'builds match key from multiple fields' do
        result = described_class.fetch_products(
          app_identifier: app_identifier,
          match_fields: ['plan_id', 'region'],
        )
        expect(result.keys).to eq(['pro_v1|US'])
      end
    end

    context 'with missing match field values' do
      let(:incomplete_product) do
        mock_product(
          id: 'prod_incomplete',
          metadata: { 'app' => app_identifier },
        )
      end

      before do
        allow(product_list).to receive(:auto_paging_each)
          .and_yield(incomplete_product)
      end

      it 'excludes products with nil match field values' do
        result = described_class.fetch_products(app_identifier: app_identifier)
        expect(result).to be_empty
      end
    end

    context 'Stripe API retry' do
      it 'uses StripeRetry.with_retry' do
        allow(product_list).to receive(:auto_paging_each)
        expect(Billing::Operations::Catalog::StripeRetry).to receive(:with_retry).and_call_original

        described_class.fetch_products(app_identifier: app_identifier)
      end
    end
  end

  describe '.fetch_prices' do
    let(:price_list) { instance_double('PriceList') }

    before do
      allow(Stripe::Price).to receive(:list).and_return(price_list)
    end

    context 'with empty products' do
      it 'returns empty hash without calling Stripe' do
        expect(Stripe::Price).not_to receive(:list)
        result = described_class.fetch_prices({})
        expect(result).to eq({})
      end
    end

    context 'with products' do
      let(:product) do
        mock_product(
          id: 'prod_123',
          metadata: { 'app' => app_identifier, 'plan_id' => 'basic_v1' },
        )
      end

      let(:products) { { 'basic_v1' => product } }

      let(:matching_price) do
        mock_price(
          id: 'price_123',
          product_id: 'prod_123',
          amount: 1900,
          currency: 'cad',
          interval: 'month',
        )
      end

      let(:other_price) do
        mock_price(
          id: 'price_456',
          product_id: 'prod_other',
          amount: 2900,
          currency: 'usd',
          interval: 'month',
        )
      end

      before do
        allow(price_list).to receive(:auto_paging_each)
          .and_yield(matching_price)
          .and_yield(other_price)
      end

      it 'returns prices grouped by match_key' do
        result = described_class.fetch_prices(products)
        expect(result.keys).to eq(['basic_v1'])
        expect(result['basic_v1']).to eq([matching_price])
      end

      it 'excludes prices for products not in input' do
        result = described_class.fetch_prices(products)
        expect(result.values.flatten.map(&:id)).not_to include('price_456')
      end
    end

    context 'multiple prices per product' do
      let(:product) do
        mock_product(
          id: 'prod_123',
          metadata: { 'plan_id' => 'pro_v1' },
        )
      end

      let(:products) { { 'pro_v1' => product } }

      let(:monthly_price) do
        mock_price(
          id: 'price_month',
          product_id: 'prod_123',
          amount: 1900,
          currency: 'cad',
          interval: 'month',
        )
      end

      let(:yearly_price) do
        mock_price(
          id: 'price_year',
          product_id: 'prod_123',
          amount: 19000,
          currency: 'cad',
          interval: 'year',
        )
      end

      before do
        allow(price_list).to receive(:auto_paging_each)
          .and_yield(monthly_price)
          .and_yield(yearly_price)
      end

      it 'collects all prices for a product' do
        result = described_class.fetch_prices(products)
        expect(result['pro_v1'].size).to eq(2)
        expect(result['pro_v1']).to contain_exactly(monthly_price, yearly_price)
      end
    end

    context 'Stripe API retry' do
      let(:product) { mock_product(id: 'prod_123', metadata: { 'plan_id' => 'basic_v1' }) }
      let(:products) { { 'basic_v1' => product } }

      it 'uses StripeRetry.with_retry' do
        allow(price_list).to receive(:auto_paging_each)
        expect(Billing::Operations::Catalog::StripeRetry).to receive(:with_retry).and_call_original

        described_class.fetch_prices(products)
      end
    end
  end
end
