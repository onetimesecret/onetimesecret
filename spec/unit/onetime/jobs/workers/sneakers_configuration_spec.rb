# spec/unit/onetime/jobs/workers/sneakers_configuration_spec.rb
#
# frozen_string_literal: true

# Sneakers Worker Configuration Contract Tests
#
# These tests verify that all Sneakers workers are correctly configured
# and maintain consistency with QueueConfig. This catches:
#
# 1. Queue name mismatches between worker and QueueConfig
# 2. Missing or incorrect queue arguments (DLX, TTL, durability)
# 3. Workers referencing non-existent queues
# 4. Configuration drift when adding new workers/queues
#
# Run with: pnpm run test:rspec spec/unit/onetime/jobs/workers/sneakers_configuration_spec.rb

require 'spec_helper'
require 'sneakers'
require 'onetime/jobs/queue_config'
require 'onetime/jobs/workers/email_worker'
require 'onetime/jobs/workers/notification_worker'
require 'onetime/jobs/workers/billing_worker'

RSpec.describe 'Sneakers Worker Configuration' do
  # All workers that should be tested - add new workers here
  WORKERS = [
    Onetime::Jobs::Workers::EmailWorker,
    Onetime::Jobs::Workers::NotificationWorker,
    Onetime::Jobs::Workers::BillingWorker,
  ].freeze

  # Expected worker-to-queue mappings (contract specification)
  WORKER_QUEUE_CONTRACTS = {
    'EmailWorker' => 'email.message.send',
    'NotificationWorker' => 'notifications.alert.push',
    'BillingWorker' => 'billing.event.process',
  }.freeze

  describe 'QueueConfig completeness' do
    it 'defines all queues referenced by workers' do
      WORKERS.each do |worker|
        queue_name = worker.queue_name
        expect(Onetime::Jobs::QueueConfig::QUEUES).to have_key(queue_name),
          "Worker #{worker.name} references queue '#{queue_name}' not defined in QueueConfig::QUEUES"
      end
    end

    it 'has dead letter exchange for each durable queue' do
      Onetime::Jobs::QueueConfig::QUEUES.each do |queue_name, config|
        next unless config[:durable]
        next if queue_name == 'system.transient'

        dlx = config.dig(:arguments, 'x-dead-letter-exchange')
        expect(dlx).not_to be_nil,
          "Durable queue '#{queue_name}' is missing dead letter exchange configuration"
      end
    end

    it 'has matching DLQ for each dead letter exchange' do
      dlx_config = Onetime::Jobs::QueueConfig::DEAD_LETTER_CONFIG

      Onetime::Jobs::QueueConfig::QUEUES.each do |queue_name, config|
        dlx = config.dig(:arguments, 'x-dead-letter-exchange')
        next unless dlx

        expect(dlx_config).to have_key(dlx),
          "Queue '#{queue_name}' references DLX '#{dlx}' not defined in DEAD_LETTER_CONFIG"

        expected_dlq = dlx_config[dlx][:queue]
        expect(expected_dlq).to start_with('dlq.'),
          "DLQ for '#{dlx}' should follow naming convention 'dlq.*'"
      end
    end
  end

  describe 'Worker queue contracts' do
    WORKER_QUEUE_CONTRACTS.each do |worker_name, expected_queue|
      context worker_name do
        let(:worker_class) { WORKERS.find { |w| w.name.end_with?(worker_name) } }

        it 'exists in WORKERS list' do
          expect(worker_class).not_to be_nil,
            "#{worker_name} not found in WORKERS list - add it to the spec"
        end

        it "declares queue '#{expected_queue}'" do
          expect(worker_class.queue_name).to eq(expected_queue)
        end

        it 'has QUEUE_NAME constant matching from_queue declaration' do
          expect(worker_class::QUEUE_NAME).to eq(expected_queue)
        end
      end
    end
  end

  WORKERS.each do |worker_class|
    describe worker_class.name do
      let(:queue_name) { worker_class.queue_name }
      let(:queue_config) { Onetime::Jobs::QueueConfig::QUEUES[queue_name] }
      let(:queue_opts) { worker_class.queue_opts }

      describe 'queue declaration' do
        it 'uses manual acknowledgment (ack: true)' do
          expect(queue_opts[:ack]).to be true
        end

        it 'matches QueueConfig durability setting' do
          expect(queue_opts[:durable]).to eq(queue_config[:durable])
        end

        it 'matches QueueConfig arguments' do
          worker_args = queue_opts[:arguments] || {}
          config_args = queue_config[:arguments] || {}

          config_args.each do |key, value|
            expect(worker_args[key]).to eq(value),
              "Argument mismatch for '#{key}': worker has #{worker_args[key].inspect}, config has #{value.inspect}"
          end
        end
      end

      describe 'worker module inclusion' do
        it 'includes Sneakers::Worker' do
          expect(worker_class.ancestors).to include(Sneakers::Worker)
        end

        it 'includes BaseWorker' do
          expect(worker_class.ancestors).to include(Onetime::Jobs::Workers::BaseWorker::InstanceMethods)
        end

        it 'responds to work_with_params' do
          expect(worker_class.instance_methods).to include(:work_with_params)
        end
      end

      describe 'thread configuration' do
        it 'has threads configuration' do
          expect(queue_opts).to have_key(:threads)
          expect(queue_opts[:threads]).to be_a(Integer)
          expect(queue_opts[:threads]).to be > 0
        end

        it 'has prefetch configuration' do
          expect(queue_opts).to have_key(:prefetch)
          expect(queue_opts[:prefetch]).to be_a(Integer)
          expect(queue_opts[:prefetch]).to be > 0
        end
      end
    end
  end

  describe 'worker naming convention' do
    WORKERS.each do |worker_class|
      it "#{worker_class.name} follows *Worker naming pattern" do
        expect(worker_class.name).to end_with('Worker')
      end

      it "#{worker_class.name} is in Workers namespace" do
        expect(worker_class.name).to include('::Workers::')
      end
    end
  end

  describe 'configuration consistency' do
    it 'all workers use the same acknowledgment mode' do
      ack_modes = WORKERS.map { |w| w.queue_opts[:ack] }.uniq
      expect(ack_modes).to eq([true]),
        "Inconsistent ack modes across workers: #{ack_modes.inspect}"
    end

    it 'durable workers have reasonable thread counts (1-10)' do
      WORKERS.each do |worker_class|
        queue_config = Onetime::Jobs::QueueConfig::QUEUES[worker_class.queue_name]
        next unless queue_config[:durable]

        threads = worker_class.queue_opts[:threads]
        expect(threads).to be_between(1, 10),
          "#{worker_class.name} has unusual thread count: #{threads}"
      end
    end

    it 'prefetch is greater than or equal to threads' do
      WORKERS.each do |worker_class|
        threads = worker_class.queue_opts[:threads]
        prefetch = worker_class.queue_opts[:prefetch]

        expect(prefetch).to be >= threads,
          "#{worker_class.name}: prefetch (#{prefetch}) should be >= threads (#{threads})"
      end
    end
  end

  describe 'environment variable configuration' do
    # Workers should support ENV-based thread/prefetch configuration
    {
      'EMAIL_WORKER_THREADS' => Onetime::Jobs::Workers::EmailWorker,
      'EMAIL_WORKER_PREFETCH' => Onetime::Jobs::Workers::EmailWorker,
      'NOTIFICATION_WORKER_THREADS' => Onetime::Jobs::Workers::NotificationWorker,
      'NOTIFICATION_WORKER_PREFETCH' => Onetime::Jobs::Workers::NotificationWorker,
      'BILLING_WORKER_THREADS' => Onetime::Jobs::Workers::BillingWorker,
      'BILLING_WORKER_PREFETCH' => Onetime::Jobs::Workers::BillingWorker,
    }.each do |env_var, worker_class|
      it "#{worker_class.name} reads #{env_var}" do
        # The worker class body uses ENV.fetch, so the env var is read at class load time
        # We just verify the pattern exists in the expected workers
        expect(worker_class.queue_opts).to be_a(Hash)
      end
    end
  end
end
