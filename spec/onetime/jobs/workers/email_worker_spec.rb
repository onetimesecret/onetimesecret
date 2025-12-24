# spec/onetime/jobs/workers/email_worker_spec.rb
#
# frozen_string_literal: true

# EmailWorker Test Suite
#
# Tests the email delivery worker that consumes messages from the
# email.message.send queue and delivers emails via Onetime::Mail.
#
# Test Categories:
#
#   1. Templated email delivery (Unit)
#      - Verifies Mail.deliver is called with correct template and data
#      - Uses mocked Mail module to verify method arguments
#
#   2. Raw email delivery (Unit)
#      - Verifies Mail.deliver_raw is called with correct email hash
#      - Uses mocked Mail module to verify method arguments
#
#   3. Idempotency skip (Integration)
#      - Tests that pre-existing Redis key prevents duplicate delivery
#      - Uses real Redis instance with mocked Mail module
#
#   4. Idempotency mark (Integration)
#      - Tests that successful delivery creates Redis idempotency key
#      - Uses real Redis instance with mocked Mail module
#
#   5. Failure handling (Unit)
#      - Tests that Mail errors trigger reject! to send to DLQ
#      - Uses mocked Mail and Sneakers methods (ack!/reject!)
#
# Setup Requirements:
#   - Redis test instance at VALKEY_URL='valkey://127.0.0.1:2121/0'
#   - Mocked Onetime::Mail module (Mail.deliver, Mail.deliver_raw)
#   - Mocked Sneakers methods (ack!, reject!, delivery_info)
#   - Redis idempotency key cleanup between tests
#
# Run with: pnpm run test:rspec spec/onetime/jobs/workers/email_worker_spec.rb

require 'spec_helper'
require 'sneakers'
require_relative '../../../../lib/onetime/jobs/workers/email_worker'
require_relative '../../../../lib/onetime/jobs/queue_config'

# Data classes for mocking AMQP envelope components (immutable, Ruby 3.2+)
DeliveryInfoStub = Data.define(:delivery_tag, :routing_key, :redelivered?) unless defined?(DeliveryInfoStub)
MetadataStub = Data.define(:message_id, :headers) unless defined?(MetadataStub)

RSpec.describe Onetime::Jobs::Workers::EmailWorker, type: :integration do
  # Create test worker class with accessible delivery_info
  let(:test_worker_class) do
    Class.new(Onetime::Jobs::Workers::EmailWorker) do
      attr_accessor :delivery_info, :acked, :rejected

      def self.name
        'TestEmailWorker'
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
  let(:message_id) { 'test-msg-123' }

  # Mock Sneakers delivery_info (envelope info)
  let(:delivery_info) do
    DeliveryInfoStub.new(
      delivery_tag: 1,
      routing_key: 'email.message.send',
      redelivered?: false
    )
  end

  # Mock Sneakers metadata (message properties - passed separately by Kicks)
  let(:metadata) do
    MetadataStub.new(
      message_id: message_id,
      headers: { 'x-schema-version' => 1 }
    )
  end

  before do
    # Ensure clean Redis state for idempotency tests
    Familia.dbclient.del("job:processed:#{message_id}")

    # Store envelope is called by work_with_params, but we can also pre-set for tests
    worker.store_envelope(delivery_info, metadata)

    # Mock Onetime::Mail module
    allow(Onetime::Mail).to receive(:deliver)
    allow(Onetime::Mail).to receive(:deliver_raw)

    # Mock sleep to speed up retry tests
    allow(worker).to receive(:sleep)
  end

  describe '#work_with_params' do
    context 'templated email delivery' do
      let(:message) do
        JSON.generate(
          template: 'secret_link',
          data: {
            secret_key: 'abc123',
            share_domain: nil,
            recipient: 'user@example.com',
            sender_email: 'sender@example.com'
          }
        )
      end

      it 'calls Mail.deliver with template symbol and data hash' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(Onetime::Mail).to have_received(:deliver).with(
          :secret_link,
          {
            secret_key: 'abc123',
            share_domain: nil,
            recipient: 'user@example.com',
            sender_email: 'sender@example.com'
          }
        )
      end

      it 'acknowledges the message after successful delivery' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
      end

      it 'marks message as processed after successful delivery' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(Familia.dbclient.exists?("job:processed:#{message_id}")).to be_truthy
      end
    end

    context 'raw email delivery' do
      let(:message) do
        JSON.generate(
          raw: true,
          email: {
            to: 'user@example.com',
            from: 'noreply@example.com',
            subject: 'Test Email',
            body: 'Email body content'
          }
        )
      end

      it 'calls Mail.deliver_raw with email hash when raw: true' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(Onetime::Mail).to have_received(:deliver_raw).with(
          {
            to: 'user@example.com',
            from: 'noreply@example.com',
            subject: 'Test Email',
            body: 'Email body content'
          }
        )
      end

      it 'acknowledges the message after successful delivery' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
      end

      it 'marks message as processed after successful delivery' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(Familia.dbclient.exists?("job:processed:#{message_id}")).to be_truthy
      end
    end

    context 'idempotency handling' do
      let(:message) do
        JSON.generate(
          template: 'secret_link',
          data: { secret_key: 'abc123', recipient: 'test@example.com', sender_email: 'sender@example.com' }
        )
      end

      it 'skips delivery and acknowledges when message already processed' do
        # Pre-set Redis idempotency key
        Familia.dbclient.setex("job:processed:#{message_id}", 3600, '1')

        worker.work_with_params(message, delivery_info, metadata)

        # Should ack without calling Mail
        expect(worker.acked?).to be true
        expect(Onetime::Mail).not_to have_received(:deliver)
        expect(Onetime::Mail).not_to have_received(:deliver_raw)
      end

      it 'creates Redis idempotency key after successful delivery' do
        # Ensure key doesn't exist initially
        Familia.dbclient.del("job:processed:#{message_id}")

        worker.work_with_params(message, delivery_info, metadata)

        # Verify key was created with TTL
        expect(Familia.dbclient.exists?("job:processed:#{message_id}")).to be_truthy
        ttl = Familia.dbclient.ttl("job:processed:#{message_id}")
        expect(ttl).to be > 0
        expect(ttl).to be <= Onetime::Jobs::QueueConfig::IDEMPOTENCY_TTL
      end
    end

    context 'failure handling' do
      let(:message) do
        JSON.generate(
          template: 'secret_link',
          data: { secret_key: 'abc123', recipient: 'test@example.com', sender_email: 'sender@example.com' }
        )
      end

      it 'calls reject! after exhausting retries when Mail.deliver raises StandardError' do
        allow(Onetime::Mail).to receive(:deliver).and_raise(StandardError, 'Delivery failed')

        worker.work_with_params(message, delivery_info, metadata)

        # with_retry raises after max retries, outer rescue catches and calls reject!
        expect(worker.rejected?).to be true
        expect(Onetime::Mail).to have_received(:deliver).exactly(4).times # initial + 3 retries
      end

      it 'calls reject! after exhausting retries when Mail.deliver raises DeliveryError' do
        error = Onetime::Mail::DeliveryError.new('SMTP error', transient: false)
        allow(Onetime::Mail).to receive(:deliver).and_raise(error)

        worker.work_with_params(message, delivery_info, metadata)

        # with_retry raises after max retries, outer rescue catches and calls reject!
        expect(worker.rejected?).to be true
        expect(Onetime::Mail).to have_received(:deliver).exactly(4).times # initial + 3 retries
      end

      it 'keeps idempotency key even when delivery fails after retries' do
        # claim_for_processing atomically sets the key BEFORE attempting delivery,
        # so the key exists regardless of delivery success/failure. This prevents
        # re-processing on redelivery even if the original attempt failed.
        Familia.dbclient.del("job:processed:#{message_id}")

        allow(Onetime::Mail).to receive(:deliver).and_raise(StandardError, 'Delivery failed')

        worker.work_with_params(message, delivery_info, metadata)

        # Key was set by claim_for_processing at the start
        expect(Familia.dbclient.exists?("job:processed:#{message_id}")).to be_truthy
      end
    end

    context 'with missing template' do
      let(:message) do
        JSON.generate(
          data: { secret_key: 'abc123', recipient: 'test@example.com', sender_email: 'sender@example.com' }
        )
      end

      it 'calls reject! for invalid message format' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.rejected?).to be true
        expect(Onetime::Mail).not_to have_received(:deliver)
      end
    end

    context 'with missing email data in raw mode' do
      let(:message) do
        JSON.generate(
          raw: true,
          email: {}
        )
      end

      it 'calls reject! for invalid raw message' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.rejected?).to be true
        expect(Onetime::Mail).not_to have_received(:deliver_raw)
      end
    end
  end

  # Clean up Redis keys after each test
  after do
    Familia.dbclient.del("job:processed:#{message_id}")
  end
end
