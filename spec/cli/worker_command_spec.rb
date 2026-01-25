# spec/cli/worker_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'
require 'onetime/cli/worker_command'

RSpec.describe Onetime::CLI::WorkerCommand, type: :cli do
  let(:command) { described_class.new }

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
end
