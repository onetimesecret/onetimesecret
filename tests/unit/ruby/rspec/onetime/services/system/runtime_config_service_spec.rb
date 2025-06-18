# tests/unit/ruby/rspec/onetime/services/system/runtime_config_service_spec.rb

require_relative '../../../spec_helper'

# Load the service provider system components
require 'onetime/services/system/runtime_config_service'

RSpec.describe 'Service Provider System' do
  let(:registry_klass) { Onetime::Services::ServiceRegistry }
  let(:immutable_config) do
    {
      'site' => {
        'host' => 'localhost:3000',
        'ssl' => false,
        'authentication' => {
          'enabled' => true,
          'colonels' => ['CHANGEME@example.com']
        },
        'middleware' => {
          'static_files' => true,
          'utf8_sanitizer' => true
        }
      },
      'storage' => {
        'db' => {
          'connection' => {
            'url' => 'redis://localhost:6379'
          },
          'database_mapping' => {}
        }
      }
    }
  end
  let(:mutable_config) do
    {
      'user_interface' => {
        'enabled' => true,
        'header' => {
          'enabled' => true,
          'branding' => {
            'logo' => {
              'url' => 'DefaultLogo.vue',
              'alt' => 'Share a Secret One-Time',
              'href' => '/'
            },
            'site_name' => 'My Test Site'
          },
          'navigation' => {
            'enabled' => true
          }
        },
        'footer_links' => {
          'enabled' => false
        }
      }
    }
  end

  before do
    # Clear ServiceRegistry state between tests
    registry_klass.instance_variable_set(:@providers, Concurrent::Map.new)
    registry_klass.instance_variable_set(:@app_state, Concurrent::Map.new)
  end

  describe OT::Services::System::RuntimeConfigService do
    subject(:provider) { described_class.new }

    before do
      allow(OT).to receive(:logger).and_return(double(info: nil, debug: nil, warn: nil))
    end

    describe '#initialize' do
      it 'sets up config provider with high priority' do
        expect(provider.name).to eq(:runtime_config)
        expect(provider.instance_variable_get(:@type)).to eq(:config)
        expect(provider.config).to be_nil()
        expect(provider.priority).to eq(10)
      end
    end

    describe '#start' do
      let(:mock_mutable_settings) { double('MutableSettings') }

      before do
        # Stub registry methods
        allow(registry_klass).to receive(:get_state).with(:runtime_config).and_return(nil)
        allow(registry_klass).to receive(:set_state)

        # Stub MutableSettings
        allow(V2::MutableSettings).to receive(:current).and_return(mock_mutable_settings)
        allow(mock_mutable_settings).to receive(:safe_dump).and_return(mutable_config)
      end

      it 'accepts the config and starts the provider' do
        provider.start(immutable_config)

        # Verify provider stores the static config
        expect(provider.config).to be_a(Hash)
        expect(provider.config['site']).to be_a(Hash)
        expect(provider.config['storage']).to be_a(Hash)
        expect(provider.config).to include('site', 'storage')

        # Verify V2::MutableSettings.current was called to fetch dynamic config
        expect(V2::MutableSettings).to have_received(:current).once
        expect(mock_mutable_settings).to have_received(:safe_dump).once

        # Verify merged config was stored in registry with frozen hash
        expect(registry_klass).to have_received(:set_state).with(:runtime_config, kind_of(Hash)).once

        # Verify the merge process was initiated (registry.get_state called to check existing config)
        expect(registry_klass).to have_received(:get_state).with(:runtime_config)
      end

      it 'handles Redis connection errors gracefully' do
        # Stub MutableSettings.current to raise error
        redis_error = StandardError.new('Redis connection failed')
        allow(V2::MutableSettings).to receive(:current).and_raise(redis_error)

        expect { provider.start(immutable_config) }.not_to raise_error

        # Verify fallback behavior - should still store static config as merged config
        expect(registry_klass).to have_received(:set_state).with(:runtime_config, kind_of(Hash)).once

        # Verify provider still has the static config
        expect(provider.config).to eq(immutable_config)

        # Verify Redis error was attempted but handled gracefully
        expect(V2::MutableSettings).to have_received(:current).once
      end

      it 'exits early if runtime config already exists' do
        # Stub get_state to return existing config
        existing_config = { 'existing' => true, 'user_interface' => { 'enabled' => true } }
        allow(registry_klass).to receive(:get_state).with(:runtime_config).and_return(existing_config)

        provider.start(immutable_config)

        # Should not call MutableSettings or set_state again
        expect(V2::MutableSettings).not_to have_received(:current)
        expect(registry_klass).not_to have_received(:set_state)

        # Should still store the static config in provider
        expect(provider.config).to eq(immutable_config)

        # Should have checked for existing config
        expect(registry_klass).to have_received(:get_state).with(:runtime_config).once
      end

      it 'handles missing MutableSettings gracefully' do
        # Stub MutableSettings.current to raise RecordNotFound
        record_not_found_error = Onetime::RecordNotFound.new('No config stack found')
        allow(V2::MutableSettings).to receive(:current).and_raise(record_not_found_error)

        expect { provider.start(immutable_config) }.not_to raise_error

        # Should still store static config as fallback (no dynamic config to merge)
        expect(registry_klass).to have_received(:set_state).with(:runtime_config, kind_of(Hash)).once

        # Verify provider stores the static config
        expect(provider.config).to eq(immutable_config)

        # Should have attempted to load MutableSettings
        expect(V2::MutableSettings).to have_received(:current).once
      end
    end

    describe '#healthy?' do
      before do
        provider.start_internal(immutable_config)
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
        provider.start_internal(immutable_config)
      end

      it 'reloads configuration' do
        expect(provider).to receive(:start).with(immutable_config)
        provider.reload(immutable_config)
      end
    end
  end

end
