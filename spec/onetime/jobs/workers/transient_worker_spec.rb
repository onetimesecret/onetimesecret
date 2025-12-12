# spec/onetime/jobs/workers/transient_worker_spec.rb
#
# frozen_string_literal: true

# TransientWorker Test Suite
#
# Tests the transient event worker that consumes messages from the
# system.transient queue for analytics and stats updates.
#
# Key Characteristics:
#   - Fire-and-forget: No retries, no DLQ, no idempotency
#   - Data loss acceptable: Always acknowledges, even on error
#   - Simple dispatch: Routes events to handlers by event_type
#
# Test Categories:
#   1. Event dispatch - routes to correct handler
#   2. Stats updates - increments/decrements Redis counters
#   3. Error handling - always acknowledges, never rejects
#   4. Malformed messages - handles gracefully
#
# Run with: pnpm run test:rspec spec/onetime/jobs/workers/transient_worker_spec.rb

require 'spec_helper'
require 'sneakers'
require_relative '../../../../lib/onetime/jobs/workers/transient_worker'
require_relative '../../../../lib/onetime/jobs/queue_config'

# Data classes for mocking AMQP envelope components
DeliveryInfoStub = Data.define(:delivery_tag, :routing_key, :redelivered?) unless defined?(DeliveryInfoStub)
MetadataStub = Data.define(:message_id, :headers) unless defined?(MetadataStub)

RSpec.describe Onetime::Jobs::Workers::TransientWorker do
  # Create test worker class with accessible ack/reject state
  let(:test_worker_class) do
    Class.new(Onetime::Jobs::Workers::TransientWorker) do
      attr_accessor :acked, :rejected

      def self.name
        'TestTransientWorker'
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

  # Mock Sneakers delivery_info
  let(:delivery_info) do
    DeliveryInfoStub.new(
      delivery_tag: 1,
      routing_key: 'system.transient',
      redelivered?: false
    )
  end

  # Mock Sneakers metadata
  let(:metadata) do
    MetadataStub.new(
      message_id: nil, # Transient events don't need message_id
      headers: { 'x-schema-version' => 1 }
    )
  end

  before do
    worker.store_envelope(delivery_info, metadata)

    # Clean up stats keys before each test
    Familia.dbclient.del('stats:domains:verified_count')
    Familia.dbclient.del('stats:domains:verification_failures')
    Familia.dbclient.del('stats:domains:total_count')
  end

  describe 'queue configuration' do
    it 'consumes from system.transient queue' do
      expect(described_class::QUEUE_NAME).to eq('system.transient')
    end

    it 'uses non-durable queue configuration' do
      expect(described_class::QUEUE_OPTS[:durable]).to be false
    end
  end

  describe '#work_with_params' do
    context 'domain.verified event' do
      let(:message) do
        JSON.generate(
          event_type: 'domain.verified',
          data: { domain: 'example.com', organization_id: 'org123' },
          timestamp: Time.now.utc.iso8601
        )
      end

      it 'increments domains:verified_count stat' do
        worker.work_with_params(message, delivery_info, metadata)

        count = Familia.dbclient.get('stats:domains:verified_count').to_i
        expect(count).to eq(1)
      end

      it 'acknowledges the message' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
      end

      it 'never rejects messages' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.rejected?).to be false
      end
    end

    context 'domain.verification_failed event' do
      let(:message) do
        JSON.generate(
          event_type: 'domain.verification_failed',
          data: { domain: 'example.com', reason: 'TXT record not found' },
          timestamp: Time.now.utc.iso8601
        )
      end

      it 'increments domains:verification_failures stat' do
        worker.work_with_params(message, delivery_info, metadata)

        count = Familia.dbclient.get('stats:domains:verification_failures').to_i
        expect(count).to eq(1)
      end

      it 'acknowledges the message' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
      end
    end

    context 'domain.added event' do
      let(:message) do
        JSON.generate(
          event_type: 'domain.added',
          data: { domain: 'newdomain.com', organization_id: 'org456' },
          timestamp: Time.now.utc.iso8601
        )
      end

      it 'increments domains:total_count stat' do
        worker.work_with_params(message, delivery_info, metadata)

        count = Familia.dbclient.get('stats:domains:total_count').to_i
        expect(count).to eq(1)
      end

      it 'acknowledges the message' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
      end
    end

    context 'domain.removed event' do
      let(:message) do
        JSON.generate(
          event_type: 'domain.removed',
          data: { domain: 'olddomain.com', organization_id: 'org789' },
          timestamp: Time.now.utc.iso8601
        )
      end

      before do
        # Set initial count so we can verify decrement
        Familia.dbclient.set('stats:domains:total_count', 5)
      end

      it 'decrements domains:total_count stat' do
        worker.work_with_params(message, delivery_info, metadata)

        count = Familia.dbclient.get('stats:domains:total_count').to_i
        expect(count).to eq(4)
      end

      it 'acknowledges the message' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
      end
    end

    context 'unknown event type' do
      let(:message) do
        JSON.generate(
          event_type: 'unknown.event',
          data: { foo: 'bar' },
          timestamp: Time.now.utc.iso8601
        )
      end

      it 'acknowledges the message without error' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
        expect(worker.rejected?).to be false
      end

      it 'does not modify any stats' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(Familia.dbclient.get('stats:domains:verified_count')).to be_nil
        expect(Familia.dbclient.get('stats:domains:total_count')).to be_nil
      end
    end

    context 'malformed JSON message' do
      let(:message) { 'not valid json {{{' }

      it 'acknowledges without raising error' do
        expect {
          worker.work_with_params(message, delivery_info, metadata)
        }.not_to raise_error

        expect(worker.acked?).to be true
      end

      it 'never rejects malformed messages' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.rejected?).to be false
      end
    end

    context 'when Redis fails' do
      let(:message) do
        JSON.generate(
          event_type: 'domain.verified',
          data: { domain: 'example.com' },
          timestamp: Time.now.utc.iso8601
        )
      end

      before do
        allow(Familia.dbclient).to receive(:incr).and_raise(Redis::ConnectionError, 'Connection refused')
      end

      it 'acknowledges despite Redis error' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.acked?).to be true
      end

      it 'never rejects on Redis errors' do
        worker.work_with_params(message, delivery_info, metadata)

        expect(worker.rejected?).to be false
      end
    end

    context 'multiple events in sequence' do
      it 'correctly accumulates stats' do
        3.times do
          msg = JSON.generate(event_type: 'domain.verified', data: {}, timestamp: Time.now.utc.iso8601)
          worker.work_with_params(msg, delivery_info, metadata)
        end

        2.times do
          msg = JSON.generate(event_type: 'domain.added', data: {}, timestamp: Time.now.utc.iso8601)
          worker.work_with_params(msg, delivery_info, metadata)
        end

        expect(Familia.dbclient.get('stats:domains:verified_count').to_i).to eq(3)
        expect(Familia.dbclient.get('stats:domains:total_count').to_i).to eq(2)
      end
    end
  end

  # Clean up Redis keys after each test
  after do
    Familia.dbclient.del('stats:domains:verified_count')
    Familia.dbclient.del('stats:domains:verification_failures')
    Familia.dbclient.del('stats:domains:total_count')
  end
end
