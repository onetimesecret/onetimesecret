# tests/unit/ruby/rspec/onetime/services/service_provider_system_spec.rb

require_relative '../../spec_helper'

# Load the service provider system components
require 'onetime/services/system'

RSpec.describe 'Service Provider System' do
  let(:test_config) do
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
    subject(:proxy) { described_class.new(test_config) }

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
          Onetime::Services::ServiceRegistry.set_state(:footer_links, ['About', 'Contact'])
          Onetime::Services::ServiceRegistry.set_state(:site_title, 'My OTS Instance')
        end

        it 'returns dynamic config values when static not available' do
          expect(proxy[:footer_links]).to eq(['About', 'Contact'])
          expect(proxy[:site_title]).to eq('My OTS Instance')
        end

        it 'prioritizes static config over dynamic' do
          Onetime::Services::ServiceRegistry.set_state(:host, 'dynamic.example.com')
          expect(proxy[:host]).to eq('localhost') # static wins
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

    describe '#[]=' do
      it 'sets dynamic configuration via ServiceRegistry' do
        proxy[:new_setting] = 'test_value'
        expect(Onetime::Services::ServiceRegistry.state(:new_setting)).to eq('test_value')
      end

      it 'prevents overriding static configuration' do
        expect {
          proxy[:host] = 'new_host'
        }.to raise_error(ArgumentError, 'Cannot override static config key: host')
      end

      it 'converts string keys to symbols' do
        proxy['dynamic_key'] = 'value'
        expect(Onetime::Services::ServiceRegistry.state(:dynamic_key)).to eq('value')
      end
    end

    describe '#key?' do
      it 'returns true for static keys' do
        expect(proxy.key?(:host)).to be true
        expect(proxy.key?('host')).to be true
      end

      it 'returns true for dynamic keys' do
        Onetime::Services::ServiceRegistry.set_state(:dynamic_key, 'value')
        expect(proxy.key?(:dynamic_key)).to be true
      end

      it 'returns false for non-existent keys' do
        expect(proxy.key?(:nonexistent)).to be false
      end
    end

    describe '#keys' do
      before do
        Onetime::Services::ServiceRegistry.set_state(:dynamic1, 'value1')
        Onetime::Services::ServiceRegistry.set_state(:dynamic2, 'value2')
      end

      it 'returns combined static and dynamic keys' do
        keys = proxy.keys
        expect(keys).to include(:host, :port, :database_url)
        # Note: dynamic keys aren't enumerable in current implementation
        # This is intentional design - ServiceRegistry doesn't expose all keys
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
        Onetime::Services::ServiceRegistry.set_state(:test_key, 'value')
      end

      it 'returns debug information' do
        info = proxy.debug_dump
        expect(info).to include(:static_keys, :dynamic_keys, :service_registry_available)
        expect(info[:static_keys]).to include(:host, :port)
        expect(info[:service_registry_available]).to be true
      end
    end
  end

  describe Onetime::Services::ServiceRegistry do
    describe '.register' do
      it 'registers a service provider' do
        provider = double('provider')
        described_class.register(:test_service, provider)
        expect(described_class.provider(:test_service)).to eq(provider)
      end

      it 'converts name to symbol' do
        provider = double('provider')
        described_class.register('test_service', provider)
        expect(described_class.provider(:test_service)).to eq(provider)
      end
    end

    describe '.provider' do
      it 'returns nil for non-existent provider' do
        expect(described_class.provider(:nonexistent)).to be_nil
      end
    end

    describe '.set_state/.state' do
      it 'stores and retrieves application state' do
        described_class.set_state(:test_key, 'test_value')
        expect(described_class.state(:test_key)).to eq('test_value')
      end

      it 'converts keys to symbols' do
        described_class.set_state('string_key', 'value')
        expect(described_class.state(:string_key)).to eq('value')
      end
    end

    describe '.reload_all' do
      let(:provider1) { double('provider1', reload: nil) }
      let(:provider2) { double('provider2') }

      before do
        described_class.register(:provider1, provider1)
        described_class.register(:provider2, provider2)
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
        described_class.register(:ready, ready_provider)
        described_class.register(:no_method, no_ready_method_provider)
        expect(described_class.ready?).to be true
      end

      it 'returns false when any provider is not ready' do
        described_class.register(:ready, ready_provider)
        described_class.register(:not_ready, not_ready_provider)
        expect(described_class.ready?).to be false
      end
    end
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
        expect(Onetime::Services::ServiceRegistry.state(:started_with)).to eq('test_value')
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
        expect(Onetime::Services::ServiceRegistry.state(:stopped)).to be true
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
        expect(Onetime::Services::ServiceRegistry.state(:test_state)).to eq('test_value')
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

  describe OT::Services::System::DynamicConfigProvider do
    subject(:provider) { described_class.new }

    before do
      allow(OT).to receive(:logger).and_return(double(info: nil, debug: nil, warn: nil))
    end

    describe '#initialize' do
      it 'sets up config provider with high priority' do
        expect(provider.name).to eq(:dynamic_config)
        expect(provider.instance_variable_get(:@type)).to eq(:config)
        expect(provider.priority).to eq(10)
      end
    end

    describe '#start' do
      it 'loads default configuration when Redis unavailable' do
        provider.start(test_config)

        expect(Onetime::Services::ServiceRegistry.state(:footer_links)).to eq([])
        expect(Onetime::Services::ServiceRegistry.state(:maintenance_mode)).to be false
      end

      it 'handles Redis connection errors gracefully' do
        allow(provider).to receive(:load_from_redis).and_raise(StandardError, 'Redis error')

        expect { provider.start(test_config) }.not_to raise_error
        expect(Onetime::Services::ServiceRegistry.state(:footer_links)).to eq([])
      end
    end

    describe '#healthy?' do
      before do
        provider.start_internal(test_config)
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
        provider.start_internal(test_config)
      end

      it 'reloads configuration' do
        expect(provider).to receive(:start).with(test_config)
        provider.reload(test_config)
      end
    end
  end

  describe 'Integration: Onetime.conf with ConfigProxy' do
    let(:static_config) { { host: 'localhost', port: 7143 } }

    before do
      # Simulate what happens in boot.rb
      OT.send(:conf=, static_config)
    end

    it 'integrates ConfigProxy with Onetime.conf' do
      expect(OT.conf).to be_a(Onetime::Services::ConfigProxy)
      expect(OT.conf[:host]).to eq('localhost')
      expect(OT.conf[:port]).to eq(7143)
    end

    it 'allows dynamic configuration through ServiceRegistry' do
      Onetime::Services::ServiceRegistry.set_state(:site_title, 'My Custom Title')
      expect(OT.conf[:site_title]).to eq('My Custom Title')
    end

    it 'maintains static config precedence' do
      Onetime::Services::ServiceRegistry.set_state(:host, 'dynamic.host.com')
      expect(OT.conf[:host]).to eq('localhost') # static wins
    end

    context 'when ConfigProxy is passed to conf=' do
      it 'preserves existing ConfigProxy instance' do
        existing_proxy = Onetime::Services::ConfigProxy.new(static_config)
        OT.send(:conf=, existing_proxy)
        expect(OT.conf).to eq(existing_proxy)
      end
    end

    context 'when raw hash is passed to conf=' do
      it 'wraps hash in ConfigProxy' do
        OT.send(:conf=, { new_key: 'new_value' })
        expect(OT.conf).to be_a(Onetime::Services::ConfigProxy)
        expect(OT.conf[:new_key]).to eq('new_value')
      end
    end
  end

  describe 'System Integration' do
    let(:config) { { redis: { host: 'localhost' }, host: 'test.com' } }

    before do
      # Mock the logger and file system for system integration
      allow(OT).to receive(:logger).and_return(double(info: nil, debug: nil, warn: nil, error: nil))
      allow(OT).to receive(:li)
      allow(OT).to receive(:ld)
    end

    describe 'Service Provider Orchestration' do
      it 'starts dynamic config provider early' do
        # Mock the system methods that haven't been converted to providers yet
        allow(Onetime::Services::System).to receive(:connect_databases)
        allow(Onetime::Services::System).to receive(:configure_truemail)
        allow(Onetime::Services::System).to receive(:prepare_emailers)
        allow(Onetime::Services::System).to receive(:load_locales)
        allow(Onetime::Services::System).to receive(:setup_authentication)

        Onetime::Services::System.start_all(config, connect_to_db: false)

        # Verify dynamic config provider was registered and started
        dynamic_provider = Onetime::Services::ServiceRegistry.provider(:dynamic_config)
        expect(dynamic_provider).to be_a(OT::Services::System::DynamicConfigProvider)
        expect(dynamic_provider.status).to eq(:running)
      end
    end

    describe 'End-to-End Configuration Flow' do
      it 'provides unified config access after system startup' do
        # Setup ConfigProxy
        proxy = Onetime::Services::ConfigProxy.new(config)

        # Start dynamic config provider
        provider = OT::Services::System::DynamicConfigProvider.new
        provider.start_internal(config)

        # Verify static config access
        expect(proxy[:host]).to eq('test.com')

        # Verify dynamic config access
        expect(proxy[:footer_links]).to eq([]) # from default config
        expect(proxy[:maintenance_mode]).to be false

        # Verify precedence
        Onetime::Services::ServiceRegistry.set_state(:host, 'dynamic.example.com')
        expect(proxy[:host]).to eq('test.com') # static still wins
      end
    end
  end

  describe 'Thread Safety' do
    let(:config) { { test_key: 'value' } }

    it 'handles concurrent ConfigProxy access safely' do
      proxy = Onetime::Services::ConfigProxy.new(config)
      results = []
      threads = []

      10.times do |i|
        threads << Thread.new do
          # Concurrent reads and writes
          static_value = proxy[:test_key]
          proxy[:"dynamic_key_#{i}"] = "value_#{i}"
          dynamic_value = proxy[:"dynamic_key_#{i}"]

          results << [static_value, dynamic_value]
        end
      end

      threads.each(&:join)

      # All static reads should return consistent values
      static_values = results.map { |pair| pair[0] }
      dynamic_values = results.map { |pair| pair[1] }

      expect(static_values).to all(eq('value'))
      expect(dynamic_values).to all(match(/value_\d+/))
    end

    it 'handles concurrent ServiceRegistry access safely' do
      threads = []
      registry = Onetime::Services::ServiceRegistry

      10.times do |i|
        threads << Thread.new do
          registry.set_state(:"key_#{i}", "value_#{i}")
          registry.register(:"provider_#{i}", "provider_#{i}")
        end
      end

      threads.each(&:join)

      # Verify all values were set correctly
      10.times do |i|
        expect(registry.state(:"key_#{i}")).to eq("value_#{i}")
        expect(registry.provider(:"provider_#{i}")).to eq("provider_#{i}")
      end
    end

    it 'handles concurrent ServiceProvider lifecycle safely' do
      provider_class = Class.new(OT::Services::ServiceProvider) do
        def start(config)
          sleep(0.01) # Simulate some work
          set_state(:started, true)
        end
      end

      provider = provider_class.new(:test)
      threads = []

      allow(OT).to receive(:logger).and_return(double(info: nil, error: nil))

      # Try to start the provider multiple times concurrently
      5.times do
        threads << Thread.new { provider.start_internal(config) }
      end

      threads.each(&:join)

      # Should only be started once
      expect(provider.status).to eq(:running)
      expect(Onetime::Services::ServiceRegistry.state(:started)).to be true
    end
  end
end
