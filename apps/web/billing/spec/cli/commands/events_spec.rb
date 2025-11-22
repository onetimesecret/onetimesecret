# frozen_string_literal: true

require 'spec_helper'
require 'cli/cli_spec_helper'
require_relative '../../support/billing_spec_helper'

RSpec.describe 'Billing events CLI command', type: :cli do
  let(:event1) do
    double('Event',
      id: 'evt_001',
      type: 'customer.created',
      created: Time.now.to_i - 3600
    )
  end

  let(:event2) do
    double('Event',
      id: 'evt_002',
      type: 'invoice.paid',
      created: Time.now.to_i - 1800
    )
  end

  let(:event3) do
    double('Event',
      id: 'evt_003',
      type: 'subscription.created',
      created: Time.now.to_i - 900
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

  describe 'billing events' do
    context 'when listing recent events' do
      before do
        events = double('ListObject', data: [event1, event2, event3])
        allow(Stripe::Event).to receive(:list).and_return(events)
      end

      it 'lists recent Stripe events' do
        output = run_cli_command_quietly('billing', 'events')

        expect(output[:stdout]).to include('evt_001')
        expect(output[:stdout]).to include('evt_002')
        expect(output[:stdout]).to include('evt_003')
        expect(last_exit_code).to eq(0)
      end

      it 'displays events in formatted table' do
        output = run_cli_command_quietly('billing', 'events')

        expect(output[:stdout]).to match(/ID.*TYPE.*CREATED/)
      end

      it 'shows event types' do
        output = run_cli_command_quietly('billing', 'events')

        expect(output[:stdout]).to include('customer.created')
        expect(output[:stdout]).to include('invoice.paid')
        expect(output[:stdout]).to include('subscription.created')
      end

      it 'displays total event count' do
        output = run_cli_command_quietly('billing', 'events')

        expect(output[:stdout]).to include('Total: 3 event(s)')
      end

      it 'shows common event types hint' do
        output = run_cli_command_quietly('billing', 'events')

        expect(output[:stdout]).to include('Common types:')
        expect(output[:stdout]).to include('customer.created')
        expect(output[:stdout]).to include('payment_intent.succeeded')
      end

      it 'uses default limit of 20' do
        expect(Stripe::Event).to receive(:list).with(hash_including(
          limit: 20
        ))

        run_cli_command_quietly('billing', 'events')
      end
    end

    context 'with type filter' do
      before do
        invoice_events = double('ListObject', data: [event2])
        allow(Stripe::Event).to receive(:list).and_return(invoice_events)
      end

      it 'filters events by type' do
        expect(Stripe::Event).to receive(:list).with(hash_including(
          type: 'invoice.paid',
          limit: 20
        ))

        output = run_cli_command_quietly('billing', 'events', '--type', 'invoice.paid')

        expect(output[:stdout]).to include('invoice.paid')
        expect(last_exit_code).to eq(0)
      end

      it 'shows only matching events' do
        output = run_cli_command_quietly('billing', 'events', '--type', 'invoice.paid')

        expect(output[:stdout]).to include('evt_002')
        expect(output[:stdout]).not_to include('evt_001')
        expect(output[:stdout]).not_to include('evt_003')
      end
    end

    context 'with custom limit' do
      before do
        events = double('ListObject', data: [event1])
        allow(Stripe::Event).to receive(:list).and_return(events)
      end

      it 'respects custom limit parameter' do
        expect(Stripe::Event).to receive(:list).with(hash_including(
          limit: 50
        ))

        run_cli_command_quietly('billing', 'events', '--limit', '50')
      end

      it 'allows small limits' do
        expect(Stripe::Event).to receive(:list).with(hash_including(
          limit: 5
        ))

        run_cli_command_quietly('billing', 'events', '--limit', '5')
      end

      it 'allows large limits' do
        expect(Stripe::Event).to receive(:list).with(hash_including(
          limit: 100
        ))

        run_cli_command_quietly('billing', 'events', '--limit', '100')
      end
    end

    context 'when no events exist' do
      before do
        events = double('ListObject', data: [])
        allow(Stripe::Event).to receive(:list).and_return(events)
      end

      it 'displays no events message' do
        output = run_cli_command_quietly('billing', 'events')

        expect(output[:stdout]).to include('No events found')
        expect(last_exit_code).to eq(0)
      end
    end

    context 'with pagination' do
      before do
        large_events = double('ListObject', data: Array.new(20) do |i|
          double('Event',
            id: "evt_#{i.to_s.rjust(3, '0')}",
            type: 'test.event',
            created: Time.now.to_i
          )
        end)
        allow(Stripe::Event).to receive(:list).and_return(large_events)
      end

      it 'handles large result sets' do
        output = run_cli_command_quietly('billing', 'events')

        expect(output[:stdout]).to include('Total: 20 event(s)')
      end
    end

    context 'when Stripe API fails' do
      context 'with connection error' do
        before do
          allow(Stripe::Event).to receive(:list).and_raise(
            Stripe::APIConnectionError.new('Network error')
          )
        end

        it 'handles connection errors' do
          output = run_cli_command_quietly('billing', 'events')

          expect(output[:stdout]).to include('Error fetching events')
          expect(output[:stdout]).to include('Network error')
        end
      end

      context 'with invalid request error' do
        before do
          allow(Stripe::Event).to receive(:list).and_raise(
            Stripe::InvalidRequestError.new('Invalid type', 'type')
          )
        end

        it 'handles invalid request errors' do
          output = run_cli_command_quietly('billing', 'events', '--type', 'invalid.type')

          expect(output[:stdout]).to include('Error fetching events')
          expect(output[:stdout]).to include('Invalid type')
        end
      end

      context 'with authentication error' do
        before do
          allow(Stripe::Event).to receive(:list).and_raise(
            Stripe::AuthenticationError.new('Invalid API key')
          )
        end

        it 'handles authentication errors' do
          output = run_cli_command_quietly('billing', 'events')

          expect(output[:stdout]).to include('Error fetching events')
          expect(output[:stdout]).to include('Invalid API key')
        end
      end
    end

    context 'when billing not configured' do
      before do
        allow(OT).to receive(:billing_config).and_return(
          double('BillingConfig', enabled?: false)
        )
      end

      it 'exits early with error message' do
        output = run_cli_command_quietly('billing', 'events')

        expect(output[:stdout]).to include('Billing not enabled in etc/billing.yaml')
      end

      it 'does not attempt to fetch events' do
        expect(Stripe::Event).not_to receive(:list)

        run_cli_command_quietly('billing', 'events')
      end
    end

    context 'when Stripe key not configured' do
      before do
        allow(OT).to receive(:billing_config).and_return(
          double('BillingConfig', enabled?: true, stripe_key: nil)
        )
      end

      it 'exits early with error message' do
        output = run_cli_command_quietly('billing', 'events')

        expect(output[:stdout]).to include('STRIPE_KEY environment variable not set or billing.yaml has no valid key')
      end
    end

    context 'with different event types' do
      let(:payment_intent_event) do
        double('Event',
          id: 'evt_payment',
          type: 'payment_intent.succeeded',
          created: Time.now.to_i
        )
      end

      let(:subscription_event) do
        double('Event',
          id: 'evt_sub',
          type: 'subscription.updated',
          created: Time.now.to_i
        )
      end

      before do
        events = double('ListObject', data: [payment_intent_event, subscription_event])
        allow(Stripe::Event).to receive(:list).and_return(events)
      end

      it 'displays various event types correctly' do
        output = run_cli_command_quietly('billing', 'events')

        expect(output[:stdout]).to include('payment_intent.succeeded')
        expect(output[:stdout]).to include('subscription.updated')
      end
    end
  end
end
