# apps/web/billing/spec/operations/catalog/data_extractor_spec.rb
#
# frozen_string_literal: true

# Unit tests for Billing::Operations::Catalog::DataExtractor
#
# This module transforms Stripe product/price objects into the hash format
# expected by PlanPersister. Tests cover the extraction logic itself, which
# was previously untested because callers stubbed .call.
#
# Run: pnpm run test:rspec apps/web/billing/spec/operations/catalog/data_extractor_spec.rb

require_relative '../../support/billing_spec_helper'
require_relative '../../../operations/catalog/data_extractor'
require_relative '../../../operations/catalog/metadata_validator'
require_relative '../../../metadata'

RSpec.describe Billing::Operations::Catalog::DataExtractor, :billing do
  # Helper to call private methods on the module for unit testing
  def extract(method, *args, **kwargs)
    described_class.send(method, *args, **kwargs)
  end

  # ---------------------------------------------------------------------------
  # Test data factories
  # ---------------------------------------------------------------------------

  # Build a mock Stripe::Product with configurable metadata
  #
  # @option overrides [Hash] :metadata Replace metadata entirely (no defaults merged)
  # @option overrides [Hash] :metadata_merge Merge with default metadata
  def build_product(overrides = {})
    metadata_defaults = {
      'app' => 'onetimesecret',
      'plan_id' => 'test_plan_v1',
      'tier' => 'premium',
      'region' => 'US',
      'currency' => 'usd',
      'tenancy' => 'multi',
      'entitlements' => 'create_secrets,api_access',
      'display_order' => '10',
      'show_on_plans_page' => 'true',
      'ots_plan_code' => 'test_plan',
      'ots_is_popular' => 'false',
      'ots_plan_name_label' => 'For Teams',
      'ots_includes_plan' => 'basic_v1',
      'limit_secrets_per_day' => '100',
      'limit_teams' => '5',
      'limit_custom_domains' => '-1', # unlimited
    }

    # Allow complete replacement OR merge with defaults
    if overrides.key?(:metadata)
      metadata = overrides.delete(:metadata)
    else
      metadata = metadata_defaults.merge(overrides.delete(:metadata_merge) || {})
    end

    product_defaults = {
      id: 'prod_test123',
      name: 'Test Plan',
      description: 'A comprehensive test plan',
      updated: 1700000000,
      marketing_features: [
        double(name: 'Feature One'),
        double(name: 'Feature Two'),
      ],
      metadata: metadata,
    }

    double('Stripe::Product', product_defaults.merge(overrides))
  end

  # Build a mock Stripe::Price with configurable attributes
  def build_price(overrides = {})
    recurring_defaults = {
      interval: 'month',
      usage_type: 'licensed',
      trial_period_days: nil,
    }
    recurring = double('recurring', recurring_defaults.merge(overrides.delete(:recurring) || {}))

    price_defaults = {
      id: 'price_test123',
      product: 'prod_test123',
      type: 'recurring',
      active: true,
      currency: 'usd',
      unit_amount: 1999,
      billing_scheme: 'per_unit',
      nickname: 'Monthly',
      recurring: recurring,
    }

    double('Stripe::Price', price_defaults.merge(overrides))
  end

  # ---------------------------------------------------------------------------
  # Happy path - .call returns expected structure
  # ---------------------------------------------------------------------------

  describe '.call' do
    let(:product) { build_product }
    let(:price) { build_price }

    it 'returns a hash with all expected top-level keys' do
      result = described_class.call(product, price)

      expected_keys = %i[
        plan_id stripe_product_id stripe_updated_at name tier currency
        region tenancy display_order show_on_plans_page description
        plan_code is_popular plan_name_label includes_plan active
        entitlements features limits stripe_snapshot prices
      ]

      expect(result.keys).to match_array(expected_keys)
    end

    it 'extracts plan_id from product metadata' do
      result = described_class.call(product, price)
      expect(result[:plan_id]).to eq('test_plan_v1')
    end

    it 'extracts stripe_product_id from product' do
      result = described_class.call(product, price)
      expect(result[:stripe_product_id]).to eq('prod_test123')
    end

    it 'extracts stripe_updated_at as string' do
      result = described_class.call(product, price)
      expect(result[:stripe_updated_at]).to eq('1700000000')
    end

    it 'extracts name from product' do
      result = described_class.call(product, price)
      expect(result[:name]).to eq('Test Plan')
    end

    it 'extracts tier from metadata' do
      result = described_class.call(product, price)
      expect(result[:tier]).to eq('premium')
    end

    it 'extracts currency from metadata, falling back to price' do
      result = described_class.call(product, price)
      expect(result[:currency]).to eq('usd')
    end

    context 'when currency not in metadata' do
      let(:product) { build_product(metadata_merge: { 'currency' => nil }) }
      let(:price) { build_price(currency: 'eur') }

      it 'falls back to price currency' do
        result = described_class.call(product, price)
        expect(result[:currency]).to eq('eur')
      end
    end

    it 'extracts region from metadata' do
      result = described_class.call(product, price)
      expect(result[:region]).to eq('US')
    end

    it 'extracts description from product' do
      result = described_class.call(product, price)
      expect(result[:description]).to eq('A comprehensive test plan')
    end

    it 'extracts plan_code from metadata' do
      result = described_class.call(product, price)
      expect(result[:plan_code]).to eq('test_plan')
    end

    it 'extracts active status from price as string' do
      result = described_class.call(product, price)
      expect(result[:active]).to eq('true')
    end

    it 'extracts features from marketing_features' do
      result = described_class.call(product, price)
      expect(result[:features]).to eq(['Feature One', 'Feature Two'])
    end

    it 'builds prices hash keyed by interval' do
      result = described_class.call(product, price)

      expect(result[:prices]).to have_key(:month)
      expect(result[:prices][:month]).to include(
        stripe_price_id: 'price_test123',
        amount: '1999',
        currency: 'usd',
        billing_scheme: 'per_unit',
        usage_type: 'licensed',
        nickname: 'Monthly',
        active: 'true'
      )
    end
  end

  # ---------------------------------------------------------------------------
  # validate_metadata! failures (via MetadataValidator)
  # ---------------------------------------------------------------------------

  describe 'metadata validation' do
    let(:price) { build_price }

    context 'when required metadata fields are missing' do
      let(:product) do
        build_product(metadata: {
          'app' => 'onetimesecret',
          # Missing: plan_id, tier, region
        })
      end

      it 'raises Onetime::ConfigError' do
        expect {
          described_class.call(product, price)
        }.to raise_error(Onetime::ConfigError, /missing: plan_id, tier, region/)
      end

      it 'includes product id and name in error message' do
        expect {
          described_class.call(product, price)
        }.to raise_error(Onetime::ConfigError, /prod_test123.*Test Plan/)
      end
    end

    context 'when single required field is missing' do
      let(:product) do
        build_product(metadata: {
          'plan_id' => 'test_v1',
          'tier' => 'basic',
          # Missing: region
        })
      end

      it 'raises ConfigError with missing field' do
        expect {
          described_class.call(product, price)
        }.to raise_error(Onetime::ConfigError, /missing: region/)
      end
    end

    context 'when required metadata fields are blank' do
      let(:product) do
        build_product(metadata: {
          'plan_id' => '',
          'tier' => '   ',
          'region' => 'US',
        })
      end

      it 'raises Onetime::ConfigError with blank fields' do
        expect {
          described_class.call(product, price)
        }.to raise_error(Onetime::ConfigError, /blank: plan_id, tier/)
      end
    end

    context 'when both missing and blank fields' do
      let(:product) do
        build_product(metadata: {
          'plan_id' => '',
          'tier' => 'basic',
          # Missing: region
        })
      end

      it 'includes both problems in error message' do
        expect {
          described_class.call(product, price)
        }.to raise_error(Onetime::ConfigError, /missing: region.*blank: plan_id|blank: plan_id.*missing: region/)
      end
    end

    context 'when metadata is valid' do
      let(:product) { build_product }

      it 'does not raise' do
        expect { described_class.call(product, price) }.not_to raise_error
      end
    end

    context 'when metadata is nil' do
      let(:product) do
        p = build_product
        allow(p).to receive(:metadata).and_return(nil)
        p
      end

      it 'raises ConfigError for all required fields missing' do
        expect {
          described_class.call(product, price)
        }.to raise_error(Onetime::ConfigError, /missing: plan_id, tier, region/)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # extract_tenancy (private method, tested via send)
  # ---------------------------------------------------------------------------

  describe '.extract_tenancy' do
    context 'when tenancy is specified' do
      let(:product) { build_product(metadata_merge: { 'tenancy' => 'single' }) }

      it 'returns the specified tenancy' do
        expect(extract(:extract_tenancy, product)).to eq('single')
      end
    end

    context 'when tenancy is nil' do
      let(:product) { build_product(metadata_merge: { 'tenancy' => nil }) }

      it 'defaults to multi' do
        expect(extract(:extract_tenancy, product)).to eq('multi')
      end
    end

    context 'when tenancy key is missing' do
      let(:product) do
        build_product(metadata: { 'plan_id' => 'test', 'tier' => 'basic', 'region' => 'US' })
      end

      it 'defaults to multi' do
        expect(extract(:extract_tenancy, product)).to eq('multi')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # extract_boolean (private method, tested via send)
  # ---------------------------------------------------------------------------

  describe '.extract_boolean' do
    context 'with truthy string values' do
      %w[true TRUE True 1 yes YES Yes].each do |value|
        it "returns true for '#{value}'" do
          product = build_product(metadata_merge: { 'show_on_plans_page' => value })
          result = extract(:extract_boolean, product, 'show_on_plans_page', default: false)
          expect(result).to be true
        end
      end
    end

    context 'with falsy string values' do
      %w[false FALSE False 0 no NO No nope anything_else].each do |value|
        it "returns false for '#{value}'" do
          product = build_product(metadata_merge: { 'show_on_plans_page' => value })
          result = extract(:extract_boolean, product, 'show_on_plans_page', default: true)
          expect(result).to be false
        end
      end
    end

    context 'with nil value' do
      let(:product) { build_product(metadata_merge: { 'show_on_plans_page' => nil }) }

      it 'returns default when true' do
        expect(extract(:extract_boolean, product, 'show_on_plans_page', default: true)).to be true
      end

      it 'returns default when false' do
        expect(extract(:extract_boolean, product, 'show_on_plans_page', default: false)).to be false
      end
    end

    context 'with empty string' do
      let(:product) { build_product(metadata_merge: { 'show_on_plans_page' => '' }) }

      it 'returns default' do
        expect(extract(:extract_boolean, product, 'show_on_plans_page', default: true)).to be true
      end
    end

    context 'with whitespace-only string' do
      let(:product) { build_product(metadata_merge: { 'show_on_plans_page' => '   ' }) }

      it 'returns default' do
        expect(extract(:extract_boolean, product, 'show_on_plans_page', default: false)).to be false
      end
    end
  end

  # ---------------------------------------------------------------------------
  # extract_optional_string (private method, tested via send)
  # ---------------------------------------------------------------------------

  describe '.extract_optional_string' do
    context 'with a non-empty value' do
      let(:product) { build_product(metadata_merge: { 'ots_plan_name_label' => 'For Teams' }) }

      it 'returns the value' do
        expect(extract(:extract_optional_string, product, 'ots_plan_name_label')).to eq('For Teams')
      end
    end

    context 'with nil value' do
      let(:product) { build_product(metadata_merge: { 'ots_plan_name_label' => nil }) }

      it 'returns nil' do
        expect(extract(:extract_optional_string, product, 'ots_plan_name_label')).to be_nil
      end
    end

    context 'with empty string' do
      let(:product) { build_product(metadata_merge: { 'ots_plan_name_label' => '' }) }

      it 'returns nil' do
        expect(extract(:extract_optional_string, product, 'ots_plan_name_label')).to be_nil
      end
    end

    context 'with whitespace-only string' do
      let(:product) { build_product(metadata_merge: { 'ots_plan_name_label' => '   ' }) }

      it 'returns nil' do
        expect(extract(:extract_optional_string, product, 'ots_plan_name_label')).to be_nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # extract_is_popular - fallback to billing.yaml (private method, tested via send)
  # ---------------------------------------------------------------------------

  describe '.extract_is_popular' do
    context 'when ots_is_popular is explicitly true' do
      let(:product) { build_product(metadata_merge: { 'ots_is_popular' => 'true' }) }

      it 'returns true' do
        expect(extract(:extract_is_popular, product)).to be true
      end
    end

    context 'when ots_is_popular is 1' do
      let(:product) { build_product(metadata_merge: { 'ots_is_popular' => '1' }) }

      it 'returns true' do
        expect(extract(:extract_is_popular, product)).to be true
      end
    end

    context 'when ots_is_popular is yes (case insensitive)' do
      let(:product) { build_product(metadata_merge: { 'ots_is_popular' => 'YES' }) }

      it 'returns true' do
        expect(extract(:extract_is_popular, product)).to be true
      end
    end

    context 'when ots_is_popular is explicitly false' do
      let(:product) { build_product(metadata_merge: { 'ots_is_popular' => 'false' }) }

      it 'returns false' do
        expect(extract(:extract_is_popular, product)).to be false
      end
    end

    context 'when ots_is_popular is 0' do
      let(:product) { build_product(metadata_merge: { 'ots_is_popular' => '0' }) }

      it 'returns false' do
        expect(extract(:extract_is_popular, product)).to be false
      end
    end

    context 'when ots_is_popular is nil (fallback to billing.yaml)' do
      # Default ots_plan_code from metadata_defaults is 'test_plan'
      let(:product) { build_product(metadata_merge: { 'ots_is_popular' => nil }) }

      context 'and billing.yaml has is_popular: true for plan_code' do
        before do
          allow(OT).to receive(:billing_config).and_return(
            double(
              stripe_key: 'sk_test_xxx',
              region: 'US',
              currency: 'usd',
              plans: { 'test_plan' => { 'is_popular' => true } },
            ),
          )
        end

        it 'returns true from config' do
          expect(extract(:extract_is_popular, product)).to be true
        end
      end

      context 'and billing.yaml has is_popular: false for plan_code' do
        before do
          allow(OT).to receive(:billing_config).and_return(
            double(
              stripe_key: 'sk_test_xxx',
              region: 'US',
              currency: 'usd',
              plans: { 'test_plan' => { 'is_popular' => false } },
            ),
          )
        end

        it 'returns false from config' do
          expect(extract(:extract_is_popular, product)).to be false
        end
      end

      context 'and billing.yaml has no entry for plan_code' do
        before do
          allow(OT).to receive(:billing_config).and_return(
            double(
              stripe_key: 'sk_test_xxx',
              region: 'US',
              currency: 'usd',
              plans: {},
            ),
          )
        end

        it 'returns false' do
          expect(extract(:extract_is_popular, product)).to be false
        end
      end

      context 'and billing.yaml has no is_popular key for plan_code' do
        before do
          allow(OT).to receive(:billing_config).and_return(
            double(
              stripe_key: 'sk_test_xxx',
              region: 'US',
              currency: 'usd',
              plans: { 'test_plan' => { 'tier' => 'premium' } },
            ),
          )
        end

        it 'returns false' do
          expect(extract(:extract_is_popular, product)).to be false
        end
      end
    end

    context 'when ots_is_popular is empty string (fallback)' do
      let(:product) { build_product(metadata_merge: { 'ots_is_popular' => '' }) }

      before do
        allow(OT).to receive(:billing_config).and_return(
          double(
            stripe_key: 'sk_test_xxx',
            region: 'US',
            currency: 'usd',
            plans: { 'test_plan' => { 'is_popular' => true } },
          ),
        )
      end

      it 'falls back to config' do
        expect(extract(:extract_is_popular, product)).to be true
      end
    end

    context 'when ots_is_popular is whitespace only (fallback)' do
      let(:product) { build_product(metadata_merge: { 'ots_is_popular' => '   ' }) }

      before do
        allow(OT).to receive(:billing_config).and_return(
          double(
            stripe_key: 'sk_test_xxx',
            region: 'US',
            currency: 'usd',
            plans: { 'test_plan' => { 'is_popular' => true } },
          ),
        )
      end

      it 'falls back to config' do
        expect(extract(:extract_is_popular, product)).to be true
      end
    end
  end

  # ---------------------------------------------------------------------------
  # extract_entitlements (private method, tested via send)
  # ---------------------------------------------------------------------------

  describe '.extract_entitlements' do
    context 'with comma-separated entitlements' do
      let(:product) do
        build_product(metadata_merge: { 'entitlements' => 'create_secrets,api_access,custom_domains' })
      end

      it 'splits into array' do
        result = extract(:extract_entitlements, product)
        expect(result).to eq(%w[create_secrets api_access custom_domains])
      end
    end

    context 'with whitespace around entries' do
      let(:product) do
        build_product(metadata_merge: { 'entitlements' => '  create_secrets , api_access , custom_domains  ' })
      end

      it 'strips whitespace' do
        result = extract(:extract_entitlements, product)
        expect(result).to eq(%w[create_secrets api_access custom_domains])
      end
    end

    context 'with empty entries from consecutive commas' do
      let(:product) do
        build_product(metadata_merge: { 'entitlements' => 'create_secrets,,api_access,' })
      end

      it 'rejects empty entries' do
        result = extract(:extract_entitlements, product)
        expect(result).to eq(%w[create_secrets api_access])
      end
    end

    context 'with whitespace-only entries' do
      let(:product) do
        build_product(metadata_merge: { 'entitlements' => 'create_secrets,   ,api_access' })
      end

      it 'rejects whitespace-only entries' do
        result = extract(:extract_entitlements, product)
        expect(result).to eq(%w[create_secrets api_access])
      end
    end

    context 'with nil entitlements' do
      let(:product) { build_product(metadata_merge: { 'entitlements' => nil }) }

      it 'returns empty array' do
        expect(extract(:extract_entitlements, product)).to eq([])
      end
    end

    context 'with missing entitlements key' do
      # Use metadata: to completely replace, excluding entitlements
      let(:product) do
        build_product(metadata: {
          'plan_id' => 'test_v1',
          'tier' => 'test',
          'region' => 'US',
        })
      end

      it 'returns empty array' do
        expect(extract(:extract_entitlements, product)).to eq([])
      end
    end

    context 'with empty string' do
      let(:product) { build_product(metadata_merge: { 'entitlements' => '' }) }

      it 'returns empty array' do
        expect(extract(:extract_entitlements, product)).to eq([])
      end
    end

    context 'with single entitlement' do
      let(:product) { build_product(metadata_merge: { 'entitlements' => 'create_secrets' }) }

      it 'returns single-element array' do
        expect(extract(:extract_entitlements, product)).to eq(['create_secrets'])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # extract_limits (private method, tested via send)
  # ---------------------------------------------------------------------------

  describe '.extract_limits' do
    context 'with numeric limit values' do
      let(:product) do
        build_product(metadata_merge: {
          'limit_secrets_per_day' => '100',
          'limit_teams' => '5',
          'limit_custom_domains' => '10',
        })
      end

      it 'extracts limits with resource names as symbols' do
        result = extract(:extract_limits, product)
        # Note: defaults also include limit_ fields, so we check for these specific ones
        expect(result[:secrets_per_day]).to eq(100)
        expect(result[:teams]).to eq(5)
        expect(result[:custom_domains]).to eq(10)
      end
    end

    context 'with unlimited value (-1)' do
      let(:product) do
        build_product(metadata_merge: { 'limit_custom_domains' => '-1' })
      end

      it 'normalizes to Float::INFINITY' do
        result = extract(:extract_limits, product)
        expect(result[:custom_domains]).to eq(Float::INFINITY)
      end
    end

    context 'with unlimited value (infinity string)' do
      let(:product) do
        build_product(metadata_merge: { 'limit_secrets_per_day' => 'infinity' })
      end

      it 'normalizes to Float::INFINITY' do
        result = extract(:extract_limits, product)
        expect(result[:secrets_per_day]).to eq(Float::INFINITY)
      end
    end

    context 'with INFINITY uppercase' do
      let(:product) do
        build_product(metadata_merge: { 'limit_secrets_per_day' => 'INFINITY' })
      end

      it 'normalizes to Float::INFINITY (case insensitive)' do
        result = extract(:extract_limits, product)
        expect(result[:secrets_per_day]).to eq(Float::INFINITY)
      end
    end

    context 'with zero value' do
      let(:product) do
        build_product(metadata_merge: { 'limit_teams' => '0' })
      end

      it 'converts to integer 0' do
        result = extract(:extract_limits, product)
        expect(result[:teams]).to eq(0)
      end
    end

    context 'with no limit_ prefixed fields' do
      # Use metadata: to completely replace, excluding limit_ fields
      let(:product) do
        build_product(metadata: {
          'plan_id' => 'test_v1',
          'tier' => 'test',
          'region' => 'US',
        })
      end

      it 'returns empty hash' do
        result = extract(:extract_limits, product)
        expect(result).to eq({})
      end
    end

    context 'ignores non-limit metadata' do
      let(:product) do
        build_product(metadata: {
          'plan_id' => 'test_v1',
          'tier' => 'premium',
          'region' => 'US',
          'app' => 'onetimesecret',
          'limit_teams' => '5',
          'non_limit_field' => 'ignored',
        })
      end

      it 'only extracts limit_ prefixed fields' do
        result = extract(:extract_limits, product)
        expect(result.keys).to eq([:teams])
      end
    end

    context 'with multiple limit fields' do
      let(:product) do
        build_product(metadata: {
          'plan_id' => 'test_v1',
          'tier' => 'test',
          'region' => 'US',
          'limit_teams' => '5',
          'limit_members_per_team' => '25',
          'limit_secret_lifetime' => '604800',
          'limit_secrets_per_day' => '-1',
        })
      end

      it 'extracts all limit fields' do
        result = extract(:extract_limits, product)
        expect(result).to eq({
          teams: 5,
          members_per_team: 25,
          secret_lifetime: 604_800,
          secrets_per_day: Float::INFINITY,
        })
      end
    end
  end

  # ---------------------------------------------------------------------------
  # build_stripe_snapshot (private method, tested via send)
  # ---------------------------------------------------------------------------

  describe '.build_stripe_snapshot' do
    let(:product) { build_product }
    let(:price) { build_price }
    let(:interval) { 'month' }

    it 'includes product section with expected fields' do
      result = extract(:build_stripe_snapshot, product, price, interval)

      expect(result[:product]).to include(
        id: 'prod_test123',
        name: 'Test Plan',
        currency: 'usd',
      )
    end

    it 'includes product metadata as hash' do
      result = extract(:build_stripe_snapshot, product, price, interval)

      expect(result[:product][:metadata]).to be_a(Hash)
      expect(result[:product][:metadata]['plan_id']).to eq('test_plan_v1')
    end

    it 'includes marketing_features as array of names' do
      result = extract(:build_stripe_snapshot, product, price, interval)

      expect(result[:product][:marketing_features]).to eq(['Feature One', 'Feature Two'])
    end

    it 'includes prices section keyed by interval' do
      result = extract(:build_stripe_snapshot, product, price, interval)

      expect(result[:prices]).to have_key(:month)
      expect(result[:prices][:month]).to include(
        id: 'price_test123',
        type: 'recurring',
        currency: 'usd',
        unit_amount: 1999,
      )
    end

    it 'includes recurring info in price' do
      result = extract(:build_stripe_snapshot, product, price, interval)

      expect(result[:prices][:month][:recurring]).to eq(interval: 'month')
    end

    it 'includes cached_at timestamp' do
      before_time = Time.now.to_i
      result = extract(:build_stripe_snapshot, product, price, interval)
      after_time = Time.now.to_i

      expect(result[:cached_at]).to be_between(before_time, after_time)
    end

    context 'with yearly interval' do
      let(:price) { build_price(recurring: { interval: 'year' }) }
      let(:interval) { 'year' }

      it 'keys prices by year' do
        result = extract(:build_stripe_snapshot, product, price, interval)

        expect(result[:prices]).to have_key(:year)
        expect(result[:prices][:year][:recurring][:interval]).to eq('year')
      end
    end

    context 'with nil marketing_features' do
      let(:product) { build_product(marketing_features: nil) }

      it 'defaults to empty array' do
        result = extract(:build_stripe_snapshot, product, price, interval)

        expect(result[:product][:marketing_features]).to eq([])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # build_price_data (private method, tested via send)
  # ---------------------------------------------------------------------------

  describe '.build_price_data' do
    let(:price) { build_price }

    it 'extracts stripe_price_id' do
      result = extract(:build_price_data, price)
      expect(result[:stripe_price_id]).to eq('price_test123')
    end

    it 'extracts amount as string' do
      result = extract(:build_price_data, price)
      expect(result[:amount]).to eq('1999')
    end

    it 'extracts currency' do
      result = extract(:build_price_data, price)
      expect(result[:currency]).to eq('usd')
    end

    it 'extracts billing_scheme' do
      result = extract(:build_price_data, price)
      expect(result[:billing_scheme]).to eq('per_unit')
    end

    it 'extracts usage_type from recurring' do
      result = extract(:build_price_data, price)
      expect(result[:usage_type]).to eq('licensed')
    end

    it 'extracts trial_period_days as string when present' do
      price = build_price(recurring: { trial_period_days: 14 })
      result = extract(:build_price_data, price)
      expect(result[:trial_period_days]).to eq('14')
    end

    it 'converts nil trial_period_days to empty string' do
      result = extract(:build_price_data, price)
      # .to_s on nil returns ""
      expect(result[:trial_period_days]).to eq('')
    end

    it 'extracts nickname' do
      result = extract(:build_price_data, price)
      expect(result[:nickname]).to eq('Monthly')
    end

    it 'extracts active as string' do
      result = extract(:build_price_data, price)
      expect(result[:active]).to eq('true')
    end

    context 'with inactive price' do
      let(:price) { build_price(active: false) }

      it 'returns active as false string' do
        result = extract(:build_price_data, price)
        expect(result[:active]).to eq('false')
      end
    end

    context 'with nil usage_type in recurring' do
      let(:price) { build_price(recurring: { usage_type: nil }) }

      it 'defaults usage_type to licensed' do
        result = extract(:build_price_data, price)
        expect(result[:usage_type]).to eq('licensed')
      end
    end

    context 'with metered usage_type' do
      let(:price) { build_price(recurring: { usage_type: 'metered' }) }

      it 'extracts metered usage_type' do
        result = extract(:build_price_data, price)
        expect(result[:usage_type]).to eq('metered')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Integration: full .call with various scenarios
  # ---------------------------------------------------------------------------

  describe '.call integration' do
    let(:price) { build_price }

    context 'with invalid product metadata' do
      let(:product) do
        build_product(metadata: {
          'app' => 'onetimesecret',
          'plan_id' => '',
          # Missing tier, region
        })
      end

      it 'raises ConfigError before extraction' do
        expect {
          described_class.call(product, price)
        }.to raise_error(Onetime::ConfigError)
      end
    end

    context 'with valid product' do
      let(:product) { build_product }

      before do
        allow(OT).to receive(:billing_config).and_return(
          double(
            stripe_key: 'sk_test_xxx',
            region: 'US',
            currency: 'usd',
            plans: {},
          ),
        )
      end

      it 'returns complete data hash' do
        result = described_class.call(product, price)

        expect(result[:plan_id]).to eq('test_plan_v1')
        expect(result[:name]).to eq('Test Plan')
        expect(result[:tier]).to eq('premium')
        expect(result[:entitlements]).to eq(%w[create_secrets api_access])
        expect(result[:limits]).to include(secrets_per_day: 100, teams: 5)
        expect(result[:limits][:custom_domains]).to eq(Float::INFINITY)
        expect(result[:features]).to eq(['Feature One', 'Feature Two'])
        expect(result[:prices][:month][:stripe_price_id]).to eq('price_test123')
      end
    end

    context 'with yearly price' do
      let(:product) { build_product }
      let(:yearly_price) { build_price(id: 'price_yearly', recurring: { interval: 'year' }) }

      before do
        allow(OT).to receive(:billing_config).and_return(
          double(stripe_key: 'sk_test_xxx', region: 'US', currency: 'usd', plans: {}),
        )
      end

      it 'keys prices by year interval' do
        result = described_class.call(product, yearly_price)

        expect(result[:prices]).to have_key(:year)
        expect(result[:prices]).not_to have_key(:month)
        expect(result[:prices][:year][:stripe_price_id]).to eq('price_yearly')
      end
    end

    context 'with minimal valid metadata' do
      let(:product) do
        build_product(metadata: {
          'plan_id' => 'minimal_v1',
          'tier' => 'free',
          'region' => 'US',
        })
      end

      before do
        allow(OT).to receive(:billing_config).and_return(
          double(stripe_key: 'sk_test_xxx', region: 'US', currency: 'usd', plans: {}),
        )
      end

      it 'extracts with defaults for missing optional fields' do
        result = described_class.call(product, price)

        expect(result[:plan_id]).to eq('minimal_v1')
        expect(result[:tenancy]).to eq('multi')           # default
        expect(result[:display_order]).to eq('0')         # default
        expect(result[:show_on_plans_page]).to eq('true') # default
        expect(result[:is_popular]).to eq('false')        # default
        expect(result[:entitlements]).to eq([])           # empty
        expect(result[:limits]).to eq({})                 # empty
      end
    end
  end
end
