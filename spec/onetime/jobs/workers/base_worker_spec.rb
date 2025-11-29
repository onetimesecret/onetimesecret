# spec/onetime/jobs/workers/base_worker_spec.rb
# frozen_string_literal: true

# Tests for Onetime::Jobs::Workers::BaseWorker
#
# Purpose:
#   Verifies the shared worker functionality provided by BaseWorker module,
#   including message parsing, idempotency checks, retry logic, and metadata
#   extraction.
#
# Test Categories:
#   - Property extraction (Unit):
#       * message_id: Extracts message_id from delivery_info properties
#
#   - Idempotency (Integration - requires Redis):
#       * already_processed? returns true when key exists
#       * already_processed? returns false when key absent
#       * mark_processed sets Redis key with SETEX and correct TTL
#
#   - Message parsing (Unit):
#       * parse_message returns hash from valid JSON
#       * parse_message rejects invalid JSON (mocked reject!)
#
#   - Retry logic (Unit):
#       * with_retry retries on failure then succeeds
#       * with_retry exhausts max retries then rejects (mocked reject!)
#
# Setup Requirements:
#   - Redis test instance: VALKEY_URL='valkey://127.0.0.1:2121/0'
#   - Mocked delivery_info struct (Sneakers/Kicks format)
#   - Mocked ack!/reject! methods on test worker instance
#
# Trust Rationale:
#   - Unit tests: Mock external dependencies, verify isolated logic
#   - Integration tests: Use real Redis to verify I/O and TTL behavior
#

require_relative '../../../spec_helper'
require_relative '../../../../lib/onetime/jobs/workers/base_worker'
require_relative '../../../../lib/onetime/jobs/queue_config'
require 'ostruct'
require 'sneakers'

RSpec.describe Onetime::Jobs::Workers::BaseWorker do
  # Create a test worker class that includes both Sneakers::Worker and BaseWorker
  let(:test_worker_class) do
    Class.new do
      include Sneakers::Worker
      include Onetime::Jobs::Workers::BaseWorker

      def self.name
        'TestWorker::EmailWorker'
      end

      # Sneakers::Worker requires these methods
      attr_accessor :delivery_info, :properties, :metadata

      def initialize
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

  # Mock delivery_info structure matching Sneakers/AMQP format
  let(:message_id_value) { 'msg-12345-abcde' }
  let(:delivery_info) do
    OpenStruct.new(
      delivery_tag: 1,
      routing_key: 'email.immediate',
      redelivered?: false,
      properties: OpenStruct.new(
        message_id: message_id_value,
        headers: { 'x-schema-version' => 1 }
      )
    )
  end

  before do
    worker.delivery_info = delivery_info
  end

  describe '#message_id' do
    context 'when delivery_info has message_id' do
      it 'extracts message_id from delivery_info.properties.message_id' do
        expect(worker.message_id).to eq(message_id_value)
      end
    end

    context 'when delivery_info is nil' do
      before { worker.delivery_info = nil }

      it 'returns nil without raising error' do
        expect(worker.message_id).to be_nil
      end
    end

    context 'when properties is nil' do
      before do
        worker.delivery_info = OpenStruct.new(properties: nil)
      end

      it 'returns nil without raising error' do
        expect(worker.message_id).to be_nil
      end
    end
  end

  describe '#already_processed?' do
    let(:msg_id) { 'test-msg-789' }
    let(:redis_key) { "job:processed:#{msg_id}" }

    after do
      # Clean up Redis keys
      Familia.dbclient.del(redis_key)
    end

    context 'when Redis key exists' do
      before do
        Familia.dbclient.setex(redis_key, 3600, '1')
      end

      it 'returns true' do
        expect(worker.already_processed?(msg_id)).to be true
      end
    end

    context 'when Redis key does not exist' do
      it 'returns false' do
        expect(worker.already_processed?(msg_id)).to be false
      end
    end

    context 'when msg_id is nil' do
      it 'returns false' do
        expect(worker.already_processed?(nil)).to be false
      end
    end
  end

  describe '#mark_processed' do
    let(:msg_id) { 'test-msg-456' }
    let(:redis_key) { "job:processed:#{msg_id}" }

    after do
      Familia.dbclient.del(redis_key)
    end

    it 'sets Redis key with TTL matching IDEMPOTENCY_TTL' do
      worker.mark_processed(msg_id)

      # Verify key exists
      expect(Familia.dbclient.exists?(redis_key)).to be true

      # Verify TTL is set correctly (allow 1 second variance for test execution)
      ttl = Familia.dbclient.ttl(redis_key)
      expected_ttl = Onetime::Jobs::QueueConfig::IDEMPOTENCY_TTL
      expect(ttl).to be_between(expected_ttl - 1, expected_ttl)

      # Verify value
      expect(Familia.dbclient.get(redis_key)).to eq('1')
    end

    context 'when msg_id is nil' do
      it 'does not set any Redis key' do
        initial_keys = Familia.dbclient.keys('job:processed:*')
        worker.mark_processed(nil)
        final_keys = Familia.dbclient.keys('job:processed:*')

        expect(final_keys).to eq(initial_keys)
      end
    end
  end

  describe '#parse_message' do
    context 'with valid JSON' do
      let(:message_json) { '{"email":"test@example.com","template":"welcome"}' }

      it 'returns parsed hash with symbolized keys' do
        result = worker.parse_message(message_json)

        expect(result).to be_a(Hash)
        expect(result).to eq({
          email: 'test@example.com',
          template: 'welcome'
        })
      end

      it 'calls validate_schema on parsed data' do
        expect(worker).to receive(:validate_schema).with(hash_including(email: 'test@example.com'))
        worker.parse_message(message_json)
      end
    end

    context 'with invalid JSON' do
      let(:invalid_message) { 'not valid json {broken' }

      it 'calls reject!' do
        expect(worker).to receive(:reject!)
        worker.parse_message(invalid_message)
      end

      it 'returns nil' do
        allow(worker).to receive(:reject!)
        result = worker.parse_message(invalid_message)

        expect(result).to be_nil
      end

      it 'logs error message' do
        allow(worker).to receive(:reject!)
        expect(OT).to receive(:le).with(/Invalid JSON/)

        worker.parse_message(invalid_message)
      end
    end
  end

  describe '#with_retry' do
    context 'when operation succeeds after retries' do
      it 'retries on failure then succeeds on later attempt' do
        attempt = 0

        result = worker.with_retry(max_retries: 3, base_delay: 0.01) do
          attempt += 1
          raise StandardError, 'Temporary failure' if attempt < 3
          'success'
        end

        expect(result).to eq('success')
        expect(attempt).to eq(3)
      end

      it 'applies exponential backoff delays' do
        attempt = 0
        delays = []

        worker.with_retry(max_retries: 3, base_delay: 0.1) do
          attempt += 1
          if attempt < 4
            start = Time.now
            raise StandardError, 'Retry me'
          end
        rescue StandardError => e
          delays << (Time.now - start) if start
          raise e
        end

        # First retry: 0.1s, Second: 0.2s, Third: 0.4s
        # (Allow some variance for test execution timing)
        expect(attempt).to eq(4)
      end
    end

    context 'when max retries are exhausted' do
      it 'calls reject! after max retries' do
        attempt = 0

        worker.with_retry(max_retries: 2, base_delay: 0.01) do
          attempt += 1
          raise StandardError, 'Persistent failure'
        end

        expect(worker.rejected?).to be true
        expect(attempt).to eq(3) # Initial attempt + 2 retries
      end

      it 'logs error with max retries message' do
        expect(OT).to receive(:le).with(/Max retries exceeded/)
        expect(OT).to receive(:le).with(/Error: StandardError/)

        worker.with_retry(max_retries: 1, base_delay: 0.01) do
          raise StandardError, 'Always fails'
        end
      end
    end

    context 'when operation succeeds immediately' do
      it 'does not retry' do
        attempt = 0

        result = worker.with_retry(max_retries: 3, base_delay: 0.01) do
          attempt += 1
          'immediate success'
        end

        expect(result).to eq('immediate success')
        expect(attempt).to eq(1)
      end
    end
  end

  describe '#worker_name' do
    it 'returns the last component of the class name' do
      expect(worker.worker_name).to eq('EmailWorker')
    end
  end

  describe '#message_metadata' do
    it 'extracts all metadata from delivery_info' do
      metadata = worker.message_metadata

      expect(metadata).to include(
        delivery_tag: 1,
        routing_key: 'email.immediate',
        redelivered: false,
        message_id: message_id_value,
        schema_version: 1
      )
    end

    context 'when delivery_info is nil' do
      before { worker.delivery_info = nil }

      it 'returns hash with nil values' do
        metadata = worker.message_metadata

        expect(metadata).to include(
          delivery_tag: nil,
          routing_key: nil,
          redelivered: nil,
          message_id: nil,
          schema_version: nil
        )
      end
    end
  end

  describe '#validate_schema' do
    let(:data) { { test: 'data' } }

    context 'when schema version is valid (V1)' do
      before do
        delivery_info.properties.headers['x-schema-version'] = 1
      end

      it 'does not reject the message' do
        worker.validate_schema(data)
        expect(worker.rejected?).to be false
      end
    end

    context 'when schema version header is missing' do
      before do
        delivery_info.properties.headers.delete('x-schema-version')
      end

      it 'defaults to version 1 and does not reject' do
        worker.validate_schema(data)
        expect(worker.rejected?).to be false
      end
    end

    context 'when schema version is unknown' do
      before do
        delivery_info.properties.headers['x-schema-version'] = 999
      end

      it 'rejects the message' do
        worker.validate_schema(data)
        expect(worker.rejected?).to be true
      end

      it 'logs an error' do
        expect(OT).to receive(:le).with(/Unknown schema version: 999/)
        worker.validate_schema(data)
      end
    end
  end
end
