# spec/lib/onetime/jobs/workers/favicon_fetch_worker_spec.rb
#
# frozen_string_literal: true

# FaviconFetchWorker Test Suite (#3780)
#
# Tests the thin Sneakers wrapper that consumes domain.favicon.fetch and
# delegates to Onetime::Operations::FetchDomainFavicon. The operation is
# fully stubbed here — these tests exercise the worker's translation of the
# operation's raise-vs-return contract into RabbitMQ ack/requeue/reject:
#
#   1. Happy path            -> ack
#   2. ping.test             -> ack, no processing
#   3. Feature flag disabled -> ack, no processing (drop)
#   4. Idempotency dup        -> ack, no reprocess
#   5. Transient FetchTimeout -> retry in-process, then ack on success
#   6. Transient exhausted    -> requeue (broker retry), NOT DLQ
#   7. Hard StandardError     -> reject (DLQ), no retry
#   8. not_found Result       -> ack (domain deleted between enqueue/process)
#   9. Queue-config drift     -> QueueDeclarator.validate_worker! passes
#
# Setup Requirements:
#   - Redis test instance (idempotency claim via Familia.dbclient)
#   - Stubbed Onetime::Operations::FetchDomainFavicon
#   - Stubbed Sneakers ack!/reject!/requeue! (via test subclass)

require 'spec_helper'
require 'support/amqp_stubs'
require 'sneakers'
require 'onetime/jobs/workers/favicon_fetch_worker'
require 'onetime/jobs/queues/config'
require 'onetime/jobs/queues/declarator'

RSpec.describe Onetime::Jobs::Workers::FaviconFetchWorker, type: :integration do
  # Test subclass captures the broker action without a real AMQP handler.
  let(:test_worker_class) do
    Class.new(described_class) do
      attr_accessor :delivery_info

      def self.name
        'TestFaviconFetchWorker'
      end

      def initialize
        super
        @acked    = false
        @rejected = false
        @requeued = false
      end

      def ack!
        @acked = true
        :ack
      end

      def reject!
        @rejected = true
        :reject
      end

      def requeue!
        @requeued = true
        :requeue
      end

      def acked?
        @acked
      end

      def rejected?
        @rejected
      end

      def requeued?
        @requeued
      end
    end
  end

  let(:worker) { test_worker_class.new }
  let(:message_id) { 'favicon-msg-123' }
  let(:domain_id) { 'domain-abc123' }

  let(:delivery_info) do
    DeliveryInfoStub.new(
      delivery_tag: 1,
      routing_key: 'domain.favicon.fetch',
      redelivered?: false,
    )
  end

  let(:metadata) do
    MetadataStub.new(
      message_id: message_id,
      headers: { 'x-schema-version' => 1 },
    )
  end

  let(:message) do
    JSON.generate(domain_id: domain_id, requested_at: '2026-07-13T00:00:00Z')
  end

  # Real Result objects exercise the actual Data.define shape the worker reads.
  let(:success_result) do
    Onetime::Operations::FetchDomainFavicon::Result.new(
      domain_id: domain_id,
      status: 'completed',
      favicon_fetched: true,
      favicon_source: 'auto_fetch',
      content_type: 'image/png',
      final_url: "https://#{domain_id}/favicon.ico",
      skipped: false,
      not_found: false,
      error: nil,
    )
  end

  let(:not_found_result) do
    Onetime::Operations::FetchDomainFavicon::Result.new(
      domain_id: domain_id,
      status: nil,
      favicon_fetched: nil,
      favicon_source: nil,
      content_type: nil,
      final_url: nil,
      skipped: false,
      not_found: true,
      error: nil,
    )
  end

  let(:operation) { instance_double(Onetime::Operations::FetchDomainFavicon) }

  before do
    worker.store_envelope(delivery_info, metadata)

    # Feature flag ON for the processing paths (default is OFF in test config).
    allow(worker).to receive(:favicon_fetch_enabled?).and_return(true)

    # Stub the operation — the worker under test is only the wrapper.
    allow(Onetime::Operations::FetchDomainFavicon).to receive(:new).and_return(operation)
    allow(operation).to receive(:call).and_return(success_result)

    # Collapse in-process retry backoff (RetryHelper.with_retry calls sleep).
    allow(Onetime::Utils::RetryHelper).to receive(:sleep)

    # Idempotency key hygiene between examples.
    Familia.dbclient.del("job:processed:#{message_id}")
  end

  after do
    Familia.dbclient.del("job:processed:#{message_id}")
  end

  describe '#work_with_params' do
    context 'happy path' do
      it 'delegates to the operation and acks' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(Onetime::Operations::FetchDomainFavicon)
          .to have_received(:new).with(domain_id: domain_id, force: false)
        expect(operation).to have_received(:call)
        expect(worker.acked?).to be true
      end

      it 'marks the message as processed (idempotency claim)' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(Familia.dbclient.exists?("job:processed:#{message_id}")).to be_truthy
      end

      it 'passes force: true when the payload requests it (Phase 2 refresh)' do
        forced = JSON.generate(domain_id: domain_id, force: true)

        worker.work_with_params(forced, delivery_info, metadata)

        expect(Onetime::Operations::FetchDomainFavicon)
          .to have_received(:new).with(domain_id: domain_id, force: true)
        expect(worker.acked?).to be true
      end
    end

    context 'ping test' do
      let(:message) { JSON.generate(domain_id: 'ping.test') }

      it 'acks without processing' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
        expect(Onetime::Operations::FetchDomainFavicon).not_to have_received(:new)
      end
    end

    context 'feature flag disabled' do
      before do
        allow(worker).to receive(:favicon_fetch_enabled?).and_return(false)
      end

      it 'drops the message with ack (no reject, no processing)' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
        expect(worker.rejected?).to be false
        expect(Onetime::Operations::FetchDomainFavicon).not_to have_received(:new)
      end

      it 'does not claim an idempotency key' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(Familia.dbclient.exists?("job:processed:#{message_id}")).to be_falsey
      end
    end

    context 'idempotency' do
      it 'acks and does not reprocess a duplicate message' do
        # Pre-claim the message as another worker would have.
        Familia.dbclient.setex("job:processed:#{message_id}", 3600, '1')

        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
        expect(Onetime::Operations::FetchDomainFavicon).not_to have_received(:new)
      end
    end

    context 'transient timeout' do
      it 'retries in-process then acks on success' do
        calls = 0
        allow(operation).to receive(:call) do
          calls += 1
          raise Onetime::Net::SafeFetch::FetchTimeout, 'slow endpoint' if calls < 3

          success_result
        end

        worker.work_with_params(message, delivery_info, metadata)

        expect(calls).to eq(3) # initial + 2 retries (max_retries: 2)
        expect(worker.acked?).to be true
        expect(worker.requeued?).to be false
      end

      it 'requeues (not DLQ) after exhausting in-process retries' do
        calls = 0
        allow(operation).to receive(:call) do
          calls += 1
          raise Onetime::Net::SafeFetch::FetchTimeout, 'always slow'
        end

        worker.work_with_params(message, delivery_info, metadata)

        expect(calls).to eq(3) # initial + 2 retries, then re-raised
        expect(worker.requeued?).to be true
        expect(worker.rejected?).to be false
        expect(worker.acked?).to be false
      end
    end

    context 'unexpected error' do
      it 'rejects to the DLQ without retrying' do
        allow(operation).to receive(:call).and_raise(StandardError, 'boom')

        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.rejected?).to be true
        expect(worker.requeued?).to be false
        # Non-transient errors are not retriable — operation called exactly once.
        expect(operation).to have_received(:call).once
      end
    end

    context 'domain missing (deleted between enqueue and processing)' do
      it 'acks a not_found Result and does not DLQ' do
        allow(operation).to receive(:call).and_return(not_found_result)

        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
        expect(worker.rejected?).to be false
        expect(worker.requeued?).to be false
      end
    end
  end

  describe 'queue configuration' do
    it 'declares QUEUE_NAME matching from_queue' do
      expect(described_class::QUEUE_NAME).to eq('domain.favicon.fetch')
      expect(described_class.queue_name).to eq('domain.favicon.fetch')
    end

    it 'resolves sneakers_options_for without UnknownQueueError' do
      expect { Onetime::Jobs::QueueDeclarator.sneakers_options_for('domain.favicon.fetch') }
        .not_to raise_error

      opts = Onetime::Jobs::QueueDeclarator.sneakers_options_for('domain.favicon.fetch')
      expect(opts[:ack]).to be true
      expect(opts.dig(:queue_options, :arguments)).to include('x-dead-letter-exchange' => 'dlx.domain.favicon')
    end

    it 'passes the QueueDeclarator drift check (--check contract)' do
      expect(Onetime::Jobs::QueueDeclarator.validate_worker!(described_class)).to be true
    end

    it 'includes Sneakers::Worker and BaseWorker' do
      expect(described_class.ancestors).to include(Sneakers::Worker)
      expect(described_class.ancestors)
        .to include(Onetime::Jobs::Workers::BaseWorker::InstanceMethods)
    end
  end
end
