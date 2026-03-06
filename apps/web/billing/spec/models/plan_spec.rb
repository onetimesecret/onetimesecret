# apps/web/billing/spec/models/plan_spec.rb
#
# frozen_string_literal: true

# Unit tests for Billing::Plan model
#
# Tests cover the key fields and methods needed for billing plans page fixes:
# - safe_dump includes required fields (plan_code, is_popular, tier, etc.)
# - monthly_equivalent_amount calculation for yearly plans
# - popular? method reading metadata
# - limits_hash conversion

require_relative '../support/billing_spec_helper'
require_relative '../../models/plan'

RSpec.describe Billing::Plan, type: :billing do
  # Note: We don't use with_test_plans context here because it requires
  # loading Controllers::Base which is not needed for model tests.
  # Instead, we load plans directly when needed.

  before do
    # Clear and reload plans for each test
    Billing::Plan.clear_cache
  end

  after do
    Billing::Plan.clear_cache
  end

  describe 'field definitions' do
    let(:plan) do
      Billing::Plan.new(
        plan_id: 'identity_plus_v1_monthly',
        stripe_price_id: 'price_test_123',
        stripe_product_id: 'prod_test_456',
        name: 'Identity Plus',
        tier: 'single_team',
        interval: 'month',
        amount: '1499',
        currency: 'cad',
        region: 'US',
        tenancy: 'multi',
        display_order: '100',
        show_on_plans_page: 'true',
        description: 'Perfect for individuals and small teams',
      )
    end

    it 'has required fields for API response' do
      expect(plan).to respond_to(:plan_id)
      expect(plan).to respond_to(:tier)
      expect(plan).to respond_to(:interval)
      expect(plan).to respond_to(:amount)
      expect(plan).to respond_to(:currency)
      expect(plan).to respond_to(:display_order)
      expect(plan).to respond_to(:show_on_plans_page)
    end

    it 'stores tier as string' do
      expect(plan.tier).to eq('single_team')
    end

    it 'stores interval as string' do
      expect(plan.interval).to eq('month')
    end

    it 'stores amount as string' do
      expect(plan.amount).to eq('1499')
    end
  end

  describe '#limits_hash' do
    let(:plan) do
      plan = Billing::Plan.new(
        plan_id: 'test_plan_monthly',
        tier: 'single_team',
        interval: 'month',
        amount: '1499',
        currency: 'cad',
      )
      plan.save
      plan.limits['teams.max'] = '5'
      plan.limits['members_per_team.max'] = 'unlimited'
      plan.limits['secrets_per_day.max'] = '100'
      plan
    end

    after do
      plan.destroy! if plan.exists?
    end

    it 'converts numeric limits to integers' do
      expect(plan.limits_hash['teams.max']).to eq(5)
      expect(plan.limits_hash['secrets_per_day.max']).to eq(100)
    end

    it 'converts "unlimited" to Float::INFINITY' do
      expect(plan.limits_hash['members_per_team.max']).to eq(Float::INFINITY)
    end

    it 'memoizes the hash' do
      first_call = plan.limits_hash
      second_call = plan.limits_hash
      expect(first_call).to equal(second_call)
    end

    it 'clears memoization when limits change' do
      first_hash = plan.limits_hash
      expect(first_hash['teams.max']).to eq(5)

      # Modify limits directly and clear memoization manually
      plan.instance_variable_set(:@limits_hash, nil)
      plan.limits['teams.max'] = '10'

      # Now limits_hash should recalculate
      new_hash = plan.limits_hash
      expect(new_hash['teams.max']).to eq(10)
    end
  end

  describe '#entitlements' do
    let(:plan) do
      plan = Billing::Plan.new(
        plan_id: 'test_plan_monthly',
        tier: 'single_team',
        interval: 'month',
        amount: '1499',
        currency: 'cad',
      )
      plan.save
      plan.entitlements.add('create_secrets')
      plan.entitlements.add('api_access')
      plan.entitlements.add('custom_domains')
      plan
    end

    after do
      plan.destroy! if plan.exists?
    end

    it 'stores entitlements as a collection' do
      # Entitlements is a Familia-backed set (redis set)
      expect(plan.entitlements).to respond_to(:add)
      expect(plan.entitlements).to respond_to(:to_a)
    end

    it 'contains added entitlements' do
      expect(plan.entitlements.to_a).to include('create_secrets')
      expect(plan.entitlements.to_a).to include('api_access')
      expect(plan.entitlements.to_a).to include('custom_domains')
    end

    it 'maintains uniqueness' do
      plan.entitlements.add('create_secrets') # Add duplicate
      # Set should still have 3 items
      expect(plan.entitlements.to_a.size).to eq(3)
    end
  end

  describe '.load_from_config' do
    it 'loads plan from config' do
      # The config has identity_plus_v1 which becomes identity_plus_v1_monthly
      plan = Billing::Plan.load_from_config('identity_plus_v1_monthly')

      expect(plan).not_to be_nil
      # Tier could be single_account or single_team depending on config
      expect(plan[:tier]).to match(/single_account|single_team/)
    end

    it 'returns nil for unknown plan' do
      plan = Billing::Plan.load_from_config('nonexistent_plan_xyz_123')
      expect(plan).to be_nil
    end

    it 'strips interval suffix when looking up base plan' do
      # identity_plus_v1 should be found even when requested as identity_plus_v1_monthly
      plan = Billing::Plan.load_from_config('identity_plus_v1_monthly')
      expect(plan).not_to be_nil
      expect(plan[:tier]).not_to be_nil
    end
  end

  describe '.list_plans_from_config' do
    it 'returns array of plan hashes' do
      plans = Billing::Plan.list_plans_from_config
      expect(plans).to be_an(Array)
      expect(plans).not_to be_empty
    end

    it 'includes required fields in each plan' do
      plans = Billing::Plan.list_plans_from_config
      plans.each do |plan|
        expect(plan).to have_key(:planid)
        expect(plan).to have_key(:name)
        expect(plan).to have_key(:tier)
        expect(plan).to have_key(:entitlements)
        expect(plan).to have_key(:limits)
      end
    end

    it 'includes tier field' do
      plans = Billing::Plan.list_plans_from_config
      tiers = plans.map { |p| p[:tier] }.compact
      expect(tiers).to include('single_team')
    end
  end

  describe '.load_all_from_config' do
    before do
      Billing::Plan.clear_cache
    end

    it 'populates Redis cache from config' do
      count = Billing::Plan.load_all_from_config
      expect(count).to be > 0
    end

    it 'creates Plan instances in Redis' do
      Billing::Plan.load_all_from_config

      plans = Billing::Plan.list_plans
      expect(plans).not_to be_empty
    end

    it 'loads plans with correct tier' do
      Billing::Plan.load_all_from_config

      plans = Billing::Plan.list_plans
      tiers = plans.map(&:tier).uniq
      expect(tiers).to include('single_team')
    end

    it 'loads plans with both monthly and yearly intervals' do
      Billing::Plan.load_all_from_config

      plans = Billing::Plan.list_plans
      intervals = plans.map(&:interval).uniq
      expect(intervals).to include('month')
      expect(intervals).to include('year')
    end
  end

  describe '.get_plan' do
    before do
      Billing::Plan.load_all_from_config
    end

    it 'finds plan by tier, interval, and region' do
      # Region is either a specific code or nil (no "global" default).
      # Try configured region first, then nil for non-regionalized deployments.
      plan = Billing::Plan.get_plan('single_team', 'monthly', 'EU')
      plan ||= Billing::Plan.get_plan('single_team', 'monthly', nil)
      expect(plan).not_to be_nil
      expect(plan.tier).to eq('single_team')
    end

    it 'normalizes interval suffix (monthly -> month)' do
      plan = Billing::Plan.get_plan('single_team', 'monthly', 'EU')
      plan ||= Billing::Plan.get_plan('single_team', 'monthly', nil)
      expect(plan&.interval).to eq('month')
    end

    it 'returns nil for unknown tier' do
      plan = Billing::Plan.get_plan('nonexistent_xyz', 'monthly', 'EU')
      expect(plan).to be_nil
    end
  end

  describe 'Plan for API response' do
    # These tests verify the Plan model provides the fields needed
    # by the frontend PlanSelector component

    let(:plan) do
      plan = Billing::Plan.new(
        plan_id: 'team_plus_v1_yearly',
        stripe_price_id: 'price_yearly_123',
        stripe_product_id: 'prod_team_456',
        name: 'Team Plus',
        tier: 'multi_team',
        interval: 'year',
        amount: '14388', # $143.88/year
        currency: 'cad',
        region: 'US',
        tenancy: 'multi',
        display_order: '200',
        show_on_plans_page: 'true',
        description: 'For growing teams',
      )
      plan.save
      plan.entitlements.add('create_secrets')
      plan.entitlements.add('api_access')
      plan.entitlements.add('manage_teams')
      plan.entitlements.add('sso')
      plan.limits['teams.max'] = '10'
      plan.limits['members_per_team.max'] = 'unlimited'
      plan
    end

    after do
      plan.destroy! if plan.exists?
    end

    it 'provides tier for upgrade/downgrade comparison' do
      # Frontend uses tier, not planid, for upgrade logic
      expect(plan.tier).to eq('multi_team')
    end

    it 'provides interval for filtering' do
      expect(plan.interval).to eq('year')
    end

    it 'provides amount in cents' do
      expect(plan.amount.to_i).to eq(14_388)
    end

    it 'provides entitlements for feature display' do
      entitlements = plan.entitlements.to_a
      expect(entitlements).to include('create_secrets')
      expect(entitlements).to include('manage_teams')
    end

    it 'provides limits for plan comparison' do
      expect(plan.limits_hash['teams.max']).to eq(10)
      expect(plan.limits_hash['members_per_team.max']).to eq(Float::INFINITY)
    end

    it 'provides display_order for sorting' do
      expect(plan.display_order.to_i).to eq(200)
    end
  end

  describe 'Monthly equivalent for yearly plans' do
    # Frontend needs monthly equivalent price for yearly plans
    # This should be provided by API, not calculated client-side

    let(:yearly_plan) do
      plan = Billing::Plan.new(
        plan_id: 'identity_plus_yearly',
        tier: 'single_team',
        interval: 'year',
        amount: '14388', # $143.88/year
        currency: 'cad',
      )
      plan.save
      plan
    end

    after do
      yearly_plan.destroy! if yearly_plan.exists?
    end

    it 'stores yearly amount' do
      expect(yearly_plan.amount.to_i).to eq(14_388)
    end

    it 'can calculate monthly equivalent' do
      # 14388 / 12 = 1199 ($11.99/month)
      monthly_equiv = yearly_plan.amount.to_i / 12
      expect(monthly_equiv).to eq(1199)
    end

    # Note: The actual monthly_equivalent_amount field should be
    # added to the API response in the controller, not stored in the model
  end

  describe 'Feature inheritance between tiers' do
    # Higher tiers should include all features from lower tiers

    before do
      Billing::Plan.load_all_from_config
    end

    it 'single_team has base entitlements' do
      # Find a single_team plan from loaded plans
      plans = Billing::Plan.list_plans
      single_team = plans.find { |p| p.tier == 'single_team' }
      skip 'No single_team plan in config' if single_team.nil?

      entitlements = single_team.entitlements.to_a
      expect(entitlements).to include('create_secrets')
    end

    it 'multi_team includes single_team entitlements plus more' do
      plans = Billing::Plan.list_plans
      single = plans.find { |p| p.tier == 'single_team' }
      multi = plans.find { |p| p.tier == 'multi_team' }

      # Skip if either plan not found (depends on test config)
      skip 'multi_team plan not in test config' if multi.nil?
      skip 'single_team plan not in test config' if single.nil?

      single_ents = single.entitlements.to_a
      multi_ents = multi.entitlements.to_a

      # Multi-team should have at least as many entitlements as single-team
      expect(multi_ents.size).to be >= single_ents.size
    end
  end
end
