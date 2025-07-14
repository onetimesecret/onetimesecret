# tests/unit/ruby/rspec/onetime/services/service_registry_spec.rb

require_relative '../../../spec_helper'

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

  describe Onetime::Services::ServiceRegistry do
    describe '.register' do
      it 'registers a service provider' do
        provider = double('provider')
        described_class.register_provider(:test_service, provider)
        expect(described_class.provider(:test_service)).to eq(provider)
      end

      it 'converts name to symbol' do
        provider = double('provider')
        described_class.register_provider('test_service', provider)
        expect(described_class.provider(:test_service)).to eq(provider)
      end
    end

    describe '.provider' do
      it 'returns nil for non-existent provider' do
        expect(described_class.provider(:nonexistent)).to be_nil
      end
    end

    describe '.set_state/.get_state' do
      it 'stores and retrieves application state' do
        described_class.set_state('test_key', 'test_value')
        expect(described_class.get_state('test_key')).to eq('test_value')
      end

      it 'converts keys to strings' do
        described_class.set_state(:symbol_key, 'value')
        expect(described_class.get_state('symbol_key')).to eq('value')
      end
    end

    describe '.reload_all' do
      let(:provider1) { double('provider1', reload: nil) }
      let(:provider2) { double('provider2') }

      before do
        described_class.register_provider(:provider1, provider1)
        described_class.register_provider(:provider2, provider2)
      end

      it 'calls reload on providers that support it' do
        new_config = { updated: true }
        expect(provider1).to receive(:reload).with(new_config)
        allow(provider2).to receive(:respond_to?).with(:reload).and_return(false)

        described_class.reload_all(new_config)
      end
    end

    describe '.ready?' do
      let(:ready_provider) { double('ready', ready?: true) }
      let(:not_ready_provider) { double('not_ready', ready?: false) }
      let(:no_ready_method_provider) { double('no_method') }

      it 'returns true when all providers are ready' do
        described_class.register_provider(:ready, ready_provider)
        described_class.register_provider(:no_method, no_ready_method_provider)
        expect(described_class.ready?).to be true
      end

      it 'returns false when any provider is not ready' do
        described_class.register_provider(:ready, ready_provider)
        described_class.register_provider(:not_ready, not_ready_provider)
        expect(described_class.ready?).to be false
      end
    end
  end
end
