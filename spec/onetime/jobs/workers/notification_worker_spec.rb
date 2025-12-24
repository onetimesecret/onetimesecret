# spec/onetime/jobs/workers/notification_worker_spec.rb
#
# frozen_string_literal: true

# NotificationWorker Test Suite
#
# Tests the notification worker that consumes messages from the
# notifications.alert.push queue and delegates to DispatchNotification operation.
#
# Test Categories:
#
#   1. Message processing (Unit)
#      - Verifies operation is called with correct data
#      - Verifies ack! after successful processing
#
#   2. Idempotency handling (Integration)
#      - Tests that pre-existing Redis key prevents duplicate processing
#      - Tests that successful processing creates Redis idempotency key
#
#   3. Failure handling (Unit)
#      - Tests that errors trigger reject! to send to DLQ
#
# Note: Channel-specific delivery logic is tested in dispatch_notification_spec.rb
#
# Setup Requirements:
#   - Redis test instance at VALKEY_URL='valkey://127.0.0.1:2121/0'
#   - Mocked DispatchNotification operation
#
# Run with: pnpm run test:rspec spec/onetime/jobs/workers/notification_worker_spec.rb

require 'spec_helper'
require 'sneakers'
require_relative '../../../../lib/onetime/jobs/workers/notification_worker'
require_relative '../../../../lib/onetime/jobs/queue_config'

# Data classes for mocking AMQP envelope components (immutable, Ruby 3.2+)
DeliveryInfoStub = Data.define(:delivery_tag, :routing_key, :redelivered?) unless defined?(DeliveryInfoStub)
MetadataStub = Data.define(:message_id, :headers) unless defined?(MetadataStub)

RSpec.describe Onetime::Jobs::Workers::NotificationWorker, type: :integration do
  # Create test worker class with accessible delivery_info
  let(:test_worker_class) do
    Class.new(Onetime::Jobs::Workers::NotificationWorker) do
      attr_accessor :delivery_info, :acked, :rejected

      def self.name
        'TestNotificationWorker'
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
  let(:message_id) { 'test-notification-123' }
  let(:custid) { 'cust:test-user-456' }

  # Mock Sneakers delivery_info (envelope info)
  let(:delivery_info) do
    DeliveryInfoStub.new(
      delivery_tag: 1,
      routing_key: 'notifications.alert.push',
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

  let(:operation_instance) { instance_double(Onetime::Operations::DispatchNotification) }

  before do
    # Ensure clean Redis state
    Familia.dbclient.del("job:processed:#{message_id}")

    # Store envelope
    worker.store_envelope(delivery_info, metadata)

    # Mock sleep to speed up retry tests
    allow(worker).to receive(:sleep)

    # Mock operation by default
    allow(Onetime::Operations::DispatchNotification).to receive(:new).and_return(operation_instance)
    allow(operation_instance).to receive(:call).and_return({ via_bell: :success })
  end

  after do
    Familia.dbclient.del("job:processed:#{message_id}")
  end

  describe '#work_with_params' do
    let(:message) do
      JSON.generate(
        type: 'secret.viewed',
        addressee: {
          custid: custid,
          email: 'user@example.com'
        },
        template: 'secret_viewed',
        locale: 'en',
        channels: ['via_bell'],
        data: {
          secret_key: 'abc123'
        }
      )
    end

    context 'successful processing' do
      it 'calls DispatchNotification operation with parsed data' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(Onetime::Operations::DispatchNotification).to have_received(:new).with(
          data: hash_including(
            type: 'secret.viewed',
            template: 'secret_viewed',
            addressee: hash_including(custid: custid)
          ),
          context: hash_including(source_message_id: message_id)
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
    end

    context 'idempotency handling' do
      it 'skips processing and acknowledges when message already processed' do
        # Pre-set Redis idempotency key
        Familia.dbclient.setex("job:processed:#{message_id}", 3600, '1')

        worker.work_with_params(message, delivery_info, metadata)

        # Should ack without calling operation
        expect(worker.acked?).to be true
        expect(Onetime::Operations::DispatchNotification).not_to have_received(:new)
      end

      it 'creates Redis idempotency key with TTL after successful processing' do
        Familia.dbclient.del("job:processed:#{message_id}")

        worker.work_with_params(message, delivery_info, metadata)

        expect(Familia.dbclient.exists?("job:processed:#{message_id}")).to be_truthy
        ttl = Familia.dbclient.ttl("job:processed:#{message_id}")
        expect(ttl).to be > 0
        expect(ttl).to be <= Onetime::Jobs::QueueConfig::IDEMPOTENCY_TTL
      end
    end

    context 'failure handling' do
      it 'calls reject! when operation raises unexpected error after retries' do
        allow(operation_instance).to receive(:call).and_raise(StandardError, 'Unexpected error')

        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.rejected?).to be true
        # Initial + 2 retries = 3 calls
        expect(operation_instance).to have_received(:call).exactly(3).times
      end

      it 'retries on transient errors' do
        call_count = 0
        allow(operation_instance).to receive(:call) do
          call_count += 1
          raise StandardError, 'Transient error' if call_count < 2
          { via_bell: :success }
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
        expect(Onetime::Operations::DispatchNotification).not_to have_received(:new)
      end
    end
  end

  describe 'queue configuration' do
    it 'uses correct queue name' do
      expect(described_class::QUEUE_NAME).to eq('notifications.alert.push')
    end

    it 'uses queue config from QueueConfig' do
      expect(described_class::QUEUE_OPTS).to eq(Onetime::Jobs::QueueConfig::QUEUES['notifications.alert.push'])
    end
  end

  # === Additional Edge Case Coverage ===

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
          type: 'secret.viewed',
          addressee: { custid: custid },
          template: 'secret_viewed',
          channels: ['via_bell'],
          data: {}
        )
      end

      it 'skips processing when message_id is nil (safety measure)' do
        worker.store_envelope(delivery_info, metadata_without_id)

        worker.work_with_params(message, delivery_info, metadata_without_id)

        # Messages without message_id are acked but skipped
        # This is intentional - idempotency requires a message_id
        expect(worker.acked?).to be true
        expect(operation_instance).not_to have_received(:call)
      end
    end
  end

  describe 'schema version validation' do
    let(:message) do
      JSON.generate(
        type: 'secret.viewed',
        addressee: { custid: custid },
        template: 'secret_viewed',
        channels: ['via_bell'],
        data: {}
      )
    end

    context 'with unknown schema version' do
      let(:metadata_v99) do
        MetadataStub.new(
          message_id: message_id,
          headers: { 'x-schema-version' => 99 }
        )
      end

      it 'rejects message with unknown schema version' do
        worker.store_envelope(delivery_info, metadata_v99)

        worker.work_with_params(message, delivery_info, metadata_v99)

        expect(worker.rejected?).to be true
        expect(operation_instance).not_to have_received(:call)
      end
    end

    context 'with missing schema version header' do
      let(:metadata_no_version) do
        MetadataStub.new(
          message_id: message_id,
          headers: {}
        )
      end

      it 'defaults to schema version 1 and processes normally' do
        worker.store_envelope(delivery_info, metadata_no_version)

        worker.work_with_params(message, delivery_info, metadata_no_version)

        expect(worker.acked?).to be true
        expect(operation_instance).to have_received(:call)
      end
    end

    context 'when metadata headers is nil' do
      let(:metadata_nil_headers) do
        MetadataStub.new(
          message_id: message_id,
          headers: nil
        )
      end

      it 'handles nil headers gracefully and defaults to version 1' do
        worker.store_envelope(delivery_info, metadata_nil_headers)

        worker.work_with_params(message, delivery_info, metadata_nil_headers)

        expect(worker.acked?).to be true
        expect(operation_instance).to have_received(:call)
      end
    end
  end

  describe 'redelivered messages' do
    let(:delivery_info_redelivered) do
      DeliveryInfoStub.new(
        delivery_tag: 2,
        routing_key: 'notifications.alert.push',
        redelivered?: true
      )
    end

    let(:message) do
      JSON.generate(
        type: 'secret.viewed',
        addressee: { custid: custid },
        template: 'secret_viewed',
        channels: ['via_bell'],
        data: {}
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

  describe 'operation result handling' do
    let(:message) do
      JSON.generate(
        type: 'secret.viewed',
        addressee: { custid: custid, email: 'user@example.com', webhook_url: 'https://example.com/hook' },
        template: 'secret_viewed',
        channels: %w[via_bell via_email via_webhook],
        data: {}
      )
    end

    context 'when operation returns partial errors' do
      before do
        allow(operation_instance).to receive(:call).and_return({
          via_bell: :success,
          via_email: :error,
          via_webhook: :skipped
        })
      end

      it 'acknowledges message even with partial channel failures' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
        expect(worker.rejected?).to be false
      end
    end

    context 'when operation returns all errors' do
      before do
        allow(operation_instance).to receive(:call).and_return({
          via_bell: :error,
          via_email: :error,
          via_webhook: :error
        })
      end

      it 'still acknowledges message (errors are per-channel, not fatal)' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
        expect(worker.rejected?).to be false
      end
    end
  end

  describe 'different event types' do
    %w[secret.viewed secret.burned secret.created secret.expired].each do |event_type|
      it "processes #{event_type} events" do
        event_message = JSON.generate(
          type: event_type,
          addressee: { custid: custid },
          template: event_type.tr('.', '_'),
          channels: ['via_bell'],
          data: {}
        )

        worker.work_with_params(event_message, delivery_info, metadata)

        expect(worker.acked?).to be true
        expect(Onetime::Operations::DispatchNotification).to have_received(:new).with(
          data: hash_including(type: event_type),
          context: anything
        )
      end
    end
  end

  describe 'empty and minimal payloads' do
    context 'with empty JSON object' do
      let(:empty_message) { '{}' }

      it 'processes empty payload and delegates to operation' do
        worker.work_with_params(empty_message, delivery_info, metadata)

        expect(worker.acked?).to be true
        expect(operation_instance).to have_received(:call)
      end
    end

    context 'with minimal valid payload' do
      let(:minimal_message) do
        JSON.generate(type: 'test.event')
      end

      it 'processes minimal payload' do
        worker.work_with_params(minimal_message, delivery_info, metadata)

        expect(worker.acked?).to be true
        expect(operation_instance).to have_received(:call)
      end
    end
  end
end
