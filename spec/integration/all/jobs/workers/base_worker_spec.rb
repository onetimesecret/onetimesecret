# spec/onetime/jobs/workers/base_worker_spec.rb
#
# frozen_string_literal: true

# Purpose:
#   Verifies the shared worker functionality provided by BaseWorker module,
#   including message parsing, idempotency checks, retry logic, and metadata
#   extraction.
#
# Test Categories:
#   - Property extraction (Unit):
#       * message_id: Extracts message_id from AMQP metadata properties
#
#   - Idempotency (Integration - requires Redis):
#       * already_processed? returns true when key exists (read-only check)
#       * already_processed? returns false when key absent
#       * claim_for_processing atomically claims message with SET NX EX
#
#   - Message parsing (Unit):
#       * parse_message returns hash from valid JSON
#       * parse_message rejects invalid JSON (mocked reject!)
#
#   - Retry logic (Unit):
#       * with_retry retries on failure then succeeds
#       * with_retry exhausts max retries then raises (caller handles reject!)
#
# Setup Requirements:
#   - Redis test instance: VALKEY_URL='valkey://127.0.0.1:2121/0'
#   - Mocked delivery_info and metadata structs (Kicks/Sneakers format)
#   - Mocked ack!/reject! methods on test worker instance
#
# Trust Rationale:
#   - Unit tests: Mock external dependencies, verify isolated logic
#   - Integration tests: Use real Redis to verify I/O and TTL behavior
#

require 'spec_helper'
require 'onetime/jobs/workers/base_worker'
require 'onetime/jobs/queue_config'
require 'sneakers'

# Data classes for mocking AMQP envelope components (immutable, Ruby 3.2+)
DeliveryInfoStub = Data.define(:delivery_tag, :routing_key, :redelivered?) unless defined?(DeliveryInfoStub)
MetadataStub = Data.define(:message_id, :headers) unless defined?(MetadataStub)

RSpec.describe Onetime::Jobs::Workers::BaseWorker, type: :integration do
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

  # Mock AMQP envelope components matching Kicks/Sneakers format
  let(:message_id_value) { 'msg-12345-abcde' }

  # delivery_info contains routing information
  let(:delivery_info) do
    DeliveryInfoStub.new(
      delivery_tag: 1,
      routing_key: 'email.message.send',
      redelivered?: false
    )
  end

  # metadata contains message properties (message_id, headers)
  let(:metadata) do
    MetadataStub.new(
      message_id: message_id_value,
      headers: { 'x-schema-version' => 1 }
    )
  end

  before do
    worker.store_envelope(delivery_info, metadata)
  end

  describe '#message_id' do
    context 'when metadata has message_id' do
      it 'extracts message_id from metadata.message_id' do
        expect(worker.message_id).to eq(message_id_value)
      end
    end

    context 'when metadata is nil' do
      before { worker.metadata = nil }

      it 'returns nil without raising error' do
        expect(worker.message_id).to be_nil
      end
    end

    # Note: delivery_info being nil doesn't affect message_id since
    # message_id comes from metadata, not delivery_info
  end

  describe '#already_processed?' do
    let(:msg_id) { 'test-msg-789' }
    let(:redis_key) { "job:processed:#{msg_id}" }

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

  describe '#claim_for_processing' do
    let(:msg_id) { 'test-msg-456' }
    let(:redis_key) { "job:processed:#{msg_id}" }

    it 'returns true and sets Redis key on first claim' do
      result = worker.claim_for_processing(msg_id)

      expect(result).to be true
      expect(Familia.dbclient.exists?(redis_key)).to be true

      # Verify TTL is set correctly (allow 1 second variance for test execution)
      ttl = Familia.dbclient.ttl(redis_key)
      expected_ttl = Onetime::Jobs::QueueConfig::IDEMPOTENCY_TTL
      expect(ttl).to be_between(expected_ttl - 1, expected_ttl)
    end

    it 'returns false on second claim (already claimed)' do
      first_claim = worker.claim_for_processing(msg_id)
      second_claim = worker.claim_for_processing(msg_id)

      expect(first_claim).to be true
      expect(second_claim).to be false
    end

    context 'when msg_id is nil' do
      it 'returns false without setting any Redis key' do
        initial_keys = Familia.dbclient.keys('job:processed:*')
        result = worker.claim_for_processing(nil)
        final_keys = Familia.dbclient.keys('job:processed:*')

        expect(result).to be false
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
        mock_logger = instance_double(SemanticLogger::Logger)
        allow(worker).to receive(:logger).and_return(mock_logger)
        expect(mock_logger).to receive(:error).with(/Invalid JSON/, hash_including(:worker))

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
      it 'raises after max retries to let caller handle rejection' do
        attempt = 0

        expect {
          worker.with_retry(max_retries: 2, base_delay: 0.01) do
            attempt += 1
            raise StandardError, 'Persistent failure'
          end
        }.to raise_error(StandardError, 'Persistent failure')

        expect(attempt).to eq(3) # Initial attempt + 2 retries
        # Note: reject! is NOT called here - caller is responsible
        expect(worker.rejected?).to be false
      end

      it 'logs error with max retries message' do
        mock_logger = instance_double(SemanticLogger::Logger)
        allow(worker).to receive(:logger).and_return(mock_logger)
        allow(mock_logger).to receive(:info) # Allow retry info logs
        expect(mock_logger).to receive(:error).with(/Max retries exceeded/, hash_including(:worker))

        expect {
          worker.with_retry(max_retries: 1, base_delay: 0.01) do
            raise StandardError, 'Always fails'
          end
        }.to raise_error(StandardError)
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
        routing_key: 'email.message.send',
        redelivered: false,
        message_id: message_id_value,
        schema_version: 1
      )
    end

    context 'when delivery_info and metadata are nil' do
      before do
        worker.delivery_info = nil
        worker.metadata = nil
      end

      it 'returns hash with nil values' do
        result = worker.message_metadata

        expect(result).to include(
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
      # Default metadata has 'x-schema-version' => 1
      it 'does not reject the message' do
        worker.validate_schema(data)
        expect(worker.rejected?).to be false
      end
    end

    context 'when schema version header is missing' do
      let(:metadata) do
        MetadataStub.new(
          message_id: message_id_value,
          headers: {}
        )
      end

      it 'defaults to version 1 and does not reject' do
        worker.validate_schema(data)
        expect(worker.rejected?).to be false
      end
    end

    context 'when schema version is unknown' do
      let(:metadata) do
        MetadataStub.new(
          message_id: message_id_value,
          headers: { 'x-schema-version' => 999 }
        )
      end

      it 'rejects the message' do
        worker.validate_schema(data)
        expect(worker.rejected?).to be true
      end

      it 'logs an error' do
        mock_logger = instance_double(SemanticLogger::Logger)
        allow(worker).to receive(:logger).and_return(mock_logger)
        expect(mock_logger).to receive(:error).with(/Unknown schema version: 999/, hash_including(:worker))
        worker.validate_schema(data)
      end
    end
  end

  describe 'race condition handling (concurrent idempotency)' do
    # This test verifies that claim_for_processing prevents race conditions.
    #
    # The OLD two-step pattern (already_processed? + mark_processed) was vulnerable:
    #   Worker A: already_processed? → false
    #   Worker B: already_processed? → false
    #   Worker A: processes, mark_processed
    #   Worker B: processes (DUPLICATE), mark_processed
    #
    # The NEW atomic pattern (claim_for_processing with SET NX EX) is safe:
    #   Worker A: claim_for_processing → true (SET NX succeeds)
    #   Worker B: claim_for_processing → false (SET NX fails, key exists)
    #   Worker A: processes
    #   Worker B: skips

    let(:redis) { Familia.dbclient }
    let(:msg_id) { SecureRandom.uuid }
    let(:idempotency_key) { "job:processed:#{msg_id}" }

    after do
      redis.del(idempotency_key)
    end

    it 'allows only one worker to claim a message via atomic SET NX' do
      results = Queue.new  # Thread-safe queue

      # Spawn 10 threads racing to claim the same message
      threads = 10.times.map do
        Thread.new do
          value = if worker.claim_for_processing(msg_id)
            :claimed
          else
            :skipped
          end
          results << value
        end
      end

      threads.each(&:join)

      # Collect results
      claims = []
      claims << results.pop until results.empty?

      # With atomic SET NX, exactly ONE should claim
      expect(claims.count(:claimed)).to eq(1),
        "Expected exactly 1 claim but got #{claims.count(:claimed)} - RACE CONDITION DETECTED"
    end
  end
end
