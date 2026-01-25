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
require 'onetime/jobs/workers/billing_worker'
require 'onetime/jobs/queue_config'

RSpec.describe 'Sneakers Worker Harness', type: :integration do
  # All available workers (constant for use in describe blocks)
  ALL_WORKERS = [
    Onetime::Jobs::Workers::EmailWorker,
    Onetime::Jobs::Workers::NotificationWorker,
    Onetime::Jobs::Workers::BillingWorker,
  ].freeze

  # Required queues that must have workers
  REQUIRED_QUEUES = %w[
    email.message.send
    notifications.alert.push
    billing.event.process
  ].freeze

  # Let blocks for use within examples
  let(:all_workers) { ALL_WORKERS }
  let(:required_queues) { REQUIRED_QUEUES }

  describe 'worker class configuration' do
    all_workers_data = [
      { class_name: 'EmailWorker', queue: 'email.message.send' },
      { class_name: 'NotificationWorker', queue: 'notifications.alert.push' },
      { class_name: 'BillingWorker', queue: 'billing.event.process' },
    ]

    all_workers_data.each do |worker_data|
      context worker_data[:class_name] do
        let(:worker_class) do
          Onetime::Jobs::Workers.const_get(worker_data[:class_name])
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

        it 'responds to store_envelope' do
          expect(worker).to respond_to(:store_envelope)
        end

        it 'responds to parse_message' do
          expect(worker).to respond_to(:parse_message)
        end

        it 'responds to claim_for_processing' do
          expect(worker).to respond_to(:claim_for_processing)
        end

        it 'responds to already_processed?' do
          expect(worker).to respond_to(:already_processed?)
        end

        it 'responds to message_metadata' do
          expect(worker).to respond_to(:message_metadata)
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

    describe '#store_envelope' do
      it 'stores delivery_info and metadata accessors' do
        delivery_info = double('delivery_info', delivery_tag: 123)
        metadata = double('metadata', message_id: 'test-123', headers: {})

        worker.store_envelope(delivery_info, metadata)

        expect(worker.delivery_info).to eq(delivery_info)
        expect(worker.metadata).to eq(metadata)
      end
    end

    describe '#parse_message' do
      before do
        # Store minimal envelope for validate_schema
        metadata = double('metadata', headers: { 'x-schema-version' => 1 })
        worker.store_envelope(nil, metadata)
      end

      it 'parses valid JSON' do
        result = worker.parse_message('{"key": "value"}')
        expect(result).to eq({ key: 'value' })
      end

      it 'rejects invalid JSON' do
        result = worker.parse_message('not valid json')
        expect(result).to be_nil
        expect(worker.rejected).to be true
      end

      it 'rejects unknown schema versions' do
        metadata = double('metadata', headers: { 'x-schema-version' => 999 })
        worker.store_envelope(nil, metadata)

        result = worker.parse_message('{"key": "value"}')
        expect(result).to be_nil
        expect(worker.rejected).to be true
      end
    end

    describe '#message_metadata' do
      it 'returns structured metadata hash' do
        delivery_info = double(
          'delivery_info',
          delivery_tag: 42,
          routing_key: 'test.queue',
          redelivered?: false
        )
        metadata = double(
          'metadata',
          message_id: 'msg-abc',
          headers: { 'x-schema-version' => 1 }
        )

        worker.store_envelope(delivery_info, metadata)
        meta = worker.message_metadata

        expect(meta[:delivery_tag]).to eq(42)
        expect(meta[:routing_key]).to eq('test.queue')
        expect(meta[:redelivered]).to be false
        expect(meta[:message_id]).to eq('msg-abc')
        expect(meta[:schema_version]).to eq(1)
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
    it 'each worker instance has isolated state' do
      worker1 = Onetime::Jobs::Workers::EmailWorker.new
      worker2 = Onetime::Jobs::Workers::EmailWorker.new

      delivery_info1 = double('di1', delivery_tag: 1)
      delivery_info2 = double('di2', delivery_tag: 2)
      metadata = double('metadata', message_id: nil, headers: {})

      worker1.store_envelope(delivery_info1, metadata)
      worker2.store_envelope(delivery_info2, metadata)

      expect(worker1.delivery_info.delivery_tag).to eq(1)
      expect(worker2.delivery_info.delivery_tag).to eq(2)
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
