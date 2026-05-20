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
  # NOTE: Plan IDs are now family-keyed (no interval suffix). Price data is
  # stored in the nested `prices` hash keyed by interval (month/year).
  #
  # @param overrides [Hash] Fields to override in the default plan data
  # @return [Hash] Complete plan data hash ready for upsert_from_stripe_data
  def build_plan_data(overrides = {})
    unique_id = SecureRandom.hex(4)
    price_id = "price_test_#{SecureRandom.hex(8)}"
    {
      plan_id: "test_plan_#{unique_id}",
      stripe_product_id: "prod_test_#{SecureRandom.hex(8)}",
      name: 'Test Plan',
      tier: 'basic',
      currency: 'cad',
      region: 'US',
      tenancy: 'multi',
      display_order: '100',
      show_on_plans_page: 'true',
      description: 'Test plan for upsert specs',
      active: 'true',
      plan_code: 'test_plan',
      is_popular: 'false',
      plan_name_label: nil,
      entitlements: %w[create_secrets view_secrets],
      features: ['Basic support'],
      # NOTE: Resource names without .max suffix - implementation adds it
      limits: { 'secrets' => '100', 'recipients' => '5' },
      # Prices keyed by interval (new schema)
      prices: {
        month: {
          stripe_price_id: price_id,
          amount: '999',
          currency: 'cad',
          billing_scheme: 'per_unit',
          usage_type: 'licensed',
          trial_period_days: nil,
          nickname: nil,
          active: 'true',
        },
      },
      stripe_snapshot: {
        product: { id: 'prod_xxx', name: 'Test', metadata: {} },
        prices: {
          month: { id: price_id, unit_amount: 999 },
        },
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
          plan_id: "batch_plan_#{i}_#{SecureRandom.hex(4)}",
          name: "Batch Plan #{i}",
        )
      )
    end
  end

  # Create and save a plan directly in Redis for test setup
  #
  # This bypasses upsert_from_stripe_data for setting up test fixtures.
  # Uses the same limits format as upsert_from_stripe_data (resource name without .max suffix).
  # NOTE: Updated for family-keyed schema - prices stored in nested hashkey.
  #
  # @param plan_data [Hash] Plan data hash (from build_plan_data)
  # @return [Billing::Plan] Saved plan instance
  def create_test_plan(plan_data)
    plan = Billing::Plan.new(
      plan_id: plan_data[:plan_id],
      stripe_product_id: plan_data[:stripe_product_id],
      name: plan_data[:name],
      tier: plan_data[:tier],
      currency: plan_data[:currency],
      region: plan_data[:region],
      tenancy: plan_data[:tenancy],
      display_order: plan_data[:display_order],
      show_on_plans_page: plan_data[:show_on_plans_page],
      description: plan_data[:description],
    )

    plan.active = plan_data[:active]
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

    # Store prices keyed by interval (new schema)
    plan_data[:prices]&.each do |interval, price_data|
      plan.prices[interval.to_s] = price_data.to_json
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

      # Family-level fields
      expect(plan.name).to eq(plan_data[:name])
      expect(plan.tier).to eq(plan_data[:tier])
      expect(plan.currency).to eq(plan_data[:currency])
      expect(plan.region).to eq(plan_data[:region])
      expect(plan.tenancy).to eq(plan_data[:tenancy])
      expect(plan.display_order).to eq(plan_data[:display_order])
      expect(plan.show_on_plans_page).to eq(plan_data[:show_on_plans_page])
      expect(plan.description).to eq(plan_data[:description])
      expect(plan.active).to eq(plan_data[:active])
      expect(plan.plan_code).to eq(plan_data[:plan_code])
      expect(plan.is_popular).to eq(plan_data[:is_popular])

      # Price-level fields now in nested prices hash
      monthly_price = plan.prices_hash['month']
      expect(monthly_price).not_to be_nil
      expect(monthly_price['amount']).to eq('999')
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
      # New schema: prices keyed by interval
      expect(snapshot['prices']).to be_a(Hash)
      expect(snapshot['prices']['month']).to include('id')
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
    let(:original_data) { build_plan_data(name: 'Original Name') }
    let!(:existing_plan) { create_test_plan(original_data) }
    let(:updated_data) do
      original_data.merge(
        name: 'Updated Name',
        entitlements: %w[create_secrets view_secrets api_access],
        features: ['Basic support', 'Priority email'],
        limits: { 'secrets' => '500', 'recipients' => '10' },
        prices: {
          month: {
            stripe_price_id: 'price_updated',
            amount: '1999',
            currency: 'cad',
            billing_scheme: 'per_unit',
            usage_type: 'licensed',
            active: 'true',
          },
        },
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
      # Amount is now in nested prices hash
      expect(plan.prices_hash['month']['amount']).to eq('1999')
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
        plan_name_label: nil,
        description: nil
      )
      plan = Billing::Plan.upsert_from_stripe_data(data)

      # Family-level optional fields
      expect(plan.plan_name_label).to be_nil
      expect(plan.description).to be_nil
      # NOTE: trial_period_days and nickname are now in nested prices hash
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
    let!(:active_plan1) { create_test_plan(build_plan_data(plan_id: 'active_plan_1')) }
    let!(:active_plan2) { create_test_plan(build_plan_data(plan_id: 'active_plan_2')) }
    let!(:stale_plan) { create_test_plan(build_plan_data(plan_id: 'stale_plan')) }

    it 'marks plans not in current_plan_ids as inactive' do
      current_ids = %w[active_plan_1 active_plan_2]
      Billing::Plan.prune_stale_plans(current_ids)

      stale = Billing::Plan.load('stale_plan')
      expect(stale.active).to eq('false')
    end

    it 'preserves plans that are in current_plan_ids' do
      current_ids = %w[active_plan_1 active_plan_2]
      Billing::Plan.prune_stale_plans(current_ids)

      plan1 = Billing::Plan.load('active_plan_1')
      plan2 = Billing::Plan.load('active_plan_2')
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
  # Handling orphaned entries (missing plan hash cleanup)
  # --------------------------------------------------------------------------

  describe 'handling orphaned entries' do
    it 'removes instances entry when plan hash is missing' do
      # Setup: Create orphan entry in instances set (no corresponding plan data)
      Billing::Plan.instances.add('orphan_plan')

      # Verify orphan exists
      expect(Billing::Plan.instances.member?('orphan_plan')).to be true

      Billing::Plan.prune_stale_plans([])

      # Orphan entry should be removed
      expect(Billing::Plan.instances.member?('orphan_plan')).to be false
    end

    it 'does not raise Familia::NoIdentifier' do
      # Setup: Create orphan entry
      Billing::Plan.instances.add('ghost_plan')

      expect {
        Billing::Plan.prune_stale_plans([])
      }.not_to raise_error
    end

    it 'counts orphan cleanup in pruned total' do
      # Setup: Create orphan entry
      Billing::Plan.instances.add('orphan_plan')

      count = Billing::Plan.prune_stale_plans([])
      expect(count).to eq(1)
    end
  end

  # --------------------------------------------------------------------------
  # Soft-delete behavior
  # --------------------------------------------------------------------------

  describe 'soft-delete behavior' do
    let!(:stale_plan) { create_test_plan(build_plan_data(plan_id: 'soft_delete_test', name: 'Soft Delete Test')) }

    it 'sets active=false instead of destroying' do
      Billing::Plan.prune_stale_plans([])

      plan = Billing::Plan.load('soft_delete_test')
      expect(plan).not_to be_nil
      expect(plan.exists?).to be true
      expect(plan.active).to eq('false')
    end

    it 'keeps soft-deleted plan queryable by plan_id' do
      Billing::Plan.prune_stale_plans([])

      plan = Billing::Plan.load('soft_delete_test')
      expect(plan.plan_id).to eq('soft_delete_test')
      expect(plan.name).to eq('Soft Delete Test')
    end
  end

  # --------------------------------------------------------------------------
  # Return value and logging
  # --------------------------------------------------------------------------

  describe 'return value and logging' do
    let!(:plan1) { create_test_plan(build_plan_data(plan_id: 'keep_me')) }
    let!(:plan2) { create_test_plan(build_plan_data(plan_id: 'prune_me')) }

    it 'returns count of pruned plans' do
      count = Billing::Plan.prune_stale_plans(['keep_me'])
      expect(count).to eq(1)
    end

    it 'returns zero when no plans are stale' do
      count = Billing::Plan.prune_stale_plans(%w[keep_me prune_me])
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
      plan1 = build_plan_data(plan_id: 'plan_a')
      plan2 = build_plan_data(plan_id: 'plan_b')
      Billing::Plan.upsert_from_stripe_data(plan1)
      Billing::Plan.upsert_from_stripe_data(plan2)

      # Verify initial state
      expect(Billing::Plan.list_plans.size).to eq(2)

      # Step 2: Simulate Stripe sync with different plans
      # - plan_a updated
      # - plan_b removed (not in new catalog)
      # - plan_c added
      new_plan1 = build_plan_data(plan_id: 'plan_a', name: 'Updated A')
      new_plan3 = build_plan_data(plan_id: 'plan_c')

      Billing::Plan.upsert_from_stripe_data(new_plan1)
      Billing::Plan.upsert_from_stripe_data(new_plan3)
      Billing::Plan.prune_stale_plans(%w[plan_a plan_c])

      # Verify results
      plan_a = Billing::Plan.load('plan_a')
      plan_b = Billing::Plan.load('plan_b')
      plan_c = Billing::Plan.load('plan_c')

      expect(plan_a.name).to eq('Updated A')
      expect(plan_a.active).to eq('true')
      expect(plan_b.active).to eq('false') # Pruned (soft-deleted)
      expect(plan_c.active).to eq('true')  # New
    end

    it 'handles reactivation of previously pruned plan' do
      # Create and prune a plan
      plan_data = build_plan_data(plan_id: 'reactivate_me')
      Billing::Plan.upsert_from_stripe_data(plan_data)
      Billing::Plan.prune_stale_plans([])

      plan = Billing::Plan.load('reactivate_me')
      expect(plan.active).to eq('false')

      # Reactivate via upsert with active=true
      reactivate_data = plan_data.merge(active: 'true')
      Billing::Plan.upsert_from_stripe_data(reactivate_data)

      plan = Billing::Plan.load('reactivate_me')
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
    # NOTE: amount is now in nested prices hash, not a direct field
    it_behaves_like 'upsert scalar field', :tier, 'basic', 'premium'
    it_behaves_like 'upsert scalar field', :description, 'Old desc', 'New desc'
  end

  describe 'collection fields' do
    it_behaves_like 'upsert collection field', :entitlements
    it_behaves_like 'upsert collection field', :features
  end
end

# ==============================================================================
# SECTION 5: Missing Plan Hash Scenarios (P0 Tests - Issue #2354)
# ==============================================================================
#
# These tests verify correct behavior when Plan Redis hashes are missing
# (e.g., after explicit destroy!, clear_cache, or manual deletion) but the
# instances sorted set entries persist. This was originally caused by a
# 12-hour TTL asymmetry (CATALOG_TTL) which has since been removed — plans
# now persist until explicitly deleted. The scenarios remain valid because
# plan hashes can still go missing via destroy! or clear_cache.
#
# The upsert pattern handles this gracefully, but we need to verify that
# lookup methods return appropriate values (nil/empty) rather than raising.

RSpec.describe 'Missing plan hash handling', type: :billing do
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
  # find_by_stripe_price_id with missing plan hashes
  # --------------------------------------------------------------------------

  describe 'find_by_stripe_price_id' do
    context 'when plan hash is missing but instances entry persists' do
      let(:price_id) { 'price_expired_test_123' }
      let(:plan_id) { 'expired_plan' }

      before do
        # Simulate missing hash state: instances entry exists, but plan hash is gone.
        # This can happen after explicit destroy! or clear_cache. Previously this
        # also occurred via Redis TTL expiration (CATALOG_TTL), now removed.
        Billing::Plan.instances.add(plan_id)

        # Rebuild cache to pick up the orphan entry
        # The cache builder should handle missing plan data gracefully
        Billing::Plan.rebuild_stripe_price_id_cache
      end

      it 'returns nil for missing plan' do
        # The cache should not contain a mapping for a price_id
        # that belonged to a destroyed plan
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
      let(:plan_data) do
        build_plan_data.tap do |data|
          data[:prices][:month][:stripe_price_id] = 'price_valid_123'
        end
      end

      before do
        create_test_plan(plan_data)
        Billing::Plan.rebuild_stripe_price_id_cache
      end

      it 'returns the plan for valid price_id' do
        result = Billing::Plan.find_by_stripe_price_id('price_valid_123')
        expect(result).not_to be_nil
        # Price ID is now in nested prices hash
        expect(result.all_stripe_price_ids).to include('price_valid_123')
      end
    end

    context 'when cache is rebuilt after plan destruction' do
      let(:plan_data) do
        build_plan_data.tap do |data|
          data[:prices][:month][:stripe_price_id] = 'price_will_expire_456'
        end
      end

      before do
        # Create valid plan and cache it
        plan = create_test_plan(plan_data)
        Billing::Plan.rebuild_stripe_price_id_cache

        # Simulate missing hash: delete plan hash but keep instances entry.
        # This mimics explicit deletion (destroy!, clear_cache, or admin action).
        plan.destroy!

        # Force cache rebuild to test it handles missing plans
        Billing::Plan.instance_variable_set(:@stripe_price_id_cache, nil)
      end

      it 'returns nil after plan is destroyed and cache rebuilds' do
        result = Billing::Plan.find_by_stripe_price_id('price_will_expire_456')
        expect(result).to be_nil
      end
    end
  end

  # --------------------------------------------------------------------------
  # list_plans with missing plan hashes
  # --------------------------------------------------------------------------

  describe 'list_plans' do
    context 'when all plan hashes are missing' do
      before do
        # Add orphan entries to instances (simulating deleted plan hashes)
        Billing::Plan.instances.add('orphan_plan_1')
        Billing::Plan.instances.add('orphan_plan_2')
      end

      it 'returns empty array when all plan hashes are missing' do
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

    context 'when some plan hashes are missing' do
      let(:valid_plan_data) { build_plan_data(plan_id: 'valid_plan') }

      before do
        # Create one valid plan
        create_test_plan(valid_plan_data)

        # Add orphan entry (simulating one deleted plan hash)
        Billing::Plan.instances.add('orphan_plan')
      end

      it 'returns only valid plans' do
        result = Billing::Plan.list_plans
        plan_ids = result.map(&:plan_id)

        expect(plan_ids).to include('valid_plan')
        expect(plan_ids).not_to include('orphan_plan')
      end

      it 'filters out missing plans without raising' do
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
  # Catalog state after plan hash deletion
  # --------------------------------------------------------------------------

  describe 'catalog state consistency' do
    context 'after plan hash is explicitly destroyed' do
      let(:plan_data) do
        build_plan_data(plan_id: 'deleted_plan').tap do |data|
          data[:prices][:month][:stripe_price_id] = 'price_deleted_test_789'
        end
      end

      before do
        # Create plan and verify it's accessible
        plan = create_test_plan(plan_data)
        Billing::Plan.rebuild_stripe_price_id_cache

        expect(Billing::Plan.find_by_stripe_price_id('price_deleted_test_789')).not_to be_nil
        expect(Billing::Plan.list_plans.map(&:plan_id)).to include('deleted_plan')

        # Simulate explicit deletion (e.g., destroy! or admin cleanup)
        plan.destroy!

        # Reset cache to force rebuild
        Billing::Plan.instance_variable_set(:@stripe_price_id_cache, nil)
      end

      it 'find_by_stripe_price_id returns nil' do
        expect(Billing::Plan.find_by_stripe_price_id('price_deleted_test_789')).to be_nil
      end

      it 'list_plans excludes destroyed plan' do
        expect(Billing::Plan.list_plans.map(&:plan_id)).not_to include('deleted_plan')
      end

      it 'upsert_from_stripe_data can recreate the plan' do
        # The upsert pattern should handle re-creation gracefully
        new_plan = Billing::Plan.upsert_from_stripe_data(plan_data)

        expect(new_plan.plan_id).to eq('deleted_plan')
        expect(new_plan.exists?).to be true
      end

      it 'after upsert, plan is accessible again' do
        Billing::Plan.upsert_from_stripe_data(plan_data)
        Billing::Plan.rebuild_stripe_price_id_cache

        expect(Billing::Plan.find_by_stripe_price_id('price_deleted_test_789')).not_to be_nil
        expect(Billing::Plan.list_plans.map(&:plan_id)).to include('deleted_plan')
      end
    end
  end
end

# ==============================================================================
# SECTION 6: Orphaned Plan Hash Regression Tests (Cross-Region Bug)
# ==============================================================================
#
# Regression tests for a production bug where paid plans became invisible
# after regional catalog sync. Two interacting bugs created an orphan cycle:
#
# Bug 1 (FIXED): clear_cache only iterated instances.to_a to find plans to
#   destroy. Plan hashes that existed in Redis but weren't in the instances
#   sorted set survived clearing. Fix: clear_cache now SCANs for
#   billing_plan:*:object keys and destroys any remaining orphaned hashes.
#
# Bug 2 (FIXED): upsert_from_stripe_data had a stale update check that compared
#   stripe_updated_at timestamps without considering product identity. When an
#   orphaned hash (not in instances) had a newer timestamp than the incoming sync
#   data, the upsert skipped the save — so the plan never got added to instances.
#   Fix: Added a stripe_product_id gate so the stale check only applies when the
#   Stripe product is the same. Cross-product replacements always overwrite.
RSpec.describe 'Orphaned plan hash regression (cross-region bug)', type: :billing do
  include PlanUpsertTestHelpers

  before do
    Billing::Plan.clear_cache
  end

  after do
    Billing::Plan.clear_cache
  end

  # Helper: create a plan and then orphan it (remove from instances but
  # leave the Redis hash intact).
  def create_orphaned_plan(plan_data, stripe_updated_at:)
    plan = create_test_plan(plan_data)
    plan.stripe_updated_at = stripe_updated_at.to_s
    plan.save
    Billing::Plan.instances.remove(plan_data[:plan_id])
    plan
  end

  # --------------------------------------------------------------------------
  # Bug 1 (FIXED): clear_cache removes orphaned plan hashes via SCAN
  # --------------------------------------------------------------------------

  describe 'clear_cache removes orphaned plan hashes' do
    let(:plan_data) { build_plan_data(plan_id: 'orphan_survive', region: 'UK') }

    it 'removes orphaned plan hashes not tracked in instances' do
      # Create a plan, then remove it from instances (orphan it)
      plan = create_test_plan(plan_data)
      Billing::Plan.instances.remove('orphan_survive')

      # Verify orphan state: hash exists, not in instances
      expect(Billing::Plan.load('orphan_survive')&.exists?).to be true
      expect(Billing::Plan.instances.member?('orphan_survive')).to be false

      # clear_cache now SCANs for billing_plan:*:object keys — orphan is removed
      Billing::Plan.clear_cache

      loaded = Billing::Plan.load('orphan_survive')
      expect(loaded&.exists?).to be_falsey
    end
  end

  # --------------------------------------------------------------------------
  # Bug 2: Stale update check blocks cross-region overwrite
  # --------------------------------------------------------------------------

  describe 'upsert_from_stripe_data bypasses stale check for cross-product update' do
    let(:plan_id) { 'region_conflict' }
    let(:uk_data) { build_plan_data(plan_id: plan_id, region: 'UK') }
    let(:ca_data) { build_plan_data(plan_id: plan_id, region: 'CA', stripe_updated_at: '1000') }

    before do
      # Create UK plan with newer timestamp, then orphan it.
      # Because build_plan_data generates distinct stripe_product_id values,
      # the stale check is bypassed (different product = always overwrite).
      create_orphaned_plan(uk_data, stripe_updated_at: 2000)
    end

    it 'adds plan to instances despite older timestamp' do
      Billing::Plan.upsert_from_stripe_data(ca_data)

      expect(Billing::Plan.instances.member?(plan_id)).to be true
    end

    it 'overwrites with CA region data' do
      Billing::Plan.upsert_from_stripe_data(ca_data)

      loaded = Billing::Plan.load(plan_id)
      expect(loaded.region).to eq('CA')
    end
  end

  # --------------------------------------------------------------------------
  # Full reproduction: clear_cache removes orphan, allowing correct upsert
  # --------------------------------------------------------------------------

  describe 'clear_cache removes orphan, allowing correct region upsert' do
    let(:plan_id) { 'cross_region_bug' }
    let(:uk_data) { build_plan_data(plan_id: plan_id, region: 'UK', name: 'UK Plan') }
    let(:ca_data) do
      build_plan_data(
        plan_id: plan_id,
        region: 'CA',
        name: 'CA Plan',
        stripe_updated_at: '1000'
      )
    end

    before do
      # Step 1: UK plan exists with newer timestamp, orphaned from instances
      create_orphaned_plan(uk_data, stripe_updated_at: 2000)

      # Step 2: clear_cache runs — orphaned UK hash is now destroyed
      Billing::Plan.clear_cache
    end

    it 'clear_cache removes the orphaned UK hash' do
      loaded = Billing::Plan.load(plan_id)
      expect(loaded&.exists?).to be_falsey
    end

    it 'CA upsert registers plan in instances' do
      Billing::Plan.upsert_from_stripe_data(ca_data)

      expect(Billing::Plan.instances.member?(plan_id)).to be true
    end

    it 'plan is visible in list_plans with CA data' do
      Billing::Plan.upsert_from_stripe_data(ca_data)

      plan_ids = Billing::Plan.list_plans.map(&:plan_id)
      expect(plan_ids).to include(plan_id)

      loaded = Billing::Plan.load(plan_id)
      expect(loaded.region).to eq('CA')
    end
  end

  # --------------------------------------------------------------------------
  # Positive case: newer incoming timestamp overwrites and registers
  # --------------------------------------------------------------------------

  describe 'upsert_from_stripe_data overwrites when incoming timestamp is newer' do
    let(:plan_id) { 'newer_overwrite' }
    let(:product_id) { "prod_shared_#{SecureRandom.hex(8)}" }
    let(:uk_data) { build_plan_data(plan_id: plan_id, region: 'UK', stripe_product_id: product_id) }
    let(:ca_data) do
      build_plan_data(
        plan_id: plan_id,
        region: 'CA',
        stripe_product_id: product_id,
        stripe_updated_at: '2000'
      )
    end

    before do
      # UK plan with older timestamp, same product — registered normally
      plan = create_test_plan(uk_data)
      plan.stripe_updated_at = '1000'
      plan.save
    end

    it 'updates region to CA' do
      Billing::Plan.upsert_from_stripe_data(ca_data)

      loaded = Billing::Plan.load(plan_id)
      expect(loaded.region).to eq('CA')
    end

    it 'plan remains in instances' do
      Billing::Plan.upsert_from_stripe_data(ca_data)

      expect(Billing::Plan.instances.member?(plan_id)).to be true
    end
  end

  # --------------------------------------------------------------------------
  # Equal timestamps also trigger skip (the <= check)
  # --------------------------------------------------------------------------

  describe 'stale update check with equal timestamps skips save' do
    let(:plan_id) { 'equal_timestamp' }
    let(:plan_data) { build_plan_data(plan_id: plan_id, region: 'US') }

    before do
      # Create plan with timestamp 1000, then orphan it
      create_orphaned_plan(plan_data, stripe_updated_at: 1000)
    end

    it 'does not add orphaned plan back to instances' do
      incoming_data = plan_data.merge(stripe_updated_at: '1000')
      Billing::Plan.upsert_from_stripe_data(incoming_data)

      expect(Billing::Plan.instances.member?(plan_id)).to be false
    end
  end

  # --------------------------------------------------------------------------
  # Regression: same-product stale check still applies
  # --------------------------------------------------------------------------

  describe 'stale check still applies for same-product updates' do
    let(:plan_id) { 'same_product_stale' }
    let(:product_id) { "prod_shared_#{SecureRandom.hex(8)}" }
    let(:plan_data) do
      build_plan_data(
        plan_id: plan_id,
        region: 'US',
        stripe_product_id: product_id
      )
    end

    before do
      # Create plan with shared product ID and newer timestamp, then orphan it
      create_orphaned_plan(
        plan_data.merge(stripe_product_id: product_id),
        stripe_updated_at: 2000
      )
    end

    it 'skips save when same product has newer timestamp' do
      incoming = plan_data.merge(
        stripe_product_id: product_id,
        stripe_updated_at: '1000'
      )
      Billing::Plan.upsert_from_stripe_data(incoming)

      expect(Billing::Plan.instances.member?(plan_id)).to be false
    end

    it 'allows save when same product has newer incoming timestamp' do
      incoming = plan_data.merge(
        stripe_product_id: product_id,
        stripe_updated_at: '3000'
      )
      Billing::Plan.upsert_from_stripe_data(incoming)

      expect(Billing::Plan.instances.member?(plan_id)).to be true
    end
  end

  # --------------------------------------------------------------------------
  # P1: nil vs non-nil product ID bypasses stale check
  # --------------------------------------------------------------------------

  describe 'stale check bypassed when product IDs differ (nil vs non-nil)' do
    let(:plan_id) { 'nil_vs_real_product' }
    let(:config_plan_data) do
      build_plan_data(
        plan_id: plan_id,
        region: 'US',
        stripe_product_id: nil
      )
    end

    before do
      # Simulate a config-only plan (no stripe_product_id) with a newer timestamp,
      # then orphan it. This mimics a plan created via upsert_config_only_plans.
      create_orphaned_plan(config_plan_data, stripe_updated_at: 2000)
    end

    it 'overwrites nil-product plan with real product despite older timestamp' do
      incoming = build_plan_data(
        plan_id: plan_id,
        region: 'EU',
        stripe_product_id: 'prod_real_123',
        stripe_updated_at: '1000'
      )
      Billing::Plan.upsert_from_stripe_data(incoming)

      expect(Billing::Plan.instances.member?(plan_id)).to be true
      loaded = Billing::Plan.load(plan_id)
      expect(loaded.stripe_product_id).to eq('prod_real_123')
      expect(loaded.region).to eq('EU')
    end

    it 'overwrites real-product plan with nil product despite older timestamp' do
      # First, create a plan WITH a product ID
      real_product_data = build_plan_data(
        plan_id: plan_id,
        region: 'US',
        stripe_product_id: 'prod_real_456'
      )
      # Clear the orphan first, then set up the real-product plan
      Billing::Plan.clear_cache
      create_orphaned_plan(real_product_data, stripe_updated_at: 2000)

      incoming = build_plan_data(
        plan_id: plan_id,
        region: 'CA',
        stripe_product_id: nil,
        stripe_updated_at: '1000'
      )
      Billing::Plan.upsert_from_stripe_data(incoming)

      expect(Billing::Plan.instances.member?(plan_id)).to be true
      loaded = Billing::Plan.load(plan_id)
      expect(loaded.region).to eq('CA')
    end
  end

  # --------------------------------------------------------------------------
  # P1: nil == nil product ID applies stale check
  # --------------------------------------------------------------------------

  describe 'stale check applies when both product IDs are nil' do
    let(:plan_id) { 'both_nil_product' }
    let(:plan_data) do
      build_plan_data(
        plan_id: plan_id,
        region: 'US',
        stripe_product_id: nil
      )
    end

    before do
      # Both plans have nil stripe_product_id (config-only plans).
      # nil == nil is true, so same_product = true and stale check applies.
      create_orphaned_plan(plan_data, stripe_updated_at: 2000)
    end

    it 'skips save when both have nil product ID and incoming is older' do
      incoming = plan_data.merge(stripe_updated_at: '1000')
      Billing::Plan.upsert_from_stripe_data(incoming)

      expect(Billing::Plan.instances.member?(plan_id)).to be false
    end

    it 'allows save when both have nil product ID and incoming is newer' do
      incoming = plan_data.merge(stripe_updated_at: '3000')
      Billing::Plan.upsert_from_stripe_data(incoming)

      expect(Billing::Plan.instances.member?(plan_id)).to be true
    end
  end

  # --------------------------------------------------------------------------
  # P2: Missing stripe_updated_at bypasses stale check entirely
  # --------------------------------------------------------------------------

  describe 'stale check bypassed when incoming data has no stripe_updated_at' do
    let(:plan_id) { 'no_timestamp' }
    let(:product_id) { "prod_shared_#{SecureRandom.hex(8)}" }
    let(:plan_data) do
      build_plan_data(
        plan_id: plan_id,
        region: 'US',
        stripe_product_id: product_id
      )
    end

    before do
      # Create plan with same product ID and a timestamp, then orphan it
      create_orphaned_plan(
        plan_data.merge(stripe_product_id: product_id),
        stripe_updated_at: 2000
      )
    end

    it 'proceeds with upsert when stripe_updated_at is absent from incoming data' do
      # Remove stripe_updated_at entirely — should bypass the stale check guard
      incoming = plan_data.merge(stripe_product_id: product_id)
      incoming.delete(:stripe_updated_at)

      Billing::Plan.upsert_from_stripe_data(incoming)

      expect(Billing::Plan.instances.member?(plan_id)).to be true
    end

    it 'proceeds with upsert when stripe_updated_at is explicitly nil' do
      incoming = plan_data.merge(
        stripe_product_id: product_id,
        stripe_updated_at: nil
      )
      Billing::Plan.upsert_from_stripe_data(incoming)

      expect(Billing::Plan.instances.member?(plan_id)).to be true
    end
  end
end

# ==============================================================================
# SECTION 4: Plan.collect_stripe_plans fail-closed validation (#3120 Phase 1)
# ==============================================================================

RSpec.describe 'Billing::Plan.send(:collect_stripe_plans) validation', type: :billing do
  include PlanUpsertTestHelpers

  # Mock Stripe objects for testing
  let(:valid_metadata) do
    {
      'app' => 'onetimesecret',
      'plan_id' => 'identity_plus_v1',
      'tier' => 'identity',
      'region' => 'US',
    }
  end

  let(:invalid_metadata_missing_plan_id) do
    {
      'app' => 'onetimesecret',
      'tier' => 'identity',
      'region' => 'US',
    }
  end

  let(:invalid_metadata_blank_plan_id) do
    {
      'app' => 'onetimesecret',
      'plan_id' => '   ',
      'tier' => 'identity',
      'region' => 'US',
    }
  end

  def build_mock_product(id:, name:, metadata:)
    Stripe::StripeObject.construct_from({
      id: id,
      name: name,
      description: "Description for #{name}",
      metadata: metadata,
      active: true,
      marketing_features: [],
      updated: Time.now.to_i,
    })
  end

  def build_mock_price(id:, product_id:, interval: 'month')
    Stripe::Price.construct_from({
      id: id,
      product: product_id,
      type: 'recurring',
      currency: 'cad',
      unit_amount: 2900,
      active: true,
      billing_scheme: 'per_unit',
      nickname: nil,
      recurring: { interval: interval },
    })
  end

  def mock_product_list(*products)
    list = instance_double(Stripe::ListObject)
    stub = allow(list).to receive(:auto_paging_each)
    products.flatten.each { |p| stub = stub.and_yield(p) }
    list
  end

  def mock_price_list(*prices)
    list = instance_double(Stripe::ListObject)
    stub = allow(list).to receive(:auto_paging_each)
    prices.flatten.each { |p| stub = stub.and_yield(p) }
    list
  end

  before do
    allow(Billing::Plan).to receive(:ensure_stripe_configured!)
    # Allow all regions to pass through (no regional isolation in tests)
    allow(OT.billing_config).to receive(:region).and_return(nil)
  end

  # --------------------------------------------------------------------------
  # Single product with bad metadata
  # --------------------------------------------------------------------------

  describe 'single product with bad metadata' do
    let(:bad_product) { build_mock_product(id: 'prod_bad', name: 'Bad Product', metadata: invalid_metadata_missing_plan_id) }
    let(:price) { build_mock_price(id: 'price_bad', product_id: 'prod_bad') }

    before do
      allow(Stripe::Product).to receive(:list).and_return(mock_product_list(bad_product))
      allow(Stripe::Price).to receive(:list).and_return(mock_price_list(price))
    end

    it 'raises CatalogValidationError with one error' do
      expect { Billing::Plan.send(:collect_stripe_plans) }
        .to raise_error(Billing::CatalogValidationError) do |e|
          expect(e.errors.size).to eq(1)
          expect(e.errors.first[:product_id]).to eq('prod_bad')
          expect(e.errors.first[:error]).to include('missing: plan_id')
        end
    end
  end

  # --------------------------------------------------------------------------
  # Multiple products with bad metadata
  # --------------------------------------------------------------------------

  describe 'multiple products with bad metadata' do
    let(:bad_product1) { build_mock_product(id: 'prod_bad1', name: 'Bad Product 1', metadata: invalid_metadata_missing_plan_id) }
    let(:bad_product2) { build_mock_product(id: 'prod_bad2', name: 'Bad Product 2', metadata: invalid_metadata_blank_plan_id) }
    let(:price1) { build_mock_price(id: 'price_bad1', product_id: 'prod_bad1') }
    let(:price2) { build_mock_price(id: 'price_bad2', product_id: 'prod_bad2') }

    before do
      product_list = instance_double(Stripe::ListObject)
      allow(product_list).to receive(:auto_paging_each).and_yield(bad_product1).and_yield(bad_product2)
      allow(Stripe::Product).to receive(:list).and_return(product_list)

      allow(Stripe::Price).to receive(:list).with(hash_including(product: 'prod_bad1')).and_return(mock_price_list(price1))
      allow(Stripe::Price).to receive(:list).with(hash_including(product: 'prod_bad2')).and_return(mock_price_list(price2))
    end

    it 'accumulates all errors before raising' do
      expect { Billing::Plan.send(:collect_stripe_plans) }
        .to raise_error(Billing::CatalogValidationError) do |e|
          expect(e.errors.size).to eq(2)
          product_ids = e.errors.map { |err| err[:product_id] }
          expect(product_ids).to contain_exactly('prod_bad1', 'prod_bad2')
        end
    end
  end

  # --------------------------------------------------------------------------
  # Mix of good and bad products
  # --------------------------------------------------------------------------

  describe 'mix of good and bad products' do
    let(:good_product) { build_mock_product(id: 'prod_good', name: 'Good Product', metadata: valid_metadata) }
    let(:bad_product) { build_mock_product(id: 'prod_bad', name: 'Bad Product', metadata: invalid_metadata_missing_plan_id) }
    let(:good_price) { build_mock_price(id: 'price_good', product_id: 'prod_good') }
    let(:bad_price) { build_mock_price(id: 'price_bad', product_id: 'prod_bad') }

    before do
      product_list = instance_double(Stripe::ListObject)
      allow(product_list).to receive(:auto_paging_each).and_yield(good_product).and_yield(bad_product)
      allow(Stripe::Product).to receive(:list).and_return(product_list)

      allow(Stripe::Price).to receive(:list).with(hash_including(product: 'prod_good')).and_return(mock_price_list(good_price))
      allow(Stripe::Price).to receive(:list).with(hash_including(product: 'prod_bad')).and_return(mock_price_list(bad_price))
    end

    it 'collects valid plans then raises with bad ones' do
      expect { Billing::Plan.send(:collect_stripe_plans) }
        .to raise_error(Billing::CatalogValidationError) do |e|
          expect(e.errors.size).to eq(1)
          expect(e.errors.first[:product_id]).to eq('prod_bad')
        end
    end
  end

  # --------------------------------------------------------------------------
  # All products valid
  # --------------------------------------------------------------------------

  describe 'all products valid' do
    let(:good_product1) { build_mock_product(id: 'prod_good1', name: 'Good Product 1', metadata: valid_metadata) }
    let(:good_product2) { build_mock_product(id: 'prod_good2', name: 'Good Product 2', metadata: valid_metadata.merge('plan_id' => 'team_plus_v1')) }
    let(:price1) { build_mock_price(id: 'price_good1', product_id: 'prod_good1') }
    let(:price2) { build_mock_price(id: 'price_good2', product_id: 'prod_good2') }

    before do
      product_list = instance_double(Stripe::ListObject)
      allow(product_list).to receive(:auto_paging_each).and_yield(good_product1).and_yield(good_product2)
      allow(Stripe::Product).to receive(:list).and_return(product_list)

      allow(Stripe::Price).to receive(:list).with(hash_including(product: 'prod_good1')).and_return(mock_price_list(price1))
      allow(Stripe::Price).to receive(:list).with(hash_including(product: 'prod_good2')).and_return(mock_price_list(price2))
    end

    it 'returns plan_data_list without raising' do
      result = Billing::Plan.send(:collect_stripe_plans)
      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      plan_ids = result.map { |d| d[:plan_id] }
      expect(plan_ids).to contain_exactly('identity_plus_v1', 'team_plus_v1')
    end
  end

  # --------------------------------------------------------------------------
  # Products skipped for valid reasons (wrong app, wrong region)
  # --------------------------------------------------------------------------

  describe 'products skipped for valid reasons do not trigger validation error' do
    let(:other_app_product) { build_mock_product(id: 'prod_other', name: 'Other App', metadata: { 'app' => 'other_app' }) }
    let(:good_product) { build_mock_product(id: 'prod_good', name: 'Good Product', metadata: valid_metadata) }
    let(:good_price) { build_mock_price(id: 'price_good', product_id: 'prod_good') }

    before do
      product_list = instance_double(Stripe::ListObject)
      allow(product_list).to receive(:auto_paging_each).and_yield(other_app_product).and_yield(good_product)
      allow(Stripe::Product).to receive(:list).and_return(product_list)

      allow(Stripe::Price).to receive(:list).with(hash_including(product: 'prod_good')).and_return(mock_price_list(good_price))
    end

    it 'skips non-OTS products without error' do
      result = Billing::Plan.send(:collect_stripe_plans)
      expect(result.size).to eq(1)
      expect(result.first[:plan_id]).to eq('identity_plus_v1')
    end
  end
end
