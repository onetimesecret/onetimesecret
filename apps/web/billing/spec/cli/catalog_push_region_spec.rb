# apps/web/billing/spec/cli/catalog_push_region_spec.rb
#
# frozen_string_literal: true

# Tests for catalog push region isolation fixes (Issue #2554)
#
# NOTE: These tests now target Operations::Catalog::Push directly, as the
# CLI command is a thin wrapper. For CLI interface tests, see catalog_push_spec.rb.
#
# Region filtering tests (Bug #1) now target StripeReader since fetch_existing_products
# was extracted there. Metadata tests (Bug #2) remain on Push.
#
# Covers:
#   Bug #1 (P0): fetch_existing_products used raw != for region comparison
#   Bug #2 (P1): build_syncable_metadata wrote nil.to_s -> "" erasing Stripe metadata
#
# Run: bundle exec rspec apps/web/billing/spec/cli/catalog_push_region_spec.rb

require_relative '../support/billing_spec_helper'
require_relative '../../operations/catalog/push'
require_relative '../../operations/catalog/stripe_reader'

# ==============================================================================
# SECTION 1: build_syncable_metadata - nil region handling (Bug #2)
# ==============================================================================

RSpec.describe 'Catalog::Push region handling in metadata', :billing_cli do
  # Access the private method on the operation class instance
  let(:operation) { Billing::Operations::Catalog::Push.new(dry_run: true, plan_filter: nil, skip_prices: true, progress: nil) }

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
      result = operation.send(:build_syncable_metadata, 'test_plan', plan_def, 'cad')
      expect(result).not_to have_key('region')
    end

    it 'excludes region field when plan region is empty string' do
      plan_def = base_plan_def.merge('region' => '')
      result = operation.send(:build_syncable_metadata, 'test_plan', plan_def, 'cad')
      expect(result).not_to have_key('region')
    end

    it 'excludes region field when plan region is whitespace' do
      plan_def = base_plan_def.merge('region' => '   ')
      result = operation.send(:build_syncable_metadata, 'test_plan', plan_def, 'cad')
      expect(result).not_to have_key('region')
    end

    it 'normalizes lowercase region to uppercase' do
      plan_def = base_plan_def.merge('region' => 'nz')
      result = operation.send(:build_syncable_metadata, 'test_plan', plan_def, 'cad')
      expect(result['region']).to eq('NZ')
    end

    it 'preserves already-uppercase region' do
      plan_def = base_plan_def.merge('region' => 'EU')
      result = operation.send(:build_syncable_metadata, 'test_plan', plan_def, 'cad')
      expect(result['region']).to eq('EU')
    end

    it 'strips whitespace from region before normalizing' do
      plan_def = base_plan_def.merge('region' => ' ca ')
      result = operation.send(:build_syncable_metadata, 'test_plan', plan_def, 'cad')
      expect(result['region']).to eq('CA')
    end
  end

  # This is the exact scenario that caused the P1 bug: nil.to_s produced ""
  # which was written back to Stripe, erasing existing region metadata.
  describe 'nil region does not produce empty string (regression)' do
    it 'never writes empty string for region field' do
      plan_def = base_plan_def.merge('region' => nil)
      result = operation.send(:build_syncable_metadata, 'test_plan', plan_def, 'cad')

      # The key must either be absent or have a non-empty value
      if result.key?('region')
        expect(result['region']).not_to eq('')
        expect(result['region']).not_to be_nil
      end
    end
  end
end

# ==============================================================================
# SECTION 2: StripeReader.fetch_products region filtering (Bug #1)
# ==============================================================================

RSpec.describe 'StripeReader.fetch_products region filtering', :billing_cli do
  def mock_stripe_product(id:, plan_id:, region:)
    metadata = {
      'app' => 'onetimesecret',
      'plan_id' => plan_id,
      'region' => region,
    }
    double("Stripe::Product(#{id})", id: id, name: "Plan #{plan_id}", metadata: metadata)
  end

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
  end

  it 'includes products matching region filter with same case' do
    result = Billing::Operations::Catalog::StripeReader.fetch_products(
      app_identifier: 'onetimesecret',
      region_filter: 'NZ',
    )
    product_ids = result.values.map(&:id)
    expect(product_ids).to include('prod_nz')
  end

  it 'includes products matching region filter case-insensitively (Bug #1 fix)' do
    # Product has region "nz" (lowercase), filter is "NZ" (uppercase)
    # Before the fix, raw != comparison would reject this product
    result = Billing::Operations::Catalog::StripeReader.fetch_products(
      app_identifier: 'onetimesecret',
      region_filter: 'NZ',
    )
    product_ids = result.values.map(&:id)
    expect(product_ids).to include('prod_nz2')
  end

  it 'excludes products from non-matching regions' do
    result = Billing::Operations::Catalog::StripeReader.fetch_products(
      app_identifier: 'onetimesecret',
      region_filter: 'NZ',
    )
    product_ids = result.values.map(&:id)
    expect(product_ids).not_to include('prod_eu')
  end

  it 'includes all products when region filter is nil (pass-through)' do
    result = Billing::Operations::Catalog::StripeReader.fetch_products(
      app_identifier: 'onetimesecret',
      region_filter: nil,
    )
    product_ids = result.values.map(&:id)
    expect(product_ids).to include('prod_nz', 'prod_nz2', 'prod_eu')
  end

  it 'matches lowercase filter against uppercase product region' do
    result = Billing::Operations::Catalog::StripeReader.fetch_products(
      app_identifier: 'onetimesecret',
      region_filter: 'nz',
    )
    product_ids = result.values.map(&:id)
    expect(product_ids).to include('prod_nz')
    expect(product_ids).not_to include('prod_eu')
  end

  it 'excludes products with nil region when filter is set (fail-closed)' do
    result = Billing::Operations::Catalog::StripeReader.fetch_products(
      app_identifier: 'onetimesecret',
      region_filter: 'NZ',
    )
    product_ids = result.values.map(&:id)
    expect(product_ids).not_to include('prod_none')
  end

  it 'includes products with nil region when filter is nil (pass-through)' do
    result = Billing::Operations::Catalog::StripeReader.fetch_products(
      app_identifier: 'onetimesecret',
      region_filter: nil,
    )
    product_ids = result.values.map(&:id)
    expect(product_ids).to include('prod_none')
  end
end

# ==============================================================================
# SECTION 3: Override products bypass region filter (Issue #3157)
# ==============================================================================

RSpec.describe 'StripeReader override + region interaction', :billing_cli do
  def mock_stripe_product(id:, plan_id:, region:, app: 'onetimesecret')
    metadata = { 'app' => app, 'plan_id' => plan_id }
    metadata['region'] = region if region
    double("Stripe::Product(#{id})", id: id, name: "Plan #{plan_id}", metadata: metadata)
  end

  let(:match_fields) { ['plan_id'] }

  # Legacy product with explicit override but no region metadata
  let(:override_no_region) { mock_stripe_product(id: 'prod_override_legacy', plan_id: 'legacy_v1', region: nil) }
  # Product with app match but wrong region and no override
  let(:app_match_wrong_region) { mock_stripe_product(id: 'prod_wrong_region', plan_id: 'starter_v1', region: 'EU') }
  # Product with correct region for baseline
  let(:nz_product) { mock_stripe_product(id: 'prod_nz', plan_id: 'identity_v1', region: 'NZ') }

  # Override product IDs extracted from plans with stripe_product_id
  let(:override_product_ids) { Set.new(['prod_override_legacy']) }

  before do
    product_list = double('ProductList')
    allow(product_list).to receive(:auto_paging_each)
      .and_yield(override_no_region)
      .and_yield(app_match_wrong_region)
      .and_yield(nz_product)
    allow(Stripe::Product).to receive(:list).and_return(product_list)
  end

  it 'includes override product without region metadata when region filter is set (Issue #3157 fix)' do
    # Product has explicit stripe_product_id override but no region metadata
    # Before the fix, region filter would exclude this product
    result = Billing::Operations::Catalog::StripeReader.fetch_products(
      app_identifier: 'onetimesecret',
      region_filter: 'NZ',
      match_fields: match_fields,
      override_product_ids: override_product_ids,
    )
    product_ids = result.values.map(&:id)
    expect(product_ids).to include('prod_override_legacy')
  end

  it 'excludes app-matched products with wrong region when they have no override (regression)' do
    # Product matches app but has EU region while filter is NZ, and no override
    # This should still be filtered out (existing behavior preserved)
    result = Billing::Operations::Catalog::StripeReader.fetch_products(
      app_identifier: 'onetimesecret',
      region_filter: 'NZ',
      match_fields: match_fields,
      override_product_ids: override_product_ids,
    )
    product_ids = result.values.map(&:id)
    expect(product_ids).not_to include('prod_wrong_region')
  end

  it 'includes products with correct region as baseline' do
    result = Billing::Operations::Catalog::StripeReader.fetch_products(
      app_identifier: 'onetimesecret',
      region_filter: 'NZ',
      match_fields: match_fields,
      override_product_ids: override_product_ids,
    )
    product_ids = result.values.map(&:id)
    expect(product_ids).to include('prod_nz')
  end
end

# ==============================================================================
# SECTION 4: detect_product_updates detects missing plan_id (Issue #3157)
# ==============================================================================

RSpec.describe 'Catalog::Push detect_product_updates plan_id detection', :billing_cli do
  let(:operation) { Billing::Operations::Catalog::Push.new(dry_run: true, plan_filter: nil, skip_prices: true, progress: nil) }

  it 'detects missing plan_id as a change needing update' do
    # Product exists but lacks plan_id metadata
    existing = double('Stripe::Product',
      id: 'prod_legacy',
      name: 'Test Plan',
      metadata: { 'app' => 'onetimesecret', 'tier' => 'pro' }, # No plan_id
      marketing_features: []
    )

    plan_def = { 'name' => 'Test Plan', 'tier' => 'pro' }

    updates = operation.send(:detect_product_updates, 'test_plan', existing, plan_def, 'cad')

    expect(updates).to have_key(:metadata_plan_id)
    expect(updates[:metadata_plan_id][:from]).to be_nil
    expect(updates[:metadata_plan_id][:to]).to eq('test_plan')
  end

  it 'detects mismatched plan_id as a change needing update' do
    existing = double('Stripe::Product',
      id: 'prod_legacy',
      name: 'Test Plan',
      metadata: { 'app' => 'onetimesecret', 'plan_id' => 'old_plan_id' },
      marketing_features: []
    )

    plan_def = { 'name' => 'Test Plan', 'tier' => 'pro' }

    updates = operation.send(:detect_product_updates, 'new_plan_id', existing, plan_def, 'cad')

    expect(updates).to have_key(:metadata_plan_id)
    expect(updates[:metadata_plan_id][:from]).to eq('old_plan_id')
    expect(updates[:metadata_plan_id][:to]).to eq('new_plan_id')
  end

  it 'does not flag plan_id when it already matches' do
    existing = double('Stripe::Product',
      id: 'prod_current',
      name: 'Test Plan',
      metadata: { 'app' => 'onetimesecret', 'plan_id' => 'test_plan' },
      marketing_features: []
    )

    plan_def = { 'name' => 'Test Plan', 'tier' => 'pro' }

    updates = operation.send(:detect_product_updates, 'test_plan', existing, plan_def, 'cad')

    expect(updates).not_to have_key(:metadata_plan_id)
  end
end
