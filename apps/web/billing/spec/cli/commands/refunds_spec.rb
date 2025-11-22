# frozen_string_literal: true

require 'spec_helper'
require 'cli/cli_spec_helper'
require_relative '../../support/billing_spec_helper'
require_relative '../../support/shared_examples/cli_safety'

RSpec.describe 'Billing refunds CLI commands', type: :cli do
  let(:charge_id) { 'ch_test123' }
  let(:charge) { mock_stripe_charge(id: charge_id, amount: 5000, currency: 'usd') }

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

  describe 'billing refunds' do
    context 'when listing refunds' do
      let(:refunds) { double('ListObject', data: [
        mock_stripe_refund(id: 'ref_001', charge: charge_id, amount: 1000),
        mock_stripe_refund(id: 'ref_002', charge: charge_id, amount: 2000, status: 'pending')
      ]) }

      before do
        allow(Stripe::Refund).to receive(:list).and_return(refunds)
      end

      it 'lists all refunds' do
        output = run_cli_command_quietly('billing', 'refunds')

        expect(output[:stdout]).to include('ref_001')
        expect(output[:stdout]).to include('ref_002')
        expect(output[:stdout]).to include('Total: 2 refund(s)')
        expect(last_exit_code).to eq(0)
      end

      it 'displays refund details in formatted table' do
        output = run_cli_command_quietly('billing', 'refunds')

        expect(output[:stdout]).to match(/ID.*CHARGE.*AMOUNT.*STATUS.*CREATED/)
        expect(output[:stdout]).to include('USD 10.00')
        expect(output[:stdout]).to include('USD 20.00')
      end

      it 'filters by charge ID' do
        expect(Stripe::Refund).to receive(:list).with(hash_including(
          charge: charge_id,
          limit: 100
        )).and_return(refunds)

        output = run_cli_command_quietly('billing', 'refunds', '--charge', charge_id)

        expect(last_exit_code).to eq(0)
      end

      it 'respects limit parameter' do
        expect(Stripe::Refund).to receive(:list).with(hash_including(
          limit: 50
        )).and_return(refunds)

        run_cli_command_quietly('billing', 'refunds', '--limit', '50')
      end

      context 'when no refunds exist' do
        let(:empty_list) { double('ListObject', data: []) }

        before do
          allow(Stripe::Refund).to receive(:list).and_return(empty_list)
        end

        it 'displays no refunds message' do
          output = run_cli_command_quietly('billing', 'refunds')

          expect(output[:stdout]).to include('No refunds found')
          expect(last_exit_code).to eq(0)
        end
      end

      context 'when Stripe API fails' do
        before do
          allow(Stripe::Refund).to receive(:list).and_raise(
            Stripe::APIConnectionError.new('Network error')
          )
        end

        it 'displays error message' do
          output = run_cli_command_quietly('billing', 'refunds')

          expect(output[:stdout]).to include('Error fetching refunds')
          expect(output[:stdout]).to include('Network error')
        end
      end
    end
  end

  describe 'billing refunds create' do
    let(:refund) { mock_stripe_refund(id: 'ref_new', charge: charge_id, amount: 5000) }

    before do
      allow(Stripe::Charge).to receive(:retrieve).and_return(charge)
    end

    context 'with valid parameters' do
      before do
        allow(Stripe::Refund).to receive(:create).and_return(refund)
        allow($stdin).to receive(:gets).and_return("y\n")
      end

      it 'creates a full refund by default' do
        expect(Stripe::Refund).to receive(:create).with(hash_including(
          charge: charge_id
        )).and_return(refund)

        output = run_cli_command_quietly('billing', 'refunds', 'create', '--charge', charge_id)

        expect(output[:stdout]).to include('Refund created successfully')
        expect(output[:stdout]).to include(refund.id)
        expect(last_exit_code).to eq(0)
      end

      it 'displays charge details before creating refund' do
        output = run_cli_command_quietly('billing', 'refunds', 'create', '--charge', charge_id)

        expect(output[:stdout]).to include("Charge: #{charge_id}")
        expect(output[:stdout]).to include('Amount: USD 50.00')
        expect(output[:stdout]).to include(charge.customer)
      end

      it 'creates a partial refund when amount specified' do
        partial_refund = mock_stripe_refund(id: 'ref_partial', charge: charge_id, amount: 2500)
        allow(Stripe::Refund).to receive(:create).and_return(partial_refund)

        expect(Stripe::Refund).to receive(:create).with(hash_including(
          charge: charge_id,
          amount: 2500
        ))

        output = run_cli_command_quietly('billing', 'refunds', 'create',
          '--charge', charge_id, '--amount', '2500')

        expect(output[:stdout]).to include('Refund amount: USD 25.00')
        expect(output[:stdout]).to include('USD 25.00')
      end

      it 'includes refund reason when specified' do
        expect(Stripe::Refund).to receive(:create).with(hash_including(
          charge: charge_id,
          reason: 'requested_by_customer'
        )).and_return(refund)

        output = run_cli_command_quietly('billing', 'refunds', 'create',
          '--charge', charge_id, '--reason', 'requested_by_customer')

        expect(output[:stdout]).to include('Reason: requested_by_customer')
      end

      it 'supports all valid refund reasons' do
        %w[duplicate fraudulent requested_by_customer].each do |reason|
          allow(Stripe::Refund).to receive(:create).and_return(refund)

          expect(Stripe::Refund).to receive(:create).with(hash_including(
            reason: reason
          ))

          run_cli_command_quietly('billing', 'refunds', 'create',
            '--charge', charge_id, '--reason', reason)
        end
      end

      it 'displays refund status after creation' do
        output = run_cli_command_quietly('billing', 'refunds', 'create', '--charge', charge_id)

        expect(output[:stdout]).to include('Refund created successfully')
        expect(output[:stdout]).to include("ID: #{refund.id}")
        expect(output[:stdout]).to include("Amount: USD 50.00")
        expect(output[:stdout]).to include("Status: #{refund.status}")
      end
    end

    context 'with confirmation prompt' do
      before do
        allow(Stripe::Refund).to receive(:create).and_return(refund)
      end

      it 'prompts for confirmation by default' do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = run_cli_command_quietly('billing', 'refunds', 'create', '--charge', charge_id)

        expect(output[:stdout]).to include('Create refund? (y/n):')
      end

      it 'aborts when user declines' do
        allow($stdin).to receive(:gets).and_return("n\n")

        expect(Stripe::Refund).not_to receive(:create)

        output = run_cli_command_quietly('billing', 'refunds', 'create', '--charge', charge_id)

        expect(output[:stdout]).not_to include('Refund created successfully')
      end

      it 'skips prompt with --yes flag' do
        expect($stdin).not_to receive(:gets)

        output = run_cli_command_quietly('billing', 'refunds', 'create',
          '--charge', charge_id, '--yes')

        expect(output[:stdout]).to include('Refund created successfully')
      end
    end

    context 'with error scenarios' do
      it 'handles charge not found' do
        allow(Stripe::Charge).to receive(:retrieve).and_raise(
          Stripe::InvalidRequestError.new('No such charge', 'charge')
        )

        output = run_cli_command_quietly('billing', 'refunds', 'create', '--charge', 'ch_invalid')

        expect(output[:stdout]).to include('Error creating refund')
        expect(output[:stdout]).to include('No such charge')
      end

      it 'handles already refunded charge' do
        allow($stdin).to receive(:gets).and_return("y\n")
        allow(Stripe::Refund).to receive(:create).and_raise(
          Stripe::InvalidRequestError.new('Charge already refunded', 'charge')
        )

        output = run_cli_command_quietly('billing', 'refunds', 'create', '--charge', charge_id)

        expect(output[:stdout]).to include('Error creating refund')
        expect(output[:stdout]).to include('already refunded')
      end

      it 'handles invalid refund amount' do
        allow($stdin).to receive(:gets).and_return("y\n")
        allow(Stripe::Refund).to receive(:create).and_raise(
          Stripe::InvalidRequestError.new('Refund amount exceeds charge amount', 'amount')
        )

        output = run_cli_command_quietly('billing', 'refunds', 'create',
          '--charge', charge_id, '--amount', '99999')

        expect(output[:stdout]).to include('Error creating refund')
      end

      it 'handles network errors' do
        allow($stdin).to receive(:gets).and_return("y\n")
        allow(Stripe::Refund).to receive(:create).and_raise(
          Stripe::APIConnectionError.new('Connection failed')
        )

        output = run_cli_command_quietly('billing', 'refunds', 'create', '--charge', charge_id)

        expect(output[:stdout]).to include('Error creating refund')
        expect(output[:stdout]).to include('Connection failed')
      end

      it 'handles authentication errors' do
        allow(Stripe::Charge).to receive(:retrieve).and_raise(
          Stripe::AuthenticationError.new('Invalid API key')
        )

        output = run_cli_command_quietly('billing', 'refunds', 'create', '--charge', charge_id)

        expect(output[:stdout]).to include('Error creating refund')
      end

      it 'handles rate limit errors' do
        allow($stdin).to receive(:gets).and_return("y\n")
        allow(Stripe::Refund).to receive(:create).and_raise(
          Stripe::RateLimitError.new('Rate limit exceeded')
        )

        output = run_cli_command_quietly('billing', 'refunds', 'create', '--charge', charge_id)

        expect(output[:stdout]).to include('Error creating refund')
      end
    end

    context 'when billing not configured' do
      before do
        billing_config = double('BillingConfig', enabled?: false)
        allow(OT).to receive(:billing_config).and_return(billing_config)
      end

      it 'exits early with error message' do
        output = run_cli_command_quietly('billing', 'refunds', 'create', '--charge', charge_id)

        expect(output[:stdout]).to include('Billing not enabled')
      end
    end

    context 'when Stripe key not configured' do
      before do
        billing_config = double('BillingConfig',
          enabled?: true,
          stripe_key: 'nostripkey'
        )
        allow(OT).to receive(:billing_config).and_return(billing_config)
      end

      it 'exits early with error message' do
        output = run_cli_command_quietly('billing', 'refunds', 'create', '--charge', charge_id)

        expect(output[:stdout]).to include('STRIPE_KEY environment variable not set')
      end
    end

    context 'with required parameter validation' do
      it 'requires charge parameter' do
        output = run_cli_command_quietly('billing', 'refunds', 'create')

        # Dry::CLI will handle missing required parameter
        expect(last_exit_code).not_to eq(0)
      end
    end

    context 'edge cases' do
      before do
        allow($stdin).to receive(:gets).and_return("y\n")
        allow(Stripe::Refund).to receive(:create).and_return(refund)
      end

      it 'handles zero amount (full refund)' do
        output = run_cli_command_quietly('billing', 'refunds', 'create',
          '--charge', charge_id, '--amount', '0')

        # Amount 0 should be treated as full refund
        expect(Stripe::Refund).to have_received(:create).with(hash_including(
          charge: charge_id,
          amount: 0
        ))
      end

      it 'handles charges with different currencies' do
        eur_charge = mock_stripe_charge(id: 'ch_eur', amount: 5000, currency: 'eur')
        allow(Stripe::Charge).to receive(:retrieve).and_return(eur_charge)

        eur_refund = mock_stripe_refund(id: 'ref_eur', charge: 'ch_eur',
          amount: 5000, currency: 'eur')
        allow(Stripe::Refund).to receive(:create).and_return(eur_refund)

        output = run_cli_command_quietly('billing', 'refunds', 'create', '--charge', 'ch_eur')

        expect(output[:stdout]).to include('EUR 50.00')
      end

      it 'formats large amounts correctly' do
        large_charge = mock_stripe_charge(id: 'ch_large', amount: 123456789)
        large_refund = mock_stripe_refund(id: 'ref_large', amount: 123456789)

        allow(Stripe::Charge).to receive(:retrieve).and_return(large_charge)
        allow(Stripe::Refund).to receive(:create).and_return(large_refund)

        output = run_cli_command_quietly('billing', 'refunds', 'create', '--charge', 'ch_large')

        expect(output[:stdout]).to include('USD 1234567.89')
      end
    end
  end
end
