# frozen_string_literal: true

require 'spec_helper'
require 'cli/cli_spec_helper'
require_relative '../../support/billing_spec_helper'

RSpec.describe 'Billing sync CLI command', type: :cli do
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

  describe 'billing sync' do
    context 'when sync is successful' do
      before do
        allow(Billing::Plan).to receive(:refresh_from_stripe).and_yield('Syncing products...').and_return(5)
      end

      it 'syncs products and prices from Stripe to Redis' do
        expect(Billing::Plan).to receive(:refresh_from_stripe)

        output = run_cli_command_quietly('billing', 'sync')

        expect(output[:stdout]).to include('Syncing from Stripe to Redis cache')
        expect(last_exit_code).to eq(0)
      end

      it 'displays success message with count' do
        output = run_cli_command_quietly('billing', 'sync')

        expect(output[:stdout]).to include('Successfully synced 5 plan(s) to cache')
      end

      it 'shows usage hint after sync' do
        output = run_cli_command_quietly('billing', 'sync')

        expect(output[:stdout]).to include('To view cached plans')
        expect(output[:stdout]).to include('bin/ots billing plans')
      end

      it 'calls refresh_from_stripe with progress callback' do
        expect(Billing::Plan).to receive(:refresh_from_stripe).with(hash_including(
          progress: instance_of(Method)
        ))

        run_cli_command_quietly('billing', 'sync')
      end
    end

    context 'when syncing zero plans' do
      before do
        allow(Billing::Plan).to receive(:refresh_from_stripe).and_return(0)
      end

      it 'displays zero count' do
        output = run_cli_command_quietly('billing', 'sync')

        expect(output[:stdout]).to include('Successfully synced 0 plan(s) to cache')
        expect(last_exit_code).to eq(0)
      end
    end

    context 'when syncing large number of plans' do
      before do
        allow(Billing::Plan).to receive(:refresh_from_stripe).and_return(50)
      end

      it 'handles large sync counts' do
        output = run_cli_command_quietly('billing', 'sync')

        expect(output[:stdout]).to include('Successfully synced 50 plan(s) to cache')
      end
    end

    context 'with progress updates' do
      before do
        allow(Billing::Plan).to receive(:refresh_from_stripe) do |**opts|
          progress = opts[:progress]
          progress&.call('Processing product 1/10...')
          progress&.call('Processing product 5/10...')
          progress&.call('Processing product 10/10...')
          10
        end
      end

      it 'shows progress during sync' do
        output = run_cli_command_quietly('billing', 'sync')

        expect(last_exit_code).to eq(0)
      end
    end

    context 'when Stripe API fails' do
      context 'with connection error' do
        before do
          allow(Billing::Plan).to receive(:refresh_from_stripe).and_raise(
            Stripe::APIConnectionError.new('Network error')
          )
        end

        it 'displays error message' do
          output = run_cli_command_quietly('billing', 'sync')

          expect(output[:stdout]).to include('Sync failed')
          expect(output[:stdout]).to include('Network error')
        end

        it 'shows troubleshooting hints' do
          output = run_cli_command_quietly('billing', 'sync')

          expect(output[:stdout]).to include('Troubleshooting:')
          expect(output[:stdout]).to include('Verify STRIPE_KEY')
          expect(output[:stdout]).to include('Check your internet connection')
        end
      end

      context 'with authentication error' do
        before do
          allow(Billing::Plan).to receive(:refresh_from_stripe).and_raise(
            Stripe::AuthenticationError.new('Invalid API key')
          )
        end

        it 'displays authentication error' do
          output = run_cli_command_quietly('billing', 'sync')

          expect(output[:stdout]).to include('Sync failed')
          expect(output[:stdout]).to include('Invalid API key')
        end
      end

      context 'with permission error' do
        before do
          allow(Billing::Plan).to receive(:refresh_from_stripe).and_raise(
            Stripe::PermissionError.new('Access denied')
          )
        end

        it 'displays permission error' do
          output = run_cli_command_quietly('billing', 'sync')

          expect(output[:stdout]).to include('Sync failed')
          expect(output[:stdout]).to include('Access denied')
        end

        it 'suggests verifying account access' do
          output = run_cli_command_quietly('billing', 'sync')

          expect(output[:stdout]).to include('Verify Stripe account has access to products')
        end
      end

      context 'with rate limit error' do
        before do
          allow(Billing::Plan).to receive(:refresh_from_stripe).and_raise(
            Stripe::RateLimitError.new('Rate limit exceeded')
          )
        end

        it 'displays rate limit error' do
          output = run_cli_command_quietly('billing', 'sync')

          expect(output[:stdout]).to include('Sync failed')
          expect(output[:stdout]).to include('Rate limit exceeded')
        end
      end
    end

    context 'when unexpected error occurs' do
      before do
        allow(Billing::Plan).to receive(:refresh_from_stripe).and_raise(
          StandardError.new('Unexpected error')
        )
      end

      it 'displays generic error message' do
        output = run_cli_command_quietly('billing', 'sync')

        expect(output[:stdout]).to include('Error during sync')
        expect(output[:stdout]).to include('Unexpected error')
      end
    end

    context 'when billing not configured' do
      before do
        allow(OT).to receive(:billing_config).and_return(
          double('BillingConfig', enabled?: false)
        )
      end

      it 'exits early with error message' do
        output = run_cli_command_quietly('billing', 'sync')

        expect(output[:stdout]).to include('Billing is not configured')
      end

      it 'does not attempt to sync' do
        expect(Billing::Plan).not_to receive(:refresh_from_stripe)

        run_cli_command_quietly('billing', 'sync')
      end
    end

    context 'when Stripe key not configured' do
      before do
        allow(OT).to receive(:billing_config).and_return(
          double('BillingConfig', enabled?: true, stripe_key: nil)
        )
      end

      it 'exits early with error message' do
        output = run_cli_command_quietly('billing', 'sync')

        expect(output[:stdout]).to include('Stripe API key not configured')
      end
    end
  end
end
