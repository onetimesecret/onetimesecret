# spec/cli/server_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'

RSpec.describe 'Server Command', type: :cli do
  let(:rack_app) { double('RackApp') }
  let(:rack_builder) { double('Rack::Builder') }
  let(:puma_handler) { double('Puma::Handler') }

  before do
    allow(Rack::Builder).to receive(:parse_file).and_return([rack_app, {}])
    allow(Rackup::Handler).to receive(:get).and_return(puma_handler)
    allow(puma_handler).to receive(:run)
  end

  describe 'default options' do
    it 'starts Puma server on port 7143' do
      expect(puma_handler).to receive(:run).with(
        rack_app,
        hash_including(Port: 7143, Host: '127.0.0.1')
      )

      run_cli_command_quietly('server')
    end

    it 'uses development environment by default' do
      expect(puma_handler).to receive(:run).with(
        rack_app,
        hash_including(environment: 'development')
      )

      run_cli_command_quietly('server')
    end
  end

  describe 'port option' do
    it 'accepts --port flag' do
      expect(puma_handler).to receive(:run).with(
        rack_app,
        hash_including(Port: 8080)
      )

      run_cli_command_quietly('server', '--port', '8080')
    end

    it 'accepts -p short flag' do
      expect(puma_handler).to receive(:run).with(
        rack_app,
        hash_including(Port: 9000)
      )

      run_cli_command_quietly('server', '-p', '9000')
    end
  end

  describe 'environment option' do
    it 'accepts --environment flag' do
      expect(puma_handler).to receive(:run).with(
        rack_app,
        hash_including(environment: 'production')
      )

      run_cli_command_quietly('server', '--environment', 'production')
    end

    it 'accepts -e short flag' do
      expect(puma_handler).to receive(:run).with(
        rack_app,
        hash_including(environment: 'test')
      )

      run_cli_command_quietly('server', '-e', 'test')
    end
  end

  describe 'bind option' do
    it 'accepts --bind flag' do
      expect(puma_handler).to receive(:run).with(
        rack_app,
        hash_including(Host: '0.0.0.0')
      )

      run_cli_command_quietly('server', '--bind', '0.0.0.0')
    end

    it 'accepts -b short flag' do
      expect(puma_handler).to receive(:run).with(
        rack_app,
        hash_including(Host: 'localhost')
      )

      run_cli_command_quietly('server', '-b', 'localhost')
    end
  end

  describe 'puma-specific options' do
    it 'accepts --threads option' do
      expect(puma_handler).to receive(:run).with(
        rack_app,
        hash_including(Threads: '4:8')
      )

      run_cli_command_quietly('server', '--threads', '4:8')
    end

    it 'accepts --workers option' do
      expect(puma_handler).to receive(:run).with(
        rack_app,
        hash_including(Workers: 4)
      )

      run_cli_command_quietly('server', '--workers', '4')
    end

    it 'parses threads string correctly' do
      expect(puma_handler).to receive(:run).with(
        rack_app,
        hash_including(Threads: '1:2')
      )

      run_cli_command_quietly('server', '-t', '1:2')
    end
  end

  describe 'server type option' do
    it 'accepts --server flag for thin' do
      thin_handler = double('Thin::Handler')
      allow(Rackup::Handler).to receive(:get).with('thin').and_return(thin_handler)
      expect(thin_handler).to receive(:run)

      run_cli_command_quietly('server', '--server', 'thin')
    end

    it 'defaults to puma without --server flag' do
      expect(Rackup::Handler).to receive(:get).with('puma').and_return(puma_handler)
      run_cli_command_quietly('server')
    end
  end

  describe 'config file' do
    it 'accepts config file as positional argument' do
      expect(puma_handler).to receive(:run).with(
        rack_app,
        hash_including(config_files: 'config/puma.rb')
      )

      run_cli_command_quietly('server', 'config/puma.rb')
    end

    it 'rejects config file with command-line options' do
      expect {
        run_cli_command('server', 'config/puma.rb', '--port', '8080')
      }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end
    end
  end

  describe 'error handling' do
    it 'logs server configuration' do
      # Stub app_logger to return a consistent mock since Onetime.app_logger
      # returns a new SemanticLogger instance each time it's called
      logger_mock = instance_double(SemanticLogger::Logger)
      allow(Onetime).to receive(:app_logger).and_return(logger_mock)
      expect(logger_mock).to receive(:debug).with(/Starting puma with config/)
      run_cli_command_quietly('server')
    end
  end
end
