# spec/unit/onetime/jobs/publisher_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/jobs/publisher'

RSpec.describe Onetime::Jobs::Publisher do
  describe 'class methods' do
    it 'responds to enqueue_email' do
      expect(described_class).to respond_to(:enqueue_email)
    end

    it 'responds to enqueue_email_raw' do
      expect(described_class).to respond_to(:enqueue_email_raw)
    end

    it 'responds to schedule_email' do
      expect(described_class).to respond_to(:schedule_email)
    end
  end

  describe 'instance methods' do
    subject(:publisher) { described_class.new }

    it 'responds to enqueue_email' do
      expect(publisher).to respond_to(:enqueue_email)
    end

    it 'responds to schedule_email' do
      expect(publisher).to respond_to(:schedule_email)
    end

    it 'responds to publish' do
      expect(publisher).to respond_to(:publish)
    end
  end

  describe 'constants' do
    it 'defines FALLBACK_STRATEGIES with valid options' do
      expect(described_class::FALLBACK_STRATEGIES).to eq(%i[async_thread sync raise none])
    end

    it 'defines DEFAULT_FALLBACK as :async_thread' do
      expect(described_class::DEFAULT_FALLBACK).to eq(:async_thread)
    end
  end

  describe '#publish with RabbitMQ' do
    subject(:publisher) { described_class.new }

    it 'includes message_id in UUID format when publishing' do
      mock_channel = instance_double(Bunny::Channel)
      mock_exchange = instance_double(Bunny::Exchange)
      mock_channel_pool = instance_double(ConnectionPool)

      allow(mock_channel_pool).to receive(:with).and_yield(mock_channel)
      allow(mock_channel).to receive(:default_exchange).and_return(mock_exchange)
      allow(mock_exchange).to receive(:publish)

      $rmq_channel_pool = mock_channel_pool

      publisher.publish('test.queue', { data: 'test' })

      expect(mock_exchange).to have_received(:publish) do |payload, options|
        expect(options[:message_id]).to match(/^[0-9a-f-]{36}$/)
      end
    end
  end

  describe '#enqueue_email without RabbitMQ' do
    subject(:publisher) { described_class.new }

    before do
      $rmq_channel_pool = nil
    end

    context 'with fallback: :sync' do
      it 'falls back to synchronous email delivery' do
        allow(Onetime::Mail).to receive(:deliver)

        publisher.enqueue_email(:welcome, { email: 'test@example.com' }, fallback: :sync)

        expect(Onetime::Mail).to have_received(:deliver).with(:welcome, { email: 'test@example.com' })
      end
    end

    context 'with fallback: :async_thread (default)' do
      it 'spawns a thread for email delivery' do
        delivered = Concurrent::AtomicBoolean.new(false)
        allow(Onetime::Mail).to receive(:deliver) { delivered.make_true }

        # Default fallback spawns a thread
        publisher.enqueue_email(:welcome, { email: 'test@example.com' })

        # Wait for thread to complete with timeout
        Timeout.timeout(5) { sleep 0.05 until delivered.true? }

        expect(Onetime::Mail).to have_received(:deliver).with(:welcome, { email: 'test@example.com' })
      end
    end

    context 'with fallback: :none' do
      it 'does not attempt to send email' do
        allow(Onetime::Mail).to receive(:deliver)

        publisher.enqueue_email(:welcome, { email: 'test@example.com' }, fallback: :none)

        expect(Onetime::Mail).not_to have_received(:deliver)
      end
    end

    context 'with fallback: :raise' do
      it 'raises DeliveryError' do
        expect {
          publisher.enqueue_email(:welcome, { email: 'test@example.com' }, fallback: :raise)
        }.to raise_error(Onetime::Mail::DeliveryError, /RabbitMQ unavailable/)
      end
    end

    context 'with invalid fallback strategy' do
      it 'raises ArgumentError' do
        expect {
          publisher.enqueue_email(:welcome, { email: 'test@example.com' }, fallback: :invalid)
        }.to raise_error(ArgumentError, /Invalid fallback strategy/)
      end
    end
  end

  describe '#enqueue_email_raw without RabbitMQ' do
    subject(:publisher) { described_class.new }

    before do
      $rmq_channel_pool = nil
    end

    let(:raw_email) { { to: 'test@example.com', from: 'noreply@example.com', subject: 'Test', body: 'Hello' } }

    context 'with fallback: :sync' do
      it 'falls back to synchronous raw email delivery' do
        allow(Onetime::Mail).to receive(:deliver_raw)

        publisher.enqueue_email_raw(raw_email, fallback: :sync)

        expect(Onetime::Mail).to have_received(:deliver_raw).with(raw_email)
      end
    end
  end

  # ==========================================================================
  # Chaos/Failure Injection Tests
  # ==========================================================================
  # These tests verify behavior during mid-operation failures such as
  # connection drops, pool exhaustion, and network errors.
  # ==========================================================================

  describe 'chaos/failure scenarios' do
    subject(:publisher) { described_class.new }

    describe 'channel pool exhaustion' do
      let(:mock_pool) { instance_double(ConnectionPool) }

      before do
        $rmq_channel_pool = mock_pool
      end

      after do
        $rmq_channel_pool = nil
      end

      context 'when ConnectionPool::TimeoutError occurs' do
        before do
          allow(mock_pool).to receive(:with).and_raise(ConnectionPool::TimeoutError.new('Timed out waiting for connection'))
        end

        it 'triggers fallback for enqueue_email with default strategy' do
          delivered = Concurrent::AtomicBoolean.new(false)
          allow(Onetime::Mail).to receive(:deliver) { delivered.make_true }

          result = publisher.enqueue_email(:welcome, { email: 'test@example.com' })

          # Fallback returns false, but spawns thread for delivery
          expect(result).to be false
          Timeout.timeout(5) { sleep 0.05 until delivered.true? }
          expect(Onetime::Mail).to have_received(:deliver)
        end

        it 'raises with fallback: :raise' do
          expect {
            publisher.enqueue_email(:welcome, { email: 'test@example.com' }, fallback: :raise)
          }.to raise_error(Onetime::Mail::DeliveryError, /RabbitMQ unavailable/)
        end

        it 'delivers synchronously with fallback: :sync' do
          allow(Onetime::Mail).to receive(:deliver)

          result = publisher.enqueue_email(:welcome, { email: 'test@example.com' }, fallback: :sync)

          expect(result).to be false
          expect(Onetime::Mail).to have_received(:deliver)
        end
      end
    end

    describe 'connection closed mid-publish' do
      let(:mock_pool) { instance_double(ConnectionPool) }
      let(:mock_channel) { instance_double(Bunny::Channel) }

      before do
        $rmq_channel_pool = mock_pool
      end

      after do
        $rmq_channel_pool = nil
      end

      context 'when Bunny::ConnectionClosedError occurs during publish' do
        before do
          allow(mock_pool).to receive(:with).and_yield(mock_channel)
          allow(mock_channel).to receive(:default_exchange).and_raise(Bunny::ConnectionClosedError.new(nil))
        end

        it 'triggers fallback with default strategy' do
          delivered = Concurrent::AtomicBoolean.new(false)
          allow(Onetime::Mail).to receive(:deliver) { delivered.make_true }

          result = publisher.enqueue_email(:welcome, { email: 'test@example.com' })

          expect(result).to be false
          Timeout.timeout(5) { sleep 0.05 until delivered.true? }
          expect(Onetime::Mail).to have_received(:deliver)
        end

        it 'respects fallback: :none by not delivering' do
          allow(Onetime::Mail).to receive(:deliver)

          result = publisher.enqueue_email(:welcome, { email: 'test@example.com' }, fallback: :none)

          expect(result).to be false
          expect(Onetime::Mail).not_to have_received(:deliver)
        end
      end

      context 'when Bunny::NetworkFailure occurs during publish' do
        before do
          mock_exchange = instance_double(Bunny::Exchange)
          allow(mock_pool).to receive(:with).and_yield(mock_channel)
          allow(mock_channel).to receive(:default_exchange).and_return(mock_exchange)
          # NetworkFailure requires (message, cause)
          allow(mock_exchange).to receive(:publish).and_raise(Bunny::NetworkFailure.new('Network unreachable', nil))
        end

        it 'triggers fallback' do
          allow(Onetime::Mail).to receive(:deliver)

          result = publisher.enqueue_email(:welcome, { email: 'test@example.com' }, fallback: :sync)

          expect(result).to be false
          expect(Onetime::Mail).to have_received(:deliver)
        end
      end
    end

    describe 'unexpected errors during publish' do
      let(:mock_pool) { instance_double(ConnectionPool) }
      let(:mock_channel) { instance_double(Bunny::Channel) }
      let(:mock_exchange) { instance_double(Bunny::Exchange) }

      before do
        $rmq_channel_pool = mock_pool
        allow(mock_pool).to receive(:with).and_yield(mock_channel)
        allow(mock_channel).to receive(:default_exchange).and_return(mock_exchange)
      end

      after do
        $rmq_channel_pool = nil
      end

      context 'when an unexpected StandardError occurs' do
        before do
          allow(mock_exchange).to receive(:publish).and_raise(StandardError.new('Unexpected error'))
        end

        it 'still triggers fallback (caught by rescue StandardError)' do
          allow(Onetime::Mail).to receive(:deliver)

          result = publisher.enqueue_email(:welcome, { email: 'test@example.com' }, fallback: :sync)

          expect(result).to be false
          expect(Onetime::Mail).to have_received(:deliver)
        end
      end
    end

    describe '#publish without pool' do
      before do
        $rmq_channel_pool = nil
      end

      it 'raises Onetime::Problem with descriptive message' do
        expect {
          publisher.publish('some.queue', { data: 'test' })
        }.to raise_error(Onetime::Problem, /RabbitMQ channel pool not initialized/)
      end
    end

    describe 'fallback thread error handling' do
      let(:mock_pool) { instance_double(ConnectionPool) }

      before do
        $rmq_channel_pool = mock_pool
        allow(mock_pool).to receive(:with).and_raise(Bunny::ConnectionClosedError.new(nil))
      end

      after do
        $rmq_channel_pool = nil
      end

      context 'when async_thread fallback delivery itself fails' do
        it 'does not raise to caller (fire-and-forget)' do
          attempted = Concurrent::AtomicBoolean.new(false)
          allow(Onetime::Mail).to receive(:deliver) do
            attempted.make_true
            raise StandardError.new('SMTP connection failed')
          end

          # The fallback spawns a thread that may fail, but the caller should not see it
          expect {
            publisher.enqueue_email(:welcome, { email: 'test@example.com' })
          }.not_to raise_error

          # Wait for thread to attempt delivery (will fail silently)
          Timeout.timeout(5) { sleep 0.05 until attempted.true? }
        end
      end
    end
  end

  # ==========================================================================
  # Billing Event Fallback Tests
  # ==========================================================================
  # These tests verify billing event publishing behavior when jobs are
  # disabled or RabbitMQ is unavailable.
  # ==========================================================================

  describe '#enqueue_billing_event' do
    subject(:publisher) { described_class.new }

    let(:mock_event) do
      instance_double(Stripe::Event, id: 'evt_123', type: 'invoice.paid')
    end
    let(:payload) { '{"id":"evt_123","type":"invoice.paid"}' }

    # Note: The 'jobs disabled' synchronous fallback test is skipped because
    # Billing::Operations::ProcessWebhookEvent is loaded dynamically and
    # defining stub modules in unit tests is fragile. This path is covered
    # by integration tests.
    #
    # See: spec/integration/all/jobs/rabbitmq_publishing_spec.rb for full coverage

    context 'when RabbitMQ is available' do
      let(:mock_pool) { instance_double(ConnectionPool) }
      let(:mock_channel) { instance_double(Bunny::Channel) }
      let(:mock_exchange) { instance_double(Bunny::Exchange) }

      before do
        $rmq_channel_pool = mock_pool
        allow(mock_pool).to receive(:with).and_yield(mock_channel)
        allow(mock_channel).to receive(:default_exchange).and_return(mock_exchange)
        allow(mock_exchange).to receive(:publish)
      end

      after do
        $rmq_channel_pool = nil
      end

      it 'publishes to billing.event.process queue' do
        result = publisher.enqueue_billing_event(mock_event, payload)

        expect(result).to be true
        expect(mock_exchange).to have_received(:publish) do |message_json, options|
          message = JSON.parse(message_json, symbolize_names: true)
          expect(message[:event_id]).to eq('evt_123')
          expect(message[:event_type]).to eq('invoice.paid')
          expect(message[:payload]).to eq(payload)
          expect(options[:routing_key]).to eq('billing.event.process')
        end
      end

      it 'includes received_at timestamp in message' do
        Timecop.freeze(Time.utc(2025, 1, 15, 12, 0, 0)) do
          publisher.enqueue_billing_event(mock_event, payload)

          expect(mock_exchange).to have_received(:publish) do |message_json, _options|
            message = JSON.parse(message_json, symbolize_names: true)
            expect(message[:received_at]).to eq('2025-01-15T12:00:00Z')
          end
        end
      end
    end

    context 'when RabbitMQ connection fails mid-publish' do
      let(:mock_pool) { instance_double(ConnectionPool) }

      before do
        $rmq_channel_pool = mock_pool
        allow(mock_pool).to receive(:with).and_raise(Bunny::ConnectionClosedError.new(nil))
      end

      after do
        $rmq_channel_pool = nil
      end

      it 'raises error (billing events do not use fallback)' do
        # Unlike email, billing events raise on RabbitMQ failure when jobs are enabled
        # This ensures Stripe retries the webhook
        expect {
          publisher.enqueue_billing_event(mock_event, payload)
        }.to raise_error(Bunny::ConnectionClosedError)
      end
    end
  end
end
