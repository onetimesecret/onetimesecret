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
#   - Redis test instance at VALKEY_URL='valkey://127.0.0.1:2163/0'
#   - Mocked Onetime::Mail module (Mail.deliver, Mail.deliver_raw)
#   - Mocked Sneakers methods (ack!, reject!, delivery_info)
#   - Redis idempotency key cleanup between tests
#
# Run with: pnpm run test:rspec spec/onetime/jobs/workers/email_worker_spec.rb

require 'spec_helper'
require 'support/amqp_stubs'
require 'sneakers'
require 'timeout'
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
  let(:retry_delays) { [] }

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

    # Collapse the retry backoff. The sleep is RetryHelper's, not the
    # worker's: BaseWorker#with_retry delegates to
    # Onetime::Utils::RetryHelper.with_retry, which calls sleep on itself
    # (`extend self`), so a stub on the worker never fires and every example
    # that exhausts the retries pays the real 2s + 4s + 8s (+jitter). Record
    # the delays requested instead, so those examples can assert the schedule.
    allow(Onetime::Utils::RetryHelper).to receive(:sleep) { |delay| retry_delays << delay }
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

      it 'falls back to the default locale when the payload locale is an empty string' do
        message_with_empty_locale = JSON.generate(
          template: 'secret_link',
          data: {
            secret_key: 'abc123',
            share_domain: nil,
            recipient: 'user@example.com',
            sender_email: 'sender@example.com',
            locale: ''
          }
        )

        worker.work_with_params(message_with_empty_locale, delivery_info, metadata)

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

      it 'falls back to the default locale when the payload locale is whitespace-only' do
        message_with_whitespace_locale = JSON.generate(
          template: 'secret_link',
          data: {
            secret_key: 'abc123',
            share_domain: nil,
            recipient: 'user@example.com',
            sender_email: 'sender@example.com',
            locale: '   '
          }
        )

        worker.work_with_params(message_with_whitespace_locale, delivery_info, metadata)

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

      it 'strips surrounding whitespace from a valid payload locale' do
        message_with_padded_locale = JSON.generate(
          template: 'secret_link',
          data: {
            secret_key: 'abc123',
            share_domain: nil,
            recipient: 'user@example.com',
            sender_email: 'sender@example.com',
            locale: ' fr '
          }
        )

        worker.work_with_params(message_with_padded_locale, delivery_info, metadata)

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
        # Backoff requested (base_delay 2.0, doubling, up to 30% jitter), not slept
        expect(retry_delays.size).to eq(3)
        expect(retry_delays.zip([2.0, 4.0, 8.0])).to all(satisfy { |delay, base| delay.between?(base, base * 1.3) })
      end

      it 'calls reject! without retrying when Mail.deliver raises non-transient DeliveryError' do
        error = Onetime::Mail::DeliveryError.new('SMTP error', transient: false)
        allow(Onetime::Mail).to receive(:deliver).and_raise(error)

        worker.work_with_params(message, delivery_info, metadata)

        # Non-transient DeliveryError skips retries and goes straight to DLQ
        expect(worker.rejected?).to be true
        expect(Onetime::Mail).to have_received(:deliver).exactly(1).times
        expect(retry_delays).to be_empty
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

    context 'delivery events (#4479)' do
      let(:message_id) { "evt-#{SecureRandom.hex(6)}" }
      let(:message) do
        JSON.generate(
          template: 'secret_viewed',
          correlation_id: 'notif-msg-1',
          event_type: 'secret.viewed',
          customer_extid: 'ur2a3b4c5d',
          data: { secret_key: 'abc123', to: 'user@example.com', locale: 'en' },
        )
      end

      def recorded
        Onetime::DeliveryEvent.recent(20)
      end

      before { Onetime::DeliveryEvent.events.clear }
      after  { Onetime::DeliveryEvent.events.clear }

      it 'records one terminal sent event carrying the correlation id from the payload' do
        allow(Onetime::Mail).to receive(:deliver).and_return(double('response', message_id: 'ses-0100'))

        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
        expect(recorded.size).to eq(1)
        expect(recorded.first).to include(
          'channel' => 'email',
          'stage' => 'delivery',
          'outcome' => 'sent',
          'correlation_id' => 'notif-msg-1',
          'message_id' => message_id,
          'event_type' => 'secret.viewed',
          'template' => 'secret_viewed',
          'customer_id' => 'ur2a3b4c5d',
          'provider_message_id' => 'ses-0100',
          'attempt_count' => 1,
        )
        expect(recorded.first['provider']).to eq(Onetime::Mail::Mailer.determine_provider)
        expect(recorded.first.to_json).not_to include('user@example.com', 'abc123')
      end

      it 'records one failed event with the attempt count after retries are exhausted' do
        allow(Onetime::Mail).to receive(:deliver)
          .and_raise(Onetime::Mail::DeliveryError.new('SMTP delivery error: 451 try later for user@example.com', transient: true))

        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.rejected?).to be true
        expect(recorded.size).to eq(1)
        expect(recorded.first).to include(
          'outcome' => 'failed',
          'reason' => 'retries_exhausted',
          'error_class' => 'Onetime::Mail::DeliveryError',
          'attempt_count' => 4,
          'correlation_id' => 'notif-msg-1',
        )
        expect(recorded.first).not_to have_key('error_message')
        expect(recorded.first.to_json).not_to include('user@example.com')
      end

      it 'records a permanent failure without retries' do
        allow(Onetime::Mail).to receive(:deliver)
          .and_raise(Onetime::Mail::DeliveryError.new('rejected', transient: false))

        worker.work_with_params(message, delivery_info, metadata)

        expect(recorded.first).to include('outcome' => 'failed', 'reason' => 'permanent', 'attempt_count' => 1)
      end

      it 'records skipped when the backend returns nil (suppressed recipient or delivery disabled)' do
        allow(Onetime::Mail).to receive(:deliver).and_return(nil)

        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
        expect(recorded.first).to include('outcome' => 'skipped', 'reason' => 'not_dispatched')
      end

      it 'uses its own queue message id as the correlation id for a legacy payload' do
        legacy = JSON.generate(template: 'secret_link', data: { secret_key: 'abc123', recipient: 'user@example.com' })
        allow(Onetime::Mail).to receive(:deliver).and_return(double('response'))

        worker.work_with_params(legacy, delivery_info, metadata)

        expect(recorded.first).to include(
          'correlation_id' => message_id,
          'message_id' => message_id,
          'template' => 'secret_link',
        )
        expect(recorded.first).not_to have_key('event_type')
      end

      it 'records nothing for a duplicate message' do
        Familia.dbclient.setex("job:processed:#{message_id}", 3600, '1')

        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
        expect(recorded).to be_empty
      end

      it 'records a failed invalid_message event for a malformed payload' do
        worker.work_with_params(JSON.generate(data: { to: 'user@example.com' }), delivery_info, metadata)

        expect(worker.rejected?).to be true
        expect(recorded.first).to include(
          'outcome' => 'failed',
          'reason' => 'invalid_message',
          'error_class' => 'ArgumentError',
        )
      end

      context 'when parsing rejects the message before delivery' do
        before { allow(Onetime::DeliveryEvent).to receive(:record).and_call_original }

        shared_examples 'an observable parse rejection' do
          it 'records one failed event using only the envelope id and zero delivery attempts' do
            expect(worker).to receive(:reject!).once.and_call_original
            expect(worker).not_to receive(:claim_for_processing)

            worker.work_with_params(invalid_message, delivery_info, invalid_metadata)

            expect(worker.rejected?).to be true
            expect(worker.acked?).to be false
            expect(Onetime::Mail).not_to have_received(:deliver)
            expect(Onetime::Mail).not_to have_received(:deliver_raw)
            expect(Onetime::DeliveryEvent).to have_received(:record).once.with(hash_including(
              channel: 'email',
              stage: 'delivery',
              outcome: 'failed',
              reason: 'invalid_message',
              message_id: message_id,
              correlation_id: message_id,
              attempt_count: 0,
              event_type: nil,
              template: nil,
              customer_id: nil,
            ))
            expect(recorded.size).to eq(1)
            expect(recorded.first).to include(
              'outcome' => 'failed',
              'reason' => 'invalid_message',
              'message_id' => message_id,
              'correlation_id' => message_id,
            )
            # DeliveryEvent currently omits zero counts from the stored shape;
            # the recorder call above verifies that no delivery was attempted.
            expect(recorded.first.keys & %w[event_type template customer_id error_class error_message]).to be_empty
            expect(recorded.first.to_json).not_to include('untrusted', 'user@example.com', 'abc123')
            expect(retry_delays).to be_empty
          end

          it 'still rejects once when recording the parse failure raises' do
            allow(Onetime::DeliveryEvent).to receive(:record).and_raise(RedisClient::CannotConnectError, 'down')
            expect(worker).to receive(:reject!).once.and_call_original

            worker.work_with_params(invalid_message, delivery_info, invalid_metadata)

            expect(worker.rejected?).to be true
            expect(worker.acked?).to be false
            expect(Onetime::DeliveryEvent).to have_received(:record).once
          end
        end

        context 'with malformed JSON' do
          let(:invalid_message) { '{"template":"untrusted","body":"abc123 user@example.com"' }
          let(:invalid_metadata) { metadata }

          include_examples 'an observable parse rejection'
        end

        context 'with an unsupported schema' do
          let(:invalid_message) do
            JSON.generate(
              template: 'untrusted',
              correlation_id: 'untrusted-correlation',
              event_type: 'untrusted.event',
              customer_extid: 'uruntrusted',
              data: { secret_key: 'abc123', to: 'user@example.com' },
            )
          end
          let(:invalid_metadata) do
            MetadataStub.new(message_id: message_id, headers: { 'x-schema-version' => 999 })
          end

          include_examples 'an observable parse rejection'
        end
      end

      it 'records both terminal events for overlapping calls on the same worker instance' do
        first_started = Queue.new
        release_first = Queue.new
        worker_instance = worker
        first_message = JSON.generate(template: 'secret_viewed', data: { secret_key: 'first' })
        second_message = JSON.generate(template: 'secret_viewed', data: { secret_key: 'second' })
        first_metadata = MetadataStub.new(message_id: "#{message_id}-first", headers: { 'x-schema-version' => 1 })
        second_metadata = MetadataStub.new(message_id: "#{message_id}-second", headers: { 'x-schema-version' => 1 })
        envelope = delivery_info
        response = double('response', message_id: 'provider-first')
        allow(Onetime::Mail).to receive(:deliver) do |_template, data, **_options|
          if data[:secret_key] == 'first'
            first_started << true
            release_first.pop
            response
          else
            raise Onetime::Mail::DeliveryError.new('rejected', transient: false)
          end
        end

        first_thread = Thread.new { worker_instance.work_with_params(first_message, envelope, first_metadata) }
        Timeout.timeout(10) { first_started.pop }
        worker_instance.work_with_params(second_message, envelope, second_metadata)
        release_first << true
        Timeout.timeout(10) { first_thread.value }

        expect(recorded.size).to eq(2)
        events = recorded.to_h { |event| [event['message_id'], event] }
        expect(events.fetch(first_metadata.message_id)).to include(
          'outcome' => 'sent', 'correlation_id' => first_metadata.message_id, 'attempt_count' => 1,
        )
        expect(events.fetch(second_metadata.message_id)).to include(
          'outcome' => 'failed', 'reason' => 'permanent', 'correlation_id' => second_metadata.message_id,
          'attempt_count' => 1,
        )
      ensure
        first_thread&.kill
        first_thread&.join
      end

      it 'keeps the single sent event when acknowledgment raises after successful delivery' do
        allow(Onetime::Mail).to receive(:deliver).and_return(double('response'))
        allow(worker).to receive(:ack!).and_raise(StandardError, 'ack failed')
        expect(Onetime::DeliveryEvent).to receive(:record).once.and_call_original

        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.rejected?).to be true
        expect(recorded.size).to eq(1)
        expect(recorded.first).to include('outcome' => 'sent', 'message_id' => message_id, 'attempt_count' => 1)
      end

      it 'does not record again when recording fails and acknowledgment then raises' do
        allow(Onetime::Mail).to receive(:deliver).and_return(double('response'))
        allow(worker).to receive(:ack!).and_raise(StandardError, 'ack failed')
        expect(Onetime::DeliveryEvent).to receive(:record).once
          .with(hash_including(outcome: 'sent', message_id: message_id))
          .and_raise(RedisClient::CannotConnectError, 'down')

        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.rejected?).to be true
        expect(recorded).to be_empty
      end

      it 'records nothing for a ping message' do
        ping = JSON.generate(template: 'ping_test', data: { test: true, ping_id: 'ping-1' })
        expect(worker).not_to receive(:claim_for_processing)
        expect(Onetime::DeliveryEvent).not_to receive(:record)

        worker.work_with_params(ping, delivery_info, metadata)

        expect(worker.acked?).to be true
        expect(Onetime::Mail).not_to have_received(:deliver)
        expect(recorded).to be_empty
      end

      it 'does not reset an in-flight guard when another call starts before acknowledgment fails' do
        first_at_ack = Queue.new
        release_first_ack = Queue.new
        second_started = Queue.new
        release_second = Queue.new
        worker_instance = worker
        first_message = JSON.generate(template: 'secret_viewed', data: { secret_key: 'first' })
        second_message = JSON.generate(template: 'secret_viewed', data: { secret_key: 'second' })
        first_metadata = MetadataStub.new(message_id: "#{message_id}-first", headers: { 'x-schema-version' => 1 })
        second_metadata = MetadataStub.new(message_id: "#{message_id}-second", headers: { 'x-schema-version' => 1 })
        envelope = delivery_info
        response = double('response')
        allow(Onetime::Mail).to receive(:deliver) do |_template, data, **_options|
          if data[:secret_key] == 'second'
            second_started << true
            release_second.pop
          end
          response
        end
        first_ack = true
        allow(worker_instance).to receive(:ack!) do
          if first_ack
            first_ack = false
            first_at_ack << true
            release_first_ack.pop
            raise StandardError, 'ack failed'
          end
        end

        first_thread = Thread.new { worker_instance.work_with_params(first_message, envelope, first_metadata) }
        Timeout.timeout(10) { first_at_ack.pop }
        second_thread = Thread.new { worker_instance.work_with_params(second_message, envelope, second_metadata) }
        Timeout.timeout(10) { second_started.pop }
        release_first_ack << true
        Timeout.timeout(10) { first_thread.value }
        release_second << true
        Timeout.timeout(10) { second_thread.value }

        expect(recorded.size).to eq(2)
        expect(recorded.map { |event| event['outcome'] }).to eq(%w[sent sent])
        expect(recorded.map { |event| event['message_id'] }).to contain_exactly(
          first_metadata.message_id, second_metadata.message_id,
        )
      ensure
        first_thread&.kill
        second_thread&.kill
        first_thread&.join
        second_thread&.join
      end

      it 'still acknowledges when event recording fails' do
        allow(Onetime::Mail).to receive(:deliver).and_return(double('response'))
        allow(Onetime::DeliveryEvent).to receive(:record).and_raise(RedisClient::CannotConnectError, 'down')

        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
        expect(worker.rejected?).to be false
      end
    end
  end
end
