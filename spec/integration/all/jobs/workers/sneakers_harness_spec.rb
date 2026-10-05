# spec/integration/all/jobs/workers/sneakers_harness_spec.rb
#
# frozen_string_literal: true

# Sneakers Worker Harness Integration Tests
#
# These tests validate Sneakers worker configuration, lifecycle, and behavior
# without necessarily requiring a live RabbitMQ connection for all tests.
#
# Tests cover:
# 1. Worker class configuration (queue name, exchange, threads)
# 2. Worker instantiation and interface compliance
# 3. Thread pool sizing and acknowledgment modes
# 4. Worker registration and discovery
# 5. Graceful shutdown handling
#
# Run with: pnpm run test:rspec spec/integration/all/jobs/workers/sneakers_harness_spec.rb

require 'spec_helper'
require 'sneakers'
require 'onetime/jobs/workers/email_worker'
require 'onetime/jobs/workers/notification_worker'
require 'onetime/jobs/workers/dns_record_check_worker'
require 'onetime/jobs/workers/domain_validation_worker'
require 'onetime/jobs/workers/favicon_fetch_worker'
require 'onetime/jobs/workers/session_revocation_sweep_worker'
require 'onetime/jobs/workers/transient_worker'
require 'onetime/jobs/queues/config'

# Load billing worker only when billing is enabled
if Onetime.billing_config.enabled?
  require 'billing/workers/billing_worker'
end

RSpec.describe 'Sneakers Worker Harness', type: :integration do
  # All available workers (constant for use in describe blocks)
  # BillingWorker is conditionally included when billing is enabled
  ALL_WORKERS = [
    Onetime::Jobs::Workers::EmailWorker,
    Onetime::Jobs::Workers::NotificationWorker,
    (Billing::Workers::BillingWorker if Onetime.billing_config.enabled?),
  ].compact.freeze

  # Required queues that must have workers
  # billing.event.process is conditionally included when billing is enabled
  REQUIRED_QUEUES = [
    'email.message.send',
    'notifications.alert.push',
    (Onetime.billing_config.enabled? ? 'billing.event.process' : nil),
  ].compact.freeze

  # Let blocks for use within examples
  let(:all_workers) { ALL_WORKERS }
  let(:required_queues) { REQUIRED_QUEUES }

  describe 'worker class configuration' do
    all_workers_data = [
      { class_name: 'EmailWorker', queue: 'email.message.send', namespace: Onetime::Jobs::Workers },
      { class_name: 'NotificationWorker', queue: 'notifications.alert.push', namespace: Onetime::Jobs::Workers },
      (Onetime.billing_config.enabled? ? { class_name: 'BillingWorker', queue: 'billing.event.process', namespace: Billing::Workers } : nil),
    ].compact

    all_workers_data.each do |worker_data|
      context worker_data[:class_name] do
        let(:worker_class) do
          worker_data[:namespace].const_get(worker_data[:class_name])
        end

        it 'includes Sneakers::Worker module' do
          expect(worker_class.included_modules).to include(Sneakers::Worker)
        end

        it 'includes BaseWorker module' do
          expect(worker_class.included_modules).to include(
            Onetime::Jobs::Workers::BaseWorker::InstanceMethods
          )
        end

        it "is configured for queue '#{worker_data[:queue]}'" do
          queue_name = worker_class.queue_name
          expect(queue_name).to eq(worker_data[:queue])
        end

        it 'uses manual acknowledgment mode' do
          opts = worker_class.queue_opts
          expect(opts[:ack]).to be true
        end

        it 'has positive thread count configuration' do
          opts = worker_class.queue_opts
          expect(opts[:threads]).to be_a(Integer)
          expect(opts[:threads]).to be > 0
        end

        it 'has positive prefetch configuration' do
          opts = worker_class.queue_opts
          expect(opts[:prefetch]).to be_a(Integer)
          expect(opts[:prefetch]).to be > 0
        end

        it 'queue config matches QueueConfig::QUEUES to prevent PRECONDITION_FAILED' do
          queue_name = worker_class.queue_name
          expected_config = Onetime::Jobs::QueueConfig::QUEUES[queue_name]

          expect(expected_config).not_to be_nil, "Queue #{queue_name} not in QueueConfig::QUEUES"

          opts = worker_class.queue_opts
          # Sneakers stores queue options under :queue_options key (see QueueDeclarator.sneakers_options_for)
          queue_options = opts[:queue_options] || {}
          expect(queue_options[:durable]).to eq(expected_config[:durable])
        end
      end
    end
  end

  # Kicks settles a message from the value work_with_params returns; nil
  # leaves it unacknowledged, holding a prefetch slot. Every worker must
  # return :reject for a message it cannot decode.
  describe 'undecodable messages' do
    [
      *ALL_WORKERS,
      Onetime::Jobs::Workers::DnsRecordCheckWorker,
      Onetime::Jobs::Workers::DomainValidationWorker,
      Onetime::Jobs::Workers::FaviconFetchWorker,
      Onetime::Jobs::Workers::SessionRevocationSweepWorker,
      Onetime::Jobs::Workers::TransientWorker,
    ].each do |worker_class|
      context worker_class.name.split('::').last do
        let(:worker) { worker_class.new }

        it 'returns :reject for a message that is not JSON' do
          metadata = double('metadata', message_id: 'harness-not-json', headers: { 'x-schema-version' => 1 })

          expect(worker.work_with_params('not valid json', nil, metadata)).to eq(:reject)
        end

        it 'returns :reject for an unknown schema version' do
          metadata = double('metadata', message_id: 'harness-schema', headers: { 'x-schema-version' => 999 })

          expect(worker.work_with_params('{"key": "value"}', nil, metadata)).to eq(:reject)
        end

        ['[]', '"x"', '5', 'false'].each do |body|
          it "returns :reject for the JSON body #{body}, which is not an object" do
            metadata = double('metadata', message_id: 'harness-not-object', headers: { 'x-schema-version' => 1 })

            expect(worker.work_with_params(body, nil, metadata)).to eq(:reject)
          end
        end
      end
    end
  end

  describe 'worker instantiation' do
    ALL_WORKERS.each do |worker_class|
      context worker_class.name.split('::').last do
        let(:worker) { worker_class.new }

        it 'can be instantiated' do
          expect { worker_class.new }.not_to raise_error
        end

        it 'responds to work_with_params' do
          expect(worker).to respond_to(:work_with_params)
        end

        it 'responds to ack!' do
          expect(worker).to respond_to(:ack!)
        end

        it 'responds to reject!' do
          expect(worker).to respond_to(:reject!)
        end

        it 'takes the message envelope as an argument to decode_message' do
          expect(worker.method(:decode_message).arity).to eq(2)
        end

        it 'keeps no message envelope on the instance' do
          expect(worker).not_to respond_to(:delivery_info)
          expect(worker).not_to respond_to(:metadata)
          expect(worker).not_to respond_to(:message_id)
        end

        it 'responds to claim_for_processing' do
          expect(worker).to respond_to(:claim_for_processing)
        end

        it 'responds to already_processed?' do
          expect(worker).to respond_to(:already_processed?)
        end
      end
    end
  end

  describe 'worker registration' do
    it 'has a worker for each required queue' do
      worker_queues = all_workers.map(&:queue_name)

      required_queues.each do |queue|
        expect(worker_queues).to include(queue),
          "No worker registered for required queue: #{queue}"
      end
    end

    it 'all workers have distinct queue names (no duplicates)' do
      worker_queues = all_workers.map(&:queue_name)
      expect(worker_queues.uniq.size).to eq(worker_queues.size)
    end

    it 'all configured queues have DLX defined' do
      all_workers.each do |worker_class|
        queue_name = worker_class.queue_name
        queue_config = Onetime::Jobs::QueueConfig::QUEUES[queue_name]

        next unless queue_config&.dig(:arguments, 'x-dead-letter-exchange')

        dlx_name = queue_config.dig(:arguments, 'x-dead-letter-exchange')
        expect(Onetime::Jobs::QueueConfig::DEAD_LETTER_CONFIG).to have_key(dlx_name),
          "Queue #{queue_name} references undefined DLX: #{dlx_name}"
      end
    end
  end

  describe 'worker naming convention' do
    ALL_WORKERS.each do |worker_class|
      it "#{worker_class.name.split('::').last} follows naming pattern" do
        worker_name = worker_class.name.split('::').last
        expect(worker_name).to end_with('Worker')
      end
    end
  end

  describe 'BaseWorker behavior' do
    # Create a test worker class for isolated testing
    let(:test_worker_class) do
      Class.new do
        include Sneakers::Worker
        include Onetime::Jobs::Workers::BaseWorker

        from_queue 'test.harness.queue', ack: true, durable: false

        attr_accessor :acked, :rejected

        # Provide a name for the anonymous class
        def self.name
          'TestHarnessWorker'
        end

        def ack!
          @acked = true
        end

        def reject!
          @rejected = true
        end
      end
    end

    let(:worker) { test_worker_class.new }

    describe '#decode_message' do
      # A minimal envelope for the schema version check
      let(:envelope) do
        metadata = double('metadata', message_id: nil, headers: { 'x-schema-version' => 1 })
        Onetime::Jobs::Workers::Envelope.new(nil, metadata)
      end

      it 'parses valid JSON' do
        result = worker.decode_message('{"key": "value"}', envelope)
        expect(result).to eq({ key: 'value' })
      end

      it 'returns nil for invalid JSON and leaves settling to the caller' do
        result = worker.decode_message('not valid json', envelope)
        expect(result).to be_nil
        expect(worker.rejected).to be_nil
      end

      it 'returns nil for unknown schema versions' do
        metadata = double('metadata', message_id: nil, headers: { 'x-schema-version' => 999 })
        unknown  = Onetime::Jobs::Workers::Envelope.new(nil, metadata)

        result = worker.decode_message('{"key": "value"}', unknown)
        expect(result).to be_nil
        expect(worker.rejected).to be_nil
      end
    end

    describe '#with_retry' do
      it 'executes block on success' do
        executed = false
        worker.with_retry(max_retries: 3, base_delay: 0.01) do
          executed = true
        end
        expect(executed).to be true
      end

      it 'retries on failure up to max_retries' do
        attempts = 0
        expect {
          worker.with_retry(max_retries: 2, base_delay: 0.01) do
            attempts += 1
            raise StandardError, 'test error' if attempts < 3
          end
        }.not_to raise_error
        expect(attempts).to eq(3)
      end

      it 'raises after max_retries exceeded' do
        attempts = 0
        expect {
          worker.with_retry(max_retries: 2, base_delay: 0.01) do
            attempts += 1
            raise StandardError, 'persistent error'
          end
        }.to raise_error(StandardError, 'persistent error')
        expect(attempts).to eq(3) # 1 initial + 2 retries
      end
    end
  end

  describe 'thread safety considerations' do
    # Kicks runs work_with_params on a thread pool against one worker
    # instance. Both pings are held at their first log line until the other
    # is in flight, then each must report its own message id.
    it 'two messages worked at once on one worker instance each see their own message id' do
      worker  = Onetime::Jobs::Workers::TransientWorker.new
      arrived = Queue.new
      release = Queue.new
      pings   = Queue.new
      logger  = instance_double(SemanticLogger::Logger, error: nil)
      allow(logger).to receive(:debug) do |text, _payload|
        if text == 'Parsing message'
          arrived << true
          release.pop
        end
      end
      allow(logger).to receive(:info) { |_text, payload| pings << payload.slice(:ping_id, :message_id) }
      allow(worker).to receive(:logger).and_return(logger)

      threads = %w[a b].map do |name|
        Thread.new do
          worker.work_with_params(
            JSON.generate(action: 'ping', ping_id: "ping-#{name}"),
            double("delivery_info_#{name}", delivery_tag: 1, routing_key: 'system.transient', redelivered?: false),
            double("metadata_#{name}", message_id: "msg-#{name}", headers: { 'x-schema-version' => 1 }),
          )
        end
      end
      2.times { arrived.pop }
      2.times { release << true }

      expect(threads.map(&:value)).to eq([:ack, :ack])
      expect(Array.new(2) { pings.pop }).to contain_exactly(
        { ping_id: 'ping-a', message_id: 'msg-a' },
        { ping_id: 'ping-b', message_id: 'msg-b' },
      )
    end
  end

  describe 'QueueConfig consistency' do
    Onetime::Jobs::QueueConfig::QUEUES.each do |queue_name, config|
      context "queue '#{queue_name}'" do
        it 'has valid durable setting' do
          expect([true, false]).to include(config[:durable])
        end

        if config.dig(:arguments, 'x-dead-letter-exchange')
          dlx = config.dig(:arguments, 'x-dead-letter-exchange')

          it "DLX '#{dlx}' is defined in DEAD_LETTER_CONFIG" do
            expect(Onetime::Jobs::QueueConfig::DEAD_LETTER_CONFIG).to have_key(dlx)
          end
        end

        if config.dig(:arguments, 'x-message-ttl')
          it 'has positive TTL' do
            ttl = config.dig(:arguments, 'x-message-ttl')
            expect(ttl).to be > 0
          end
        end
      end
    end
  end
end
