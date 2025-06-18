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
        expect(dynamic_provider).to be_a(OT::Services::System::RuntimeConfigServiceProvider)
        expect(dynamic_provider.status).to eq(:running)
      end
    end

    describe 'End-to-End Configuration Flow' do
      it 'provides unified config access after system startup' do
        # Setup ConfigProxy
        proxy = Onetime::Services::ConfigProxy.new(config)

        # Start dynamic config provider
        provider = OT::Services::System::RuntimeConfigServiceProvider.new
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
          registry.register_provider(:"provider_#{i}", "provider_#{i}")
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
      expect(Onetime::Services::ServiceRegistry.state[:started]).to be true
    end
  end
end
