# frozen_string_literal: true

require 'spec_helper'
require 'cli/cli_spec_helper'
require_relative '../../support/billing_spec_helper'
require_relative '../../support/shared_examples/cli_safety'

RSpec.describe 'Billing invoices CLI commands', type: :cli do
  let(:invoice_id) { 'in_test123' }
  let(:invoice) { mock_stripe_invoice(id: invoice_id) }

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

  describe 'billing invoices' do
    context 'when listing invoices' do
      let(:invoices) { double('ListObject', data: [
        mock_stripe_invoice(
          id: 'in_001',
          customer: 'cus_001',
          status: 'paid',
          amount_due: 1000
        ),
        mock_stripe_invoice(
          id: 'in_002',
          customer: 'cus_002',
          status: 'open',
          amount_due: 2000
        ),
        mock_stripe_invoice(
          id: 'in_003',
          customer: 'cus_003',
          status: 'void',
          amount_due: 1500
        )
      ]) }

      before do
        allow(Stripe::Invoice).to receive(:list).and_return(invoices)
      end

      it 'lists all invoices' do
        output = run_cli_command_quietly('billing', 'invoices')

        expect(output[:stdout]).to include('in_001')
        expect(output[:stdout]).to include('in_002')
        expect(output[:stdout]).to include('in_003')
        expect(output[:stdout]).to include('Total: 3 invoice(s)')
        expect(last_exit_code).to eq(0)
      end

      it 'displays invoice details in formatted table' do
        output = run_cli_command_quietly('billing', 'invoices')

        expect(output[:stdout]).to match(/ID.*CUSTOMER.*AMOUNT.*STATUS.*CREATED/)
        expect(output[:stdout]).to include('paid')
        expect(output[:stdout]).to include('open')
        expect(output[:stdout]).to include('void')
      end

      it 'formats amounts correctly' do
        output = run_cli_command_quietly('billing', 'invoices')

        expect(output[:stdout]).to include('USD 10.00')
        expect(output[:stdout]).to include('USD 20.00')
        expect(output[:stdout]).to include('USD 15.00')
      end

      it 'shows available statuses in output' do
        output = run_cli_command_quietly('billing', 'invoices')

        expect(output[:stdout]).to include('Statuses: draft, open, paid, uncollectible, void')
      end

      it 'filters by status' do
        expect(Stripe::Invoice).to receive(:list).with(hash_including(
          status: 'paid',
          limit: 100
        )).and_return(invoices)

        run_cli_command_quietly('billing', 'invoices', '--status', 'paid')
      end

      it 'filters by customer' do
        expect(Stripe::Invoice).to receive(:list).with(hash_including(
          customer: 'cus_001',
          limit: 100
        )).and_return(invoices)

        run_cli_command_quietly('billing', 'invoices', '--customer', 'cus_001')
      end

      it 'filters by subscription' do
        expect(Stripe::Invoice).to receive(:list).with(hash_including(
          subscription: 'sub_001',
          limit: 100
        )).and_return(invoices)

        run_cli_command_quietly('billing', 'invoices', '--subscription', 'sub_001')
      end

      it 'respects limit parameter' do
        expect(Stripe::Invoice).to receive(:list).with(hash_including(
          limit: 50
        )).and_return(invoices)

        run_cli_command_quietly('billing', 'invoices', '--limit', '50')
      end

      it 'combines multiple filters' do
        expect(Stripe::Invoice).to receive(:list).with(hash_including(
          status: 'open',
          customer: 'cus_001',
          limit: 25
        )).and_return(invoices)

        run_cli_command_quietly('billing', 'invoices',
          '--status', 'open',
          '--customer', 'cus_001',
          '--limit', '25')
      end

      context 'when no invoices exist' do
        let(:empty_list) { double('ListObject', data: []) }

        before do
          allow(Stripe::Invoice).to receive(:list).and_return(empty_list)
        end

        it 'displays no invoices message' do
          output = run_cli_command_quietly('billing', 'invoices')

          expect(output[:stdout]).to include('No invoices found')
          expect(last_exit_code).to eq(0)
        end
      end

      context 'with different invoice statuses' do
        it 'handles draft invoices' do
          draft_invoices = double('ListObject', data: [
            mock_stripe_invoice(id: 'in_draft', status: 'draft')
          ])
          allow(Stripe::Invoice).to receive(:list).and_return(draft_invoices)

          output = run_cli_command_quietly('billing', 'invoices', '--status', 'draft')

          expect(output[:stdout]).to include('draft')
        end

        it 'handles uncollectible invoices' do
          uncollectible = double('ListObject', data: [
            mock_stripe_invoice(id: 'in_uncollectible', status: 'uncollectible')
          ])
          allow(Stripe::Invoice).to receive(:list).and_return(uncollectible)

          output = run_cli_command_quietly('billing', 'invoices', '--status', 'uncollectible')

          expect(output[:stdout]).to include('uncollectible')
        end
      end

      context 'with different currencies' do
        let(:multi_currency_invoices) { double('ListObject', data: [
          mock_stripe_invoice(id: 'in_usd', amount_due: 1000, currency: 'usd'),
          mock_stripe_invoice(id: 'in_eur', amount_due: 2000, currency: 'eur'),
          mock_stripe_invoice(id: 'in_gbp', amount_due: 1500, currency: 'gbp')
        ]) }

        before do
          allow(Stripe::Invoice).to receive(:list).and_return(multi_currency_invoices)
        end

        it 'displays amounts in respective currencies' do
          output = run_cli_command_quietly('billing', 'invoices')

          expect(output[:stdout]).to include('USD 10.00')
          expect(output[:stdout]).to include('EUR 20.00')
          expect(output[:stdout]).to include('GBP 15.00')
        end
      end

      context 'with large amounts' do
        let(:large_invoices) { double('ListObject', data: [
          mock_stripe_invoice(id: 'in_large', amount_due: 123456789, currency: 'usd')
        ]) }

        before do
          allow(Stripe::Invoice).to receive(:list).and_return(large_invoices)
        end

        it 'formats large amounts correctly' do
          output = run_cli_command_quietly('billing', 'invoices')

          expect(output[:stdout]).to include('USD 1234567.89')
        end
      end

      context 'when Stripe API fails' do
        it 'handles connection errors' do
          allow(Stripe::Invoice).to receive(:list).and_raise(
            Stripe::APIConnectionError.new('Network error')
          )

          output = run_cli_command_quietly('billing', 'invoices')

          expect(output[:stdout]).to include('Error fetching invoices')
          expect(output[:stdout]).to include('Network error')
        end

        it 'handles authentication errors' do
          allow(Stripe::Invoice).to receive(:list).and_raise(
            Stripe::AuthenticationError.new('Invalid API key')
          )

          output = run_cli_command_quietly('billing', 'invoices')

          expect(output[:stdout]).to include('Error fetching invoices')
        end

        it 'handles rate limit errors' do
          allow(Stripe::Invoice).to receive(:list).and_raise(
            Stripe::RateLimitError.new('Rate limit exceeded')
          )

          output = run_cli_command_quietly('billing', 'invoices')

          expect(output[:stdout]).to include('Error fetching invoices')
        end

        it 'handles invalid request errors' do
          allow(Stripe::Invoice).to receive(:list).and_raise(
            Stripe::InvalidRequestError.new('Invalid parameter', 'status')
          )

          output = run_cli_command_quietly('billing', 'invoices')

          expect(output[:stdout]).to include('Error fetching invoices')
        end
      end
    end

    context 'when billing not configured' do
      before do
        billing_config = double('BillingConfig', enabled?: false)
        allow(OT).to receive(:billing_config).and_return(billing_config)
      end

      it 'exits early with error message' do
        output = run_cli_command_quietly('billing', 'invoices')

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
        output = run_cli_command_quietly('billing', 'invoices')

        expect(output[:stdout]).to include('STRIPE_KEY environment variable not set')
      end
    end

    context 'with timestamp formatting' do
      let(:time_now) { Time.now }
      let(:invoices_with_times) { double('ListObject', data: [
        mock_stripe_invoice(id: 'in_recent', created: time_now.to_i),
        mock_stripe_invoice(id: 'in_old', created: (time_now - 365.days).to_i)
      ]) }

      before do
        allow(Stripe::Invoice).to receive(:list).and_return(invoices_with_times)
      end

      it 'formats timestamps correctly' do
        output = run_cli_command_quietly('billing', 'invoices')

        expect(output[:stdout]).to match(/\d{4}-\d{2}-\d{2}/)
      end
    end

    context 'with edge cases' do
      it 'handles invoices with zero amount' do
        zero_invoices = double('ListObject', data: [
          mock_stripe_invoice(id: 'in_zero', amount_due: 0, currency: 'usd')
        ])
        allow(Stripe::Invoice).to receive(:list).and_return(zero_invoices)

        output = run_cli_command_quietly('billing', 'invoices')

        expect(output[:stdout]).to include('USD 0.00')
      end

      it 'handles invoices without customer' do
        no_customer = double('ListObject', data: [
          mock_stripe_invoice(id: 'in_no_cust', customer: nil)
        ])
        allow(Stripe::Invoice).to receive(:list).and_return(no_customer)

        output = run_cli_command_quietly('billing', 'invoices')

        expect(last_exit_code).to eq(0)
      end

      it 'handles invoices without subscription' do
        no_sub = double('ListObject', data: [
          mock_stripe_invoice(id: 'in_no_sub', subscription: nil)
        ])
        allow(Stripe::Invoice).to receive(:list).and_return(no_sub)

        output = run_cli_command_quietly('billing', 'invoices')

        expect(last_exit_code).to eq(0)
      end
    end

    context 'with table formatting' do
      let(:invoices) { double('ListObject', data: [
        mock_stripe_invoice(
          id: 'in_very_long_id_that_needs_truncation',
          customer: 'cus_very_long_customer_id',
          amount_due: 999999
        )
      ]) }

      before do
        allow(Stripe::Invoice).to receive(:list).and_return(invoices)
      end

      it 'truncates long IDs to fit table width' do
        output = run_cli_command_quietly('billing', 'invoices')

        # IDs should be truncated to 21 characters based on format string
        lines = output[:stdout].lines
        data_line = lines.find { |l| l.include?('in_very_long') }

        expect(data_line).not_to be_nil
        # Extract just the ID field (first 22 chars after whitespace)
        id_field = data_line.strip.split(/\s+/).first
        expect(id_field.length).to be <= 22
      end
    end

    context 'with pagination' do
      it 'handles large result sets with default limit' do
        many_invoices = double('ListObject', data: Array.new(100) do |i|
          mock_stripe_invoice(id: "in_#{i.to_s.rjust(3, '0')}")
        end)

        allow(Stripe::Invoice).to receive(:list).and_return(many_invoices)

        output = run_cli_command_quietly('billing', 'invoices')

        expect(output[:stdout]).to include('Total: 100 invoice(s)')
      end

      it 'allows custom limits for pagination' do
        expect(Stripe::Invoice).to receive(:list).with(hash_including(
          limit: 10
        ))

        run_cli_command_quietly('billing', 'invoices', '--limit', '10')
      end
    end

    context 'with metadata and additional fields' do
      let(:detailed_invoice) do
        mock_stripe_invoice(
          id: 'in_detailed',
          metadata: { order_id: '12345', customer_note: 'VIP' },
          amount_due: 5000,
          amount_paid: 5000
        )
      end
      let(:invoices) { double('ListObject', data: [detailed_invoice]) }

      before do
        allow(Stripe::Invoice).to receive(:list).and_return(invoices)
      end

      it 'displays invoice successfully' do
        output = run_cli_command_quietly('billing', 'invoices')

        expect(output[:stdout]).to include('in_detailed')
        expect(last_exit_code).to eq(0)
      end
    end

    context 'with status filter validation' do
      it 'accepts valid status values' do
        %w[draft open paid uncollectible void].each do |status|
          expect(Stripe::Invoice).to receive(:list).with(hash_including(
            status: status
          )).and_return(double('ListObject', data: []))

          run_cli_command_quietly('billing', 'invoices', '--status', status)
        end
      end
    end

    context 'performance considerations' do
      it 'completes quickly with empty results' do
        empty = double('ListObject', data: [])
        allow(Stripe::Invoice).to receive(:list).and_return(empty)

        start_time = Time.now
        run_cli_command_quietly('billing', 'invoices')
        elapsed = Time.now - start_time

        # Should complete almost instantly (< 1 second for mock)
        expect(elapsed).to be < 1.0
      end
    end
  end
end
