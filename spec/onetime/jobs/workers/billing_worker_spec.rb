# spec/onetime/jobs/workers/billing_worker_spec.rb
#
# frozen_string_literal: true

# BillingWorker Test Suite
#
# Tests the billing worker that consumes messages from the
# billing.event.process queue and delegates to ProcessWebhookEvent operation.
#
# Test Categories:
#
#   1. Message processing (Unit)
#      - Verifies operation is called with reconstructed Stripe event
#      - Verifies ack! after successful processing
#
#   2. Idempotency handling (Integration)
#      - Tests that pre-existing Redis key prevents duplicate processing
#      - Tests that successful processing creates Redis idempotency key
#
#   3. Failure handling (Unit)
#      - Tests that errors trigger reject! to send to DLQ
#
#   4. Stripe event reconstruction (Unit)
#      - Tests that raw payload is correctly parsed into Stripe::Event
#
# Setup Requirements:
#   - Redis test instance at VALKEY_URL='valkey://127.0.0.1:2121/0'
#   - Mocked ProcessWebhookEvent operation
#
# Run with: pnpm run test:rspec spec/onetime/jobs/workers/billing_worker_spec.rb

require 'spec_helper'
require 'sneakers'
require 'stripe'
require_relative '../../../../lib/onetime/jobs/workers/billing_worker'
require_relative '../../../../lib/onetime/jobs/queue_config'

# Data classes for mocking AMQP envelope components (immutable, Ruby 3.2+)
DeliveryInfoStub = Data.define(:delivery_tag, :routing_key, :redelivered?) unless defined?(DeliveryInfoStub)
MetadataStub = Data.define(:message_id, :headers) unless defined?(MetadataStub)

RSpec.describe Onetime::Jobs::Workers::BillingWorker, type: :integration do
  # Create test worker class with accessible delivery_info
  let(:test_worker_class) do
    Class.new(Onetime::Jobs::Workers::BillingWorker) do
      attr_accessor :delivery_info, :acked, :rejected

      def self.name
        'TestBillingWorker'
      end

      def initialize
        super
        @acked = false
        @rejected = false
      end

      def ack!
        @acked = true
      end

      def reject!
        @rejected = true
      end

      def acked?
        @acked
      end

      def rejected?
        @rejected
      end
    end
  end

  let(:worker) { test_worker_class.new }
  let(:message_id) { 'test-billing-123' }
  let(:event_id) { 'evt_test_checkout_completed' }

  # Mock Sneakers delivery_info (envelope info)
  let(:delivery_info) do
    DeliveryInfoStub.new(
      delivery_tag: 1,
      routing_key: 'billing.event.process',
      redelivered?: false
    )
  end

  # Mock Sneakers metadata (message properties)
  let(:metadata) do
    MetadataStub.new(
      message_id: message_id,
      headers: { 'x-schema-version' => 1 }
    )
  end

  # Sample Stripe event payload (checkout.session.completed)
  let(:stripe_event_payload) do
    {
      id: event_id,
      object: 'event',
      type: 'checkout.session.completed',
      created: Time.now.to_i,
      livemode: false,
      data: {
        object: {
          id: 'cs_test_123',
          object: 'checkout.session',
          customer: 'cus_test_456',
          subscription: 'sub_test_789',
          mode: 'subscription',
          metadata: {
            custid: 'cust:test-user'
          }
        }
      }
    }.to_json
  end

  let(:operation_instance) { instance_double('ProcessWebhookEventDouble') }

  before do
    # Store envelope
    worker.store_envelope(delivery_info, metadata)

    # Mock sleep to speed up retry tests
    allow(worker).to receive(:sleep)

    # Mock the operation class to return our controlled instance
    # (actual class is loaded at file level, we just mock its behavior)
    allow(Billing::Operations::ProcessWebhookEvent).to receive(:new).and_return(operation_instance)
    allow(operation_instance).to receive(:call).and_return(true)
  end

  describe '#work_with_params' do
    let(:message) do
      JSON.generate(
        event_id: event_id,
        event_type: 'checkout.session.completed',
        payload: stripe_event_payload,
        received_at: Time.now.utc.iso8601
      )
    end

    context 'successful processing' do
      it 'calls ProcessWebhookEvent operation with reconstructed Stripe event' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(Billing::Operations::ProcessWebhookEvent).to have_received(:new).with(
          event: an_instance_of(Stripe::Event),
          context: hash_including(
            source: :async_worker,
            source_message_id: message_id
          )
        )
        expect(operation_instance).to have_received(:call)
      end

      it 'acknowledges the message after successful processing' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
      end

      it 'marks message as processed after successful delivery' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(Familia.dbclient.exists?("job:processed:#{message_id}")).to be_truthy
      end

      it 'reconstructs Stripe event with correct type' do
        captured_event = nil
        allow(Billing::Operations::ProcessWebhookEvent).to receive(:new) do |args|
          captured_event = args[:event]
          operation_instance
        end

        worker.work_with_params(message, delivery_info, metadata)

        expect(captured_event).to be_a(Stripe::Event)
        expect(captured_event.type).to eq('checkout.session.completed')
        expect(captured_event.id).to eq(event_id)
      end
    end

    context 'idempotency handling' do
      it 'skips processing and acknowledges when message already processed' do
        # Pre-set Redis idempotency key
        Familia.dbclient.setex("job:processed:#{message_id}", 3600, '1')

        worker.work_with_params(message, delivery_info, metadata)

        # Should ack without calling operation
        expect(worker.acked?).to be true
        expect(Billing::Operations::ProcessWebhookEvent).not_to have_received(:new)
      end

      it 'creates Redis idempotency key with TTL after successful processing' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(Familia.dbclient.exists?("job:processed:#{message_id}")).to be_truthy
        ttl = Familia.dbclient.ttl("job:processed:#{message_id}")
        expect(ttl).to be > 0
        expect(ttl).to be <= Onetime::Jobs::QueueConfig::IDEMPOTENCY_TTL
      end
    end

    context 'failure handling' do
      it 'calls reject! when operation raises unexpected error after retries' do
        allow(operation_instance).to receive(:call).and_raise(StandardError, 'Stripe API error')

        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.rejected?).to be true
        # Initial + 3 retries = 4 calls
        expect(operation_instance).to have_received(:call).exactly(4).times
      end

      it 'retries on transient errors' do
        call_count = 0
        allow(operation_instance).to receive(:call) do
          call_count += 1
          raise StandardError, 'Transient error' if call_count < 2

          true
        end

        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
        expect(call_count).to eq(2)
      end
    end

    context 'with invalid JSON' do
      let(:invalid_message) { 'not valid json{' }

      it 'calls reject! for invalid JSON' do
        worker.work_with_params(invalid_message, delivery_info, metadata)

        expect(worker.rejected?).to be true
        expect(Billing::Operations::ProcessWebhookEvent).not_to have_received(:new)
      end
    end

    context 'with missing payload' do
      let(:message_without_payload) do
        JSON.generate(
          event_id: event_id,
          event_type: 'checkout.session.completed',
          received_at: Time.now.utc.iso8601
        )
      end

      it 'calls reject! when payload is missing' do
        worker.work_with_params(message_without_payload, delivery_info, metadata)

        expect(worker.rejected?).to be true
        expect(Billing::Operations::ProcessWebhookEvent).not_to have_received(:new)
      end
    end

    context 'with invalid Stripe payload' do
      let(:message_with_invalid_payload) do
        JSON.generate(
          event_id: event_id,
          event_type: 'checkout.session.completed',
          payload: 'not valid json{',
          received_at: Time.now.utc.iso8601
        )
      end

      it 'calls reject! when Stripe payload is invalid JSON' do
        worker.work_with_params(message_with_invalid_payload, delivery_info, metadata)

        expect(worker.rejected?).to be true
        expect(Billing::Operations::ProcessWebhookEvent).not_to have_received(:new)
      end
    end
  end

  describe 'queue configuration' do
    it 'uses correct queue name' do
      expect(described_class::QUEUE_NAME).to eq('billing.event.process')
    end

    it 'uses queue config from QueueConfig' do
      expect(described_class::QUEUE_OPTS).to eq(Onetime::Jobs::QueueConfig::QUEUES['billing.event.process'])
    end
  end

  describe 'message_id edge cases' do
    context 'when message_id is nil' do
      let(:metadata_without_id) do
        MetadataStub.new(
          message_id: nil,
          headers: { 'x-schema-version' => 1 }
        )
      end

      let(:message) do
        JSON.generate(
          event_id: event_id,
          event_type: 'checkout.session.completed',
          payload: stripe_event_payload,
          received_at: Time.now.utc.iso8601
        )
      end

      it 'skips processing when message_id is nil (safety measure)' do
        worker.store_envelope(delivery_info, metadata_without_id)

        worker.work_with_params(message, delivery_info, metadata_without_id)

        # Messages without message_id are acked but skipped
        expect(worker.acked?).to be true
        expect(operation_instance).not_to have_received(:call)
      end
    end
  end

  describe 'different event types' do
    %w[
      checkout.session.completed
      customer.subscription.updated
      customer.subscription.deleted
      product.updated
      price.updated
      invoice.paid
      invoice.payment_failed
    ].each do |event_type|
      it "processes #{event_type} events" do
        event_payload = {
          id: "evt_test_#{event_type.tr('.', '_')}",
          object: 'event',
          type: event_type,
          created: Time.now.to_i,
          livemode: false,
          data: { object: { id: 'obj_123' } }
        }.to_json

        event_message = JSON.generate(
          event_id: "evt_test_#{event_type.tr('.', '_')}",
          event_type: event_type,
          payload: event_payload,
          received_at: Time.now.utc.iso8601
        )

        worker.work_with_params(event_message, delivery_info, metadata)

        expect(worker.acked?).to be true
        expect(Billing::Operations::ProcessWebhookEvent).to have_received(:new).with(
          event: an_instance_of(Stripe::Event),
          context: anything
        )
      end
    end
  end

  describe 'redelivered messages' do
    let(:delivery_info_redelivered) do
      DeliveryInfoStub.new(
        delivery_tag: 2,
        routing_key: 'billing.event.process',
        redelivered?: true
      )
    end

    let(:message) do
      JSON.generate(
        event_id: event_id,
        event_type: 'checkout.session.completed',
        payload: stripe_event_payload,
        received_at: Time.now.utc.iso8601
      )
    end

    it 'processes redelivered message normally (idempotency handles duplicates)' do
      worker.store_envelope(delivery_info_redelivered, metadata)

      worker.work_with_params(message, delivery_info_redelivered, metadata)

      expect(worker.acked?).to be true
      expect(operation_instance).to have_received(:call)
    end

    it 'skips redelivered message if already processed' do
      # Pre-set idempotency key
      Familia.dbclient.setex("job:processed:#{message_id}", 3600, '1')
      worker.store_envelope(delivery_info_redelivered, metadata)

      worker.work_with_params(message, delivery_info_redelivered, metadata)

      expect(worker.acked?).to be true
      expect(operation_instance).not_to have_received(:call)
    end
  end
end
