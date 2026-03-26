# spec/cli/worker_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'
require 'onetime/cli/worker_command'

RSpec.describe Onetime::CLI::WorkerCommand, type: :cli do
  let(:command) { described_class.new }

  describe 'exit codes' do
    it 'defines semantic exit codes' do
      expect(described_class::EXIT_SUCCESS).to eq(0)
      expect(described_class::EXIT_GENERAL_ERROR).to eq(1)
      expect(described_class::EXIT_CONFIG_ERROR).to eq(2)
      expect(described_class::EXIT_DEPENDENCY_UNAVAILABLE).to eq(3)
    end
  end

  describe '#preflight_check!' do
    let(:mock_logger) { instance_double('SemanticLogger::Logger') }

    before do
      command.instance_variable_set(:@amqp_url, 'amqp://localhost:5672')
      allow(Onetime).to receive(:workers_logger).and_return(mock_logger)
      allow(mock_logger).to receive(:fatal)
    end

    context 'when RabbitMQ is reachable' do
      it 'completes without error' do
        mock_socket = instance_double('Socket')
        allow(mock_socket).to receive(:close)
        allow(Socket).to receive(:tcp).with('localhost', 5672, connect_timeout: 2).and_return(mock_socket)

        expect { command.send(:preflight_check!) }.not_to raise_error
      end
    end

    context 'when connection is refused' do
      it 'logs fatal error and exits with EXIT_DEPENDENCY_UNAVAILABLE' do
        allow(Socket).to receive(:tcp).and_raise(Errno::ECONNREFUSED.new('Connection refused'))

        expect(mock_logger).to receive(:fatal).with(/RabbitMQ unreachable/)
        expect { command.send(:preflight_check!) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(described_class::EXIT_DEPENDENCY_UNAVAILABLE)
        end
      end
    end

    context 'when host is unreachable' do
      it 'logs fatal error and exits with EXIT_DEPENDENCY_UNAVAILABLE' do
        allow(Socket).to receive(:tcp).and_raise(Errno::EHOSTUNREACH.new('No route to host'))

        expect(mock_logger).to receive(:fatal).with(/RabbitMQ unreachable/)
        expect { command.send(:preflight_check!) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(described_class::EXIT_DEPENDENCY_UNAVAILABLE)
        end
      end
    end

    context 'when connection times out' do
      it 'logs fatal error and exits with EXIT_DEPENDENCY_UNAVAILABLE' do
        allow(Socket).to receive(:tcp).and_raise(Errno::ETIMEDOUT.new('Connection timed out'))

        expect(mock_logger).to receive(:fatal).with(/RabbitMQ unreachable/)
        expect { command.send(:preflight_check!) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(described_class::EXIT_DEPENDENCY_UNAVAILABLE)
        end
      end
    end

    context 'when DNS resolution fails' do
      it 'logs fatal error and exits with EXIT_DEPENDENCY_UNAVAILABLE' do
        allow(Socket).to receive(:tcp).and_raise(SocketError.new('getaddrinfo: Name does not resolve'))

        expect(mock_logger).to receive(:fatal).with(/RabbitMQ unreachable/)
        expect { command.send(:preflight_check!) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(described_class::EXIT_DEPENDENCY_UNAVAILABLE)
        end
      end
    end

    context 'with custom host and port from URL' do
      it 'parses host and port from AMQP URL' do
        command.instance_variable_set(:@amqp_url, 'amqp://user:pass@rabbitmq.example.com:5673/vhost')
        mock_socket = instance_double('Socket')
        allow(mock_socket).to receive(:close)

        expect(Socket).to receive(:tcp).with('rabbitmq.example.com', 5673, connect_timeout: 2).and_return(mock_socket)

        command.send(:preflight_check!)
      end
    end
  end

  describe '#declare_infrastructure' do
    let(:mock_workers_logger) { instance_double('SemanticLogger::Logger') }
    let(:mock_bunny_logger) { instance_double('SemanticLogger::Logger') }
    let(:mock_conn) { instance_double('Bunny::Session') }

    before do
      command.instance_variable_set(:@amqp_url, 'amqp://localhost:5672')
      allow(Onetime).to receive(:workers_logger).and_return(mock_workers_logger)
      allow(Onetime).to receive(:bunny_logger).and_return(mock_bunny_logger)
      allow(Onetime).to receive(:get_logger).and_return(mock_bunny_logger)
      allow(mock_bunny_logger).to receive(:info)
      allow(mock_workers_logger).to receive(:fatal)
    end

    context 'when connection succeeds' do
      it 'declares infrastructure and closes connection' do
        allow(Bunny).to receive(:new).and_return(mock_conn)
        allow(mock_conn).to receive(:start)
        allow(mock_conn).to receive(:close)
        allow(Onetime::Jobs::QueueDeclarator).to receive(:declare_all)

        command.send(:declare_infrastructure)

        expect(mock_conn).to have_received(:close)
      end
    end

    context 'when TCP connection fails' do
      it 'logs fatal error and exits with EXIT_DEPENDENCY_UNAVAILABLE' do
        allow(Bunny).to receive(:new).and_return(mock_conn)
        allow(mock_conn).to receive(:start).and_raise(Bunny::TCPConnectionFailed.new('Connection refused'))

        expect(mock_workers_logger).to receive(:fatal).with(/RabbitMQ connection failed/)
        expect { command.send(:declare_infrastructure) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(described_class::EXIT_DEPENDENCY_UNAVAILABLE)
        end
      end
    end

    context 'when authentication fails' do
      it 'logs fatal error and exits with EXIT_CONFIG_ERROR' do
        allow(Bunny).to receive(:new).and_return(mock_conn)
        # Bunny::AuthenticationFailureError requires (username, vhost, password_length)
        auth_error = Bunny::AuthenticationFailureError.new('guest', '/', 5)
        allow(mock_conn).to receive(:start).and_raise(auth_error)

        expect(mock_workers_logger).to receive(:fatal).with(/RabbitMQ authentication failed/)
        expect { command.send(:declare_infrastructure) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(described_class::EXIT_CONFIG_ERROR)
        end
      end
    end

    context 'when infrastructure declaration fails' do
      it 'logs fatal error and exits with EXIT_GENERAL_ERROR' do
        allow(Bunny).to receive(:new).and_return(mock_conn)
        allow(mock_conn).to receive(:start)
        allow(mock_conn).to receive(:close)
        allow(Onetime::Jobs::QueueDeclarator).to receive(:declare_all)
          .and_raise(Onetime::Jobs::QueueDeclarator::InfrastructureError.new('Missing queues'))

        expect(mock_workers_logger).to receive(:fatal).with(/Infrastructure error/)
        expect { command.send(:declare_infrastructure) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(described_class::EXIT_GENERAL_ERROR)
        end
      end
    end
  end

  describe '#format_uptime' do
    it 'formats seconds as minutes' do
      expect(command.send(:format_uptime, 0)).to eq('0m')
      expect(command.send(:format_uptime, 30)).to eq('0m')
      expect(command.send(:format_uptime, 60)).to eq('1m')
      expect(command.send(:format_uptime, 90)).to eq('1m')
      expect(command.send(:format_uptime, 3540)).to eq('59m')
    end

    it 'formats as hours and minutes when over an hour' do
      expect(command.send(:format_uptime, 3600)).to eq('1h0m')
      expect(command.send(:format_uptime, 3660)).to eq('1h1m')
      expect(command.send(:format_uptime, 7200)).to eq('2h0m')
      expect(command.send(:format_uptime, 9000)).to eq('2h30m')
    end

    it 'formats as days and hours when over a day' do
      expect(command.send(:format_uptime, 86_400)).to eq('1d0h')
      expect(command.send(:format_uptime, 90_000)).to eq('1d1h')
      expect(command.send(:format_uptime, 172_800)).to eq('2d0h')
      expect(command.send(:format_uptime, 180_000)).to eq('2d2h')
    end
  end

  describe 'Sneakers vhost configuration' do
    # Track the config passed to Sneakers.configure
    let(:captured_config) { {} }

    before do
      # Mock Sneakers.configure to capture the config hash
      allow(Sneakers).to receive(:configure) do |config|
        captured_config.merge!(config)
      end

      # Mock the logger to avoid nil errors
      mock_logger = double('Logger', level: Logger::INFO)
      allow(mock_logger).to receive(:level=)
      allow(Sneakers).to receive(:logger).and_return(mock_logger)
    end

    around do |example|
      # Save and restore environment
      original_url = ENV['RABBITMQ_URL']
      original_vhost = ENV['RABBITMQ_VHOST']
      example.run
    ensure
      ENV['RABBITMQ_URL'] = original_url
      if original_vhost.nil?
        ENV.delete('RABBITMQ_VHOST')
      else
        ENV['RABBITMQ_VHOST'] = original_vhost
      end
    end

    context 'when RABBITMQ_VHOST is explicitly set' do
      it 'includes vhost in Sneakers config' do
        ENV['RABBITMQ_URL'] = 'amqp://host/url-vhost'
        ENV['RABBITMQ_VHOST'] = 'override-vhost'
        # Set @amqp_url as call() would do
        command.instance_variable_set(:@amqp_url, ENV['RABBITMQ_URL'])

        command.send(:configure_sneakers,
          concurrency: 10,
          daemonize: false,
          environment: 'test',
          log_level: 'info'
        )

        expect(captured_config[:vhost]).to eq('override-vhost')
      end

      it 'overrides vhost from URL with env var value' do
        ENV['RABBITMQ_URL'] = 'amqps://user:pass@host:5671/production'
        ENV['RABBITMQ_VHOST'] = 'staging'
        command.instance_variable_set(:@amqp_url, ENV['RABBITMQ_URL'])

        command.send(:configure_sneakers,
          concurrency: 10,
          daemonize: false,
          environment: 'test',
          log_level: 'info'
        )

        expect(captured_config[:vhost]).to eq('staging')
        expect(captured_config[:amqp]).to eq('amqps://user:pass@host:5671/production')
      end
    end

    context 'when RABBITMQ_VHOST is not set' do
      it 'omits vhost from config (lets Bunny parse from URL)' do
        ENV['RABBITMQ_URL'] = 'amqp://host/url-vhost'
        ENV.delete('RABBITMQ_VHOST')
        command.instance_variable_set(:@amqp_url, ENV['RABBITMQ_URL'])

        command.send(:configure_sneakers,
          concurrency: 10,
          daemonize: false,
          environment: 'test',
          log_level: 'info'
        )

        # vhost should NOT be in the config - Bunny will parse it from URL
        expect(captured_config).not_to have_key(:vhost)
      end

      it 'passes AMQP URL unchanged for Bunny to parse' do
        ENV['RABBITMQ_URL'] = 'amqps://4ef062f27f30f2ec:secret@rabbit.northflank.com:5671/4ef062f27f30f2ec'
        ENV.delete('RABBITMQ_VHOST')
        command.instance_variable_set(:@amqp_url, ENV['RABBITMQ_URL'])

        command.send(:configure_sneakers,
          concurrency: 10,
          daemonize: false,
          environment: 'test',
          log_level: 'info'
        )

        expect(captured_config[:amqp]).to eq('amqps://4ef062f27f30f2ec:secret@rabbit.northflank.com:5671/4ef062f27f30f2ec')
        expect(captured_config).not_to have_key(:vhost)
      end
    end

    context 'with default RABBITMQ_URL' do
      it 'uses localhost default when RABBITMQ_URL not set' do
        ENV.delete('RABBITMQ_URL')
        ENV.delete('RABBITMQ_VHOST')
        # Simulate what call() does with default URL
        command.instance_variable_set(:@amqp_url, 'amqp://guest:guest@localhost:5672')

        command.send(:configure_sneakers,
          concurrency: 10,
          daemonize: false,
          environment: 'test',
          log_level: 'info'
        )

        expect(captured_config[:amqp]).to eq('amqp://guest:guest@localhost:5672')
      end
    end

    context 'other Sneakers configuration' do
      it 'sets expected configuration values' do
        ENV['RABBITMQ_URL'] = 'amqp://host/vhost'
        ENV.delete('RABBITMQ_VHOST')

        command.send(:configure_sneakers,
          concurrency: 5,
          daemonize: true,
          environment: 'production',
          log_level: 'warn'
        )

        expect(captured_config[:threads]).to eq(5)
        expect(captured_config[:daemonize]).to eq(true)
        expect(captured_config[:env]).to eq('production')
        expect(captured_config[:exchange]).to eq('')
        expect(captured_config[:exchange_type]).to eq(:direct)
        expect(captured_config[:durable]).to eq(true)
        expect(captured_config[:ack]).to eq(true)
      end
    end
  end

  describe '--check option behavior' do
    # These tests verify the check mode logic in the call method
    # by testing the branch conditions directly

    let(:mock_workers_logger) { instance_double('SemanticLogger::Logger') }
    let(:mock_bunny_logger) { instance_double('SemanticLogger::Logger') }
    let(:mock_conn) { instance_double('Bunny::Session') }
    let(:mock_socket) { instance_double('Socket') }

    # Create a mock worker class for testing
    let(:mock_worker_class) do
      Class.new do
        def self.name
          'MockEmailWorker'
        end

        def self.queue_name
          'email.message.send'
        end
      end
    end

    around do |example|
      original_url = ENV['RABBITMQ_URL']
      original_vhost = ENV['RABBITMQ_VHOST']
      example.run
    ensure
      ENV['RABBITMQ_URL'] = original_url
      if original_vhost.nil?
        ENV.delete('RABBITMQ_VHOST')
      else
        ENV['RABBITMQ_VHOST'] = original_vhost
      end
    end

    before do
      ENV['RABBITMQ_URL'] = 'amqp://localhost:5672'
      ENV.delete('RABBITMQ_VHOST')

      # Mock loggers
      allow(Onetime).to receive(:workers_logger).and_return(mock_workers_logger)
      allow(Onetime).to receive(:bunny_logger).and_return(mock_bunny_logger)
      allow(Onetime).to receive(:get_logger).and_return(mock_bunny_logger)
      allow(mock_workers_logger).to receive(:info)
      allow(mock_workers_logger).to receive(:error)
      allow(mock_workers_logger).to receive(:fatal)
      allow(mock_bunny_logger).to receive(:info)
      allow(mock_bunny_logger).to receive(:level=)

      # Mock Socket for preflight check
      allow(mock_socket).to receive(:close)
      allow(Socket).to receive(:tcp).and_return(mock_socket)

      # Mock Sneakers
      allow(Sneakers).to receive(:configure)

      # Mock Bunny connection for declare_infrastructure
      allow(Bunny).to receive(:new).and_return(mock_conn)
      allow(mock_conn).to receive(:start)
      allow(mock_conn).to receive(:close)
      allow(Onetime::Jobs::QueueDeclarator).to receive(:declare_all)
    end

    context 'when check mode succeeds with workers found' do
      it 'exits with EXIT_SUCCESS and prints worker count' do
        allow(command).to receive(:boot_application!)
        allow(command).to receive(:determine_workers).and_return([mock_worker_class])

        expect {
          command.call(check: true)
        }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(described_class::EXIT_SUCCESS)
        end
      end
    end

    context 'when check mode fails with no workers' do
      it 'exits with EXIT_GENERAL_ERROR' do
        allow(command).to receive(:boot_application!)
        allow(command).to receive(:determine_workers).and_return([])

        expect {
          command.call(check: true)
        }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(described_class::EXIT_GENERAL_ERROR)
        end
      end
    end

    context 'when not in check mode with no workers' do
      it 'logs error and exits with EXIT_GENERAL_ERROR' do
        allow(command).to receive(:boot_application!)
        allow(command).to receive(:determine_workers).and_return([])

        expect(mock_workers_logger).to receive(:error).with('No worker classes found')

        expect {
          command.call(check: false)
        }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(described_class::EXIT_GENERAL_ERROR)
        end
      end
    end
  end

  describe '#determine_workers' do
    context 'when workers directory does not exist' do
      it 'returns empty array' do
        allow(Dir).to receive(:exist?).and_return(false)

        result = command.send(:determine_workers, nil)

        expect(result).to eq([])
      end
    end
  end

  describe 'log level validation' do
    let(:captured_config) { {} }
    let(:mock_workers_logger) { instance_double('SemanticLogger::Logger') }
    let(:mock_bunny_logger) { instance_double('SemanticLogger::Logger') }

    before do
      allow(Sneakers).to receive(:configure) { |config| captured_config.merge!(config) }
      allow(Onetime).to receive(:workers_logger).and_return(mock_workers_logger)
      allow(Onetime).to receive(:bunny_logger).and_return(mock_bunny_logger)
      allow(mock_workers_logger).to receive(:level=)
      allow(mock_bunny_logger).to receive(:level=)

      ENV['RABBITMQ_URL'] = 'amqp://localhost:5672'
    end

    after do
      ENV.delete('RABBITMQ_URL')
    end

    it 'accepts valid log levels' do
      %w[trace debug info warn error fatal].each do |level|
        allow(mock_workers_logger).to receive(:level=).with(level.to_sym)
        allow(mock_bunny_logger).to receive(:level=).with(level.to_sym)

        expect {
          command.send(:configure_sneakers,
            concurrency: 10,
            daemonize: false,
            environment: 'test',
            log_level: level
          )
        }.not_to raise_error
      end
    end

    it 'warns on invalid log level' do
      expect(mock_workers_logger).to receive(:warn).with(/Ignoring invalid log level/)

      command.send(:configure_sneakers,
        concurrency: 10,
        daemonize: false,
        environment: 'test',
        log_level: 'invalid'
      )
    end
  end

  describe 'error message output' do
    let(:mock_logger) { instance_double('SemanticLogger::Logger') }

    before do
      allow(Onetime).to receive(:workers_logger).and_return(mock_logger)
      allow(mock_logger).to receive(:fatal)
    end

    describe '#preflight_check! stderr output' do
      before do
        command.instance_variable_set(:@amqp_url, 'amqp://rabbitmq.example.com:5672')
      end

      it 'outputs actionable error message with fix suggestions when connection refused' do
        allow(Socket).to receive(:tcp).and_raise(Errno::ECONNREFUSED.new('Connection refused'))

        expect {
          begin
            command.send(:preflight_check!)
          rescue SystemExit
            # Expected
          end
        }.to output(
          a_string_including('ERROR: Cannot connect to RabbitMQ')
          .and(a_string_including('brew services start rabbitmq'))
        ).to_stderr
      end

      it 'includes host and port in error message' do
        allow(Socket).to receive(:tcp).and_raise(Errno::ECONNREFUSED.new('Connection refused'))

        expect {
          begin
            command.send(:preflight_check!)
          rescue SystemExit
            # Expected
          end
        }.to output(a_string_including('rabbitmq.example.com:5672')).to_stderr
      end
    end

    describe '#declare_infrastructure stderr output' do
      let(:mock_bunny_logger) { instance_double('SemanticLogger::Logger') }
      let(:mock_conn) { instance_double('Bunny::Session') }

      before do
        command.instance_variable_set(:@amqp_url, 'amqp://localhost:5672')
        allow(Onetime).to receive(:bunny_logger).and_return(mock_bunny_logger)
        allow(Onetime).to receive(:get_logger).and_return(mock_bunny_logger)
        allow(mock_bunny_logger).to receive(:info)
        allow(Bunny).to receive(:new).and_return(mock_conn)
      end

      it 'outputs authentication error with credential check suggestion' do
        auth_error = Bunny::AuthenticationFailureError.new('guest', '/', 5)
        allow(mock_conn).to receive(:start).and_raise(auth_error)

        expect {
          begin
            command.send(:declare_infrastructure)
          rescue SystemExit
            # Expected
          end
        }.to output(/Check credentials in RABBITMQ_URL/).to_stderr
      end

      it 'outputs infrastructure error with queue init suggestion' do
        allow(mock_conn).to receive(:start)
        allow(mock_conn).to receive(:close)
        allow(Onetime::Jobs::QueueDeclarator).to receive(:declare_all)
          .and_raise(Onetime::Jobs::QueueDeclarator::InfrastructureError.new('Missing queues: email.message.send'))

        expect {
          begin
            command.send(:declare_infrastructure)
          rescue SystemExit
            # Expected
          end
        }.to output(/Run: ots queue init/).to_stderr
      end
    end
  end

  describe '#declare_infrastructure connection cleanup' do
    let(:mock_workers_logger) { instance_double('SemanticLogger::Logger') }
    let(:mock_bunny_logger) { instance_double('SemanticLogger::Logger') }
    let(:mock_conn) { instance_double('Bunny::Session') }

    before do
      command.instance_variable_set(:@amqp_url, 'amqp://localhost:5672')
      allow(Onetime).to receive(:workers_logger).and_return(mock_workers_logger)
      allow(Onetime).to receive(:bunny_logger).and_return(mock_bunny_logger)
      allow(Onetime).to receive(:get_logger).and_return(mock_bunny_logger)
      allow(mock_bunny_logger).to receive(:info)
      allow(mock_workers_logger).to receive(:fatal)
      allow(Bunny).to receive(:new).and_return(mock_conn)
      allow(mock_conn).to receive(:start)
    end

    it 'closes connection even when declare_all raises InfrastructureError' do
      allow(Onetime::Jobs::QueueDeclarator).to receive(:declare_all)
        .and_raise(Onetime::Jobs::QueueDeclarator::InfrastructureError.new('Missing queues'))

      # The connection should still be closed via the ensure block
      expect(mock_conn).to receive(:close)

      expect {
        command.send(:declare_infrastructure)
      }.to raise_error(SystemExit)
    end
  end

  describe 'TLS configuration' do
    let(:mock_workers_logger) { instance_double('SemanticLogger::Logger') }
    let(:mock_bunny_logger) { instance_double('SemanticLogger::Logger') }
    let(:mock_conn) { instance_double('Bunny::Session') }

    before do
      allow(Onetime).to receive(:workers_logger).and_return(mock_workers_logger)
      allow(Onetime).to receive(:bunny_logger).and_return(mock_bunny_logger)
      allow(Onetime).to receive(:get_logger).and_return(mock_bunny_logger)
      allow(mock_bunny_logger).to receive(:info)
      allow(mock_workers_logger).to receive(:fatal)
    end

    it 'passes TLS options to Bunny for amqps:// URLs in declare_infrastructure' do
      command.instance_variable_set(:@amqp_url, 'amqps://user:pass@rabbitmq.example.com:5671')

      tls_options = { tls: true, verify_peer: true }
      allow(Onetime::Jobs::QueueConfig).to receive(:tls_options)
        .with('amqps://user:pass@rabbitmq.example.com:5671')
        .and_return(tls_options)

      expect(Bunny).to receive(:new).with(
        'amqps://user:pass@rabbitmq.example.com:5671',
        hash_including(tls: true, verify_peer: true)
      ).and_return(mock_conn)
      allow(mock_conn).to receive(:start)
      allow(mock_conn).to receive(:close)
      allow(Onetime::Jobs::QueueDeclarator).to receive(:declare_all)

      command.send(:declare_infrastructure)
    end
  end

  describe '--check mode output verification' do
    let(:mock_workers_logger) { instance_double('SemanticLogger::Logger') }
    let(:mock_bunny_logger) { instance_double('SemanticLogger::Logger') }
    let(:mock_conn) { instance_double('Bunny::Session') }
    let(:mock_socket) { instance_double('Socket') }

    let(:mock_worker_class) do
      Class.new do
        def self.name
          'MockEmailWorker'
        end

        def self.queue_name
          'email.message.send'
        end
      end
    end

    let(:mock_worker_class_2) do
      Class.new do
        def self.name
          'MockSchedulerWorker'
        end

        def self.queue_name
          'scheduler.task.run'
        end
      end
    end

    around do |example|
      original_url = ENV['RABBITMQ_URL']
      original_vhost = ENV['RABBITMQ_VHOST']
      example.run
    ensure
      ENV['RABBITMQ_URL'] = original_url
      if original_vhost.nil?
        ENV.delete('RABBITMQ_VHOST')
      else
        ENV['RABBITMQ_VHOST'] = original_vhost
      end
    end

    before do
      ENV['RABBITMQ_URL'] = 'amqp://localhost:5672'
      ENV.delete('RABBITMQ_VHOST')

      allow(Onetime).to receive(:workers_logger).and_return(mock_workers_logger)
      allow(Onetime).to receive(:bunny_logger).and_return(mock_bunny_logger)
      allow(Onetime).to receive(:get_logger).and_return(mock_bunny_logger)
      allow(mock_workers_logger).to receive(:info)
      allow(mock_workers_logger).to receive(:error)
      allow(mock_workers_logger).to receive(:fatal)
      allow(mock_bunny_logger).to receive(:info)
      allow(mock_bunny_logger).to receive(:level=)

      allow(mock_socket).to receive(:close)
      allow(Socket).to receive(:tcp).and_return(mock_socket)
      allow(Sneakers).to receive(:configure)
      allow(Bunny).to receive(:new).and_return(mock_conn)
      allow(mock_conn).to receive(:start)
      allow(mock_conn).to receive(:close)
      allow(Onetime::Jobs::QueueDeclarator).to receive(:declare_all)
    end

    it 'outputs success message with worker count' do
      allow(command).to receive(:boot_application!)
      allow(command).to receive(:determine_workers).and_return([mock_worker_class])

      expect {
        begin
          command.call(check: true)
        rescue SystemExit
          # Expected
        end
      }.to output(/Config OK: 1 worker\(s\) ready/).to_stdout
    end

    it 'outputs worker class names' do
      allow(command).to receive(:boot_application!)
      allow(command).to receive(:determine_workers).and_return([mock_worker_class, mock_worker_class_2])

      expect {
        begin
          command.call(check: true)
        rescue SystemExit
          # Expected
        end
      }.to output(/Workers: MockEmailWorker, MockSchedulerWorker/).to_stdout
    end

    it 'outputs failure message to stderr when no workers found' do
      allow(command).to receive(:boot_application!)
      allow(command).to receive(:determine_workers).and_return([])

      expect {
        begin
          command.call(check: true)
        rescue SystemExit
          # Expected
        end
      }.to output(/Check failed: No worker classes found/).to_stderr
    end
  end

  describe '#preflight_check! with URL variations' do
    let(:mock_logger) { instance_double('SemanticLogger::Logger') }
    let(:mock_socket) { instance_double('Socket') }

    before do
      allow(Onetime).to receive(:workers_logger).and_return(mock_logger)
      allow(mock_logger).to receive(:fatal)
      allow(mock_socket).to receive(:close)
    end

    it 'uses default port 5672 when port is not specified in URL' do
      command.instance_variable_set(:@amqp_url, 'amqp://rabbitmq.example.com')

      expect(Socket).to receive(:tcp).with('rabbitmq.example.com', 5672, connect_timeout: 2).and_return(mock_socket)

      command.send(:preflight_check!)
    end

    it 'uses port 5671 for amqps:// URLs when specified' do
      command.instance_variable_set(:@amqp_url, 'amqps://user:pass@rabbitmq.example.com:5671/vhost')

      expect(Socket).to receive(:tcp).with('rabbitmq.example.com', 5671, connect_timeout: 2).and_return(mock_socket)

      command.send(:preflight_check!)
    end

    it 'defaults to port 5671 for amqps:// URLs when port is not specified' do
      command.instance_variable_set(:@amqp_url, 'amqps://user:pass@rabbitmq.example.com/vhost')

      expect(Socket).to receive(:tcp).with('rabbitmq.example.com', 5671, connect_timeout: 2).and_return(mock_socket)

      command.send(:preflight_check!)
    end

    it 'handles URLs with encoded special characters in password' do
      # Password with @ symbol encoded as %40
      command.instance_variable_set(:@amqp_url, 'amqp://user:p%40ssword@rabbitmq.example.com:5672')

      expect(Socket).to receive(:tcp).with('rabbitmq.example.com', 5672, connect_timeout: 2).and_return(mock_socket)

      command.send(:preflight_check!)
    end
  end

  # ==========================================================================
  # Sneakers Fork Hook Wiring
  # ==========================================================================
  # These tests verify that configure_sneakers wires before_fork and after_fork
  # hooks that delegate to the InitializerRegistry, mirroring the Puma fork
  # hook pattern (see: spec/integration/all/puma_fork_registry_workflow_spec.rb).
  #
  # This prevents regression of GitHub issue #2766 where Sneakers workers
  # would not clean up / reconnect fork-sensitive resources (auth database,
  # loggers, RabbitMQ) after forking.
  # ==========================================================================
  describe 'Sneakers fork hook wiring' do
    let(:captured_config) { {} }
    let(:mock_bunny_logger) { instance_double('SemanticLogger::Logger') }

    around do |example|
      original_url = ENV['RABBITMQ_URL']
      original_vhost = ENV['RABBITMQ_VHOST']
      example.run
    ensure
      ENV['RABBITMQ_URL'] = original_url
      if original_vhost.nil?
        ENV.delete('RABBITMQ_VHOST')
      else
        ENV['RABBITMQ_VHOST'] = original_vhost
      end
    end

    before do
      ENV['RABBITMQ_URL'] = 'amqp://localhost:5672'
      ENV.delete('RABBITMQ_VHOST')

      allow(Sneakers).to receive(:configure) { |config| captured_config.merge!(config) }
      allow(Onetime).to receive(:bunny_logger).and_return(mock_bunny_logger)
      allow(mock_bunny_logger).to receive(:level=)

      command.instance_variable_set(:@amqp_url, ENV['RABBITMQ_URL'])
      command.send(:configure_sneakers,
        concurrency: 10,
        daemonize: false,
        environment: 'test',
        log_level: nil
      )
    end

    it 'configures a hooks hash with before_fork and after_fork' do
      expect(captured_config).to have_key(:hooks)
      expect(captured_config[:hooks]).to have_key(:before_fork)
      expect(captured_config[:hooks]).to have_key(:after_fork)
    end

    it 'sets before_fork hook as a callable (lambda/proc)' do
      expect(captured_config[:hooks][:before_fork]).to respond_to(:call)
    end

    it 'sets after_fork hook as a callable (lambda/proc)' do
      expect(captured_config[:hooks][:after_fork]).to respond_to(:call)
    end

    describe 'before_fork hook' do
      it 'calls cleanup_before_fork on the boot registry' do
        mock_registry = instance_double('Onetime::Boot::InitializerRegistry')
        allow(Onetime).to receive(:boot_registry).and_return(mock_registry)
        allow(mock_registry).to receive(:cleanup_before_fork)

        captured_config[:hooks][:before_fork].call

        expect(mock_registry).to have_received(:cleanup_before_fork)
      end

      it 'handles nil boot_registry gracefully (safe navigation)' do
        allow(Onetime).to receive(:boot_registry).and_return(nil)

        expect { captured_config[:hooks][:before_fork].call }.not_to raise_error
      end
    end

    describe 'after_fork hook' do
      it 'calls reconnect_after_fork on the boot registry' do
        mock_registry = instance_double('Onetime::Boot::InitializerRegistry')
        allow(Onetime).to receive(:boot_registry).and_return(mock_registry)
        allow(mock_registry).to receive(:reconnect_after_fork)

        captured_config[:hooks][:after_fork].call

        expect(mock_registry).to have_received(:reconnect_after_fork)
      end

      it 'handles nil boot_registry gracefully (safe navigation)' do
        allow(Onetime).to receive(:boot_registry).and_return(nil)

        expect { captured_config[:hooks][:after_fork].call }.not_to raise_error
      end
    end
  end

  describe '#start_heartbeat_thread' do
    let(:mock_logger) { instance_double('SemanticLogger::Logger') }

    let(:mock_worker_class) do
      Class.new do
        def self.name
          'MockWorker'
        end

        def self.queue_name
          'test.queue'
        end
      end
    end

    before do
      allow(Onetime).to receive(:workers_logger).and_return(mock_logger)
      allow(mock_logger).to receive(:info)
      allow(mock_logger).to receive(:warn)
    end

    it 'returns nil when heartbeat interval is 0 (disabled)' do
      allow(ENV).to receive(:fetch).with('WORKER_HEARTBEAT_INTERVAL', 300).and_return('0')

      result = command.send(:start_heartbeat_thread, [mock_worker_class])

      expect(result).to be_nil
    end

    it 'returns nil when heartbeat interval is negative' do
      allow(ENV).to receive(:fetch).with('WORKER_HEARTBEAT_INTERVAL', 300).and_return('-1')

      result = command.send(:start_heartbeat_thread, [mock_worker_class])

      expect(result).to be_nil
    end

    it 'returns a Thread when heartbeat is enabled' do
      allow(ENV).to receive(:fetch).with('WORKER_HEARTBEAT_INTERVAL', 300).and_return('60')

      thread = command.send(:start_heartbeat_thread, [mock_worker_class])

      expect(thread).to be_a(Thread)
      thread.kill # Clean up the thread
    end
  end
end
