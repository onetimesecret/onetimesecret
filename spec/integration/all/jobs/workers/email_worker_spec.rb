# spec/integration/all/jobs/workers/email_worker_spec.rb
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
require 'support/amqp_stubs'
require 'sneakers'
require 'onetime/jobs/workers/email_worker'
require 'onetime/jobs/queues/config'

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

      it 'calls Mail.deliver with template symbol, data hash, locale, and nil sender_config' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(Onetime::Mail).to have_received(:deliver).with(
          :secret_link,
          {
            secret_key: 'abc123',
            share_domain: nil,
            recipient: 'user@example.com',
            sender_email: 'sender@example.com'
          },
          locale: 'en',
          sender_config: nil
        )
      end

      it 'uses locale from payload when provided' do
        message_with_locale = JSON.generate(
          template: 'secret_link',
          data: {
            secret_key: 'abc123',
            share_domain: nil,
            recipient: 'user@example.com',
            sender_email: 'sender@example.com',
            locale: 'fr'
          }
        )

        worker.work_with_params(message_with_locale, delivery_info, metadata)

        expect(Onetime::Mail).to have_received(:deliver).with(
          :secret_link,
          {
            secret_key: 'abc123',
            share_domain: nil,
            recipient: 'user@example.com',
            sender_email: 'sender@example.com'
          },
          locale: 'fr',
          sender_config: nil
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

      it 'calls Mail.deliver_raw with email hash and nil sender_config when raw: true' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(Onetime::Mail).to have_received(:deliver_raw).with(
          {
            to: 'user@example.com',
            from: 'noreply@example.com',
            subject: 'Test Email',
            body: 'Email body content'
          },
          sender_config: nil
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

      it 'calls reject! without retrying when Mail.deliver raises non-transient DeliveryError' do
        error = Onetime::Mail::DeliveryError.new('SMTP error', transient: false)
        allow(Onetime::Mail).to receive(:deliver).and_raise(error)

        worker.work_with_params(message, delivery_info, metadata)

        # Non-transient DeliveryError skips retries and goes straight to DLQ
        expect(worker.rejected?).to be true
        expect(Onetime::Mail).to have_received(:deliver).exactly(1).times
      end

      it 'keeps idempotency key even when delivery fails after retries' do
        # claim_for_processing atomically sets the key BEFORE attempting delivery,
        # so the key exists regardless of delivery success/failure. This prevents
        # re-processing on redelivery even if the original attempt failed.
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

    # ========================================================================
    # Sender Config (domain_id threading) Tests
    # ========================================================================
    # These tests verify that domain_id is extracted from the message payload,
    # MailerConfig is loaded, and sender_config is passed through to Mail.deliver
    # and Mail.deliver_raw.
    # ========================================================================

    context 'with domain_id in templated email payload' do
      let(:mock_sender_config) do
        instance_double(
          Onetime::CustomDomain::MailerConfig,
          domain_id: 'dom_abc123',
          from_address: 'noreply@custom.example.com',
          from_name: 'Custom Sender',
          reply_to: 'support@custom.example.com',
          provider: 'ses',
          enabled?: true,
          verified?: true,
          api_key: 'test-api-key'
        )
      end

      let(:message) do
        JSON.generate(
          template: 'secret_link',
          domain_id: 'dom_abc123',
          data: {
            secret_key: 'abc123',
            share_domain: 'custom.example.com',
            recipient: 'user@example.com',
            sender_email: 'sender@example.com'
          }
        )
      end

      before do
        allow(Onetime::CustomDomain::MailerConfig)
          .to receive(:find_by_domain_id)
          .with('dom_abc123')
          .and_return(mock_sender_config)
      end

      it 'loads MailerConfig for the domain_id and passes it to Mail.deliver' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(Onetime::CustomDomain::MailerConfig).to have_received(:find_by_domain_id).with('dom_abc123')
        expect(Onetime::Mail).to have_received(:deliver).with(
          :secret_link,
          {
            secret_key: 'abc123',
            share_domain: 'custom.example.com',
            recipient: 'user@example.com',
            sender_email: 'sender@example.com'
          },
          locale: 'en',
          sender_config: mock_sender_config
        )
      end

      it 'acknowledges the message after successful delivery' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
      end
    end

    context 'with domain_id in raw email payload' do
      let(:mock_sender_config) do
        instance_double(
          Onetime::CustomDomain::MailerConfig,
          domain_id: 'dom_raw456',
          from_address: 'noreply@rawdomain.example.com',
          from_name: 'Raw Domain Sender',
          reply_to: nil,
          provider: 'smtp',
          enabled?: true,
          verified?: true,
          api_key: 'raw-api-key'
        )
      end

      let(:message) do
        JSON.generate(
          raw: true,
          domain_id: 'dom_raw456',
          email: {
            to: 'user@example.com',
            from: 'noreply@example.com',
            subject: 'Raw Test',
            body: 'Raw body'
          }
        )
      end

      before do
        allow(Onetime::CustomDomain::MailerConfig)
          .to receive(:find_by_domain_id)
          .with('dom_raw456')
          .and_return(mock_sender_config)
      end

      it 'passes sender_config to Mail.deliver_raw' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(Onetime::Mail).to have_received(:deliver_raw).with(
          {
            to: 'user@example.com',
            from: 'noreply@example.com',
            subject: 'Raw Test',
            body: 'Raw body'
          },
          sender_config: mock_sender_config
        )
      end
    end

    context 'with missing domain_id (backward compatibility)' do
      let(:message) do
        JSON.generate(
          template: 'secret_link',
          data: {
            secret_key: 'abc123',
            recipient: 'user@example.com',
            sender_email: 'sender@example.com'
          }
        )
      end

      it 'does not attempt to load MailerConfig' do
        allow(Onetime::CustomDomain::MailerConfig).to receive(:find_by_domain_id)

        worker.work_with_params(message, delivery_info, metadata)

        expect(Onetime::CustomDomain::MailerConfig).not_to have_received(:find_by_domain_id)
      end

      it 'passes nil sender_config to Mail.deliver' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(Onetime::Mail).to have_received(:deliver).with(
          :secret_link,
          hash_including(secret_key: 'abc123'),
          locale: 'en',
          sender_config: nil
        )
      end
    end

    context 'with domain_id that has no MailerConfig' do
      let(:message) do
        JSON.generate(
          template: 'secret_link',
          domain_id: 'dom_nonexistent',
          data: {
            secret_key: 'abc123',
            recipient: 'user@example.com',
            sender_email: 'sender@example.com'
          }
        )
      end

      before do
        allow(Onetime::CustomDomain::MailerConfig)
          .to receive(:find_by_domain_id)
          .with('dom_nonexistent')
          .and_return(nil)
      end

      it 'falls back to nil sender_config when no config exists' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(Onetime::Mail).to have_received(:deliver).with(
          :secret_link,
          hash_including(secret_key: 'abc123'),
          locale: 'en',
          sender_config: nil
        )
      end

      it 'still acknowledges the message' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
      end
    end

    context 'when MailerConfig lookup raises an error' do
      let(:message) do
        JSON.generate(
          template: 'secret_link',
          domain_id: 'dom_error',
          data: {
            secret_key: 'abc123',
            recipient: 'user@example.com',
            sender_email: 'sender@example.com'
          }
        )
      end

      before do
        allow(Onetime::CustomDomain::MailerConfig)
          .to receive(:find_by_domain_id)
          .with('dom_error')
          .and_raise(StandardError, 'Redis connection refused')
      end

      it 'gracefully falls back to nil sender_config' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(Onetime::Mail).to have_received(:deliver).with(
          :secret_link,
          hash_including(secret_key: 'abc123'),
          locale: 'en',
          sender_config: nil
        )
      end

      it 'still delivers the email and acknowledges' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
      end
    end
  end
end
