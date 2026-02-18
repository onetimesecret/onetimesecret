# spec/integration/all/jobs/rabbitmq_publishing_spec.rb
#
# frozen_string_literal: true

# RabbitMQ Publishing Integration Tests
#
# These tests verify end-to-end message publishing and consumption with real
# RabbitMQ. They validate:
#
# 1. Messages are actually delivered to queues (not just "no error")
# 2. Message format and headers are correct
# 3. Message persistence and durability
# 4. Error handling for connection failures
# 5. Graceful degradation when RabbitMQ is unavailable
#
# Requirements:
# - RabbitMQ running on amqp://localhost (or RABBITMQ_URL env var)
# - Tests are skipped when RabbitMQ is unavailable (CI-friendly)
#
# Run with: pnpm run test:rspec spec/integration/all/jobs/rabbitmq_publishing_spec.rb

require 'spec_helper'
require 'bunny'
require 'json'
require 'timeout'
require 'onetime/jobs/publisher'
require 'onetime/jobs/queues/config'

RSpec.describe 'RabbitMQ Publishing', :rabbitmq, type: :integration do
  # Connection URL from environment or default
  let(:rabbitmq_url) { ENV.fetch('RABBITMQ_URL', 'amqp://localhost') }

  # Shared connection for tests (lazy-initialized)
  let(:connection) do
    conn = Bunny.new(rabbitmq_url, connection_timeout: 5, read_timeout: 5)
    conn.start
    conn
  end

  let(:channel) { connection.create_channel }

  # Test queue name - isolated per test run to avoid conflicts
  let(:test_queue_name) { "test.integration.#{SecureRandom.hex(4)}" }

  # Check if RabbitMQ is available before running tests
  def rabbitmq_available?
    test_conn = Bunny.new(rabbitmq_url, connection_timeout: 3)
    test_conn.start
    test_conn.close
    true
  rescue Bunny::TCPConnectionFailed, Bunny::ConnectionClosedError, Bunny::NetworkFailure
    false
  end

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

    # Set up test channel pool for Publisher
    @original_pool = $rmq_channel_pool

    # Create a real connection pool for tests
    test_conn = Bunny.new(rabbitmq_url, connection_timeout: 5)
    test_conn.start

    $rmq_channel_pool = ConnectionPool.new(size: 2, timeout: 5) do
      test_conn.create_channel
    end

    @test_conn = test_conn
  end

  after(:each) do
    # Clean up test queues
    if @rabbitmq_available && defined?(channel)
      begin
        channel.queue_delete(test_queue_name)
      rescue StandardError
        nil
      end
    end

    # Restore original pool
    $rmq_channel_pool = @original_pool

    # Close test connection
    @test_conn&.close rescue nil

    # Close shared connection
    connection.close rescue nil if @rabbitmq_available && defined?(connection)
  end

  describe 'basic publishing' do
    it 'delivers message to queue and can be consumed' do
      # Declare queue before publishing
      queue = channel.queue(test_queue_name, durable: false, auto_delete: true)

      # Publish via the Publisher class
      publisher = Onetime::Jobs::Publisher.new
      message_id = publisher.publish(test_queue_name, { test: 'data', timestamp: Time.now.to_i })

      # Consume and verify
      received_message = nil
      Timeout.timeout(5) do
        queue.subscribe(manual_ack: false, block: false) do |_delivery_info, _metadata, payload|
          received_message = JSON.parse(payload, symbolize_names: true)
        end
        sleep 0.1 until received_message
      end

      expect(received_message[:test]).to eq('data')
      expect(received_message[:timestamp]).to be_a(Integer)
      expect(message_id).to match(/^[0-9a-f-]{36}$/) # UUID format
    end

    it 'includes schema version header in published messages' do
      queue = channel.queue(test_queue_name, durable: false, auto_delete: true)

      publisher = Onetime::Jobs::Publisher.new
      publisher.publish(test_queue_name, { data: 'test' })

      received_headers = nil
      Timeout.timeout(5) do
        queue.subscribe(manual_ack: false, block: false) do |_delivery_info, metadata, _payload|
          received_headers = metadata[:headers]
        end
        sleep 0.1 until received_headers
      end

      expect(received_headers).to have_key('x-schema-version')
      expect(received_headers['x-schema-version']).to eq(Onetime::Jobs::QueueConfig::CURRENT_SCHEMA_VERSION)
    end

    it 'publishes persistent messages by default' do
      queue = channel.queue(test_queue_name, durable: true)

      publisher = Onetime::Jobs::Publisher.new
      publisher.publish(test_queue_name, { data: 'persistent' })

      received_delivery_mode = nil
      Timeout.timeout(5) do
        queue.subscribe(manual_ack: false, block: false) do |_delivery_info, metadata, _payload|
          received_delivery_mode = metadata[:delivery_mode]
        end
        sleep 0.1 until received_delivery_mode
      end

      # delivery_mode 2 = persistent
      expect(received_delivery_mode).to eq(2)
    end
  end

  describe 'email publishing' do
    let(:email_queue) { 'email.message.send' }

    before do
      # Clean up and redeclare the email queue with proper DLX config
      begin
        channel.queue_delete(email_queue)
      rescue Bunny::NotFound
        nil
      end

      # Declare DLX and DLQ first
      channel.fanout('dlx.email.message', durable: true)
      channel.queue('dlq.email.message', durable: true).bind('dlx.email.message')

      # Now declare main queue with DLX reference
      channel.queue(
        email_queue,
        durable: true,
        arguments: { 'x-dead-letter-exchange' => 'dlx.email.message' }
      )
    end

    after do
      begin
        channel.queue_delete(email_queue)
        channel.queue_delete('dlq.email.message')
        channel.exchange_delete('dlx.email.message')
      rescue StandardError
        nil
      end
    end

    it 'enqueues templated email with correct payload structure' do
      queue = channel.queue(email_queue, passive: true)

      Onetime::Jobs::Publisher.enqueue_email(
        :secret_link,
        { secret_key: 'abc123', recipient: 'test@example.com' }
      )

      received = nil
      Timeout.timeout(5) do
        queue.subscribe(manual_ack: false, block: false) do |_delivery_info, _metadata, payload|
          received = JSON.parse(payload, symbolize_names: true)
        end
        sleep 0.1 until received
      end

      expect(received[:template]).to eq('secret_link')
      expect(received[:data][:secret_key]).to eq('abc123')
      expect(received[:data][:recipient]).to eq('test@example.com')
    end

    it 'enqueues raw email with correct payload structure' do
      queue = channel.queue(email_queue, passive: true)

      raw_email = {
        to: 'user@example.com',
        from: 'noreply@example.com',
        subject: 'Test Subject',
        body: 'Test body content',
      }

      Onetime::Jobs::Publisher.enqueue_email_raw(raw_email)

      received = nil
      Timeout.timeout(5) do
        queue.subscribe(manual_ack: false, block: false) do |_delivery_info, _metadata, payload|
          received = JSON.parse(payload, symbolize_names: true)
        end
        sleep 0.1 until received
      end

      expect(received[:raw]).to be true
      expect(received[:email][:to]).to eq('user@example.com')
      expect(received[:email][:from]).to eq('noreply@example.com')
      expect(received[:email][:subject]).to eq('Test Subject')
    end
  end

  describe 'connection failure handling' do
    context 'when RabbitMQ connection is lost mid-publish' do
      before do
        # Create a pool that will fail
        @failing_pool = instance_double(ConnectionPool)
        allow(@failing_pool).to receive(:with).and_raise(Bunny::ConnectionClosedError.new(nil))
        $rmq_channel_pool = @failing_pool
      end

      it 'falls back to async_thread delivery by default' do
        delivered = Concurrent::AtomicBoolean.new(false)
        allow(Onetime::Mail).to receive(:deliver) { delivered.make_true }

        result = Onetime::Jobs::Publisher.enqueue_email(
          :test_template,
          { email: 'test@example.com' }
        )

        # Fallback returns false (not queued), but spawns thread
        expect(result).to be false

        # Wait for thread to complete with timeout
        Timeout.timeout(5) { sleep 0.05 until delivered.true? }

        expect(Onetime::Mail).to have_received(:deliver)
      end

      it 'respects fallback: :none by not delivering' do
        allow(Onetime::Mail).to receive(:deliver)

        result = Onetime::Jobs::Publisher.enqueue_email(
          :test_template,
          { email: 'test@example.com' },
          fallback: :none
        )

        expect(result).to be false
        expect(Onetime::Mail).not_to have_received(:deliver)
      end

      it 'respects fallback: :raise by raising DeliveryError' do
        expect {
          Onetime::Jobs::Publisher.enqueue_email(
            :test_template,
            { email: 'test@example.com' },
            fallback: :raise
          )
        }.to raise_error(Onetime::Mail::DeliveryError, /RabbitMQ unavailable/)
      end

      it 'respects fallback: :sync by delivering synchronously' do
        allow(Onetime::Mail).to receive(:deliver)

        result = Onetime::Jobs::Publisher.enqueue_email(
          :test_template,
          { email: 'test@example.com' },
          fallback: :sync
        )

        expect(result).to be false
        expect(Onetime::Mail).to have_received(:deliver).with(:test_template, { email: 'test@example.com' })
      end
    end
  end

  describe 'publishing without RabbitMQ pool' do
    before do
      $rmq_channel_pool = nil
    end

    it 'does not attempt RabbitMQ publish when pool is nil' do
      allow(Onetime::Mail).to receive(:deliver)

      result = Onetime::Jobs::Publisher.enqueue_email(
        :test_template,
        { email: 'test@example.com' },
        fallback: :sync
      )

      expect(result).to be false
      expect(Onetime::Mail).to have_received(:deliver)
    end

    it 'raises when publishing directly without pool' do
      publisher = Onetime::Jobs::Publisher.new

      expect {
        publisher.publish('some.queue', { data: 'test' })
      }.to raise_error(Onetime::Problem, /RabbitMQ channel pool not initialized/)
    end
  end

  describe 'message ordering and uniqueness' do
    it 'assigns unique message_id to each message' do
      queue = channel.queue(test_queue_name, durable: false, auto_delete: true)

      publisher = Onetime::Jobs::Publisher.new
      ids = []
      3.times do |i|
        ids << publisher.publish(test_queue_name, { index: i })
      end

      expect(ids.uniq.size).to eq(3)
      ids.each { |id| expect(id).to match(/^[0-9a-f-]{36}$/) }
    end

    it 'delivers messages in FIFO order' do
      queue = channel.queue(test_queue_name, durable: false, auto_delete: true)

      publisher = Onetime::Jobs::Publisher.new
      5.times { |i| publisher.publish(test_queue_name, { index: i }) }

      received = []
      Timeout.timeout(5) do
        queue.subscribe(manual_ack: false, block: false) do |_delivery_info, _metadata, payload|
          received << JSON.parse(payload, symbolize_names: true)[:index]
        end
        sleep 0.1 until received.size == 5
      end

      expect(received).to eq([0, 1, 2, 3, 4])
    end
  end

  describe 'queue declaration scenarios' do
    context 'when queue does not exist' do
      it 'message is lost (no queue binding)' do
        # RabbitMQ default exchange: messages to non-existent routing keys are dropped
        publisher = Onetime::Jobs::Publisher.new

        # This should not raise - message is simply dropped
        expect {
          publisher.publish('nonexistent.queue', { data: 'dropped' })
        }.not_to raise_error
      end
    end

    context 'when queue properties mismatch' do
      it 'worker queue config matches QueueConfig to prevent PRECONDITION_FAILED' do
        # This is a contract test - actual PRECONDITION_FAILED would require
        # declaring queue with different properties, which we avoid by
        # having workers use QueueConfig as source of truth
        Onetime::Jobs::QueueConfig::QUEUES.each do |queue_name, config|
          expect(config).to have_key(:durable)
          expect([true, false]).to include(config[:durable])
        end
      end
    end
  end
end
