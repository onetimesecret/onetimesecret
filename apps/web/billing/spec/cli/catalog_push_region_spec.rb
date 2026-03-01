# apps/web/billing/spec/cli/catalog_push_region_spec.rb
#
# frozen_string_literal: true

# Tests for catalog push region isolation fixes (Issue #2554)
#
# Covers:
#   Bug #1 (P0): fetch_existing_products used raw != for region comparison
#   Bug #2 (P1): build_syncable_metadata wrote nil.to_s -> "" erasing Stripe metadata
#
# Run: bundle exec rspec apps/web/billing/spec/cli/catalog_push_region_spec.rb

require_relative '../support/billing_spec_helper'
require 'onetime/cli'
require_relative '../../cli/catalog_push_command'
require_relative '../../errors'

# ==============================================================================
# SECTION 1: build_syncable_metadata - nil region handling (Bug #2)
# ==============================================================================

RSpec.describe 'CatalogPushCommand#build_syncable_metadata region handling',
               :billing_cli, :integration do
  subject(:command) { Onetime::CLI::BillingCatalogPushCommand.new }

  let(:base_plan_def) do
    {
      'name' => 'Test Plan',
      'tier' => 'basic',
      'tenancy' => 'multi',
      'display_order' => 1,
      'show_on_plans_page' => true,
      'entitlements' => %w[create_secrets],
      'limits' => { 'teams' => 1 },
    }
  end

  describe 'region field in syncable metadata' do
    it 'excludes region field when plan region is nil' do
      plan_def = base_plan_def.merge('region' => nil)
      result = command.send(:build_syncable_metadata, plan_def)
      expect(result).not_to have_key('region')
    end

    it 'excludes region field when plan region is empty string' do
      plan_def = base_plan_def.merge('region' => '')
      result = command.send(:build_syncable_metadata, plan_def)
      expect(result).not_to have_key('region')
    end

    it 'excludes region field when plan region is whitespace' do
      plan_def = base_plan_def.merge('region' => '   ')
      result = command.send(:build_syncable_metadata, plan_def)
      expect(result).not_to have_key('region')
    end

    it 'normalizes lowercase region to uppercase' do
      plan_def = base_plan_def.merge('region' => 'nz')
      result = command.send(:build_syncable_metadata, plan_def)
      expect(result['region']).to eq('NZ')
    end

    it 'preserves already-uppercase region' do
      plan_def = base_plan_def.merge('region' => 'EU')
      result = command.send(:build_syncable_metadata, plan_def)
      expect(result['region']).to eq('EU')
    end

    it 'strips whitespace from region before normalizing' do
      plan_def = base_plan_def.merge('region' => ' ca ')
      result = command.send(:build_syncable_metadata, plan_def)
      expect(result['region']).to eq('CA')
    end
  end

  # This is the exact scenario that caused the P1 bug: nil.to_s produced ""
  # which was written back to Stripe, erasing existing region metadata.
  describe 'nil region does not produce empty string (regression)' do
    it 'never writes empty string for region field' do
      plan_def = base_plan_def.merge('region' => nil)
      result = command.send(:build_syncable_metadata, plan_def)

      # The key must either be absent or have a non-empty value
      if result.key?('region')
        expect(result['region']).not_to eq('')
        expect(result['region']).not_to be_nil
      end
    end
  end
end

# ==============================================================================
# SECTION 2: fetch_existing_products region filtering (Bug #1)
# ==============================================================================

RSpec.describe 'CatalogPushCommand#fetch_existing_products region filtering',
               :billing_cli, :integration do
  subject(:command) { Onetime::CLI::BillingCatalogPushCommand.new }

  def mock_stripe_product(id:, plan_id:, region:)
    metadata = {
      'app' => 'onetimesecret',
      'plan_id' => plan_id,
      'region' => region,
    }
    double("Stripe::Product(#{id})", id: id, name: "Plan #{plan_id}", metadata: metadata)
  end

  let(:match_fields) { ['plan_id'] }

  let(:nz_product) { mock_stripe_product(id: 'prod_nz', plan_id: 'identity_nz_v1', region: 'NZ') }
  let(:nz_lower_product) { mock_stripe_product(id: 'prod_nz2', plan_id: 'starter_v1', region: 'nz') }
  let(:eu_product) { mock_stripe_product(id: 'prod_eu', plan_id: 'identity_eu_v1', region: 'EU') }
  let(:no_region_product) { mock_stripe_product(id: 'prod_none', plan_id: 'legacy_v1', region: nil) }

  before do
    product_list = double('ProductList')
    allow(product_list).to receive(:auto_paging_each)
      .and_yield(nz_product)
      .and_yield(nz_lower_product)
      .and_yield(eu_product)
      .and_yield(no_region_product)
    allow(Stripe::Product).to receive(:list).and_return(product_list)
    allow(command).to receive(:with_stripe_retry).and_yield
  end

  it 'includes products matching region filter with same case' do
    result = command.send(:fetch_existing_products, 'onetimesecret', match_fields, 'NZ')
    product_ids = result.values.map(&:id)
    expect(product_ids).to include('prod_nz')
  end

  it 'includes products matching region filter case-insensitively (Bug #1 fix)' do
    # Product has region "nz" (lowercase), filter is "NZ" (uppercase)
    # Before the fix, raw != comparison would reject this product
    result = command.send(:fetch_existing_products, 'onetimesecret', match_fields, 'NZ')
    product_ids = result.values.map(&:id)
    expect(product_ids).to include('prod_nz2')
  end

  it 'excludes products from non-matching regions' do
    result = command.send(:fetch_existing_products, 'onetimesecret', match_fields, 'NZ')
    product_ids = result.values.map(&:id)
    expect(product_ids).not_to include('prod_eu')
  end

  it 'includes all products when region filter is nil (pass-through)' do
    result = command.send(:fetch_existing_products, 'onetimesecret', match_fields, nil)
    product_ids = result.values.map(&:id)
    expect(product_ids).to include('prod_nz', 'prod_nz2', 'prod_eu')
  end

  it 'matches lowercase filter against uppercase product region' do
    result = command.send(:fetch_existing_products, 'onetimesecret', match_fields, 'nz')
    product_ids = result.values.map(&:id)
    expect(product_ids).to include('prod_nz')
    expect(product_ids).not_to include('prod_eu')
  end

  it 'excludes products with nil region when filter is set (fail-closed)' do
    result = command.send(:fetch_existing_products, 'onetimesecret', match_fields, 'NZ')
    product_ids = result.values.map(&:id)
    expect(product_ids).not_to include('prod_none')
  end

  it 'includes products with nil region when filter is nil (pass-through)' do
    result = command.send(:fetch_existing_products, 'onetimesecret', match_fields, nil)
    product_ids = result.values.map(&:id)
    expect(product_ids).to include('prod_none')
  end
end
