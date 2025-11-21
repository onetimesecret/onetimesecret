# frozen_string_literal: true

require 'spec_helper'
require 'cli/cli_spec_helper'
require_relative '../support/billing_spec_helper'
require_relative '../support/stripe_test_data'

RSpec.describe 'Billing Prices CLI Commands', type: :cli do
  let(:billing_config) { double('BillingConfig', enabled?: true, stripe_key: 'sk_test_123') }

  before do
    allow(OT).to receive(:billing_config).and_return(billing_config)
    allow(Stripe).to receive(:api_key=)
  end

  describe 'billing prices (list)' do
    let(:price1) do
      mock_stripe_price(
        id: 'price_monthly',
        product: 'prod_test1',
        unit_amount: 900,
        currency: 'usd',
        recurring: { interval: 'month', interval_count: 1 },
        active: true
      )
    end
    let(:price2) do
      mock_stripe_price(
        id: 'price_annual',
        product: 'prod_test1',
        unit_amount: 9600,
        currency: 'usd',
        recurring: { interval: 'year', interval_count: 1 },
        active: true
      )
    end
    let(:prices_list) { double('ListObject', data: [price1, price2]) }

    context 'with valid configuration' do
      it 'lists all active prices' do
        expect(Stripe::Price).to receive(:list).with(hash_including(active: true, limit: 100)).and_return(prices_list)

        output = run_cli_command_quietly('billing', 'prices')

        expect(output[:stdout]).to include('price_monthly')
        expect(output[:stdout]).to include('price_annual')
        expect(output[:stdout]).to include('Total: 2 price(s)')
        expect(last_exit_code).to eq(0)
      end

      it 'displays formatted table header' do
        allow(Stripe::Price).to receive(:list).and_return(prices_list)

        output = run_cli_command_quietly('billing', 'prices')

        expect(output[:stdout]).to match(/ID.*PRODUCT.*AMOUNT.*INTERVAL.*ACTIVE/)
      end

      it 'displays formatted price amounts' do
        allow(Stripe::Price).to receive(:list).and_return(prices_list)

        output = run_cli_command_quietly('billing', 'prices')

        expect(output[:stdout]).to match(/USD.*9\.00/)
        expect(output[:stdout]).to match(/USD.*96\.00/)
      end

      it 'displays billing intervals' do
        allow(Stripe::Price).to receive(:list).and_return(prices_list)

        output = run_cli_command_quietly('billing', 'prices')

        expect(output[:stdout]).to include('month')
        expect(output[:stdout]).to include('year')
      end
    end

    context 'with --product filter' do
      it 'filters prices by product ID' do
        expect(Stripe::Price).to receive(:list).with(
          hash_including(product: 'prod_specific', active: true)
        ).and_return(prices_list)

        output = run_cli_command_quietly('billing', 'prices', '--product', 'prod_specific')

        expect(last_exit_code).to eq(0)
      end
    end

    context 'with --active-only flag set to false' do
      let(:inactive_price) { mock_stripe_price(id: 'price_inactive', active: false) }
      let(:all_prices) { double('ListObject', data: [price1, inactive_price]) }

      it 'includes inactive prices' do
        expect(Stripe::Price).to receive(:list).with(hash_including(active: false)).and_return(all_prices)

        output = run_cli_command_quietly('billing', 'prices', '--no-active-only')

        expect(output[:stdout]).to include('price_inactive')
      end
    end

    context 'when no prices found' do
      it 'displays appropriate message' do
        empty_list = double('ListObject', data: [])
        allow(Stripe::Price).to receive(:list).and_return(empty_list)

        output = run_cli_command_quietly('billing', 'prices')

        expect(output[:stdout]).to include('No prices found')
        expect(last_exit_code).to eq(0)
      end
    end

    context 'when billing not configured' do
      let(:billing_config) { double('BillingConfig', enabled?: false) }

      it 'exits with configuration error' do
        output = run_cli_command_quietly('billing', 'prices')

        expect(output[:stdout]).to match(/billing not enabled/i)
      end
    end

    context 'displaying one-time prices' do
      let(:one_time_price) do
        mock_stripe_price(
          id: 'price_onetime',
          product: 'prod_test1',
          unit_amount: 5000,
          recurring: nil,
          active: true
        )
      end
      let(:mixed_prices) { double('ListObject', data: [price1, one_time_price]) }

      it 'shows one-time as interval' do
        allow(Stripe::Price).to receive(:list).and_return(mixed_prices)

        output = run_cli_command_quietly('billing', 'prices')

        expect(output[:stdout]).to include('one-time')
      end
    end
  end

  describe 'billing prices create' do
    let(:product) { mock_stripe_product(id: 'prod_test123', name: 'Test Product') }
    let(:price) { mock_stripe_price(id: 'price_new', unit_amount: 900, currency: 'usd') }

    before do
      allow(Stripe::Product).to receive(:retrieve).with('prod_test123').and_return(product)
      allow($stdin).to receive(:gets).and_return("y\n")
    end

    context 'with valid parameters' do
      it 'creates a recurring price' do
        expect(Stripe::Price).to receive(:create).with(
          hash_including(
            product: 'prod_test123',
            unit_amount: 900,
            currency: 'usd',
            recurring: hash_including(interval: 'month', interval_count: 1)
          )
        ).and_return(price)

        output = run_cli_command_quietly(
          'billing', 'prices', 'create', 'prod_test123',
          '--amount', '900'
        )

        expect(output[:stdout]).to include('Price created successfully')
        expect(last_exit_code).to eq(0)
      end

      it 'displays price details after creation' do
        allow(Stripe::Price).to receive(:create).and_return(price)

        output = run_cli_command_quietly(
          'billing', 'prices', 'create', 'prod_test123',
          '--amount', '900'
        )

        expect(output[:stdout]).to include('ID:')
        expect(output[:stdout]).to include('Amount:')
        expect(output[:stdout]).to include('Interval:')
      end

      it 'verifies product exists before creation' do
        expect(Stripe::Product).to receive(:retrieve).with('prod_test123').and_return(product)
        allow(Stripe::Price).to receive(:create).and_return(price)

        output = run_cli_command_quietly(
          'billing', 'prices', 'create', 'prod_test123',
          '--amount', '900'
        )

        expect(output[:stdout]).to include('Product: Test Product')
      end
    end

    context 'with different intervals' do
      it 'creates yearly price' do
        expect(Stripe::Price).to receive(:create).with(
          hash_including(
            recurring: hash_including(interval: 'year', interval_count: 1)
          )
        ).and_return(price)

        run_cli_command_quietly(
          'billing', 'prices', 'create', 'prod_test123',
          '--amount', '9600',
          '--interval', 'year'
        )

        expect(last_exit_code).to eq(0)
      end

      it 'creates weekly price' do
        expect(Stripe::Price).to receive(:create).with(
          hash_including(
            recurring: hash_including(interval: 'week', interval_count: 1)
          )
        ).and_return(price)

        run_cli_command_quietly(
          'billing', 'prices', 'create', 'prod_test123',
          '--amount', '200',
          '--interval', 'week'
        )
      end

      it 'creates daily price' do
        expect(Stripe::Price).to receive(:create).with(
          hash_including(
            recurring: hash_including(interval: 'day', interval_count: 1)
          )
        ).and_return(price)

        run_cli_command_quietly(
          'billing', 'prices', 'create', 'prod_test123',
          '--amount', '50',
          '--interval', 'day'
        )
      end
    end

    context 'with interval_count option' do
      it 'creates price with custom interval count' do
        expect(Stripe::Price).to receive(:create).with(
          hash_including(
            recurring: hash_including(interval: 'month', interval_count: 3)
          )
        ).and_return(price)

        output = run_cli_command_quietly(
          'billing', 'prices', 'create', 'prod_test123',
          '--amount', '2400',
          '--interval-count', '3'
        )

        expect(output[:stdout]).to match(/interval:.*3.*month/i)
      end
    end

    context 'with different currency' do
      it 'creates price in EUR' do
        eur_price = mock_stripe_price(unit_amount: 850, currency: 'eur')
        expect(Stripe::Price).to receive(:create).with(
          hash_including(currency: 'eur')
        ).and_return(eur_price)

        run_cli_command_quietly(
          'billing', 'prices', 'create', 'prod_test123',
          '--amount', '850',
          '--currency', 'eur'
        )

        expect(last_exit_code).to eq(0)
      end
    end

    context 'without product_id parameter (interactive mode)' do
      before do
        allow($stdin).to receive(:gets).and_return("prod_test123\n", "900\n", "y\n")
      end

      it 'prompts for product ID' do
        allow(Stripe::Price).to receive(:create).and_return(price)

        output = run_cli_command_quietly('billing', 'prices', 'create')

        expect(output[:stdout]).to include('Product ID:')
      end
    end

    context 'without amount parameter (interactive mode)' do
      before do
        allow($stdin).to receive(:gets).and_return("900\n", "y\n")
      end

      it 'prompts for amount' do
        allow(Stripe::Price).to receive(:create).and_return(price)

        output = run_cli_command_quietly('billing', 'prices', 'create', 'prod_test123')

        expect(output[:stdout]).to include('Amount in cents')
      end
    end

    context 'with empty product ID' do
      before do
        allow($stdin).to receive(:gets).and_return("\n")
      end

      it 'displays validation error' do
        output = run_cli_command_quietly('billing', 'prices', 'create', '')

        expect(output[:stdout]).to match(/error.*product id.*required/i)
      end
    end

    context 'with zero amount' do
      before do
        allow($stdin).to receive(:gets).and_return("0\n")
      end

      it 'displays validation error' do
        output = run_cli_command_quietly('billing', 'prices', 'create', 'prod_test123', '--amount', '0')

        expect(output[:stdout]).to match(/error.*amount.*greater than 0/i)
      end
    end

    context 'with negative amount' do
      before do
        allow($stdin).to receive(:gets).and_return("-100\n")
      end

      it 'displays validation error' do
        output = run_cli_command_quietly('billing', 'prices', 'create', 'prod_test123', '--amount', '-100')

        expect(output[:stdout]).to match(/error.*amount.*greater than 0/i)
      end
    end

    context 'with invalid interval' do
      it 'displays validation error' do
        output = run_cli_command_quietly(
          'billing', 'prices', 'create', 'prod_test123',
          '--amount', '900',
          '--interval', 'invalid'
        )

        expect(output[:stdout]).to match(/error.*interval must be one of/i)
      end
    end

    context 'when user declines confirmation' do
      before do
        allow($stdin).to receive(:gets).and_return("n\n")
      end

      it 'does not create price' do
        expect(Stripe::Price).not_to receive(:create)

        run_cli_command_quietly('billing', 'prices', 'create', 'prod_test123', '--amount', '900')
      end
    end

    context 'when product does not exist' do
      it 'displays error message' do
        allow(Stripe::Product).to receive(:retrieve).and_raise(
          Stripe::InvalidRequestError.new('No such product', 'product', http_status: 404)
        )

        output = run_cli_command_quietly('billing', 'prices', 'create', 'prod_invalid', '--amount', '900')

        expect(output[:stdout]).to match(/error creating price/i)
      end
    end

    context 'when Stripe API fails' do
      it 'displays error message' do
        allow(Stripe::Price).to receive(:create).and_raise(
          Stripe::InvalidRequestError.new('Invalid price', 'price', http_status: 400)
        )

        output = run_cli_command_quietly('billing', 'prices', 'create', 'prod_test123', '--amount', '900')

        expect(output[:stdout]).to match(/error creating price/i)
      end
    end

    context 'displaying amount formatting' do
      it 'formats amount correctly in confirmation' do
        allow(Stripe::Price).to receive(:create).and_return(price)

        output = run_cli_command_quietly(
          'billing', 'prices', 'create', 'prod_test123',
          '--amount', '1299'
        )

        expect(output[:stdout]).to match(/USD.*12\.99/)
      end

      it 'formats amount correctly for different currency' do
        gbp_price = mock_stripe_price(unit_amount: 799, currency: 'gbp')
        allow(Stripe::Price).to receive(:create).and_return(gbp_price)

        output = run_cli_command_quietly(
          'billing', 'prices', 'create', 'prod_test123',
          '--amount', '799',
          '--currency', 'gbp'
        )

        expect(output[:stdout]).to match(/GBP.*7\.99/)
      end
    end
  end

  describe 'price validation' do
    let(:product) { mock_stripe_product(id: 'prod_test123') }

    before do
      allow(Stripe::Product).to receive(:retrieve).and_return(product)
      allow($stdin).to receive(:gets).and_return("y\n")
    end

    context 'amount validation' do
      it 'accepts valid positive amounts' do
        valid_amounts = [1, 100, 999, 1000, 10000, 999999]

        valid_amounts.each do |amount|
          price = mock_stripe_price(unit_amount: amount)
          allow(Stripe::Price).to receive(:create).and_return(price)

          output = run_cli_command_quietly(
            'billing', 'prices', 'create', 'prod_test123',
            '--amount', amount.to_s
          )

          expect(last_exit_code).to eq(0), "Failed for amount: #{amount}"
        end
      end
    end

    context 'interval validation' do
      it 'accepts valid intervals' do
        valid_intervals = %w[month year week day]

        valid_intervals.each do |interval|
          price = mock_stripe_price(recurring: { interval: interval })
          allow(Stripe::Price).to receive(:create).and_return(price)

          output = run_cli_command_quietly(
            'billing', 'prices', 'create', 'prod_test123',
            '--amount', '900',
            '--interval', interval
          )

          expect(last_exit_code).to eq(0), "Failed for interval: #{interval}"
        end
      end

      it 'rejects invalid intervals' do
        invalid_intervals = %w[hourly biweekly quarterly]

        invalid_intervals.each do |interval|
          output = run_cli_command_quietly(
            'billing', 'prices', 'create', 'prod_test123',
            '--amount', '900',
            '--interval', interval
          )

          expect(output[:stdout]).to match(/error.*interval/i), "Should reject interval: #{interval}"
        end
      end
    end

    context 'currency validation' do
      it 'accepts standard currency codes' do
        currencies = %w[usd eur gbp jpy cad]

        currencies.each do |currency|
          price = mock_stripe_price(currency: currency)
          allow(Stripe::Price).to receive(:create).and_return(price)

          output = run_cli_command_quietly(
            'billing', 'prices', 'create', 'prod_test123',
            '--amount', '900',
            '--currency', currency
          )

          expect(last_exit_code).to eq(0), "Failed for currency: #{currency}"
        end
      end
    end
  end

  describe 'integration scenarios' do
    let(:product) { mock_stripe_product(id: 'prod_workflow', name: 'Workflow Product') }

    it 'create multiple prices for same product' do
      allow(Stripe::Product).to receive(:retrieve).and_return(product)
      allow($stdin).to receive(:gets).and_return("y\n")

      # Create monthly price
      monthly_price = mock_stripe_price(id: 'price_monthly', unit_amount: 900)
      allow(Stripe::Price).to receive(:create).with(
        hash_including(recurring: hash_including(interval: 'month'))
      ).and_return(monthly_price)

      output = run_cli_command_quietly(
        'billing', 'prices', 'create', 'prod_workflow',
        '--amount', '900',
        '--interval', 'month'
      )
      expect(output[:stdout]).to include('Price created successfully')

      # Create annual price
      annual_price = mock_stripe_price(id: 'price_annual', unit_amount: 9600)
      allow(Stripe::Price).to receive(:create).with(
        hash_including(recurring: hash_including(interval: 'year'))
      ).and_return(annual_price)

      output = run_cli_command_quietly(
        'billing', 'prices', 'create', 'prod_workflow',
        '--amount', '9600',
        '--interval', 'year'
      )
      expect(output[:stdout]).to include('Price created successfully')

      # List prices for product
      prices_list = double('ListObject', data: [monthly_price, annual_price])
      allow(Stripe::Price).to receive(:list).and_return(prices_list)

      output = run_cli_command_quietly('billing', 'prices', '--product', 'prod_workflow')
      expect(output[:stdout]).to include('price_monthly')
      expect(output[:stdout]).to include('price_annual')
    end

    it 'handles price creation with various configurations' do
      allow(Stripe::Product).to receive(:retrieve).and_return(product)
      allow($stdin).to receive(:gets).and_return("y\n")

      # Standard monthly
      price1 = mock_stripe_price(id: 'price_1')
      allow(Stripe::Price).to receive(:create).and_return(price1)
      output = run_cli_command_quietly('billing', 'prices', 'create', 'prod_workflow', '--amount', '900')
      expect(last_exit_code).to eq(0)

      # Quarterly (3-month interval)
      price2 = mock_stripe_price(id: 'price_2')
      allow(Stripe::Price).to receive(:create).and_return(price2)
      output = run_cli_command_quietly(
        'billing', 'prices', 'create', 'prod_workflow',
        '--amount', '2400',
        '--interval-count', '3'
      )
      expect(last_exit_code).to eq(0)

      # Different currency
      price3 = mock_stripe_price(id: 'price_3', currency: 'eur')
      allow(Stripe::Price).to receive(:create).and_return(price3)
      output = run_cli_command_quietly(
        'billing', 'prices', 'create', 'prod_workflow',
        '--amount', '850',
        '--currency', 'eur'
      )
      expect(last_exit_code).to eq(0)
    end
  end
end
