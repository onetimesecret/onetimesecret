# tests/unit/ruby/rspec/onetime/services/system/runtime_config_service_spec.rb

require_relative '../../../../spec_helper'
require_relative '../../../../support/service_provider_context'

# Load the service provider system components
require 'onetime/services/system/runtime_config_service'

RSpec.describe 'Service Provider System' do
  include_context "service_provider_context"
  include_context "service_provider_registry_stubs"
  include_context "mutable_config_stubs"

  describe OT::Services::System::RuntimeConfigService do
    subject(:provider) { described_class.new }



    describe '#initialize' do
      it 'sets up config provider with high priority' do
        expect(provider.name).to eq(:runtime_config)
        expect(provider.instance_variable_get(:@type)).to eq(:config)
        expect(provider.config).to be_nil()
        expect(provider.priority).to eq(10)
      end
    end

    describe '#start' do
      before do
        # Stub registry methods specifically for runtime_config
        allow(registry_klass).to receive(:get_state).with(:runtime_config).and_return(nil)
        allow(mock_mutable_config).to receive(:safe_dump).and_return(runtime_mutable_config)
      end

      it 'accepts the config and starts the provider' do
        provider.start(base_service_config)

        # Verify provider stores the static config
        expect(provider.config).to be_a(Hash)
        expect(provider.config['site']).to be_a(Hash)
        expect(provider.config['storage']).to be_a(Hash)
        expect(provider.config).to include('site', 'storage')

        # Verify V2::MutableConfig.current was called to fetch dynamic config
        expect(V2::MutableConfig).to have_received(:current).once
        expect(mock_mutable_config).to have_received(:safe_dump).once

        # Verify merged config was stored in registry with frozen hash
        expect(registry_klass).to have_received(:set_state).with(:runtime_config, kind_of(Hash)).once

        # Verify the merge process was initiated (registry.get_state called to check existing config)
        expect(registry_klass).to have_received(:get_state).with(:runtime_config)
      end

      it 'handles Redis connection errors gracefully' do
        # Stub MutableConfig.current to raise error
        redis_error = StandardError.new('Redis connection failed')
        allow(V2::MutableConfig).to receive(:current).and_raise(redis_error)

        expect { provider.start(base_service_config) }.not_to raise_error

        # Verify fallback behavior - should still store static config as merged config
        expect(registry_klass).to have_received(:set_state).with(:runtime_config, kind_of(Hash)).once

        # Verify provider still has the static config
        expect(provider.config).to eq(base_service_config)

        # Verify Redis error was attempted but handled gracefully
        expect(V2::MutableConfig).to have_received(:current).once
      end

      it 'exits early if runtime config already exists' do
        # Stub get_state to return existing config
        existing_config = { 'existing' => true, 'user_interface' => { 'enabled' => true } }
        allow(registry_klass).to receive(:get_state).with(:runtime_config).and_return(existing_config)

        provider.start(base_service_config)

        # Should not call MutableConfig or set_state again
        expect(V2::MutableConfig).not_to have_received(:current)
        expect(registry_klass).not_to have_received(:set_state)

        # Should still store the static config in provider
        expect(provider.config).to eq(base_service_config)

        # Should have checked for existing config
        expect(registry_klass).to have_received(:get_state).with(:runtime_config).once
      end

      it 'handles missing MutableConfig gracefully' do
        # Stub MutableConfig.current to raise RecordNotFound
        record_not_found_error = Onetime::RecordNotFound.new('No config stack found')
        allow(V2::MutableConfig).to receive(:current).and_raise(record_not_found_error)

        expect { provider.start(base_service_config) }.not_to raise_error

        # Should still store static config as fallback (no dynamic config to merge)
        expect(registry_klass).to have_received(:set_state).with(:runtime_config, kind_of(Hash)).once

        # Verify provider stores the static config
        expect(provider.config).to eq(base_service_config)

        # Should have attempted to load MutableConfig
        expect(V2::MutableConfig).to have_received(:current).once
      end
    end

    describe '#healthy?' do
      before do
        provider.start_internal(base_service_config)
      end

      it 'returns true when provider is running and Redis available' do
        allow(provider).to receive(:redis_available?).and_return(true)

        result = provider.healthy?

        expect(result).to be true
        expect(provider).to have_received(:redis_available?).once
      end

      it 'returns false when Redis unavailable' do
        allow(provider).to receive(:redis_available?).and_return(false)

        result = provider.healthy?

        expect(result).to be false
        expect(provider).to have_received(:redis_available?).once
      end

      it 'returns false when provider is not running' do
        # Don't start the provider - it should be unhealthy
        unstarted_provider = described_class.new

        result = unstarted_provider.healthy?

        expect(result).to be false
      end
    end

    describe '#reload' do
      before do
        provider.start_internal(base_service_config)
      end

      it 'reloads configuration' do
        expect(provider).to receive(:start).with(base_service_config)
        provider.reload(base_service_config)
      end
    end
  end

end
