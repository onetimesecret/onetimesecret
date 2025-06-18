# tests/unit/ruby/rspec/onetime/services/system/runtime_config_service_spec.rb

require_relative '../../../spec_helper'

# Load the service provider system components
require 'onetime/services/system/runtime_config_service'

RSpec.describe 'Service Provider System' do
  let(:registry_klass) { Onetime::Services::ServiceRegistry }
  let(:static_config) do
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
  let(:dynamic_config) do
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
        expect(provider.name).to eq(:dynamic_config)
        expect(provider.instance_variable_get(:@type)).to eq(:config)
        expect(provider.config).to be_nil()
        expect(provider.priority).to eq(10)
      end
    end

    describe '#start' do
      it 'accepts the config and starts the provider' do
        provider.start(static_config)
        expect(provider.config).to be_a(Hash)
        expect(provider.config['user_interface']).to be_a(Hash)

        runtime_config = registry_klass.get_state(:runtime_config)
        expect(runtime_config).to be_a(Hash)
        expect(runtime_config['user_interface']).to be_a(Hash)
      end

      it 'handles Redis connection errors gracefully' do
        allow(provider).to receive(:load_from_redis).and_raise(StandardError, 'Redis error')

        expect { provider.start(static_config) }.not_to raise_error
        expect(Onetime::Services::ServiceRegistry.state[:footer_links]).to eq([])
      end
    end

    describe '#healthy?' do
      before do
        provider.start_internal(static_config)
      end

      it 'returns true when provider is running and Redis available' do
        allow(provider).to receive(:redis_available?).and_return(true)
        expect(provider.healthy?).to be true
      end

      it 'returns false when Redis unavailable' do
        allow(provider).to receive(:redis_available?).and_return(false)
        expect(provider.healthy?).to be false
      end
    end

    describe '#reload' do
      before do
        provider.start_internal(static_config)
      end

      it 'reloads configuration' do
        expect(provider).to receive(:start).with(static_config)
        provider.reload(static_config)
      end
    end
  end

end
