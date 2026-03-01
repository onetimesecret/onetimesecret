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
require 'onetime/jobs/queues/config'

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

  # ==========================================================================
  # Environment Variable Tests
  # ==========================================================================
  # These tests verify environment variable handling for worker mode and
  # connection configuration.
  # ==========================================================================

  describe 'SKIP_RABBITMQ_SETUP environment variable' do
    around do |example|
      original = ENV['SKIP_RABBITMQ_SETUP']
      example.run
    ensure
      if original.nil?
        ENV.delete('SKIP_RABBITMQ_SETUP')
      else
        ENV['SKIP_RABBITMQ_SETUP'] = original
      end
    end

    context 'when SKIP_RABBITMQ_SETUP=1' do
      before do
        ENV['SKIP_RABBITMQ_SETUP'] = '1'
        allow(OT).to receive(:conf).and_return({ 'jobs' => { 'enabled' => true } })
      end

      it 'skips connection setup entirely' do
        expect(Bunny).not_to receive(:new)
        instance.execute(nil)
      end

      it 'does not set global connection state' do
        $rmq_conn = nil
        $rmq_channel_pool = nil

        instance.execute(nil)

        expect($rmq_conn).to be_nil
        expect($rmq_channel_pool).to be_nil
      end
    end

    context 'when SKIP_RABBITMQ_SETUP is not set' do
      before do
        ENV.delete('SKIP_RABBITMQ_SETUP')
        allow(OT).to receive(:conf).and_return({
          'jobs' => {
            'enabled' => true,
            'rabbitmq_url' => 'amqp://localhost',
            'channel_pool_size' => 2
          }
        })
      end

      it 'attempts RabbitMQ connection' do
        mock_conn = instance_double(Bunny::Session, start: true, open?: true)
        mock_channel = instance_double(Bunny::Channel)
        mock_pool = instance_double(ConnectionPool)

        allow(Bunny).to receive(:new).and_return(mock_conn)
        allow(mock_conn).to receive(:create_channel).and_return(mock_channel)
        allow(ConnectionPool).to receive(:new).and_return(mock_pool)
        allow(mock_pool).to receive(:with).and_yield(mock_channel)
        allow(mock_channel).to receive(:fanout)
        allow(mock_channel).to receive(:queue).and_return(instance_double(Bunny::Queue, bind: true))
        allow(mock_channel).to receive(:open?).and_return(true)
        allow(mock_channel).to receive(:close)

        expect(Bunny).to receive(:new)
        instance.execute(nil)
      end
    end
  end

  describe 'RABBITMQ_CHANNEL_POOL_SIZE environment variable' do
    around do |example|
      original_pool_size = ENV['RABBITMQ_CHANNEL_POOL_SIZE']
      original_skip = ENV['SKIP_RABBITMQ_SETUP']
      example.run
    ensure
      if original_pool_size.nil?
        ENV.delete('RABBITMQ_CHANNEL_POOL_SIZE')
      else
        ENV['RABBITMQ_CHANNEL_POOL_SIZE'] = original_pool_size
      end
      if original_skip.nil?
        ENV.delete('SKIP_RABBITMQ_SETUP')
      else
        ENV['SKIP_RABBITMQ_SETUP'] = original_skip
      end
    end

    context 'when RABBITMQ_CHANNEL_POOL_SIZE is set' do
      before do
        ENV['RABBITMQ_CHANNEL_POOL_SIZE'] = '10'
        ENV.delete('SKIP_RABBITMQ_SETUP')
        allow(OT).to receive(:conf).and_return({
          'jobs' => {
            'enabled' => true,
            'rabbitmq_url' => 'amqp://localhost'
            # Note: no channel_pool_size in config - should use env var
          }
        })
      end

      it 'uses the environment variable value for pool size' do
        mock_conn = instance_double(Bunny::Session, start: true, open?: true)
        mock_channel = instance_double(Bunny::Channel)
        mock_pool = instance_double(ConnectionPool)

        allow(Bunny).to receive(:new).and_return(mock_conn)
        allow(mock_conn).to receive(:create_channel).and_return(mock_channel)
        allow(mock_pool).to receive(:with).and_yield(mock_channel)
        allow(mock_channel).to receive(:fanout)
        allow(mock_channel).to receive(:queue).and_return(instance_double(Bunny::Queue, bind: true))
        allow(mock_channel).to receive(:open?).and_return(true)
        allow(mock_channel).to receive(:close)

        expect(ConnectionPool).to receive(:new).with(hash_including(size: 10)).and_return(mock_pool)
        instance.execute(nil)
      end
    end
  end

  # ==========================================================================
  # URL Sanitization Tests
  # ==========================================================================
  # These tests verify credential masking in log output.
  # ==========================================================================

  describe '#sanitize_url' do
    it 'masks user:pass@host credentials' do
      result = instance.send(:sanitize_url, 'amqp://user:secretpass@host:5672')
      expect(result).to eq('amqp://user:***@host:5672')
    end

    it 'masks alphanumeric passwords' do
      # Standard password without special characters
      result = instance.send(:sanitize_url, 'amqps://admin:password123@broker.example.com:5671/vhost')
      expect(result).to eq('amqps://admin:***@broker.example.com:5671/vhost')
    end

    it 'masks key@host credentials (Northflank style without colon)' do
      result = instance.send(:sanitize_url, 'amqps://4ef062f27f30f2ec@rabbit.northflank.com:5671')
      expect(result).to eq('amqps://***@rabbit.northflank.com:5671')
    end

    it 'preserves URL without credentials' do
      result = instance.send(:sanitize_url, 'amqp://localhost:5672')
      expect(result).to eq('amqp://localhost:5672')
    end

    it 'handles URL with vhost path' do
      result = instance.send(:sanitize_url, 'amqps://user:pass@host:5671/production')
      expect(result).to eq('amqps://user:***@host:5671/production')
    end

    it 'handles managed service URLs with hex identifiers' do
      # CloudAMQP/Northflank style URLs
      result = instance.send(:sanitize_url, 'amqps://abc123def:secretkey456@rabbit.service.com:5671/abc123def')
      expect(result).to eq('amqps://abc123def:***@rabbit.service.com:5671/abc123def')
    end
  end

  # ==========================================================================
  # Chaos/Failure Injection Tests
  # ==========================================================================
  # These tests verify graceful degradation during connection failures,
  # mid-operation errors, and infrastructure instability.
  # ==========================================================================

  describe 'chaos/failure scenarios' do
    let(:mock_conn) { instance_double(Bunny::Session) }
    let(:mock_channel) { instance_double(Bunny::Channel) }
    let(:mock_pool) { instance_double(ConnectionPool) }

    before do
      allow(OT).to receive(:conf).and_return({
        'jobs' => {
          'enabled' => true,
          'rabbitmq_url' => 'amqp://localhost',
          'channel_pool_size' => 2
        }
      })
    end

    after do
      # Clean up global state
      $rmq_conn = nil
      $rmq_channel_pool = nil
    end

    describe 'connection establishment failures' do
      context 'when Bunny::TCPConnectionFailed during Bunny.new' do
        before do
          allow(Bunny).to receive(:new).and_raise(Bunny::TCPConnectionFailed.new('Connection refused'))
        end

        it 'does not raise and allows app to start with degraded functionality' do
          expect { instance.execute(nil) }.not_to raise_error
        end
      end

      context 'when Bunny::ConnectionTimeout during Bunny.new' do
        before do
          allow(Bunny).to receive(:new).and_raise(Bunny::ConnectionTimeout.new('Timeout'))
        end

        it 'does not raise and allows app to start with degraded functionality' do
          expect { instance.execute(nil) }.not_to raise_error
        end
      end

      context 'when Bunny::PreconditionFailed during conn.start' do
        before do
          allow(Bunny).to receive(:new).and_return(mock_conn)
          # PreconditionFailed requires (message, channel, code)
          allow(mock_conn).to receive(:start).and_raise(Bunny::PreconditionFailed.new('Queue property mismatch', nil, 406))
        end

        it 'does not raise (graceful degradation)' do
          expect { instance.execute(nil) }.not_to raise_error
        end
      end
    end

    describe 'mid-operation failures during exchange declaration' do
      # Note: The current implementation only declares DLX exchanges, not queues.
      # Queue declaration is deferred to workers to avoid race conditions.

      before do
        allow(Bunny).to receive(:new).and_return(mock_conn)
        allow(mock_conn).to receive(:start)
        allow(mock_conn).to receive(:create_channel).and_return(mock_channel)
        allow(mock_channel).to receive(:open?).and_return(true)
        allow(mock_channel).to receive(:close)
        allow(mock_channel).to receive(:queue).and_return(instance_double(Bunny::Queue, bind: true))
        allow(ConnectionPool).to receive(:new).and_return(mock_pool)
      end

      context 'when channel.fanout raises Bunny::ChannelLevelException on first call' do
        before do
          allow(mock_pool).to receive(:with).and_yield(mock_channel)
          # Fail on first fanout call
          allow(mock_channel).to receive(:fanout).and_raise(
            Bunny::ChannelLevelException.new('Channel error', mock_channel, 406)
          )
        end

        it 'propagates the error (unexpected errors should surface for debugging)' do
          # Bunny::ChannelLevelException inherits from StandardError, so it's re-raised
          expect { instance.execute(nil) }.to raise_error(Bunny::ChannelLevelException)
        end
      end

      context 'when channel.fanout raises Bunny::ChannelLevelException on second call' do
        before do
          call_count = 0
          allow(mock_pool).to receive(:with).and_yield(mock_channel)
          allow(mock_channel).to receive(:fanout) do |_name, _opts|
            call_count += 1
            if call_count == 2
              raise Bunny::ChannelLevelException.new('Channel error on second exchange', mock_channel, 406)
            end
            instance_double(Bunny::Exchange)
          end
        end

        it 'propagates the error (partial declaration failure)' do
          expect { instance.execute(nil) }.to raise_error(Bunny::ChannelLevelException)
        end
      end
    end

    describe 'connection start failures' do
      before do
        allow(Bunny).to receive(:new).and_return(mock_conn)
      end

      context 'when conn.start raises Bunny::TCPConnectionFailed' do
        before do
          allow(mock_conn).to receive(:start).and_raise(Bunny::TCPConnectionFailed.new('Connection lost'))
        end

        it 'handles gracefully (caught by explicit rescue)' do
          expect { instance.execute(nil) }.not_to raise_error
        end
      end

      context 'when conn.start raises Bunny::ConnectionTimeout' do
        before do
          allow(mock_conn).to receive(:start).and_raise(Bunny::ConnectionTimeout.new('Timeout during start'))
        end

        it 'handles gracefully (caught by explicit rescue)' do
          expect { instance.execute(nil) }.not_to raise_error
        end
      end
    end

    describe 'global state after failures' do
      context 'after Bunny::TCPConnectionFailed' do
        before do
          # Reset globals before test to prevent leak from other examples
          $rmq_conn         = nil
          $rmq_channel_pool = nil
          allow(Bunny).to receive(:new).and_raise(Bunny::TCPConnectionFailed.new('Connection refused'))
          instance.execute(nil)
        end

        after do
          $rmq_conn         = nil
          $rmq_channel_pool = nil
        end

        it 'leaves $rmq_conn nil' do
          expect($rmq_conn).to be_nil
        end

        it 'leaves $rmq_channel_pool nil' do
          expect($rmq_channel_pool).to be_nil
        end
      end
    end
  end

end
