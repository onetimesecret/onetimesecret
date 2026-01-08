# apps/web/billing/spec/models/plan_upsert_spec.rb
#
# frozen_string_literal: true

# Test cases for Billing::Plan upsert pattern (Issue #2354)
#
# This spec covers the catalog-first upsert approach that replaces
# the problematic clear+rebuild pattern. The upsert methods ensure:
# - Atomic plan updates without cache gaps
# - Idempotent operations for safe retries
# - Soft-delete of stale plans (not in current Stripe catalog)
#
# Run: pnpm run test:rspec apps/web/billing/spec/models/plan_upsert_spec.rb

require_relative '../support/billing_spec_helper'
require_relative '../../models/plan'

# Test data factory for creating plan data hashes
module PlanUpsertTestHelpers
  # Build a valid plan_data hash for upsert testing
  #
  # NOTE: The `limits` hash uses resource names WITHOUT the `.max` suffix.
  # The upsert_from_stripe_data method adds the `.max` suffix when storing.
  #
  # @param overrides [Hash] Fields to override in the default plan data
  # @return [Hash] Complete plan data hash ready for upsert_from_stripe_data
  def build_plan_data(overrides = {})
    unique_id = SecureRandom.hex(4)
    {
      plan_id: "test_plan_#{unique_id}_monthly",
      stripe_price_id: "price_test_#{SecureRandom.hex(8)}",
      stripe_product_id: "prod_test_#{SecureRandom.hex(8)}",
      name: 'Test Plan',
      tier: 'basic',
      interval: 'month',
      amount: '999',
      currency: 'usd',
      region: 'US',
      tenancy: 'multi',
      display_order: '100',
      show_on_plans_page: 'true',
      description: 'Test plan for upsert specs',
      active: 'true',
      billing_scheme: 'per_unit',
      usage_type: 'licensed',
      trial_period_days: nil,
      nickname: nil,
      plan_code: 'test_plan',
      is_popular: 'false',
      plan_name_label: nil,
      entitlements: %w[create_secrets view_secrets],
      features: ['Basic support'],
      # NOTE: Resource names without .max suffix - implementation adds it
      limits: { 'secrets' => '100', 'recipients' => '5' },
      stripe_snapshot: {
        product: { id: 'prod_xxx', name: 'Test', metadata: {} },
        price: { id: 'price_xxx', unit_amount: 999 },
        cached_at: Time.now.to_i,
      },
    }.merge(overrides)
  end

  # Build multiple plan data hashes with unique IDs
  #
  # @param count [Integer] Number of plan data hashes to create
  # @param base_overrides [Hash] Common overrides for all plans
  # @return [Array<Hash>] Array of plan data hashes
  def build_plan_data_batch(count, base_overrides = {})
    count.times.map do |i|
      build_plan_data(
        base_overrides.merge(
          plan_id: "batch_plan_#{i}_#{SecureRandom.hex(4)}_monthly",
          name: "Batch Plan #{i}",
        )
      )
    end
  end

  # Create and save a plan directly in Redis for test setup
  #
  # This bypasses upsert_from_stripe_data for setting up test fixtures.
  # Uses the same limits format as upsert_from_stripe_data (resource name without .max suffix).
  #
  # @param plan_data [Hash] Plan data hash (from build_plan_data)
  # @return [Billing::Plan] Saved plan instance
  def create_test_plan(plan_data)
    plan = Billing::Plan.new(
      plan_id: plan_data[:plan_id],
      stripe_price_id: plan_data[:stripe_price_id],
      stripe_product_id: plan_data[:stripe_product_id],
      name: plan_data[:name],
      tier: plan_data[:tier],
      interval: plan_data[:interval],
      amount: plan_data[:amount],
      currency: plan_data[:currency],
      region: plan_data[:region],
      tenancy: plan_data[:tenancy],
      display_order: plan_data[:display_order],
      show_on_plans_page: plan_data[:show_on_plans_page],
      description: plan_data[:description],
    )

    plan.active = plan_data[:active]
    plan.billing_scheme = plan_data[:billing_scheme]
    plan.usage_type = plan_data[:usage_type]
    plan.trial_period_days = plan_data[:trial_period_days]
    plan.nickname = plan_data[:nickname]
    plan.plan_code = plan_data[:plan_code]
    plan.is_popular = plan_data[:is_popular]
    plan.plan_name_label = plan_data[:plan_name_label]
    plan.last_synced_at = Time.now.to_i.to_s

    plan.entitlements.clear
    plan_data[:entitlements]&.each { |ent| plan.entitlements.add(ent) }

    plan.features.clear
    plan_data[:features]&.each { |feat| plan.features.add(feat) }

    # Store limits with .max suffix (same format as upsert_from_stripe_data output)
    plan.limits.clear
    plan_data[:limits]&.each do |resource, value|
      key = resource.to_s.end_with?('.max') ? resource.to_s : "#{resource}.max"
      plan.limits[key] = value.to_s
    end

    if plan_data[:stripe_snapshot]
      plan.stripe_data_snapshot.value = plan_data[:stripe_snapshot].to_json
    end

    plan.save
    plan
  end
end

RSpec.configure do |config|
  config.include PlanUpsertTestHelpers, type: :billing
end

# ==============================================================================
# SECTION 1: Plan.upsert_from_stripe_data - Creating New Plans
# ==============================================================================

RSpec.describe 'Billing::Plan.upsert_from_stripe_data', type: :billing do
  include PlanUpsertTestHelpers

  before do
    Billing::Plan.clear_cache
  end

  after do
    Billing::Plan.clear_cache
  end

  # --------------------------------------------------------------------------
  # Creating new plans
  # --------------------------------------------------------------------------

  describe 'creating new plan' do
    let(:plan_data) { build_plan_data }

    it 'creates Plan when plan_id not in catalog' do
      result = Billing::Plan.upsert_from_stripe_data(plan_data)

      expect(result).to be_a(Billing::Plan)
      expect(result.plan_id).to eq(plan_data[:plan_id])
      expect(Billing::Plan.instances.member?(plan_data[:plan_id])).to be true

      # Verify plan is loadable
      loaded = Billing::Plan.load(plan_data[:plan_id])
      expect(loaded).not_to be_nil
      expect(loaded.plan_id).to eq(plan_data[:plan_id])
    end

    it 'populates all scalar fields from plan_data' do
      plan = Billing::Plan.upsert_from_stripe_data(plan_data)

      expect(plan.name).to eq(plan_data[:name])
      expect(plan.tier).to eq(plan_data[:tier])
      expect(plan.interval).to eq(plan_data[:interval])
      expect(plan.amount).to eq(plan_data[:amount])
      expect(plan.currency).to eq(plan_data[:currency])
      expect(plan.region).to eq(plan_data[:region])
      expect(plan.tenancy).to eq(plan_data[:tenancy])
      expect(plan.display_order).to eq(plan_data[:display_order])
      expect(plan.show_on_plans_page).to eq(plan_data[:show_on_plans_page])
      expect(plan.description).to eq(plan_data[:description])
      expect(plan.active).to eq(plan_data[:active])
      expect(plan.billing_scheme).to eq(plan_data[:billing_scheme])
      expect(plan.usage_type).to eq(plan_data[:usage_type])
      expect(plan.plan_code).to eq(plan_data[:plan_code])
      expect(plan.is_popular).to eq(plan_data[:is_popular])
    end

    it 'populates entitlements set' do
      plan = Billing::Plan.upsert_from_stripe_data(plan_data)
      entitlements = plan.entitlements.to_a

      expect(entitlements).to include('create_secrets')
      expect(entitlements).to include('view_secrets')
      expect(entitlements.size).to eq(2)
    end

    it 'populates features set' do
      plan = Billing::Plan.upsert_from_stripe_data(plan_data)
      features = plan.features.to_a

      expect(features).to include('Basic support')
      expect(features.size).to eq(1)
    end

    it 'populates limits hash with flattened keys' do
      plan = Billing::Plan.upsert_from_stripe_data(plan_data)

      # Implementation adds .max suffix to resource names
      expect(plan.limits['secrets.max']).to eq('100')
      expect(plan.limits['recipients.max']).to eq('5')
    end

    it 'saves stripe_data_snapshot' do
      plan = Billing::Plan.upsert_from_stripe_data(plan_data)
      snapshot = plan.parsed_stripe_snapshot

      expect(snapshot).to be_a(Hash)
      expect(snapshot['product']).to include('id' => 'prod_xxx')
      expect(snapshot['price']).to include('id' => 'price_xxx')
    end

    it 'sets last_synced_at timestamp' do
      before_time = Time.now.to_i
      plan = Billing::Plan.upsert_from_stripe_data(plan_data)
      after_time = Time.now.to_i

      sync_time = plan.last_synced_at.to_i
      expect(sync_time).to be_between(before_time, after_time)
    end

    it 'adds plan to instances sorted set' do
      Billing::Plan.upsert_from_stripe_data(plan_data)

      plan_ids = Billing::Plan.list_plans.map(&:plan_id)
      expect(plan_ids).to include(plan_data[:plan_id])
    end
  end

  # --------------------------------------------------------------------------
  # Updating existing plans
  # --------------------------------------------------------------------------

  describe 'updating existing plan' do
    let(:original_data) { build_plan_data(name: 'Original Name', amount: '999') }
    let!(:existing_plan) { create_test_plan(original_data) }
    let(:updated_data) do
      original_data.merge(
        name: 'Updated Name',
        amount: '1999',
        entitlements: %w[create_secrets view_secrets api_access],
        features: ['Basic support', 'Priority email'],
        limits: { 'secrets' => '500', 'recipients' => '10' }
      )
    end

    it 'updates Plan when plan_id exists' do
      Billing::Plan.upsert_from_stripe_data(updated_data)
      plan = Billing::Plan.load(original_data[:plan_id])

      expect(plan.name).to eq('Updated Name')
    end

    it 'preserves plan_id (immutable)' do
      result = Billing::Plan.upsert_from_stripe_data(updated_data)

      expect(result.plan_id).to eq(original_data[:plan_id])

      # Verify no duplicate was created
      plan = Billing::Plan.load(original_data[:plan_id])
      expect(plan.plan_id).to eq(original_data[:plan_id])
    end

    it 'updates all mutable fields' do
      Billing::Plan.upsert_from_stripe_data(updated_data)
      plan = Billing::Plan.load(original_data[:plan_id])

      expect(plan.name).to eq('Updated Name')
      expect(plan.amount).to eq('1999')
    end

    it 'replaces entitlements set completely' do
      Billing::Plan.upsert_from_stripe_data(updated_data)
      plan = Billing::Plan.load(original_data[:plan_id])

      entitlements = plan.entitlements.to_a.sort
      expect(entitlements).to eq(%w[api_access create_secrets view_secrets])
    end

    it 'replaces features set completely' do
      Billing::Plan.upsert_from_stripe_data(updated_data)
      plan = Billing::Plan.load(original_data[:plan_id])

      features = plan.features.to_a.sort
      expect(features).to eq(['Basic support', 'Priority email'])
    end

    it 'replaces limits hash completely' do
      Billing::Plan.upsert_from_stripe_data(updated_data)
      plan = Billing::Plan.load(original_data[:plan_id])

      expect(plan.limits['secrets.max']).to eq('500')
      expect(plan.limits['recipients.max']).to eq('10')
    end

    it 'updates stripe_data_snapshot' do
      # Ensure different snapshot data
      new_snapshot = {
        product: { id: 'prod_updated', name: 'Updated', metadata: {} },
        price: { id: 'price_updated', unit_amount: 1999 },
        cached_at: Time.now.to_i,
      }
      updated_with_snapshot = updated_data.merge(stripe_snapshot: new_snapshot)

      Billing::Plan.upsert_from_stripe_data(updated_with_snapshot)
      plan = Billing::Plan.load(original_data[:plan_id])

      snapshot = plan.parsed_stripe_snapshot
      expect(snapshot['product']['id']).to eq('prod_updated')
    end

    it 'updates last_synced_at' do
      old_sync = existing_plan.last_synced_at.to_i
      sleep 0.1 # Ensure time difference

      Billing::Plan.upsert_from_stripe_data(updated_data)
      plan = Billing::Plan.load(original_data[:plan_id])

      expect(plan.last_synced_at.to_i).to be >= old_sync
    end
  end

  # --------------------------------------------------------------------------
  # Idempotency
  # --------------------------------------------------------------------------

  describe 'idempotency' do
    let(:plan_data) { build_plan_data }

    it 'produces same result when called multiple times with same data' do
      plan1 = Billing::Plan.upsert_from_stripe_data(plan_data)
      plan2 = Billing::Plan.upsert_from_stripe_data(plan_data)
      plan3 = Billing::Plan.upsert_from_stripe_data(plan_data)

      expect(plan1.plan_id).to eq(plan2.plan_id)
      expect(plan2.plan_id).to eq(plan3.plan_id)
      expect(plan1.name).to eq(plan3.name)
    end

    it 'does not create duplicate instances entries' do
      3.times { Billing::Plan.upsert_from_stripe_data(plan_data) }

      matching_plans = Billing::Plan.list_plans.select do |p|
        p.plan_id == plan_data[:plan_id]
      end
      expect(matching_plans.size).to eq(1)
    end
  end

  # --------------------------------------------------------------------------
  # Edge cases
  # --------------------------------------------------------------------------

  describe 'edge cases' do
    it 'handles nil entitlements gracefully' do
      data = build_plan_data(entitlements: nil)
      plan = Billing::Plan.upsert_from_stripe_data(data)

      expect(plan.entitlements.to_a).to eq([])
    end

    it 'handles empty features array' do
      data = build_plan_data(features: [])
      plan = Billing::Plan.upsert_from_stripe_data(data)

      expect(plan.features.to_a).to eq([])
    end

    it 'handles missing optional fields' do
      data = build_plan_data(
        trial_period_days: nil,
        nickname: nil,
        plan_name_label: nil,
        description: nil
      )
      plan = Billing::Plan.upsert_from_stripe_data(data)

      expect(plan.trial_period_days).to be_nil
      expect(plan.nickname).to be_nil
      expect(plan.plan_name_label).to be_nil
      expect(plan.description).to be_nil
    end

    it 'handles limits with unlimited value' do
      # The implementation converts -1 to 'unlimited' string when storing
      data = build_plan_data(
        limits: { 'secrets' => -1, 'recipients' => 'unlimited' }
      )
      plan = Billing::Plan.upsert_from_stripe_data(data)

      # Check raw storage (string values)
      expect(plan.limits['secrets.max']).to eq('unlimited')
      expect(plan.limits['recipients.max']).to eq('unlimited')

      # Check parsed limits_hash (converts to Float::INFINITY)
      expect(plan.limits_hash['secrets.max']).to eq(Float::INFINITY)
      expect(plan.limits_hash['recipients.max']).to eq(Float::INFINITY)
    end
  end
end

# ==============================================================================
# SECTION 2: Plan.prune_stale_plans
# ==============================================================================

RSpec.describe 'Billing::Plan.prune_stale_plans', type: :billing do
  include PlanUpsertTestHelpers

  before do
    Billing::Plan.clear_cache
  end

  after do
    Billing::Plan.clear_cache
  end

  # --------------------------------------------------------------------------
  # Identifying stale plans
  # --------------------------------------------------------------------------

  describe 'identifying stale plans' do
    let!(:active_plan1) { create_test_plan(build_plan_data(plan_id: 'active_plan_1_monthly')) }
    let!(:active_plan2) { create_test_plan(build_plan_data(plan_id: 'active_plan_2_monthly')) }
    let!(:stale_plan) { create_test_plan(build_plan_data(plan_id: 'stale_plan_monthly')) }

    it 'marks plans not in current_plan_ids as inactive' do
      current_ids = %w[active_plan_1_monthly active_plan_2_monthly]
      Billing::Plan.prune_stale_plans(current_ids)

      stale = Billing::Plan.load('stale_plan_monthly')
      expect(stale.active).to eq('false')
    end

    it 'preserves plans that are in current_plan_ids' do
      current_ids = %w[active_plan_1_monthly active_plan_2_monthly]
      Billing::Plan.prune_stale_plans(current_ids)

      plan1 = Billing::Plan.load('active_plan_1_monthly')
      plan2 = Billing::Plan.load('active_plan_2_monthly')
      expect(plan1.active).to eq('true')
      expect(plan2.active).to eq('true')
    end

    it 'handles empty current_plan_ids (marks all stale)' do
      Billing::Plan.prune_stale_plans([])

      Billing::Plan.list_plans.each do |plan|
        expect(plan.active).to eq('false')
      end
    end
  end

  # --------------------------------------------------------------------------
  # Handling expired entries (orphan cleanup)
  # --------------------------------------------------------------------------

  describe 'handling expired entries' do
    it 'removes instances entry when plan hash expired' do
      # Setup: Create orphan entry in instances set (no corresponding plan data)
      Billing::Plan.instances.add('orphan_plan_monthly')

      # Verify orphan exists
      expect(Billing::Plan.instances.member?('orphan_plan_monthly')).to be true

      Billing::Plan.prune_stale_plans([])

      # Orphan entry should be removed
      expect(Billing::Plan.instances.member?('orphan_plan_monthly')).to be false
    end

    it 'does not raise Familia::NoIdentifier' do
      # Setup: Create orphan entry
      Billing::Plan.instances.add('ghost_plan_monthly')

      expect {
        Billing::Plan.prune_stale_plans([])
      }.not_to raise_error
    end

    it 'counts orphan cleanup in pruned total' do
      # Setup: Create orphan entry
      Billing::Plan.instances.add('orphan_plan_monthly')

      count = Billing::Plan.prune_stale_plans([])
      expect(count).to eq(1)
    end
  end

  # --------------------------------------------------------------------------
  # Soft-delete behavior
  # --------------------------------------------------------------------------

  describe 'soft-delete behavior' do
    let!(:stale_plan) { create_test_plan(build_plan_data(plan_id: 'soft_delete_test_monthly', name: 'Soft Delete Test')) }

    it 'sets active=false instead of destroying' do
      Billing::Plan.prune_stale_plans([])

      plan = Billing::Plan.load('soft_delete_test_monthly')
      expect(plan).not_to be_nil
      expect(plan.exists?).to be true
      expect(plan.active).to eq('false')
    end

    it 'keeps soft-deleted plan queryable by plan_id' do
      Billing::Plan.prune_stale_plans([])

      plan = Billing::Plan.load('soft_delete_test_monthly')
      expect(plan.plan_id).to eq('soft_delete_test_monthly')
      expect(plan.name).to eq('Soft Delete Test')
    end
  end

  # --------------------------------------------------------------------------
  # Return value and logging
  # --------------------------------------------------------------------------

  describe 'return value and logging' do
    let!(:plan1) { create_test_plan(build_plan_data(plan_id: 'keep_me_monthly')) }
    let!(:plan2) { create_test_plan(build_plan_data(plan_id: 'prune_me_monthly')) }

    it 'returns count of pruned plans' do
      count = Billing::Plan.prune_stale_plans(['keep_me_monthly'])
      expect(count).to eq(1)
    end

    it 'returns zero when no plans are stale' do
      count = Billing::Plan.prune_stale_plans(%w[keep_me_monthly prune_me_monthly])
      expect(count).to eq(0)
    end
  end
end

# ==============================================================================
# SECTION 3: Integration - Upsert + Prune Together
# ==============================================================================

RSpec.describe 'Plan upsert + prune integration', type: :billing do
  include PlanUpsertTestHelpers

  before do
    Billing::Plan.clear_cache
  end

  after do
    Billing::Plan.clear_cache
  end

  describe 'full sync workflow' do
    it 'upserts new plans and prunes missing ones atomically' do
      # Step 1: Create initial plans
      plan1 = build_plan_data(plan_id: 'plan_a_monthly')
      plan2 = build_plan_data(plan_id: 'plan_b_monthly')
      Billing::Plan.upsert_from_stripe_data(plan1)
      Billing::Plan.upsert_from_stripe_data(plan2)

      # Verify initial state
      expect(Billing::Plan.list_plans.size).to eq(2)

      # Step 2: Simulate Stripe sync with different plans
      # - plan_a updated
      # - plan_b removed (not in new catalog)
      # - plan_c added
      new_plan1 = build_plan_data(plan_id: 'plan_a_monthly', name: 'Updated A')
      new_plan3 = build_plan_data(plan_id: 'plan_c_monthly')

      Billing::Plan.upsert_from_stripe_data(new_plan1)
      Billing::Plan.upsert_from_stripe_data(new_plan3)
      Billing::Plan.prune_stale_plans(%w[plan_a_monthly plan_c_monthly])

      # Verify results
      plan_a = Billing::Plan.load('plan_a_monthly')
      plan_b = Billing::Plan.load('plan_b_monthly')
      plan_c = Billing::Plan.load('plan_c_monthly')

      expect(plan_a.name).to eq('Updated A')
      expect(plan_a.active).to eq('true')
      expect(plan_b.active).to eq('false') # Pruned (soft-deleted)
      expect(plan_c.active).to eq('true')  # New
    end

    it 'handles reactivation of previously pruned plan' do
      # Create and prune a plan
      plan_data = build_plan_data(plan_id: 'reactivate_me_monthly')
      Billing::Plan.upsert_from_stripe_data(plan_data)
      Billing::Plan.prune_stale_plans([])

      plan = Billing::Plan.load('reactivate_me_monthly')
      expect(plan.active).to eq('false')

      # Reactivate via upsert with active=true
      reactivate_data = plan_data.merge(active: 'true')
      Billing::Plan.upsert_from_stripe_data(reactivate_data)

      plan = Billing::Plan.load('reactivate_me_monthly')
      expect(plan.active).to eq('true')
    end
  end
end

# ==============================================================================
# SECTION 4: Shared Examples for Upsert Behavior
# ==============================================================================

RSpec.shared_examples 'upsert scalar field' do |field_name, initial_value, updated_value|
  include PlanUpsertTestHelpers

  it "updates #{field_name} on existing plan" do
    original_data = build_plan_data(field_name => initial_value)
    Billing::Plan.upsert_from_stripe_data(original_data)

    updated_data = original_data.merge(field_name => updated_value)
    result = Billing::Plan.upsert_from_stripe_data(updated_data)

    expect(result.send(field_name)).to eq(updated_value)
  end
end

RSpec.shared_examples 'upsert collection field' do |collection_name|
  include PlanUpsertTestHelpers

  it "replaces #{collection_name} completely on update" do
    original_data = build_plan_data(collection_name => %w[item1 item2])
    Billing::Plan.upsert_from_stripe_data(original_data)

    updated_data = original_data.merge(collection_name => %w[item3 item4])
    result = Billing::Plan.upsert_from_stripe_data(updated_data)

    items = result.send(collection_name).to_a
    expect(items).to include('item3', 'item4')
    expect(items).not_to include('item1', 'item2')
  end

  it "handles empty #{collection_name}" do
    data = build_plan_data(collection_name => [])
    result = Billing::Plan.upsert_from_stripe_data(data)

    expect(result.send(collection_name).to_a).to eq([])
  end

  it "handles nil #{collection_name}" do
    data = build_plan_data(collection_name => nil)
    result = Billing::Plan.upsert_from_stripe_data(data)

    expect(result.send(collection_name).to_a).to eq([])
  end
end

RSpec.describe 'Billing::Plan upsert field behaviors', type: :billing do
  before { Billing::Plan.clear_cache }
  after { Billing::Plan.clear_cache }

  describe 'scalar fields' do
    it_behaves_like 'upsert scalar field', :name, 'Original', 'Updated'
    it_behaves_like 'upsert scalar field', :amount, '999', '1999'
    it_behaves_like 'upsert scalar field', :tier, 'basic', 'premium'
    it_behaves_like 'upsert scalar field', :description, 'Old desc', 'New desc'
  end

  describe 'collection fields' do
    it_behaves_like 'upsert collection field', :entitlements
    it_behaves_like 'upsert collection field', :features
  end
end

# ==============================================================================
# SECTION 5: TTL Expiration Scenarios (P0 Tests - Issue #2354)
# ==============================================================================
#
# These tests verify correct behavior when Plan Redis keys expire via TTL
# but the instances sorted set entries persist (the root cause of
# Familia::NoIdentifier errors in the original clear+rebuild pattern).
#
# The upsert pattern handles this gracefully, but we need to verify that
# lookup methods return appropriate values (nil/empty) rather than raising.

RSpec.describe 'Expired catalog handling', type: :billing do
  include PlanUpsertTestHelpers

  before do
    Billing::Plan.clear_cache
    # Reset the price ID cache to ensure fresh lookups
    Billing::Plan.instance_variable_set(:@stripe_price_id_cache, nil)
  end

  after do
    Billing::Plan.clear_cache
  end

  # --------------------------------------------------------------------------
  # find_by_stripe_price_id with expired plans
  # --------------------------------------------------------------------------

  describe 'find_by_stripe_price_id' do
    context 'when plan hash has expired but instances entry persists' do
      let(:price_id) { 'price_expired_test_123' }
      let(:plan_id) { 'expired_plan_monthly' }

      before do
        # Simulate expired state: instances entry exists, but plan hash is gone
        # This is the exact state that caused Familia::NoIdentifier errors
        Billing::Plan.instances.add(plan_id)

        # Rebuild cache to pick up the orphan entry
        # The cache builder should handle missing plan data gracefully
        Billing::Plan.rebuild_stripe_price_id_cache
      end

      it 'returns nil for expired plan' do
        # The cache should not contain a mapping for a price_id
        # that belonged to an expired plan
        result = Billing::Plan.find_by_stripe_price_id(price_id)
        expect(result).to be_nil
      end

      it 'does not raise Familia::NoIdentifier' do
        expect {
          Billing::Plan.find_by_stripe_price_id(price_id)
        }.not_to raise_error
      end
    end

    context 'when plan exists and is valid' do
      let(:plan_data) { build_plan_data(stripe_price_id: 'price_valid_123') }

      before do
        create_test_plan(plan_data)
        Billing::Plan.rebuild_stripe_price_id_cache
      end

      it 'returns the plan for valid price_id' do
        result = Billing::Plan.find_by_stripe_price_id('price_valid_123')
        expect(result).not_to be_nil
        expect(result.stripe_price_id).to eq('price_valid_123')
      end
    end

    context 'when cache is rebuilt after expiration' do
      let(:plan_data) { build_plan_data(stripe_price_id: 'price_will_expire_456') }

      before do
        # Create valid plan and cache it
        plan = create_test_plan(plan_data)
        Billing::Plan.rebuild_stripe_price_id_cache

        # Simulate expiration: delete plan hash but keep instances entry
        # This mimics Redis TTL expiration of individual keys
        plan.destroy!

        # Force cache rebuild to test it handles missing plans
        Billing::Plan.instance_variable_set(:@stripe_price_id_cache, nil)
      end

      it 'returns nil after plan expires and cache rebuilds' do
        result = Billing::Plan.find_by_stripe_price_id('price_will_expire_456')
        expect(result).to be_nil
      end
    end
  end

  # --------------------------------------------------------------------------
  # list_plans with expired plans
  # --------------------------------------------------------------------------

  describe 'list_plans' do
    context 'when all plan hashes have expired' do
      before do
        # Add orphan entries to instances (simulating TTL expiration)
        Billing::Plan.instances.add('orphan_plan_1_monthly')
        Billing::Plan.instances.add('orphan_plan_2_monthly')
      end

      it 'returns empty array when all plans expired' do
        # load_multi should handle missing plans gracefully
        result = Billing::Plan.list_plans
        expect(result).to eq([])
      end

      it 'does not raise Familia::NoIdentifier' do
        expect {
          Billing::Plan.list_plans
        }.not_to raise_error
      end
    end

    context 'when some plans have expired' do
      let(:valid_plan_data) { build_plan_data(plan_id: 'valid_plan_monthly') }

      before do
        # Create one valid plan
        create_test_plan(valid_plan_data)

        # Add orphan entry (simulating one expired plan)
        Billing::Plan.instances.add('orphan_plan_monthly')
      end

      it 'returns only valid plans' do
        result = Billing::Plan.list_plans
        plan_ids = result.map(&:plan_id)

        expect(plan_ids).to include('valid_plan_monthly')
        expect(plan_ids).not_to include('orphan_plan_monthly')
      end

      it 'filters out expired plans without raising' do
        expect {
          result = Billing::Plan.list_plans
          expect(result.size).to eq(1)
        }.not_to raise_error
      end
    end

    context 'when catalog is completely empty' do
      it 'returns empty array' do
        result = Billing::Plan.list_plans
        expect(result).to eq([])
      end
    end
  end

  # --------------------------------------------------------------------------
  # Catalog state after TTL expiration
  # --------------------------------------------------------------------------

  describe 'catalog state consistency' do
    context 'after plan TTL expiration' do
      let(:plan_data) do
        build_plan_data(
          plan_id: 'ttl_test_plan_monthly',
          stripe_price_id: 'price_ttl_test_789'
        )
      end

      before do
        # Create plan and verify it's accessible
        plan = create_test_plan(plan_data)
        Billing::Plan.rebuild_stripe_price_id_cache

        expect(Billing::Plan.find_by_stripe_price_id('price_ttl_test_789')).not_to be_nil
        expect(Billing::Plan.list_plans.map(&:plan_id)).to include('ttl_test_plan_monthly')

        # Simulate TTL expiration: destroy plan hash
        plan.destroy!

        # Reset cache to force rebuild
        Billing::Plan.instance_variable_set(:@stripe_price_id_cache, nil)
      end

      it 'find_by_stripe_price_id returns nil' do
        expect(Billing::Plan.find_by_stripe_price_id('price_ttl_test_789')).to be_nil
      end

      it 'list_plans excludes expired plan' do
        expect(Billing::Plan.list_plans.map(&:plan_id)).not_to include('ttl_test_plan_monthly')
      end

      it 'upsert_from_stripe_data can recreate the plan' do
        # The upsert pattern should handle re-creation gracefully
        new_plan = Billing::Plan.upsert_from_stripe_data(plan_data)

        expect(new_plan.plan_id).to eq('ttl_test_plan_monthly')
        expect(new_plan.exists?).to be true
      end

      it 'after upsert, plan is accessible again' do
        Billing::Plan.upsert_from_stripe_data(plan_data)
        Billing::Plan.rebuild_stripe_price_id_cache

        expect(Billing::Plan.find_by_stripe_price_id('price_ttl_test_789')).not_to be_nil
        expect(Billing::Plan.list_plans.map(&:plan_id)).to include('ttl_test_plan_monthly')
      end
    end
  end
end
