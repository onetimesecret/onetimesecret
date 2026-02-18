# spec/integration/all/jobs/dlq_routing_spec.rb
#
# frozen_string_literal: true

# Dead Letter Queue Routing Integration Tests
#
# These tests verify that messages are properly routed to dead letter queues
# when rejected or expired. They validate:
#
# 1. Rejected messages are routed to the correct DLQ
# 2. x-death headers are preserved with rejection metadata
# 3. DLQ message payload matches original message
# 4. Each queue routes to its own DLQ (isolation)
#
# Requirements:
# - RabbitMQ running on amqp://localhost (or RABBITMQ_URL env var)
# - Tests are skipped when RabbitMQ is unavailable (CI-friendly)
#
# Run with: pnpm run test:rspec spec/integration/all/jobs/dlq_routing_spec.rb

require 'spec_helper'
require 'bunny'
require 'json'
require 'timeout'
require 'onetime/jobs/queues/config'

RSpec.describe 'DLQ Routing', :rabbitmq, type: :integration do
  let(:rabbitmq_url) { ENV.fetch('RABBITMQ_URL', 'amqp://localhost') }

  let(:connection) do
    conn = Bunny.new(rabbitmq_url, connection_timeout: 5, read_timeout: 5)
    conn.start
    conn
  end

  let(:channel) { connection.create_channel }

  # Test queue names - isolated per test run
  let(:test_suffix) { SecureRandom.hex(4) }
  let(:test_queue_name) { "test.dlq.main.#{test_suffix}" }
  let(:test_dlx_name) { "test.dlx.#{test_suffix}" }
  let(:test_dlq_name) { "test.dlq.#{test_suffix}" }

  before(:all) do
    @rabbitmq_available = begin
      test_conn = Bunny.new(ENV.fetch('RABBITMQ_URL', 'amqp://localhost'), connection_timeout: 3)
      test_conn.start
      test_conn.close
      true
    rescue StandardError
      false
    end
  end

  before(:each) do
    skip 'RabbitMQ not available' unless @rabbitmq_available
  end

  after(:each) do
    next unless @rabbitmq_available

    # Clean up test resources
    begin
      channel.queue_delete(test_queue_name)
    rescue StandardError
      nil
    end
    begin
      channel.queue_delete(test_dlq_name)
    rescue StandardError
      nil
    end
    begin
      channel.exchange_delete(test_dlx_name)
    rescue StandardError
      nil
    end
    connection.close rescue nil if defined?(connection)
  end

  describe 'message rejection routing' do
    before(:each) do
      # 1. Declare DLX (fanout exchange)
      channel.fanout(test_dlx_name, durable: true)

      # 2. Declare and bind DLQ
      channel.queue(test_dlq_name, durable: true).bind(test_dlx_name)

      # 3. Declare main queue with DLX configuration
      channel.queue(
        test_queue_name,
        durable: true,
        arguments: {
          'x-dead-letter-exchange' => test_dlx_name,
        }
      )
    end

    it 'routes rejected messages to DLQ' do
      # Publish a message to main queue
      original_payload = { test: 'dlq_routing', timestamp: Time.now.to_i }
      channel.default_exchange.publish(
        JSON.generate(original_payload),
        routing_key: test_queue_name,
        persistent: true,
        message_id: SecureRandom.uuid
      )

      # Consume and reject the message
      main_queue = channel.queue(test_queue_name, passive: true)
      delivery_info = nil

      Timeout.timeout(5) do
        main_queue.subscribe(manual_ack: true, block: false) do |di, _metadata, _payload|
          delivery_info = di
        end
        sleep 0.1 until delivery_info
      end

      # Reject without requeue - should route to DLQ
      channel.basic_reject(delivery_info.delivery_tag, false)

      # Verify message appears in DLQ
      dlq = channel.queue(test_dlq_name, passive: true)
      dlq_message = nil

      Timeout.timeout(5) do
        dlq.subscribe(manual_ack: false, block: false) do |_di, _metadata, payload|
          dlq_message = JSON.parse(payload, symbolize_names: true)
        end
        sleep 0.1 until dlq_message
      end

      expect(dlq_message[:test]).to eq('dlq_routing')
      expect(dlq_message[:timestamp]).to eq(original_payload[:timestamp])
    end

    it 'preserves x-death headers with rejection metadata' do
      # Publish a message
      channel.default_exchange.publish(
        JSON.generate({ data: 'test' }),
        routing_key: test_queue_name,
        persistent: true,
        message_id: SecureRandom.uuid
      )

      # Consume and reject
      main_queue = channel.queue(test_queue_name, passive: true)
      delivery_info = nil

      Timeout.timeout(5) do
        main_queue.subscribe(manual_ack: true, block: false) do |di, _metadata, _payload|
          delivery_info = di
        end
        sleep 0.1 until delivery_info
      end

      channel.basic_reject(delivery_info.delivery_tag, false)

      # Check DLQ message headers
      dlq = channel.queue(test_dlq_name, passive: true)
      received_headers = nil

      Timeout.timeout(5) do
        dlq.subscribe(manual_ack: false, block: false) do |_di, metadata, _payload|
          received_headers = metadata[:headers]
        end
        sleep 0.1 until received_headers
      end

      expect(received_headers).to have_key('x-death')
      expect(received_headers['x-death']).to be_an(Array)

      death_info = received_headers['x-death'].first
      expect(death_info['queue']).to eq(test_queue_name)
      expect(death_info['reason']).to eq('rejected')
      expect(death_info['exchange']).to eq('')
    end

    it 'preserves original message_id in DLQ' do
      original_message_id = SecureRandom.uuid

      channel.default_exchange.publish(
        JSON.generate({ data: 'test' }),
        routing_key: test_queue_name,
        persistent: true,
        message_id: original_message_id
      )

      # Consume and reject
      main_queue = channel.queue(test_queue_name, passive: true)
      delivery_info = nil

      Timeout.timeout(5) do
        main_queue.subscribe(manual_ack: true, block: false) do |di, _metadata, _payload|
          delivery_info = di
        end
        sleep 0.1 until delivery_info
      end

      channel.basic_reject(delivery_info.delivery_tag, false)

      # Verify message_id is preserved
      dlq = channel.queue(test_dlq_name, passive: true)
      received_message_id = nil

      Timeout.timeout(5) do
        dlq.subscribe(manual_ack: false, block: false) do |_di, metadata, _payload|
          received_message_id = metadata[:message_id]
        end
        sleep 0.1 until received_message_id
      end

      expect(received_message_id).to eq(original_message_id)
    end
  end

  describe 'production queue DLQ configuration' do
    # Verify production queue config has valid DLX references
    Onetime::Jobs::QueueConfig::QUEUES.each do |queue_name, config|
      next unless config.dig(:arguments, 'x-dead-letter-exchange')

      dlx_name = config.dig(:arguments, 'x-dead-letter-exchange')

      it "queue '#{queue_name}' references existing DLX '#{dlx_name}'" do
        expect(Onetime::Jobs::QueueConfig::DEAD_LETTER_CONFIG).to have_key(dlx_name)
      end

      it "DLX '#{dlx_name}' has associated DLQ configured" do
        dlq_config = Onetime::Jobs::QueueConfig::DEAD_LETTER_CONFIG[dlx_name]
        expect(dlq_config).to have_key(:queue)
        expect(dlq_config[:queue]).to start_with('dlq.')
      end
    end
  end

  describe 'multiple queue isolation' do
    let(:queue1_name) { "test.isolation.q1.#{test_suffix}" }
    let(:queue2_name) { "test.isolation.q2.#{test_suffix}" }
    let(:dlx1_name) { "test.dlx.q1.#{test_suffix}" }
    let(:dlx2_name) { "test.dlx.q2.#{test_suffix}" }
    let(:dlq1_name) { "test.dlq.q1.#{test_suffix}" }
    let(:dlq2_name) { "test.dlq.q2.#{test_suffix}" }

    before(:each) do
      # Setup two independent queue/DLX/DLQ sets
      [
        [dlx1_name, dlq1_name, queue1_name],
        [dlx2_name, dlq2_name, queue2_name],
      ].each do |dlx, dlq, queue|
        channel.fanout(dlx, durable: true)
        channel.queue(dlq, durable: true).bind(dlx)
        channel.queue(
          queue,
          durable: true,
          arguments: { 'x-dead-letter-exchange' => dlx }
        )
      end
    end

    after(:each) do
      [queue1_name, queue2_name, dlq1_name, dlq2_name].each do |q|
        channel.queue_delete(q) rescue nil
      end
      [dlx1_name, dlx2_name].each do |ex|
        channel.exchange_delete(ex) rescue nil
      end
    end

    it 'routes each queue\'s rejected messages to its own DLQ' do
      # Publish to both queues
      channel.default_exchange.publish(
        JSON.generate({ source: 'queue1' }),
        routing_key: queue1_name,
        message_id: SecureRandom.uuid
      )
      channel.default_exchange.publish(
        JSON.generate({ source: 'queue2' }),
        routing_key: queue2_name,
        message_id: SecureRandom.uuid
      )

      # Reject both messages
      [queue1_name, queue2_name].each do |qname|
        q = channel.queue(qname, passive: true)
        di = nil
        Timeout.timeout(5) do
          q.subscribe(manual_ack: true, block: false) { |d, _, _| di = d }
          sleep 0.1 until di
        end
        channel.basic_reject(di.delivery_tag, false)
      end

      # Verify isolation - each DLQ has the correct message
      dlq1 = channel.queue(dlq1_name, passive: true)
      dlq2 = channel.queue(dlq2_name, passive: true)

      dlq1_msg = nil
      dlq2_msg = nil

      Timeout.timeout(5) do
        dlq1.subscribe(manual_ack: false, block: false) do |_, _, payload|
          dlq1_msg = JSON.parse(payload, symbolize_names: true)
        end
        dlq2.subscribe(manual_ack: false, block: false) do |_, _, payload|
          dlq2_msg = JSON.parse(payload, symbolize_names: true)
        end
        sleep 0.1 until dlq1_msg && dlq2_msg
      end

      expect(dlq1_msg[:source]).to eq('queue1')
      expect(dlq2_msg[:source]).to eq('queue2')
    end
  end
end
