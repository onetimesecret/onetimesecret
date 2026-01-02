# spec/unit/onetime/initializers/setup_rabbitmq_spec.rb
#
# frozen_string_literal: true

# SetupRabbitMQ Initializer Tests
#
# These tests verify the RabbitMQ initialization lifecycle:
# - Connection management (setup, cleanup, reconnect)
# - Error handling for various failure scenarios
# - Queue declaration consistency with QueueConfig
# - TLS configuration for secure connections
#
# Run with: pnpm run test:rspec spec/unit/onetime/initializers/setup_rabbitmq_spec.rb

require 'spec_helper'
require 'onetime/jobs/queue_config'

# rubocop:disable RSpec/SpecFilePathFormat
# File name matches implementation file setup_rabbitmq.rb
RSpec.describe Onetime::Initializers::SetupRabbitMQ do
  # These tests use mocks to avoid requiring RabbitMQ to be running

  let(:instance) { described_class.new }

  describe '#cleanup' do
    context 'when RabbitMQ connection exists and is open' do
      let(:mock_conn) { instance_double(Bunny::Session, open?: true, close: true) }
      let(:mock_pool) { instance_double(ConnectionPool) }

      before do
        $rmq_conn         = mock_conn
        $rmq_channel_pool = mock_pool
      end

      after do
        $rmq_conn         = nil
        $rmq_channel_pool = nil
      end

      it 'closes the connection' do
        allow(mock_conn).to receive(:close)
        instance.cleanup
        expect(mock_conn).to have_received(:close)
      end

      it 'sets $rmq_conn to nil' do
        instance.cleanup
        expect($rmq_conn).to be_nil
      end

      it 'sets $rmq_channel_pool to nil' do
        instance.cleanup
        expect($rmq_channel_pool).to be_nil
      end
    end

    context 'when RabbitMQ connection is already closed' do
      let(:mock_conn) { instance_double(Bunny::Session, open?: false) }
      let(:mock_pool) { instance_double(ConnectionPool) }

      before do
        $rmq_conn         = mock_conn
        $rmq_channel_pool = mock_pool
      end

      after do
        $rmq_conn         = nil
        $rmq_channel_pool = nil
      end

      it 'does not call close on the connection' do
        allow(mock_conn).to receive(:close)
        instance.cleanup
        expect(mock_conn).not_to have_received(:close)
      end

      it 'clears $rmq_conn' do
        instance.cleanup
        expect($rmq_conn).to be_nil
      end

      it 'clears $rmq_channel_pool' do
        instance.cleanup
        expect($rmq_channel_pool).to be_nil
      end
    end

    context 'when $rmq_conn is nil' do
      before do
        $rmq_conn         = nil
        $rmq_channel_pool = nil
      end

      it 'returns without error' do
        expect { instance.cleanup }.not_to raise_error
      end
    end

    context 'when close raises an error' do
      let(:mock_conn) do
        instance_double(Bunny::Session, open?: true).tap do |conn|
          allow(conn).to receive(:close).and_raise(StandardError.new('Connection error'))
        end
      end
      let(:mock_pool) { instance_double(ConnectionPool) }

      before do
        $rmq_conn         = mock_conn
        $rmq_channel_pool = mock_pool
      end

      after do
        $rmq_conn         = nil
        $rmq_channel_pool = nil
      end

      it 'logs warning but does not raise' do
        expect { instance.cleanup }.not_to raise_error
      end

      it 'clears $rmq_conn even on error' do
        instance.cleanup
        expect($rmq_conn).to be_nil
      end

      it 'clears $rmq_channel_pool even on error' do
        instance.cleanup
        expect($rmq_channel_pool).to be_nil
      end
    end
  end

  describe '#reconnect' do
    context 'when jobs are disabled' do
      before do
        allow(OT).to receive(:conf).and_return({ 'jobs' => { 'enabled' => false } })
      end

      it 'does not attempt to connect' do
        allow(instance).to receive(:setup_rabbitmq_connection)
        instance.reconnect
        expect(instance).not_to have_received(:setup_rabbitmq_connection)
      end
    end

    context 'when jobs are enabled' do
      before do
        allow(OT).to receive(:conf).and_return({ 'jobs' => { 'enabled' => true } })
        allow(instance).to receive(:setup_rabbitmq_connection)
      end

      it 'calls setup_rabbitmq_connection' do
        instance.reconnect
        expect(instance).to have_received(:setup_rabbitmq_connection)
      end
    end

    context 'when connection fails' do
      before do
        allow(OT).to receive(:conf).and_return({ 'jobs' => { 'enabled' => true } })
        allow(instance).to receive(:setup_rabbitmq_connection)
          .and_raise(Bunny::TCPConnectionFailed.new('Connection refused'))
      end

      it 'logs warning but does not raise' do
        expect { instance.reconnect }.not_to raise_error
      end
    end

    context 'when timeout occurs' do
      before do
        allow(OT).to receive(:conf).and_return({ 'jobs' => { 'enabled' => true } })
        allow(instance).to receive(:setup_rabbitmq_connection)
          .and_raise(Bunny::ConnectionTimeout.new('Timeout'))
      end

      it 'logs warning but does not raise' do
        expect { instance.reconnect }.not_to raise_error
      end
    end
  end

  # ==========================================================================
  # QueueConfig Parameterized Tests
  # ==========================================================================
  # These tests verify that all queues defined in QueueConfig have proper
  # configuration and can be declared without errors. This catches:
  # - Missing required fields (durable, arguments)
  # - Invalid dead letter exchange references
  # - Configuration drift when adding new queues
  # ==========================================================================

  describe 'QueueConfig validation' do
    describe 'all queues have required fields' do
      Onetime::Jobs::QueueConfig::QUEUES.each do |queue_name, config|
        context "queue '#{queue_name}'" do
          it 'has durable setting' do
            expect(config).to have_key(:durable),
              "Queue '#{queue_name}' missing :durable field"
          end

          it 'durable is boolean' do
            expect([true, false]).to include(config[:durable]),
              "Queue '#{queue_name}' :durable must be boolean, got #{config[:durable].class}"
          end

          it 'arguments is a hash when present' do
            if config.key?(:arguments)
              expect(config[:arguments]).to be_a(Hash),
                "Queue '#{queue_name}' :arguments must be Hash, got #{config[:arguments].class}"
            end
          end
        end
      end
    end

    describe 'dead letter exchange consistency' do
      Onetime::Jobs::QueueConfig::QUEUES.each do |queue_name, config|
        dlx = config.dig(:arguments, 'x-dead-letter-exchange')
        next unless dlx

        context "queue '#{queue_name}' with DLX '#{dlx}'" do
          it 'references a defined dead letter exchange' do
            expect(Onetime::Jobs::QueueConfig::DEAD_LETTER_CONFIG).to have_key(dlx),
              "Queue '#{queue_name}' references undefined DLX '#{dlx}'"
          end

          it 'has matching DLQ defined' do
            dlq_config = Onetime::Jobs::QueueConfig::DEAD_LETTER_CONFIG[dlx]
            expect(dlq_config).to have_key(:queue),
              "DLX '#{dlx}' missing :queue definition"
            expect(dlq_config[:queue]).to start_with('dlq.'),
              "DLQ for '#{dlx}' should follow 'dlq.*' naming convention"
          end
        end
      end
    end

    describe 'TTL configuration' do
      Onetime::Jobs::QueueConfig::QUEUES.each do |queue_name, config|
        ttl = config.dig(:arguments, 'x-message-ttl')
        next unless ttl

        context "queue '#{queue_name}' with TTL" do
          it 'TTL is a positive integer (milliseconds)' do
            expect(ttl).to be_a(Integer),
              "Queue '#{queue_name}' TTL must be Integer, got #{ttl.class}"
            expect(ttl).to be > 0,
              "Queue '#{queue_name}' TTL must be positive, got #{ttl}"
          end

          it 'TTL is within reasonable bounds (1 second to 7 days)' do
            min_ttl = 1_000          # 1 second
            max_ttl = 7 * 24 * 60 * 60 * 1_000  # 7 days

            expect(ttl).to be_between(min_ttl, max_ttl),
              "Queue '#{queue_name}' TTL #{ttl}ms outside reasonable bounds (1s-7d)"
          end
        end
      end
    end

    describe 'transient queue configuration' do
      let(:transient_queues) do
        Onetime::Jobs::QueueConfig::QUEUES.select { |_, config| !config[:durable] }
      end

      it 'transient queues have auto_delete or TTL' do
        transient_queues.each do |queue_name, config|
          has_auto_delete = config[:auto_delete] == true
          has_ttl = config.dig(:arguments, 'x-message-ttl').is_a?(Integer)

          expect(has_auto_delete || has_ttl).to be(true),
            "Transient queue '#{queue_name}' should have auto_delete or TTL to prevent orphans"
        end
      end

      it 'transient queues do not have dead letter exchange' do
        transient_queues.each do |queue_name, config|
          dlx = config.dig(:arguments, 'x-dead-letter-exchange')
          # Transient messages don't need DLQ - they're ephemeral by design
          # This is not a hard rule, but a sensible default
          expect(dlx).to be_nil,
            "Transient queue '#{queue_name}' has DLX '#{dlx}' - is this intentional?"
        end
      end
    end
  end

  describe 'TLS configuration' do
    describe '.tls_options' do
      context 'with amqp:// URL (non-TLS)' do
        it 'returns empty hash' do
          result = Onetime::Jobs::QueueConfig.tls_options('amqp://localhost')
          expect(result).to eq({})
        end
      end

      context 'with amqps:// URL (TLS)' do
        it 'returns tls: true' do
          result = Onetime::Jobs::QueueConfig.tls_options('amqps://localhost')
          expect(result[:tls]).to be true
        end

        it 'defaults to verify_peer: true' do
          result = Onetime::Jobs::QueueConfig.tls_options('amqps://localhost')
          expect(result[:verify_peer]).to be true
        end

        context 'with RABBITMQ_VERIFY_PEER=false' do
          around do |example|
            original = ENV['RABBITMQ_VERIFY_PEER']
            ENV['RABBITMQ_VERIFY_PEER'] = 'false'
            example.run
            ENV['RABBITMQ_VERIFY_PEER'] = original
          end

          it 'disables peer verification' do
            result = Onetime::Jobs::QueueConfig.tls_options('amqps://localhost')
            expect(result[:verify_peer]).to be false
          end
        end

        context 'with RABBITMQ_CA_CERTIFICATES set' do
          around do |example|
            original = ENV['RABBITMQ_CA_CERTIFICATES']
            ENV['RABBITMQ_CA_CERTIFICATES'] = '/path/to/ca.pem'
            example.run
            ENV['RABBITMQ_CA_CERTIFICATES'] = original
          end

          it 'includes custom CA certificate path' do
            result = Onetime::Jobs::QueueConfig.tls_options('amqps://localhost')
            expect(result[:tls_ca_certificates]).to eq(['/path/to/ca.pem'])
          end
        end
      end

      context 'with nil URL' do
        it 'returns empty hash' do
          result = Onetime::Jobs::QueueConfig.tls_options(nil)
          expect(result).to eq({})
        end
      end
    end
  end

  describe 'error scenarios' do
    # Note: reconnect only catches Bunny::TCPConnectionFailed and Bunny::ConnectionTimeout
    # Other errors propagate to allow debugging in production

    describe 'TCP connection failed' do
      before do
        allow(OT).to receive(:conf).and_return({ 'jobs' => { 'enabled' => true } })
        allow(instance).to receive(:setup_rabbitmq_connection)
          .and_raise(Bunny::TCPConnectionFailed.new('Connection refused'))
      end

      it 'handles TCP failure gracefully in reconnect' do
        expect { instance.reconnect }.not_to raise_error
      end
    end

    describe 'connection timeout' do
      before do
        allow(OT).to receive(:conf).and_return({ 'jobs' => { 'enabled' => true } })
        allow(instance).to receive(:setup_rabbitmq_connection)
          .and_raise(Bunny::ConnectionTimeout.new('Timeout'))
      end

      it 'handles timeout gracefully in reconnect' do
        expect { instance.reconnect }.not_to raise_error
      end
    end

    describe 'unexpected errors propagate' do
      # Unlike TCP/timeout errors, unexpected errors should propagate
      # so developers can debug issues during startup

      before do
        allow(OT).to receive(:conf).and_return({ 'jobs' => { 'enabled' => true } })
        allow(instance).to receive(:setup_rabbitmq_connection)
          .and_raise(StandardError.new('Unexpected error'))
      end

      it 'allows unexpected errors to propagate from reconnect' do
        expect { instance.reconnect }.to raise_error(StandardError, 'Unexpected error')
      end
    end
  end

  describe 'queue count consistency' do
    it 'QueueConfig has expected number of queues' do
      # Update this when adding/removing queues to catch accidental changes
      expect(Onetime::Jobs::QueueConfig::QUEUES.size).to eq(6),
        "Expected 6 queues in QueueConfig::QUEUES. If you added/removed queues, update this test."
    end

    it 'DEAD_LETTER_CONFIG covers all unique DLX references' do
      # Multiple queues can share the same DLX (e.g., email.message.send and email.message.schedule
      # both use dlx.email.message). Count unique DLX values, not queue count.
      unique_dlx_refs = Onetime::Jobs::QueueConfig::QUEUES.values
        .map { |config| config.dig(:arguments, 'x-dead-letter-exchange') }
        .compact
        .uniq

      dlx_count = Onetime::Jobs::QueueConfig::DEAD_LETTER_CONFIG.size

      expect(dlx_count).to eq(unique_dlx_refs.size),
        "DEAD_LETTER_CONFIG (#{dlx_count}) should match unique DLX references (#{unique_dlx_refs.size}): #{unique_dlx_refs}"
    end

    it 'every DLX reference in QUEUES has a DEAD_LETTER_CONFIG entry' do
      Onetime::Jobs::QueueConfig::QUEUES.each do |queue_name, config|
        dlx = config.dig(:arguments, 'x-dead-letter-exchange')
        next unless dlx

        expect(Onetime::Jobs::QueueConfig::DEAD_LETTER_CONFIG).to have_key(dlx),
          "Queue '#{queue_name}' references DLX '#{dlx}' not in DEAD_LETTER_CONFIG"
      end
    end
  end

end
