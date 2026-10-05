# spec/integration/all/jobs/workers/base_worker_spec.rb
#
# frozen_string_literal: true

# Purpose:
#   Verifies the shared worker functionality provided by BaseWorker module,
#   including message parsing, idempotency checks, retry logic and trace
#   continuation. The helpers take the message's Envelope as an argument;
#   the Envelope itself is covered in
#   spec/lib/onetime/jobs/workers/envelope_spec.rb.
#
# Test Categories:
#   - Idempotency (Integration - requires Redis):
#       * already_processed? returns true when key exists (read-only check)
#       * already_processed? returns false when key absent
#       * claim_for_processing atomically claims message with SET NX EX
#
#   - Message parsing (Unit):
#       * decode_message returns the parsed value from valid JSON
#       * decode_message returns nil for invalid JSON, JSON null and an
#         unknown schema version, and never settles the message
#
#   - Concurrency (Unit):
#       * two messages worked at once on one worker instance each see
#         their own envelope
#
#   - Retry logic (Unit):
#       * with_retry retries on failure then succeeds
#       * with_retry exhausts max retries then raises (caller handles reject!)
#
# Setup Requirements:
#   - Redis test instance: VALKEY_URL='valkey://127.0.0.1:2163/0'
#   - Mocked delivery_info and metadata structs (Kicks/Sneakers format)
#   - Mocked ack!/reject! methods on test worker instance
#
# Trust Rationale:
#   - Unit tests: Mock external dependencies, verify isolated logic
#   - Integration tests: Use real Redis to verify I/O and TTL behavior
#

require 'spec_helper'
require 'support/amqp_stubs'
require 'onetime/jobs/workers/base_worker'
require 'onetime/jobs/queues/config'
require 'sneakers'

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
      attr_accessor :properties

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

  let(:envelope) { Onetime::Jobs::Workers::Envelope.new(delivery_info, metadata) }

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

  describe '#release_processing_claim_safely' do
    let(:msg_id) { 'test-msg-release-789' }
    let(:redis_key) { "job:processed:#{msg_id}" }

    after { Familia.dbclient.del(redis_key) }

    it 'deletes the claim and returns true' do
      worker.claim_for_processing(msg_id)

      expect(worker.release_processing_claim_safely(msg_id)).to be true
      expect(Familia.dbclient.exists?(redis_key)).to be_falsey
    end

    it 'returns false when there is no claim or no message id' do
      expect(worker.release_processing_claim_safely(msg_id)).to be false
      expect(worker.release_processing_claim_safely(nil)).to be false
    end

    it 'logs and returns false instead of raising on a datastore error' do
      allow(worker).to receive(:release_processing_claim)
        .and_raise(Redis::CannotConnectError, 'datastore down')
      allow(worker).to receive(:log_error)

      expect(worker.release_processing_claim_safely(msg_id)).to be false
      expect(worker).to have_received(:log_error)
        .with(/claim not released: Redis::CannotConnectError/, message_id: msg_id)
    end
  end

  describe '#decode_message' do
    let(:mock_logger) { instance_double(SemanticLogger::Logger, debug: nil, error: nil) }

    context 'with valid JSON' do
      let(:message_json) { '{"email":"test@example.com","template":"welcome"}' }

      it 'returns parsed hash with symbolized keys' do
        result = worker.decode_message(message_json, envelope)

        expect(result).to eq({
          email: 'test@example.com',
          template: 'welcome'
        })
      end

      it 'does not settle the message' do
        worker.decode_message(message_json, envelope)

        expect(worker.acked?).to be false
        expect(worker.rejected?).to be false
      end
    end

    context 'with invalid JSON' do
      let(:invalid_message) { 'not valid json {broken' }

      it 'returns nil without settling the message' do
        expect(worker.decode_message(invalid_message, envelope)).to be_nil
        expect(worker.rejected?).to be false
      end

      it 'logs error message' do
        allow(worker).to receive(:logger).and_return(mock_logger)

        worker.decode_message(invalid_message, envelope)

        expect(mock_logger).to have_received(:error).with(/Invalid JSON/, hash_including(:worker))
      end
    end

    context 'with a JSON null body' do
      it 'returns nil and logs why' do
        allow(worker).to receive(:logger).and_return(mock_logger)

        expect(worker.decode_message('null', envelope)).to be_nil
        expect(mock_logger).to have_received(:error)
          .with('Message payload is null', hash_including(message_id: message_id_value))
      end
    end

    context 'with a JSON body that is not an object' do
      ['[1, 2]', '[]', '"x"', '5', 'false', 'true'].each do |body|
        it "returns nil for #{body} and logs why, without settling the message" do
          allow(worker).to receive(:logger).and_return(mock_logger)

          expect(worker.decode_message(body, envelope)).to be_nil
          expect(mock_logger).to have_received(:error)
            .with('Message payload is not a JSON object', hash_including(message_id: message_id_value))
          expect(worker.rejected?).to be false
        end
      end
    end

    context 'with an unknown schema version' do
      let(:metadata) do
        MetadataStub.new(message_id: message_id_value, headers: { 'x-schema-version' => 999 })
      end

      it 'returns nil for a body that parses, without settling the message' do
        expect(worker.decode_message('{"email":"test@example.com"}', envelope)).to be_nil
        expect(worker.rejected?).to be false
      end

      it 'logs the version and the message id' do
        allow(worker).to receive(:logger).and_return(mock_logger)

        worker.decode_message('{"email":"test@example.com"}', envelope)

        expect(mock_logger).to have_received(:error)
          .with('Unknown schema version: 999', hash_including(:worker, message_id: message_id_value))
      end
    end

    context 'with no schema version header' do
      let(:metadata) { MetadataStub.new(message_id: message_id_value, headers: {}) }

      it 'reads the message as version 1' do
        expect(worker.decode_message('{"email":"test@example.com"}', envelope)).to eq(email: 'test@example.com')
      end
    end

    context 'with an envelope built from nil delivery info and nil properties' do
      let(:envelope) { Onetime::Jobs::Workers::Envelope.new(nil, nil) }

      it 'parses the body and logs a nil message id' do
        allow(worker).to receive(:logger).and_return(mock_logger)

        expect(worker.decode_message('{"email":"test@example.com"}', envelope)).to eq(email: 'test@example.com')
        expect(mock_logger).to have_received(:debug)
          .with('Parsing message', hash_including(:worker, message_id: nil))
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
        # RetryHelper uses structured logging: message + keyword args
        expect(mock_logger).to receive(:error).with(
          'Max retries exceeded',
          hash_including(max: 1, context: 'EmailWorker', error_class: 'StandardError')
        )

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

    context 'with retriable: predicate' do
      it 'skips retries and re-raises when retriable returns false' do
        attempt = 0
        non_retriable = ->(_ex) { false }

        expect {
          worker.with_retry(max_retries: 3, base_delay: 0.01, retriable: non_retriable) do
            attempt += 1
            raise StandardError, 'Non-retriable failure'
          end
        }.to raise_error(StandardError, 'Non-retriable failure')

        # Should fail on first attempt without retrying
        expect(attempt).to eq(1)
      end

      it 'allows normal retry flow when retriable returns true' do
        attempt = 0
        always_retriable = ->(_ex) { true }

        result = worker.with_retry(max_retries: 3, base_delay: 0.01, retriable: always_retriable) do
          attempt += 1
          raise StandardError, 'Temporary' if attempt < 3
          'recovered'
        end

        expect(result).to eq('recovered')
        expect(attempt).to eq(3)
      end

      it 'retries all errors when retriable is nil (default behavior)' do
        attempt = 0

        result = worker.with_retry(max_retries: 3, base_delay: 0.01, retriable: nil) do
          attempt += 1
          raise StandardError, 'Retry me' if attempt < 2
          'ok'
        end

        expect(result).to eq('ok')
        expect(attempt).to eq(2)
      end

      it 'selectively retries based on error type' do
        # Simulates the EmailWorker pattern: retry transient, skip non-transient
        transient_error = Class.new(StandardError)
        fatal_error = Class.new(StandardError)

        selective = ->(ex) { ex.is_a?(transient_error) }
        attempt = 0

        # First: transient error gets retried, then fatal error skips retries
        expect {
          worker.with_retry(max_retries: 3, base_delay: 0.01, retriable: selective) do
            attempt += 1
            raise fatal_error, 'Permanent' if attempt >= 2
            raise transient_error, 'Temporary'
          end
        }.to raise_error(fatal_error, 'Permanent')

        # attempt 1: transient (retried), attempt 2: fatal (not retried)
        expect(attempt).to eq(2)
      end

      it 'logs non-retriable error before re-raising' do
        mock_logger = instance_double(SemanticLogger::Logger)
        allow(worker).to receive(:logger).and_return(mock_logger)
        # RetryHelper uses structured logging with context in the payload
        expect(mock_logger).to receive(:error).with(
          'Non-retriable error, skipping retries',
          hash_including(context: 'EmailWorker', error_class: 'StandardError', error_message: 'Stop immediately')
        )

        non_retriable = ->(_ex) { false }

        expect {
          worker.with_retry(max_retries: 3, base_delay: 0.01, retriable: non_retriable) do
            raise StandardError, 'Stop immediately'
          end
        }.to raise_error(StandardError)
      end
    end

    context 'jitter behavior' do
      it 'adds randomized jitter to backoff delays' do
        # Run multiple retries and verify delays have variance (not constant)
        delays = []
        attempt = 0

        # Sleep is called on RetryHelper module, not on the worker instance
        allow(Onetime::Utils::RetryHelper).to receive(:sleep) do |delay|
          delays << delay
        end

        expect {
          worker.with_retry(max_retries: 3, base_delay: 1.0) do
            attempt += 1
            raise StandardError, 'Keep retrying'
          end
        }.to raise_error(StandardError)

        expect(delays.length).to eq(3)

        # Base delays without jitter would be: 1.0, 2.0, 4.0
        # With up to 30% jitter: [1.0..1.3], [2.0..2.6], [4.0..5.2]
        expect(delays[0]).to be_between(1.0, 1.3)
        expect(delays[1]).to be_between(2.0, 2.6)
        expect(delays[2]).to be_between(4.0, 5.2)
      end
    end
  end

  describe '#worker_name' do
    it 'returns the last component of the class name' do
      expect(worker.worker_name).to eq('EmailWorker')
    end
  end

  describe 'messages worked concurrently on one worker instance' do
    # Kicks runs work_with_params on a thread pool against one worker
    # instance, so two messages are in flight on the same object. Each call
    # passes its own envelope down, so neither can read the other's.
    let(:concurrent_worker_class) do
      Class.new(test_worker_class) do
        attr_writer :both_received

        def work_with_params(msg, delivery_info, metadata)
          envelope = Onetime::Jobs::Workers::Envelope.new(delivery_info, metadata)
          # Hold until the other message is in flight on this instance too.
          @both_received.call

          data = decode_message(msg, envelope)
          [envelope.message_id, envelope.summary[:delivery_tag], envelope.redelivered?, data.nil?]
        end
      end
    end

    it 'gives each message its own message id, delivery info and schema check' do
      worker  = concurrent_worker_class.new
      logged  = Queue.new
      arrived = Queue.new
      release = Queue.new
      logger  = instance_double(SemanticLogger::Logger, error: nil)
      allow(logger).to receive(:debug) { |_text, payload| logged << payload[:message_id] }
      allow(worker).to receive(:logger).and_return(logger)
      worker.both_received = lambda do
        arrived << true
        release.pop
      end

      other_metadata = MetadataStub.new(message_id: 'msg-other-thread', headers: { 'x-schema-version' => 999 })
      other_info     = DeliveryInfoStub.new(delivery_tag: 2, routing_key: 'email.message.send', redelivered?: true)

      first  = Thread.new { worker.work_with_params('{"n":1}', delivery_info, metadata) }
      second = Thread.new { worker.work_with_params('{"n":2}', other_info, other_metadata) }
      2.times { arrived.pop }
      2.times { release << true }

      expect(first.value).to eq([message_id_value, 1, false, false])
      expect(second.value).to eq(['msg-other-thread', 2, true, true])
      expect(Array.new(2) { logged.pop }).to contain_exactly(message_id_value, 'msg-other-thread')
      expect(logger).to have_received(:error).once
        .with('Unknown schema version: 999', hash_including(message_id: 'msg-other-thread'))
    end

    it 'keeps no envelope on the worker' do
      worker.decode_message('{"n":1}', envelope)

      expect(worker.instance_variables).not_to include(:@delivery_info, :@metadata, :@envelope)
      expect(worker).not_to respond_to(:message_id)
    end
  end

  # ==========================================================================
  # Sentry Distributed Tracing Tests
  # ==========================================================================
  # These tests verify that workers correctly extract and continue Sentry
  # traces from incoming messages, enabling distributed tracing across
  # RabbitMQ message boundaries.
  # ==========================================================================

  describe '#with_trace_context' do
    # Stub Sentry if not defined
    before do
      unless defined?(Sentry)
        stub_const('Sentry', Module.new do
          def self.initialized?
            false
          end

          def self.get_current_scope
            nil
          end

          def self.with_scope
            yield nil if block_given?
          end

          def self.continue_trace(headers, name:, op:)
            nil
          end
        end)
      end
    end

    context 'when Sentry is not initialized' do
      before do
        allow(Sentry).to receive(:initialized?).and_return(false)
      end

      it 'yields to the block' do
        block_called = false

        worker.with_trace_context(envelope) do
          block_called = true
        end

        expect(block_called).to be true
      end

      it 'returns the result of the block' do
        result = worker.with_trace_context(envelope) do
          'worker result'
        end

        expect(result).to eq('worker result')
      end
    end

    context 'when Sentry is initialized' do
      let(:mock_transaction) { instance_double('Sentry::Transaction') }
      let(:mock_scope) { instance_double('Sentry::Scope') }

      let(:metadata) do
        MetadataStub.new(
          message_id: 'msg-trace-456',
          headers: {
            'x-schema-version' => 1,
            'sentry-trace' => '00-trace123-span456-01',
            'baggage' => 'sentry-environment=test'
          }
        )
      end

      before do
        allow(Sentry).to receive(:initialized?).and_return(true)
        allow(Sentry).to receive(:with_scope).and_yield(mock_scope)
        allow(Sentry).to receive(:continue_trace).and_return(mock_transaction)
        allow(mock_scope).to receive(:set_span)
        allow(mock_transaction).to receive(:set_status)
        allow(mock_transaction).to receive(:finish)
      end

      it 'calls Sentry.continue_trace with extracted headers' do
        expected_headers = {
          'sentry-trace' => '00-trace123-span456-01',
          'baggage' => 'sentry-environment=test'
        }

        expect(Sentry).to receive(:continue_trace).with(
          expected_headers,
          name: 'rabbitmq.EmailWorker',
          op: 'queue.process'
        ).and_return(mock_transaction)

        worker.with_trace_context(envelope) {}
      end

      it 'uses default transaction name based on worker name' do
        expect(Sentry).to receive(:continue_trace).with(
          anything,
          hash_including(name: 'rabbitmq.EmailWorker')
        ).and_return(mock_transaction)

        worker.with_trace_context(envelope) {}
      end

      it 'allows custom transaction name' do
        expect(Sentry).to receive(:continue_trace).with(
          anything,
          hash_including(name: 'custom.operation.name')
        ).and_return(mock_transaction)

        worker.with_trace_context(envelope, name: 'custom.operation.name') {}
      end

      it 'allows custom op parameter' do
        expect(Sentry).to receive(:continue_trace).with(
          anything,
          hash_including(op: 'custom.op')
        ).and_return(mock_transaction)

        worker.with_trace_context(envelope, op: 'custom.op') {}
      end

      it 'yields to the block' do
        block_called = false

        worker.with_trace_context(envelope) do
          block_called = true
        end

        expect(block_called).to be true
      end

      it 'returns the result of the block' do
        result = worker.with_trace_context(envelope) do
          'traced result'
        end

        expect(result).to eq('traced result')
      end
    end

    context 'when message has no trace headers (backwards compatibility)' do
      let(:mock_scope) { instance_double('Sentry::Scope') }

      before do
        # Default metadata has no trace headers
        allow(Sentry).to receive(:initialized?).and_return(true)
        allow(Sentry).to receive(:with_scope).and_yield(mock_scope)
        allow(Sentry).to receive(:continue_trace).and_return(nil)
      end

      it 'still yields to the block' do
        block_called = false

        worker.with_trace_context(envelope) do
          block_called = true
        end

        expect(block_called).to be true
      end

      it 'calls continue_trace with empty headers' do
        expect(Sentry).to receive(:continue_trace).with(
          {},
          name: 'rabbitmq.EmailWorker',
          op: 'queue.process'
        ).and_return(nil)

        worker.with_trace_context(envelope) {}
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
