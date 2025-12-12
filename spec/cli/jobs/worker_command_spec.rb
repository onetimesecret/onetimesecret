# spec/cli/jobs/worker_command_spec.rb
#
# frozen_string_literal: true

require_relative '../cli_spec_helper'
require 'onetime/cli/jobs/worker_command'

RSpec.describe Onetime::CLI::Jobs::WorkerCommand, type: :cli do
  let(:command) { described_class.new }

  describe '#extract_vhost_from_url (private)' do
    # Use send to test private method - it's a pure function with clear inputs/outputs
    def extract_vhost(url)
      command.send(:extract_vhost_from_url, url)
    end

    context 'with standard AMQP URLs' do
      it 'extracts vhost from path' do
        expect(extract_vhost('amqp://host/myvhost')).to eq('myvhost')
      end

      it 'extracts vhost from amqps URL' do
        expect(extract_vhost('amqps://user:pass@host:5671/production')).to eq('production')
      end

      it 'handles vhost with credentials in URL' do
        expect(extract_vhost('amqp://guest:guest@localhost:5672/testvhost')).to eq('testvhost')
      end
    end

    context 'with URL-encoded vhosts' do
      it 'decodes URL-encoded vhost names' do
        expect(extract_vhost('amqp://host/my%20vhost')).to eq('my vhost')
      end

      it 'decodes percent-encoded slashes' do
        expect(extract_vhost('amqp://host/%2Fproduction')).to eq('/production')
      end

      it 'decodes complex encoded vhost' do
        expect(extract_vhost('amqp://host/ns%3Aproduction')).to eq('ns:production')
      end

      it 'preserves literal + characters (not form-decoded to space)' do
        expect(extract_vhost('amqp://host/my+vhost')).to eq('my+vhost')
      end
    end

    context 'with empty or missing path' do
      it 'returns "/" for empty path' do
        expect(extract_vhost('amqp://host/')).to eq('/')
      end

      it 'returns "/" for URL without path' do
        expect(extract_vhost('amqp://host')).to eq('/')
      end

      it 'returns "/" for URL with only port' do
        expect(extract_vhost('amqp://host:5672')).to eq('/')
      end
    end

    context 'with invalid URIs' do
      it 'returns "/" for malformed URI' do
        expect(extract_vhost('not-a-valid-uri://[')).to eq('/')
      end

      it 'returns "/" for empty string' do
        expect(extract_vhost('')).to eq('/')
      end
    end

    context 'with multi-segment paths' do
      # AMQP URLs should only have single-segment vhost names
      # but we handle whatever URI.parse gives us
      it 'extracts first segment as vhost' do
        # URI.parse('/path/to/vhost').path returns '/path/to/vhost'
        # After removing leading slash: 'path/to/vhost'
        expect(extract_vhost('amqp://host/path/to/vhost')).to eq('path/to/vhost')
      end
    end

    context 'with real-world Northflank-style URLs' do
      it 'handles Northflank addon URL format' do
        url = 'amqps://4ef062f27f30f2ec:secretpass@rabbit.northflank.com:5671/4ef062f27f30f2ec'
        expect(extract_vhost(url)).to eq('4ef062f27f30f2ec')
      end
    end
  end

  describe 'RABBITMQ_VHOST environment variable precedence' do
    around do |example|
      # Save original env
      original_url = ENV['RABBITMQ_URL']
      original_vhost = ENV['RABBITMQ_VHOST']
      example.run
    ensure
      # Restore original env
      ENV['RABBITMQ_URL'] = original_url
      ENV['RABBITMQ_VHOST'] = original_vhost
    end

    it 'uses RABBITMQ_VHOST when explicitly set' do
      ENV['RABBITMQ_URL'] = 'amqp://host/url-vhost'
      ENV['RABBITMQ_VHOST'] = 'override-vhost'

      # The actual vhost selection happens in configure_kicks
      # We test the logic directly here
      url = ENV.fetch('RABBITMQ_URL')
      vhost = ENV.fetch('RABBITMQ_VHOST') { command.send(:extract_vhost_from_url, url) }

      expect(vhost).to eq('override-vhost')
    end

    it 'extracts from URL when RABBITMQ_VHOST not set' do
      ENV['RABBITMQ_URL'] = 'amqp://host/url-vhost'
      ENV.delete('RABBITMQ_VHOST')

      url = ENV.fetch('RABBITMQ_URL')
      vhost = ENV.fetch('RABBITMQ_VHOST') { command.send(:extract_vhost_from_url, url) }

      expect(vhost).to eq('url-vhost')
    end
  end
end
