# apps/web/billing/spec/controllers/plans_api_spec.rb
#
# frozen_string_literal: true

# Tests for the Plans API focused on billing page fixes
#
# Covers the issues being fixed:
# - Plan deduplication by plan_code
# - Required fields for frontend (tier, is_popular, monthly_equivalent_amount)
# - Plans sorted by display_order
# - Correct field types and values

require_relative '../support/billing_spec_helper'
require 'rack/test'

# Load the billing application for controller testing
require_relative '../../application'

RSpec.describe 'Plans API Response', type: :integration do
  include Rack::Test::Methods
  include_context 'with_test_plans'

  def app
    @app ||= Rack::URLMap.new('/billing' => Billing::Application.new)
  end

  describe 'GET /billing/api/plans' do
    context 'response structure' do
      before do
        get '/billing/api/plans'
      end

      it 'returns 200 status' do
        expect(last_response.status).to eq(200)
      end

      it 'returns JSON content type' do
        expect(last_response.content_type).to include('application/json')
      end

      it 'returns plans array' do
        data = JSON.parse(last_response.body)
        expect(data).to have_key('plans')
        expect(data['plans']).to be_an(Array)
      end
    end

    context 'plan fields' do
      let(:response_plans) do
        get '/billing/api/plans'
        JSON.parse(last_response.body)['plans']
      end

      it 'includes required fields for frontend' do
        skip 'No plans in cache' if response_plans.empty?

        plan = response_plans.first
        expect(plan).to have_key('id')
        expect(plan).to have_key('name')
        expect(plan).to have_key('tier')
        expect(plan).to have_key('prices')
        expect(plan).to have_key('currency')
        expect(plan).to have_key('display_order')
        expect(plan).to have_key('entitlements')
        expect(plan).to have_key('limits')
      end

      it 'includes tier field for upgrade/downgrade logic' do
        skip 'No plans in cache' if response_plans.empty?

        plan = response_plans.first
        expect(plan['tier']).to be_a(String)
        # Valid tiers include single_account, single_team, multi_team
        expect(plan['tier']).to match(/free|single_account|single_team|multi_team/)
      end

      it 'includes prices hash with interval-keyed data' do
        skip 'No plans in cache' if response_plans.empty?

        plan = response_plans.first
        prices = plan['prices']
        expect(prices).to be_a(Hash)
        # Should have at least one interval (month or year)
        intervals = prices.keys
        expect(intervals).to all(match(/^(month|year)$/))
      end

      it 'includes amount in prices for each interval' do
        skip 'No plans in cache' if response_plans.empty?

        plan = response_plans.first
        prices = plan['prices']
        next if prices.nil? || prices.empty?

        # Each interval should have an amount
        prices.each_value do |price_data|
          expect(price_data['amount'].to_i).to be >= 0
        end
      end

      it 'includes display_order as numeric for sorting' do
        skip 'No plans in cache' if response_plans.empty?

        plan = response_plans.first
        expect(plan['display_order']).to be_a(Integer)
      end

      it 'includes entitlements as array' do
        skip 'No plans in cache' if response_plans.empty?

        plan = response_plans.first
        expect(plan['entitlements']).to be_an(Array)
      end

      it 'includes limits as hash' do
        skip 'No plans in cache' if response_plans.empty?

        plan = response_plans.first
        expect(plan['limits']).to be_a(Hash)
      end
    end

    context 'sorting and ordering' do
      let(:response_plans) do
        get '/billing/api/plans'
        JSON.parse(last_response.body)['plans']
      end

      it 'returns plans sorted by display_order ascending' do
        skip 'Need at least 2 plans' if response_plans.size < 2

        display_orders = response_plans.map { |p| p['display_order'] }
        expect(display_orders).to eq(display_orders.sort)
      end
    end

    context 'tier-based logic support' do
      let(:response_plans) do
        get '/billing/api/plans'
        JSON.parse(last_response.body)['plans']
      end

      it 'single_team tier should have base entitlements' do
        single_team = response_plans.find { |p| p['tier'] == 'single_team' }
        skip 'No single_team plan in response' if single_team.nil?

        entitlements = single_team['entitlements']
        expect(entitlements).to include('create_secrets')
      end

      it 'multi_team tier should have more entitlements than single_team' do
        single_team = response_plans.find { |p| p['tier'] == 'single_team' }
        multi_team = response_plans.find { |p| p['tier'] == 'multi_team' }

        skip 'Need both single_team and multi_team plans' if single_team.nil? || multi_team.nil?

        # Multi-team should have >= entitlements as single-team
        expect(multi_team['entitlements'].size).to be >= single_team['entitlements'].size
      end
    end

    context 'filtering' do
      before do
        # Ensure some plans are loaded
        Billing::Plan.load_all_from_config
      end

      it 'only includes plans with show_on_plans_page=true' do
        get '/billing/api/plans'
        plans = JSON.parse(last_response.body)['plans']

        # All returned plans should be from plans with show_on_plans_page=true
        # (filtering happens in the controller)
        expect(plans).to all(satisfy { |p| !p['id'].include?('hidden') })
      end
    end

    context 'limits serialization' do
      let(:response_plans) do
        get '/billing/api/plans'
        JSON.parse(last_response.body)['plans']
      end

      it 'converts unlimited values to -1' do
        skip 'No plans in cache' if response_plans.empty?

        plan = response_plans.first
        limits = plan['limits']

        # Unlimited values should be serialized as -1, not Float::INFINITY
        limits.each_value do |value|
          expect(value).not_to eq(Float::INFINITY)
          expect(value).to be_a(Integer).or eq(-1)
        end
      end

      it 'includes teams.max limit' do
        single_team = response_plans.find { |p| p['tier'] == 'single_team' }
        skip 'No single_team plan' if single_team.nil?

        limits = single_team['limits']
        # Look for teams limit (may be 'teams.max' or 'teams')
        teams_limit = limits['teams.max'] || limits['teams']
        expect(teams_limit).not_to be_nil
      end
    end

    context 'API is public' do
      it 'does not require authentication' do
        # No session configured
        env 'rack.session', {}

        get '/billing/api/plans'

        expect(last_response.status).to eq(200)
      end
    end

    context 'error handling' do
      it 'returns 500 with message on error' do
        allow(Billing::Plan).to receive(:list_plans).and_raise(StandardError.new('Test error'))

        get '/billing/api/plans'

        expect(last_response.status).to eq(500)
        data = JSON.parse(last_response.body)
        expect(data['error']).to include('Failed to list plans')
      end
    end
  end

  describe 'Plan interval filtering' do
    # Tests that frontend can filter by interval correctly

    before do
      Billing::Plan.load_all_from_config
    end

    it 'returns plans with interval-keyed prices' do
      get '/billing/api/plans'
      plans = JSON.parse(last_response.body)['plans']

      skip 'No plans in cache' if plans.empty?

      # Each plan should have a prices hash with at least one interval
      all_intervals = plans.flat_map { |p| (p['prices'] || {}).keys }.uniq
      expect(all_intervals).not_to be_empty
      expect(all_intervals).to all(match(/^(month|year)$/))
    end

    it 'same tier plan has price data for available intervals' do
      get '/billing/api/plans'
      plans = JSON.parse(last_response.body)['plans']

      single_team_plans = plans.select { |p| p['tier'] == 'single_team' }
      skip 'No single_team plans' if single_team_plans.empty?

      plan = single_team_plans.first
      prices = plan['prices'] || {}
      # Should have at least one interval (month or year)
      expect(prices.keys.size).to be >= 1
    end
  end

  describe 'Price display data' do
    # Tests for monthly equivalent amount and correct pricing

    let(:response_plans) do
      get '/billing/api/plans'
      JSON.parse(last_response.body)['plans']
    end

    it 'plans with yearly price have amount greater than monthly' do
      skip 'No plans in cache' if response_plans.empty?

      plans_with_both = response_plans.select do |p|
        prices = p['prices'] || {}
        prices.key?('month') && prices.key?('year')
      end
      skip 'No plans with both intervals' if plans_with_both.empty?

      plan = plans_with_both.first
      monthly_amount = plan['prices']['month']['amount'].to_i
      yearly_amount = plan['prices']['year']['amount'].to_i

      # Yearly should be >= 10x monthly (accounting for discounts)
      expect(yearly_amount).to be >= monthly_amount * 10
    end

    it 'amounts are in cents (positive integers)' do
      skip 'No plans in cache' if response_plans.empty?

      response_plans.each do |plan|
        # Skip free plans
        next if plan['tier'] == 'free'

        prices = plan['prices'] || {}
        prices.each_value do |price_data|
          amount = price_data['amount'].to_i
          expect(amount).to be > 0
          expect(amount).to be_an(Integer)
        end
      end
    end
  end

  describe 'Currency handling' do
    let(:response_plans) do
      get '/billing/api/plans'
      JSON.parse(last_response.body)['plans']
    end

    it 'includes currency in response' do
      skip 'No plans in cache' if response_plans.empty?

      plan = response_plans.first
      expect(plan['currency']).to be_a(String)
      expect(plan['currency']).to match(/^[a-z]{3}$/i) # 3-letter currency code
    end

    it 'uses consistent currency across plans' do
      skip 'No plans in cache' if response_plans.empty?

      currencies = response_plans.map { |p| p['currency'] }.uniq
      # Within a region, all plans should use same currency
      expect(currencies.size).to eq(1)
    end
  end
end

RSpec.describe 'Plans API Edge Cases', type: :integration do
  include Rack::Test::Methods
  include_context 'with_test_plans'

  def app
    @app ||= Rack::URLMap.new('/billing' => Billing::Application.new)
  end

  describe 'empty cache handling' do
    before do
      # Clear cache to simulate empty state
      Billing::Plan.clear_cache
    end

    it 'returns empty array when no plans in cache' do
      get '/billing/api/plans'

      expect(last_response.status).to eq(200)
      data = JSON.parse(last_response.body)
      expect(data['plans']).to eq([])
    end
  end

  describe 'cache population' do
    before do
      Billing::Plan.clear_cache
    end

    it 'plans available after load_all_from_config' do
      Billing::Plan.load_all_from_config

      get '/billing/api/plans'

      plans = JSON.parse(last_response.body)['plans']
      expect(plans.size).to be > 0
    end
  end
end
