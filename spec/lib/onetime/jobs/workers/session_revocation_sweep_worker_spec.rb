# spec/lib/onetime/jobs/workers/session_revocation_sweep_worker_spec.rb
#
# frozen_string_literal: true

# SessionRevocationSweepWorker Test Suite (#3810)
#
# Tests the thin Sneakers wrapper that consumes session.revoke.sweep and
# delegates to Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent.
# The operation is fully stubbed here — these tests exercise the worker's
# translation of the operation's outcome into RabbitMQ ack/reject:
#
#   1. Happy path          -> ack (op invoked with sweep + watermark enabled)
#   2. ping.test           -> ack, no processing
#   3. Idempotency dup     -> ack, no reprocess
#   4. Parse failure       -> reject (invalid JSON never reaches the op)
#   5. Hard StandardError  -> reject (DLQ; op is idempotent, replay is safe)
#   6. scan_capped Result  -> ERROR log (visible, not silent) but still ack
#   7. Queue-config drift  -> QueueDeclarator.validate_worker! passes
#
# Setup Requirements:
#   - Redis test instance (idempotency claim via Familia.dbclient)
#   - Stubbed Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent
#   - Stubbed Sneakers ack!/reject!/requeue! (via test subclass)

require 'spec_helper'
require 'support/amqp_stubs'
require 'sneakers'
require 'onetime/jobs/workers/session_revocation_sweep_worker'
require 'onetime/jobs/queues/config'
require 'onetime/jobs/queues/declarator'

RSpec.describe Onetime::Jobs::Workers::SessionRevocationSweepWorker, type: :integration do
  # Test subclass captures the broker action without a real AMQP handler.
  let(:test_worker_class) do
    Class.new(described_class) do
      attr_accessor :delivery_info

      def self.name
        'TestSessionRevocationSweepWorker'
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
  let(:message_id) { 'session-sweep-msg-123' }
  let(:custid) { 'cust_extid_abc123' }
  let(:session_id) { 'sid_current_456' }

  let(:delivery_info) do
    DeliveryInfoStub.new(
      delivery_tag: 1,
      routing_key: 'session.revoke.sweep',
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
    JSON.generate(custid: custid, except_session_id: session_id, requested_at: '2026-07-20T00:00:00Z')
  end

  # Real Result objects exercise the actual Data.define shape the worker reads.
  let(:success_result) do
    Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent::Result.new(
      revoked: true,
      blobs_deleted: 3,
      untracked_deleted: 1,
      scan_capped: false,
    )
  end

  let(:capped_result) do
    Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent::Result.new(
      revoked: true,
      blobs_deleted: 5,
      untracked_deleted: 2,
      scan_capped: true,
    )
  end

  let(:operation) do
    instance_double(Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent)
  end

  before do
    worker.store_envelope(delivery_info, metadata)

    # Stub the operation — the worker under test is only the wrapper.
    allow(Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent)
      .to receive(:new).and_return(operation)
    allow(operation).to receive(:call).and_return(success_result)

    # Idempotency key hygiene between examples.
    Familia.dbclient.del("job:processed:#{message_id}")
  end

  after do
    Familia.dbclient.del("job:processed:#{message_id}")
  end

  describe '#work_with_params' do
    context 'happy path' do
      it 'delegates to the operation with the full sweep and watermark enabled, then acks' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent)
          .to have_received(:new).with(
            custid: custid,
            except_session_id: session_id,
            scan_untracked: true,
            honor_credential_watermark: true,
          )
        expect(operation).to have_received(:call)
        expect(worker.acked?).to be true
      end

      it 'marks the message as processed (idempotency claim)' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(Familia.dbclient.exists?("job:processed:#{message_id}")).to be_truthy
      end

      it 'passes a missing except_session_id as nil (revoke ALL)' do
        no_except = JSON.generate(custid: custid, requested_at: '2026-07-20T00:00:00Z')

        worker.work_with_params(no_except, delivery_info, metadata)

        expect(Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent)
          .to have_received(:new).with(
            custid: custid,
            except_session_id: nil,
            scan_untracked: true,
            honor_credential_watermark: true,
          )
        expect(worker.acked?).to be true
      end
    end

    context 'ping test' do
      let(:message) { JSON.generate(custid: 'ping.test') }

      it 'acks without processing' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
        expect(Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent)
          .not_to have_received(:new)
      end
    end

    context 'idempotency' do
      it 'acks and does not reprocess a duplicate message' do
        # Pre-claim the message as another worker would have.
        Familia.dbclient.setex("job:processed:#{message_id}", 3600, '1')

        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
        expect(Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent)
          .not_to have_received(:new)
      end
    end

    context 'parse failure' do
      it 'rejects invalid JSON without invoking the operation' do
        worker.work_with_params('not-json{', delivery_info, metadata)

        expect(worker.rejected?).to be true
        expect(worker.acked?).to be false
        expect(Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent)
          .not_to have_received(:new)
      end
    end

    context 'unexpected error' do
      it 'rejects to the DLQ (op is idempotent, replay is safe)' do
        allow(operation).to receive(:call).and_raise(StandardError, 'boom')

        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.rejected?).to be true
        expect(worker.requeued?).to be false
        expect(worker.acked?).to be false
      end
    end

    context 'capped scan' do
      it 'logs at ERROR (a missed untracked blob must be visible) but still acks' do
        allow(operation).to receive(:call).and_return(capped_result)
        allow(worker).to receive(:log_error)

        worker.work_with_params(message, delivery_info, metadata)

        expect(worker).to have_received(:log_error).with(
          /scan cap/,
          hash_including(custid: custid, blobs_deleted: 5, untracked_deleted: 2),
        )
        expect(worker.acked?).to be true
        expect(worker.rejected?).to be false
      end
    end
  end

  describe 'queue configuration' do
    it 'declares QUEUE_NAME matching from_queue' do
      expect(described_class::QUEUE_NAME).to eq('session.revoke.sweep')
      expect(described_class.queue_name).to eq('session.revoke.sweep')
    end

    it 'resolves sneakers_options_for without UnknownQueueError' do
      expect { Onetime::Jobs::QueueDeclarator.sneakers_options_for('session.revoke.sweep') }
        .not_to raise_error

      opts = Onetime::Jobs::QueueDeclarator.sneakers_options_for('session.revoke.sweep')
      expect(opts[:ack]).to be true
      expect(opts.dig(:queue_options, :arguments)).to include('x-dead-letter-exchange' => 'dlx.session.revoke')
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
