# frozen_string_literal: true

require 'spec_helper'
require 'billing/models/plan'

RSpec.describe Billing::Plan, type: :model do
  before do
    Billing::Plan.clear_cache
  end

  after do
    Billing::Plan.clear_cache
  end

  describe 'plan creation and retrieval' do
    it 'creates and saves a plan' do
      plan = described_class.new(
        plan_id: 'identity_v1_monthly',
        stripe_price_id: 'price_test123',
        stripe_product_id: 'prod_test123',
        name: 'Single Team',
        tier: 'single_team',
        interval: 'month',
        amount: '2900',
        currency: 'usd',
        region: 'us-east',
        features: '["Feature 1", "Feature 2"]',
        limits: '{"teams": 1, "members_per_team": 10}'
      )

      expect(plan.save).to be true
      expect(described_class.values.size).to eq 1
    end

    it 'retrieves plan by ID' do
      plan = described_class.new(
        plan_id: 'identity_v1_monthly',
        stripe_price_id: 'price_test123',
        stripe_product_id: 'prod_test123',
        name: 'Single Team',
        tier: 'single_team',
        interval: 'month',
        amount: '2900',
        currency: 'usd',
        region: 'us-east',
        features: '["Feature 1", "Feature 2"]',
        limits: '{"teams": 1, "members_per_team": 10}'
      )
      plan.save

      retrieved = described_class.load('identity_v1_monthly')
      expect(retrieved.tier).to eq 'single_team'
    end

    it 'parses JSON features' do
      plan = described_class.new(
        plan_id: 'identity_v1_monthly',
        stripe_price_id: 'price_test123',
        stripe_product_id: 'prod_test123',
        name: 'Single Team',
        tier: 'single_team',
        interval: 'month',
        amount: '2900',
        currency: 'usd',
        region: 'us-east',
        features: '["Feature 1", "Feature 2"]',
        limits: '{"teams": 1, "members_per_team": 10}'
      )
      plan.save

      retrieved = described_class.load('identity_v1_monthly')
      expect(retrieved.parsed_features).to eq ["Feature 1", "Feature 2"]
    end

    it 'parses limits' do
      plan = described_class.new(
        plan_id: 'identity_v1_monthly',
        stripe_price_id: 'price_test123',
        stripe_product_id: 'prod_test123',
        name: 'Single Team',
        tier: 'single_team',
        interval: 'month',
        amount: '2900',
        currency: 'usd',
        region: 'us-east',
        features: '["Feature 1", "Feature 2"]',
        limits: '{"teams": 1, "members_per_team": 10}'
      )
      plan.save

      retrieved = described_class.load('identity_v1_monthly')
      expect(retrieved.parsed_limits).to eq({"teams" => 1, "members_per_team" => 10})
    end
  end

  describe '.get_plan' do
    before do
      described_class.new(
        plan_id: 'identity_v1_monthly',
        stripe_price_id: 'price_test123',
        stripe_product_id: 'prod_test123',
        name: 'Single Team',
        tier: 'single_team',
        interval: 'month',
        amount: '2900',
        currency: 'usd',
        region: 'us-east',
        features: '["Feature 1", "Feature 2"]',
        limits: '{"teams": 1, "members_per_team": 10}'
      ).save

      described_class.new(
        plan_id: 'identity_v1_yearly',
        stripe_price_id: 'price_yearly123',
        stripe_product_id: 'prod_test123',
        name: 'Single Team Annual',
        tier: 'single_team',
        interval: 'year',
        amount: '29000',
        currency: 'usd',
        region: 'us-east',
        features: '["Feature 1", "Feature 2"]',
        limits: '{"teams": 1, "members_per_team": 10}'
      ).save
    end

    it 'retrieves monthly plan by tier, interval, region' do
      monthly_plan = described_class.get_plan('single_team', 'monthly', 'us-east')
      expect(monthly_plan.plan_id).to eq 'identity_v1_monthly'
    end

    it 'retrieves yearly plan by tier, interval, region' do
      yearly_plan = described_class.get_plan('single_team', 'yearly', 'us-east')
      expect(yearly_plan.plan_id).to eq 'identity_v1_yearly'
    end
  end

  describe '.list_plans' do
    it 'lists all plans' do
      described_class.new(
        plan_id: 'identity_v1_monthly',
        stripe_price_id: 'price_test123',
        stripe_product_id: 'prod_test123',
        name: 'Single Team',
        tier: 'single_team',
        interval: 'month',
        amount: '2900',
        currency: 'usd',
        region: 'us-east',
        features: '["Feature 1", "Feature 2"]',
        limits: '{"teams": 1, "members_per_team": 10}'
      ).save

      described_class.new(
        plan_id: 'identity_v1_yearly',
        stripe_price_id: 'price_yearly123',
        stripe_product_id: 'prod_test123',
        name: 'Single Team Annual',
        tier: 'single_team',
        interval: 'year',
        amount: '29000',
        currency: 'usd',
        region: 'us-east',
        features: '["Feature 1", "Feature 2"]',
        limits: '{"teams": 1, "members_per_team": 10}'
      ).save

      expect(described_class.list_plans.size).to eq 2
    end
  end

  describe '.clear_cache' do
    it 'clears all cached plans' do
      described_class.new(
        plan_id: 'identity_v1_monthly',
        stripe_price_id: 'price_test123',
        stripe_product_id: 'prod_test123',
        name: 'Single Team',
        tier: 'single_team',
        interval: 'month',
        amount: '2900',
        currency: 'usd',
        region: 'us-east',
        features: '["Feature 1", "Feature 2"]',
        limits: '{"teams": 1, "members_per_team": 10}'
      ).save

      expect(described_class.values.size).to eq 1
      described_class.clear_cache
      expect(described_class.values.size).to eq 0
    end
  end
end
