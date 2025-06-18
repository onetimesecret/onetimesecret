# tests/unit/ruby/rspec/onetime/services/service_provider_spec.rb

require_relative '../../spec_helper'

# Load the service provider system components
require 'onetime/services/system'

RSpec.describe 'Service Provider System' do
  let(:immutable_config) do
    {
      database_url: 'redis://localhost:6379/0',
      host: 'localhost',
      port: 7143,
      redis: { host: 'localhost', port: 6379 }
    }
  end

  before do
    # Clear ServiceRegistry state between tests
    Onetime::Services::ServiceRegistry.instance_variable_set(:@providers, Concurrent::Map.new)
    Onetime::Services::ServiceRegistry.instance_variable_set(:@app_state, Concurrent::Map.new)
  end

  describe OT::Services::ServiceProvider do
    let(:test_provider_class) do
      Class.new(described_class) do
        def start(config)
          set_state(:started_with, config[:test_key])
        end

        def stop
          set_state(:stopped, true)
        end
      end
    end

    subject(:provider) { test_provider_class.new(:test_provider) }

    describe '#initialize' do
      it 'sets default values' do
        expect(provider.name).to eq(:test_provider)
        expect(provider.status).to eq(:pending)
        expect(provider.priority).to eq(50)
        expect(provider.dependencies).to eq([])
      end

      it 'accepts custom options' do
        custom_provider = test_provider_class.new(
          :custom,
          type: :config,
          dependencies: [:database],
          priority: 10
        )

        expect(custom_provider.name).to eq(:custom)
        expect(custom_provider.instance_variable_get(:@type)).to eq(:config)
        expect(custom_provider.dependencies).to eq([:database])
        expect(custom_provider.priority).to eq(10)
      end
    end

    describe '#start_internal' do
      let(:config) { { test_key: 'test_value' } }

      before do
        # Mock OT.logger to avoid requiring full OT setup
        allow(OT).to receive(:logger).and_return(double(info: nil, error: nil))
      end

      it 'starts the provider successfully' do
        provider.start_internal(config)

        expect(provider.status).to eq(:running)
        expect(provider.config).to eq(config)
        expect(Onetime::Services::ServiceRegistry.state[:started_with]).to eq('test_value')
      end

      it 'handles start errors gracefully' do
        allow(provider).to receive(:start).and_raise(StandardError, 'Test error')

        expect { provider.start_internal(config) }.to raise_error(StandardError, 'Test error')
        expect(provider.status).to eq(:error)
        expect(provider.instance_variable_get(:@error)).to be_a(StandardError)
      end

      it 'prevents double-start' do
        provider.start_internal(config)
        expect(provider).not_to receive(:start)
        provider.start_internal(config) # Second call should be ignored
      end

      it 'is thread-safe' do
        threads = []
        results = []

        5.times do
          threads << Thread.new do
            provider.start_internal(config)
            results << provider.status
          end
        end

        threads.each(&:join)
        expect(results.uniq).to eq([:running])
      end
    end

    describe '#stop_internal' do
      before do
        allow(OT).to receive(:logger).and_return(double(info: nil, error: nil))
        provider.start_internal({ test_key: 'value' })
      end

      it 'stops the provider successfully' do
        provider.stop_internal

        expect(provider.status).to eq(:stopped)
        expect(Onetime::Services::ServiceRegistry.state[:stopped]).to be true
      end

      it 'handles stop errors gracefully' do
        allow(provider).to receive(:stop).and_raise(StandardError, 'Stop error')

        expect { provider.stop_internal }.to raise_error(StandardError, 'Stop error')
        expect(provider.status).to eq(:error)
      end
    end

    describe '#healthy?' do
      before do
        allow(OT).to receive(:logger).and_return(double(info: nil, error: nil))
      end

      it 'returns true when running without errors' do
        provider.start_internal({ test_key: 'value' })
        expect(provider.healthy?).to be true
      end

      it 'returns false when not running' do
        expect(provider.healthy?).to be false
      end

      it 'returns false when in error state' do
        allow(provider).to receive(:start).and_raise(StandardError, 'Error')
        expect { provider.start_internal({}) }.to raise_error(StandardError)
        expect(provider.healthy?).to be false
      end
    end

    describe '#status_info' do
      it 'returns comprehensive status information' do
        info = provider.status_info

        expect(info).to include(
          :name, :type, :status, :dependencies, :priority, :error, :healthy
        )
        expect(info[:name]).to eq(:test_provider)
        expect(info[:healthy]).to be false # not started yet
      end
    end

    describe '#reload' do
      before do
        allow(OT).to receive(:logger).and_return(double(info: nil, error: nil))
        provider.start_internal({ test_key: 'original' })
      end

      it 'stops and restarts with new config' do
        expect(provider).to receive(:stop)
        expect(provider).to receive(:start_internal).with({ test_key: 'new' })

        provider.reload({ test_key: 'new' })
      end
    end

    describe 'abstract methods' do
      let(:abstract_provider) { described_class.new(:abstract) }

      it 'raises NotImplementedError for start method' do
        expect {
          abstract_provider.start({})
        }.to raise_error(NotImplementedError, /must be implemented/)
      end
    end

    describe 'protected helper methods' do
      let(:config) { { test_key: 'value' } }

      before do
        allow(OT).to receive(:logger).and_return(double(info: nil, error: nil))
        provider.start_internal(config)
      end

      it 'provides access to configuration via #conf' do
        expect(provider.send(:conf, :test_key)).to eq('value')
      end

      it 'allows setting state via #set_state' do
        provider.send(:set_state, :test_state, 'test_value')
        expect(Onetime::Services::ServiceRegistry.state[:test_state]).to eq('test_value')
      end

      it 'allows getting state via #get_state' do
        Onetime::Services::ServiceRegistry.set_state(:existing_state, 'existing_value')
        expect(provider.send(:get_state, :existing_state)).to eq('existing_value')
      end

      it 'provides logging via #log' do
        logger = double('logger')
        allow(OT).to receive(:logger).and_return(logger)
        expect(logger).to receive(:info).with('[test_provider] Test message')

        provider.send(:log, :info, 'Test message')
      end
    end
  end
end
