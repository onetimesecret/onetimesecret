# frozen_string_literal: true

require 'spec_helper'
require 'cli/cli_spec_helper'
require_relative '../support/billing_spec_helper'
require_relative '../support/stripe_test_data'

RSpec.describe 'Billing Plans CLI Commands', type: :cli do
  let(:billing_config) { double('BillingConfig', enabled?: true, stripe_key: 'sk_test_123') }

  before do
    allow(OT).to receive(:billing_config).and_return(billing_config)
    allow(Stripe).to receive(:api_key=)
  end

  describe 'billing plans (list)' do
    let(:plan1) do
      double('Plan',
        plan_id: 'personal_monthly_us',
        tier: 'personal',
        interval: 'month',
        amount: '900',
        currency: 'usd',
        region: 'US',
        capabilities: '["create_secrets","email_support"]'
      )
    end

    let(:plan2) do
      double('Plan',
        plan_id: 'professional_yearly_eu',
        tier: 'professional',
        interval: 'year',
        amount: '9600',
        currency: 'eur',
        region: 'EU',
        capabilities: '["create_secrets","api_access","priority_support"]'
      )
    end

    let(:plans) { [plan1, plan2] }

    context 'with cached plans' do
      before do
        allow(Billing::Plan).to receive(:list_plans).and_return(plans)
      end

      it 'lists all cached plans' do
        output = run_cli_command_quietly('billing', 'plans')

        expect(output[:stdout]).to include('personal_monthly_us')
        expect(output[:stdout]).to include('professional_yearly_eu')
        expect(output[:stdout]).to include('Total: 2 plan entries')
        expect(last_exit_code).to eq(0)
      end

      it 'displays formatted table header' do
        output = run_cli_command_quietly('billing', 'plans')

        expect(output[:stdout]).to match(/PLAN ID.*TIER.*INTERVAL.*AMOUNT.*REGION.*CAPS/)
      end

      it 'displays plan details' do
        output = run_cli_command_quietly('billing', 'plans')

        expect(output[:stdout]).to include('personal')
        expect(output[:stdout]).to include('professional')
        expect(output[:stdout]).to include('month')
        expect(output[:stdout]).to include('year')
      end

      it 'displays formatted amounts' do
        output = run_cli_command_quietly('billing', 'plans')

        expect(output[:stdout]).to match(/USD.*9\.00/)
        expect(output[:stdout]).to match(/EUR.*96\.00/)
      end

      it 'displays capability counts' do
        output = run_cli_command_quietly('billing', 'plans')

        # plan1 has 2 capabilities, plan2 has 3
        expect(output[:stdout]).to match(/2/)
        expect(output[:stdout]).to match(/3/)
      end
    end

    context 'when no cached plans' do
      before do
        allow(Billing::Plan).to receive(:list_plans).and_return([])
      end

      it 'displays appropriate message' do
        output = run_cli_command_quietly('billing', 'plans')

        expect(output[:stdout]).to include('No plan entries found')
        expect(output[:stdout]).to match(/run with --refresh/i)
        expect(last_exit_code).to eq(0)
      end
    end

    context 'when billing not configured' do
      let(:billing_config) { double('BillingConfig', enabled?: false) }

      it 'exits with configuration error' do
        output = run_cli_command_quietly('billing', 'plans')

        expect(output[:stdout]).to match(/billing not enabled/i)
      end
    end

    context 'with long plan IDs' do
      let(:long_plan) do
        double('Plan',
          plan_id: 'enterprise_premium_quarterly_us_east_coast',
          tier: 'enterprise_premium',
          interval: 'month',
          amount: '50000',
          currency: 'usd',
          region: 'US',
          capabilities: '[]'
        )
      end

      it 'truncates long plan IDs' do
        allow(Billing::Plan).to receive(:list_plans).and_return([long_plan])

        output = run_cli_command_quietly('billing', 'plans')

        # Plan ID column is 20 chars wide, so should be truncated
        expect(output[:stdout]).to match(/enterprise_premium_q/)
      end
    end
  end

  describe 'billing plans --refresh' do
    let(:product) do
      mock_stripe_product(
        id: 'prod_test123',
        name: 'Test Product',
        metadata: {
          'app' => 'onetimesecret',
          'tier' => 'personal',
          'region' => 'US',
          'capabilities' => 'create_secrets,email_support'
        },
        active: true
      )
    end

    let(:price) do
      mock_stripe_price(
        id: 'price_test123',
        product: 'prod_test123',
        unit_amount: 900,
        currency: 'usd',
        recurring: { interval: 'month' },
        type: 'recurring',
        active: true
      )
    end

    let(:products_list) { double('ListObject', data: [product]) }
    let(:prices_list) { double('ListObject', data: [price]) }

    before do
      allow(Stripe::Product).to receive(:list).and_return(products_list)
      allow(products_list).to receive(:auto_paging_each).and_yield(product)
      allow(Stripe::Price).to receive(:list).and_return(prices_list)
      allow(prices_list).to receive(:auto_paging_each).and_yield(price)
    end

    context 'with valid Stripe data' do
      it 'refreshes plans from Stripe' do
        expect(Billing::Plan).to receive(:refresh_from_stripe).and_return(1)
        allow(Billing::Plan).to receive(:list_plans).and_return([])

        output = run_cli_command_quietly('billing', 'plans', '--refresh')

        expect(output[:stdout]).to include('Refreshing plans from Stripe')
        expect(output[:stdout]).to match(/refreshed.*1.*plan/i)
        expect(last_exit_code).to eq(0)
      end

      it 'displays count of refreshed plans' do
        expect(Billing::Plan).to receive(:refresh_from_stripe).and_return(5)
        allow(Billing::Plan).to receive(:list_plans).and_return([])

        output = run_cli_command_quietly('billing', 'plans', '--refresh')

        expect(output[:stdout]).to include('5 plan entries')
      end

      it 'lists plans after refresh' do
        plan = double('Plan',
          plan_id: 'personal_monthly_us',
          tier: 'personal',
          interval: 'month',
          amount: '900',
          currency: 'usd',
          region: 'US',
          capabilities: '[]'
        )

        allow(Billing::Plan).to receive(:refresh_from_stripe).and_return(1)
        allow(Billing::Plan).to receive(:list_plans).and_return([plan])

        output = run_cli_command_quietly('billing', 'plans', '--refresh')

        expect(output[:stdout]).to include('personal_monthly_us')
      end
    end

    context 'when Stripe API fails' do
      it 'handles connection errors gracefully' do
        allow(Billing::Plan).to receive(:refresh_from_stripe).and_raise(
          Stripe::APIConnectionError.new('Network error')
        )

        expect {
          run_cli_command_quietly('billing', 'plans', '--refresh')
        }.not_to raise_error
      end

      it 'handles authentication errors' do
        allow(Billing::Plan).to receive(:refresh_from_stripe).and_raise(
          Stripe::AuthenticationError.new('Invalid API key', http_status: 401)
        )

        expect {
          run_cli_command_quietly('billing', 'plans', '--refresh')
        }.not_to raise_error
      end

      it 'handles rate limit errors' do
        allow(Billing::Plan).to receive(:refresh_from_stripe).and_raise(
          Stripe::RateLimitError.new('Rate limit exceeded', http_status: 429)
        )

        expect {
          run_cli_command_quietly('billing', 'plans', '--refresh')
        }.not_to raise_error
      end
    end

    context 'without Stripe API key' do
      let(:billing_config) { double('BillingConfig', enabled?: true, stripe_key: '') }

      it 'skips refresh gracefully' do
        allow(Billing::Plan).to receive(:refresh_from_stripe).and_return(0)
        allow(Billing::Plan).to receive(:list_plans).and_return([])

        output = run_cli_command_quietly('billing', 'plans', '--refresh')

        expect(output[:stdout]).to include('Refreshed 0 plan entries')
      end
    end
  end

  describe 'plan cache behavior' do
    let(:redis) { double('Redis') }

    before do
      allow(Familia).to receive(:dbclient).and_return(redis)
    end

    context 'cache expiration' do
      it 'respects 12-hour default expiration' do
        # This test verifies the Plan model's configuration
        expect(Billing::Plan.default_expiration).to eq(12 * 3600) # 12 hours in seconds
      end
    end

    context 'cache invalidation' do
      let(:plan) do
        double('Plan',
          plan_id: 'test_monthly_us',
          destroy!: true
        )
      end

      it 'can clear the cache' do
        allow(Billing::Plan).to receive_message_chain(:instances, :to_a).and_return(['test_monthly_us'])
        allow(Billing::Plan).to receive(:load).with('test_monthly_us').and_return(plan)
        allow(Billing::Plan).to receive_message_chain(:instances, :clear)

        expect(plan).to receive(:destroy!)

        Billing::Plan.clear_cache
      end
    end
  end

  describe 'plan data parsing' do
    let(:plan) do
      Billing::Plan.new(
        plan_id: 'test_monthly_us',
        capabilities: '["create_secrets","api_access"]',
        features: '["Unlimited secrets","Priority support"]',
        limits: '{"teams":5,"members_per_team":-1}'
      )
    end

    it 'parses capabilities JSON' do
      expect(plan.parsed_capabilities).to eq(['create_secrets', 'api_access'])
    end

    it 'parses features JSON' do
      expect(plan.parsed_features).to eq(['Unlimited secrets', 'Priority support'])
    end

    it 'parses limits JSON' do
      limits = plan.parsed_limits
      expect(limits['teams']).to eq(5)
    end

    it 'converts -1 limits to infinity' do
      limits = plan.parsed_limits
      expect(limits['members_per_team']).to eq(Float::INFINITY)
    end

    context 'with invalid JSON' do
      let(:plan_with_bad_json) do
        Billing::Plan.new(
          plan_id: 'test_monthly_us',
          capabilities: 'invalid json',
          features: '{broken',
          limits: 'not json'
        )
      end

      it 'handles invalid capabilities gracefully' do
        allow(Onetime).to receive(:billing_logger).and_return(double(error: nil))

        expect(plan_with_bad_json.parsed_capabilities).to eq([])
      end

      it 'handles invalid features gracefully' do
        allow(Onetime).to receive(:billing_logger).and_return(double(error: nil))

        expect(plan_with_bad_json.parsed_features).to eq([])
      end

      it 'handles invalid limits gracefully' do
        allow(Onetime).to receive(:billing_logger).and_return(double(error: nil))

        expect(plan_with_bad_json.parsed_limits).to eq({})
      end
    end
  end

  describe 'plan filtering and lookup' do
    let(:monthly_plan) do
      double('Plan',
        plan_id: 'personal_monthly_us',
        tier: 'personal',
        interval: 'month',
        region: 'US',
        amount: '900',
        currency: 'usd',
        capabilities: '[]'
      )
    end

    let(:yearly_plan) do
      double('Plan',
        plan_id: 'personal_yearly_us',
        tier: 'personal',
        interval: 'year',
        region: 'US',
        amount: '9600',
        currency: 'usd',
        capabilities: '[]'
      )
    end

    let(:eu_plan) do
      double('Plan',
        plan_id: 'personal_monthly_eu',
        tier: 'personal',
        interval: 'month',
        region: 'EU',
        amount: '850',
        currency: 'eur',
        capabilities: '[]'
      )
    end

    before do
      allow(Billing::Plan).to receive(:list_plans).and_return([monthly_plan, yearly_plan, eu_plan])
    end

    it 'finds plan by tier, interval, and region' do
      plan = Billing::Plan.get_plan('personal', 'month', 'US')
      expect(plan).to eq(monthly_plan)
    end

    it 'normalizes interval with "ly" suffix' do
      plan = Billing::Plan.get_plan('personal', 'monthly', 'US')
      expect(plan).to eq(monthly_plan)
    end

    it 'distinguishes by region' do
      us_plan = Billing::Plan.get_plan('personal', 'month', 'US')
      eu_plan_result = Billing::Plan.get_plan('personal', 'month', 'EU')

      expect(us_plan).to eq(monthly_plan)
      expect(eu_plan_result).to eq(eu_plan)
    end

    it 'returns nil for non-existent plan' do
      plan = Billing::Plan.get_plan('enterprise', 'month', 'US')
      expect(plan).to be_nil
    end
  end

  describe 'Stripe product metadata validation' do
    let(:valid_product) do
      mock_stripe_product(
        metadata: {
          'app' => 'onetimesecret',
          'tier' => 'personal',
          'region' => 'US'
        }
      )
    end

    let(:missing_app_product) do
      mock_stripe_product(
        metadata: {
          'tier' => 'personal',
          'region' => 'US'
        }
      )
    end

    let(:missing_tier_product) do
      mock_stripe_product(
        metadata: {
          'app' => 'onetimesecret',
          'region' => 'US'
        }
      )
    end

    let(:missing_region_product) do
      mock_stripe_product(
        metadata: {
          'app' => 'onetimesecret',
          'tier' => 'personal'
        }
      )
    end

    it 'accepts products with required metadata' do
      products_list = double('ListObject', data: [valid_product])
      allow(Stripe::Product).to receive(:list).and_return(products_list)
      allow(products_list).to receive(:auto_paging_each).and_yield(valid_product)

      price = mock_stripe_price(type: 'recurring', recurring: { interval: 'month' })
      prices_list = double('ListObject', data: [price])
      allow(Stripe::Price).to receive(:list).and_return(prices_list)
      allow(prices_list).to receive(:auto_paging_each).and_yield(price)

      count = Billing::Plan.refresh_from_stripe
      expect(count).to eq(1)
    end

    it 'skips products without app metadata' do
      products_list = double('ListObject', data: [missing_app_product])
      allow(Stripe::Product).to receive(:list).and_return(products_list)
      allow(products_list).to receive(:auto_paging_each).and_yield(missing_app_product)

      count = Billing::Plan.refresh_from_stripe
      expect(count).to eq(0)
    end

    it 'skips products without tier metadata' do
      products_list = double('ListObject', data: [missing_tier_product])
      allow(Stripe::Product).to receive(:list).and_return(products_list)
      allow(products_list).to receive(:auto_paging_each).and_yield(missing_tier_product)

      count = Billing::Plan.refresh_from_stripe
      expect(count).to eq(0)
    end

    it 'skips products without region metadata' do
      products_list = double('ListObject', data: [missing_region_product])
      allow(Stripe::Product).to receive(:list).and_return(products_list)
      allow(products_list).to receive(:auto_paging_each).and_yield(missing_region_product)

      count = Billing::Plan.refresh_from_stripe
      expect(count).to eq(0)
    end
  end

  describe 'price type filtering' do
    let(:product) do
      mock_stripe_product(
        metadata: {
          'app' => 'onetimesecret',
          'tier' => 'personal',
          'region' => 'US'
        }
      )
    end

    let(:recurring_price) do
      mock_stripe_price(
        id: 'price_recurring',
        type: 'recurring',
        recurring: { interval: 'month' }
      )
    end

    let(:one_time_price) do
      mock_stripe_price(
        id: 'price_onetime',
        type: 'one_time',
        recurring: nil
      )
    end

    it 'includes only recurring prices' do
      products_list = double('ListObject', data: [product])
      allow(Stripe::Product).to receive(:list).and_return(products_list)
      allow(products_list).to receive(:auto_paging_each).and_yield(product)

      prices_list = double('ListObject', data: [recurring_price, one_time_price])
      allow(Stripe::Price).to receive(:list).and_return(prices_list)
      allow(prices_list).to receive(:auto_paging_each).and_yield(recurring_price).and_yield(one_time_price)

      count = Billing::Plan.refresh_from_stripe
      expect(count).to eq(1) # Only recurring price should be cached
    end
  end

  describe 'plan ID generation' do
    let(:product_with_explicit_id) do
      mock_stripe_product(
        metadata: {
          'app' => 'onetimesecret',
          'plan_id' => 'custom_plan_v2',
          'tier' => 'enterprise',
          'region' => 'EU'
        }
      )
    end

    let(:product_without_explicit_id) do
      mock_stripe_product(
        metadata: {
          'app' => 'onetimesecret',
          'tier' => 'personal',
          'region' => 'US'
        }
      )
    end

    let(:price) do
      mock_stripe_price(type: 'recurring', recurring: { interval: 'month' })
    end

    it 'uses explicit plan_id from metadata when provided' do
      products_list = double('ListObject', data: [product_with_explicit_id])
      allow(Stripe::Product).to receive(:list).and_return(products_list)
      allow(products_list).to receive(:auto_paging_each).and_yield(product_with_explicit_id)

      prices_list = double('ListObject', data: [price])
      allow(Stripe::Price).to receive(:list).and_return(prices_list)
      allow(prices_list).to receive(:auto_paging_each).and_yield(price)

      Billing::Plan.refresh_from_stripe

      # Verify the custom plan_id was used
      plans = Billing::Plan.list_plans
      expect(plans.first.plan_id).to eq('custom_plan_v2')
    end

    it 'generates plan_id from tier_interval_region when not provided' do
      products_list = double('ListObject', data: [product_without_explicit_id])
      allow(Stripe::Product).to receive(:list).and_return(products_list)
      allow(products_list).to receive(:auto_paging_each).and_yield(product_without_explicit_id)

      prices_list = double('ListObject', data: [price])
      allow(Stripe::Price).to receive(:list).and_return(prices_list)
      allow(prices_list).to receive(:auto_paging_each).and_yield(price)

      Billing::Plan.refresh_from_stripe

      # Verify generated plan_id follows pattern
      plans = Billing::Plan.list_plans
      expect(plans.first.plan_id).to match(/personal_monthly_US/)
    end
  end

  describe 'integration scenarios' do
    it 'handles full refresh and list workflow' do
      # Setup products and prices
      product = mock_stripe_product(
        metadata: {
          'app' => 'onetimesecret',
          'tier' => 'professional',
          'region' => 'US',
          'capabilities' => 'api_access,custom_domains'
        }
      )

      monthly_price = mock_stripe_price(
        type: 'recurring',
        recurring: { interval: 'month' },
        unit_amount: 1900
      )

      yearly_price = mock_stripe_price(
        type: 'recurring',
        recurring: { interval: 'year' },
        unit_amount: 19200
      )

      products_list = double('ListObject', data: [product])
      allow(Stripe::Product).to receive(:list).and_return(products_list)
      allow(products_list).to receive(:auto_paging_each).and_yield(product)

      prices_list = double('ListObject', data: [monthly_price, yearly_price])
      allow(Stripe::Price).to receive(:list).and_return(prices_list)
      allow(prices_list).to receive(:auto_paging_each).and_yield(monthly_price).and_yield(yearly_price)

      # Refresh plans
      allow(Billing::Plan).to receive(:refresh_from_stripe).and_return(2)

      plan1 = double('Plan',
        plan_id: 'professional_monthly_us',
        tier: 'professional',
        interval: 'month',
        amount: '1900',
        currency: 'usd',
        region: 'US',
        capabilities: '["api_access","custom_domains"]'
      )

      plan2 = double('Plan',
        plan_id: 'professional_yearly_us',
        tier: 'professional',
        interval: 'year',
        amount: '19200',
        currency: 'usd',
        region: 'US',
        capabilities: '["api_access","custom_domains"]'
      )

      allow(Billing::Plan).to receive(:list_plans).and_return([plan1, plan2])

      output = run_cli_command_quietly('billing', 'plans', '--refresh')

      expect(output[:stdout]).to include('Refreshed 2 plan entries')
      expect(output[:stdout]).to include('professional_monthly_us')
      expect(output[:stdout]).to include('professional_yearly_us')
    end
  end
end
