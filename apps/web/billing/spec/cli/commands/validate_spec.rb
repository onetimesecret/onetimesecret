# frozen_string_literal: true

require 'spec_helper'
require 'cli/cli_spec_helper'
require_relative '../../support/billing_spec_helper'

RSpec.describe 'Billing validate CLI command', type: :cli do
  let(:valid_product) do
    mock_stripe_product(
      id: 'prod_valid',
      name: 'Valid Product',
      metadata: {
        'app' => 'web',
        'tier' => 'personal',
        'region' => 'US'
      }
    )
  end

  let(:invalid_product_missing_tier) do
    mock_stripe_product(
      id: 'prod_invalid1',
      name: 'Missing Tier',
      metadata: {
        'app' => 'web',
        'region' => 'US'
      }
    )
  end

  let(:invalid_product_missing_region) do
    mock_stripe_product(
      id: 'prod_invalid2',
      name: 'Missing Region',
      metadata: {
        'app' => 'web',
        'tier' => 'personal'
      }
    )
  end

  let(:invalid_product_missing_app) do
    mock_stripe_product(
      id: 'prod_invalid3',
      name: 'Missing App',
      metadata: {
        'tier' => 'personal',
        'region' => 'US'
      }
    )
  end

  before do
    # Mock billing configuration
    billing_config = double('BillingConfig',
      enabled?: true,
      stripe_key: 'sk_test_123456'
    )
    allow(OT).to receive(:billing_config).and_return(billing_config)

    # Set Stripe API key
    Stripe.api_key = 'sk_test_123456'
  end

  describe 'billing validate' do
    context 'when all products are valid' do
      before do
        products = double('ListObject', data: [valid_product, valid_product])
        allow(Stripe::Product).to receive(:list).and_return(products)
      end

      it 'validates product metadata successfully' do
        output = run_cli_command_quietly('billing', 'validate')

        expect(output[:stdout]).to include('All 2 product(s) have valid metadata')
        expect(last_exit_code).to eq(0)
      end

      it 'displays success checkmark' do
        output = run_cli_command_quietly('billing', 'validate')

        expect(output[:stdout]).to include('✓')
      end
    end

    context 'when products have validation errors' do
      before do
        products = double('ListObject', data: [
          valid_product,
          invalid_product_missing_tier,
          invalid_product_missing_region
        ])
        allow(Stripe::Product).to receive(:list).and_return(products)
      end

      it 'reports products with errors' do
        output = run_cli_command_quietly('billing', 'validate')

        expect(output[:stdout]).to include('2 product(s) have metadata errors')
        expect(output[:stdout]).to include('Missing Tier')
        expect(output[:stdout]).to include('Missing Region')
      end

      it 'shows specific error details' do
        output = run_cli_command_quietly('billing', 'validate')

        expect(output[:stdout]).to include('✗')
        expect(output[:stdout]).to match(/Missing.*tier/i)
        expect(output[:stdout]).to match(/Missing.*region/i)
      end

      it 'displays required metadata fields' do
        output = run_cli_command_quietly('billing', 'validate')

        expect(output[:stdout]).to include('Required metadata fields:')
      end
    end

    context 'with different metadata errors' do
      before do
        products = double('ListObject', data: [invalid_product_missing_app])
        allow(Stripe::Product).to receive(:list).and_return(products)
      end

      it 'detects missing app field' do
        output = run_cli_command_quietly('billing', 'validate')

        expect(output[:stdout]).to include('Missing App')
        expect(output[:stdout]).to match(/Missing.*app/i)
      end
    end

    context 'when no products exist' do
      before do
        products = double('ListObject', data: [])
        allow(Stripe::Product).to receive(:list).and_return(products)
      end

      it 'displays no products message' do
        output = run_cli_command_quietly('billing', 'validate')

        expect(output[:stdout]).to include('No products found')
        expect(last_exit_code).to eq(0)
      end

      it 'does not show validation errors' do
        output = run_cli_command_quietly('billing', 'validate')

        expect(output[:stdout]).not_to include('metadata errors')
      end
    end

    context 'when fetching active products' do
      before do
        products = double('ListObject', data: [valid_product])
        allow(Stripe::Product).to receive(:list).and_return(products)
      end

      it 'requests only active products' do
        expect(Stripe::Product).to receive(:list).with(hash_including(
          active: true,
          limit: 100
        ))

        run_cli_command_quietly('billing', 'validate')
      end
    end

    context 'when Stripe API fails' do
      before do
        allow(Stripe::Product).to receive(:list).and_raise(
          Stripe::APIConnectionError.new('Network error')
        )
      end

      it 'handles connection errors gracefully' do
        expect {
          run_cli_command_quietly('billing', 'validate')
        }.not_to raise_error
      end
    end

    context 'when billing not configured' do
      before do
        allow(OT).to receive(:billing_config).and_return(
          double('BillingConfig', enabled?: false)
        )
      end

      it 'exits early with error message' do
        output = run_cli_command_quietly('billing', 'validate')

        expect(output[:stdout]).to include('Billing not enabled in etc/billing.yaml')
      end

      it 'does not attempt to validate' do
        expect(Stripe::Product).not_to receive(:list)

        run_cli_command_quietly('billing', 'validate')
      end
    end

    context 'when Stripe key not configured' do
      before do
        allow(OT).to receive(:billing_config).and_return(
          double('BillingConfig', enabled?: true, stripe_key: nil)
        )
      end

      it 'exits early with error message' do
        output = run_cli_command_quietly('billing', 'validate')

        expect(output[:stdout]).to include('STRIPE_KEY environment variable not set or billing.yaml has no valid key')
      end
    end

    context 'with complex metadata validation' do
      let(:product_with_invalid_json) do
        mock_stripe_product(
          id: 'prod_bad_json',
          name: 'Bad JSON',
          metadata: {
            'app' => 'web',
            'tier' => 'personal',
            'region' => 'US',
            'capabilities' => 'invalid json {'
          }
        )
      end

      before do
        products = double('ListObject', data: [product_with_invalid_json])
        allow(Stripe::Product).to receive(:list).and_return(products)
      end

      it 'handles malformed JSON in metadata' do
        expect {
          run_cli_command_quietly('billing', 'validate')
        }.not_to raise_error
      end
    end
  end
end
