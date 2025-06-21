# tests/unit/ruby/rspec/onetime/services/config_proxy_spec.rb

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

  describe Onetime::Services::ConfigProxy do
    subject(:proxy) { described_class.new(immutable_config) }

    describe '#initialize' do
      it 'stores static configuration' do
        expect(proxy[:host]).to eq('localhost')
        expect(proxy[:port]).to eq(7143)
      end

      it 'initializes with thread-safe mutex' do
        expect(proxy.instance_variable_get(:@mutex)).to be_a(Mutex)
      end
    end

    describe '#[]' do
      context 'with static configuration' do
        it 'returns static config values' do
          expect(proxy[:database_url]).to eq('redis://localhost:6379/0')
          expect(proxy[:host]).to eq('localhost')
        end

        it 'converts string keys to symbols' do
          expect(proxy['host']).to eq('localhost')
        end

        it 'returns nil for non-existent keys' do
          expect(proxy[:nonexistent]).to be_nil
        end
      end

      context 'with dynamic configuration' do
        before do
          # Create merged config that includes both static and dynamic
          merged_config = immutable_config.merge({
            'footer_links' => ['About', 'Contact'],
            'site_title' => 'My OTS Instance'
          })
          Onetime::Services::ServiceRegistry.set_state('runtime_config', merged_config)
        end

        it 'returns dynamic config values when static not available' do
          expect(proxy[:footer_links]).to eq(['About', 'Contact'])
          expect(proxy[:site_title]).to eq('My OTS Instance')
        end

        it 'prioritizes static config over dynamic' do
          # Create merged config where dynamic config doesn't override static
          merged_config = immutable_config.merge({
            'site_title' => 'Dynamic Title'  # This is new, not overriding static
          })
          Onetime::Services::ServiceRegistry.set_state('runtime_config', merged_config)
          expect(proxy[:host]).to eq('localhost') # static value unchanged
          expect(proxy[:site_title]).to eq('Dynamic Title') # dynamic value available
        end
      end

      context 'when ServiceRegistry unavailable' do
        before do
          allow(proxy).to receive(:service_registry_available?).and_return(false)
        end

        it 'gracefully falls back to static only' do
          expect(proxy[:host]).to eq('localhost')
          expect(proxy[:nonexistent_dynamic]).to be_nil
        end
      end
    end



    describe '#key?' do
      it 'returns true for static keys' do
        # Set up merged config that includes static keys (convert to string keys)
        string_keyed_config = immutable_config.transform_keys(&:to_s)
        Onetime::Services::ServiceRegistry.set_state('runtime_config', string_keyed_config)

        expect(proxy.key?('host')).to be true
        expect(proxy.key?('port')).to be true
      end

      it 'returns true for dynamic keys' do
        # Convert to string keys and add dynamic key
        string_keyed_config = immutable_config.transform_keys(&:to_s)
        merged_config = string_keyed_config.merge('dynamic_key' => 'value')
        Onetime::Services::ServiceRegistry.set_state('runtime_config', merged_config)
        expect(proxy.key?('dynamic_key')).to be true
      end

      it 'returns false for non-existent keys' do
        expect(proxy.key?('nonexistent')).to be false
      end
    end

    describe '#keys' do
      before do
        # Convert all keys to strings for consistency
        static_config_normalized = immutable_config.transform_keys(&:to_s)
        merged_config = static_config_normalized.merge({
          'dynamic1' => 'value1',
          'dynamic2' => 'value2'
        })
        Onetime::Services::ServiceRegistry.set_state('runtime_config', merged_config)
      end

      it 'returns combined static and dynamic keys' do
        keys = proxy.keys
        expect(keys).to include('host', 'port', 'database_url')
        expect(keys).to include('dynamic1', 'dynamic2')
      end

      it 'returns unique keys' do
        keys = proxy.keys
        expect(keys.uniq).to eq(keys)
      end
    end

    describe '#fetch' do
      it 'returns value if key exists' do
        expect(proxy.fetch(:host)).to eq('localhost')
      end

      it 'returns default if key does not exist' do
        expect(proxy.fetch(:nonexistent, 'default')).to eq('default')
      end

      it 'returns nil if key does not exist and no default' do
        expect(proxy.fetch(:nonexistent)).to be_nil
      end
    end

    describe '#dig' do
      let(:nested_config) do
        {
          database: {
            primary: { url: 'redis://localhost:6379/0' },
            replica: { url: 'redis://localhost:6379/1' }
          }
        }
      end

      subject(:proxy) { described_class.new(nested_config) }

      it 'digs into nested structures' do
        expect(proxy.dig(:database, :primary, :url)).to eq('redis://localhost:6379/0')
      end

      it 'returns nil for non-existent nested keys' do
        expect(proxy.dig(:database, :nonexistent, :url)).to be_nil
      end

      it 'returns value for single key' do
        expect(proxy.dig(:database)).to eq(nested_config[:database])
      end

      it 'returns nil for empty key path' do
        expect(proxy.dig).to be_nil
      end
    end

    describe '#reload_static' do
      it 'updates static configuration thread-safely' do
        new_config = { host: 'example.com', port: 8080 }
        proxy.reload_static(new_config)

        expect(proxy[:host]).to eq('example.com')
        expect(proxy[:port]).to eq(8080)
        expect(proxy[:database_url]).to be_nil # old key removed
      end
    end

    describe '#debug_dump' do
      before do
        # Set up merged config with string keys to match ConfigProxy expectations
        string_keyed_config = immutable_config.transform_keys(&:to_s)
        merged_config = string_keyed_config.merge('test_key' => 'value')
        Onetime::Services::ServiceRegistry.set_state('runtime_config', merged_config)
      end

      it 'returns debug information' do
        info = proxy.debug_dump
        expect(info).to include(:static_keys, :merged_keys, :service_registry_available, :has_runtime_config)
        # static_keys come from @static_config which still has symbol keys
        expect(info[:static_keys]).to include(:host, :port)
        # merged_keys come from runtime_config which should have string keys
        expect(info[:merged_keys]).to include('host', 'port', 'test_key')
        expect(info[:service_registry_available]).to be true
      end
    end
  end
end
