# spec/onetime/initializers/setup_diagnostics_spec.rb
#
# frozen_string_literal: true

require_relative '../../spec_helper'
# Removed ostruct dependency - using Struct instead

# Create top-level Struct definitions to prevent "already initialized constant" warnings
MockConfig = Struct.new(:dsn, :environment, :release, :breadcrumbs_logger,
                       :traces_sample_rate, :profiles_sample_rate, :before_send,
                       keyword_init: true)
EventStruct = Struct.new(:request, keyword_init: true)
RequestStruct = Struct.new(:headers, keyword_init: true)

RSpec.describe "Onetime::Initializers#setup_diagnostics" do
  let(:source_config_path) { File.expand_path(File.join(Onetime::HOME, 'spec', 'config.test.yaml')) }
  let(:loaded_config) { Onetime::Config.load(source_config_path) }
  let(:mock_config) { MockConfig.new }

  before do
    # Reset global state before each test
    Onetime.instance_variable_set(:@conf, nil)
    Onetime.instance_variable_set(:@d9s_enabled, nil)

    # Define a minimal Sentry constant if it doesn't exist to satisfy verify_partial_doubles
    unless defined?(Sentry)
      stub_const('Sentry', Module.new do
        def self.init(&block)
          # Default implementation for stubbing
        end

        def self.initialized?
          false
        end

        def self.close
          nil
        end
      end)
    end

    # Reset the config for each test
    mock_config.dsn = nil
    mock_config.environment = nil
    mock_config.release = nil
    mock_config.breadcrumbs_logger = nil
    mock_config.traces_sample_rate = nil
    mock_config.profiles_sample_rate = nil
    mock_config.before_send = nil

    # Stub Kernel.require to avoid loading the real gem
    allow(Kernel).to receive(:require).and_call_original
    allow(Kernel).to receive(:require).with('sentry-ruby').and_return(true)
    allow(Kernel).to receive(:require).with('stackprof').and_return(true)

    # Stub the Sentry methods we use
    allow(Sentry).to receive(:init) do |&block|
      block.call(mock_config) if block_given?
      true
    end
    allow(Sentry).to receive(:initialized?).and_return(true)
    allow(Sentry).to receive(:close).and_return(nil)
  end

  after do
    # Clean up global state after each test
    Onetime.instance_variable_set(:@d9s_enabled, nil)
  end

  context "when diagnostics are enabled with valid DSN" do
    it "enables diagnostics and initializes Sentry" do
      # Setup config with diagnostics enabled and valid DSN
      config = loaded_config.dup
      config['diagnostics'] = {
        'enabled' => true,
        'sentry' => {
          'backend' => { 'dsn' => "https://example-dsn@sentry.io/12345" },
          'frontend' => { 'dsn' => "https://example-dsn@sentry.io/67890" }
        }
      }
      config['site'] = { 'host' => "test.example.com" }

      # Set expectations - we should require sentry-ruby when enabled with DSN
      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered
      expect(Sentry).to receive(:init).and_yield(mock_config)

      # Execute
      Onetime.instance_variable_set(:@conf, config)
      Onetime.setup_diagnostics

      # Verify
      expect(Onetime.d9s_enabled).to be true
    end
  end

  context "when diagnostics are disabled" do
    it "does not initialize Sentry even with a DSN" do
      config = loaded_config.dup
      config['diagnostics'] = {
        'enabled' => false,
        'sentry' => {
          'backend' => { 'dsn' => "https://example-dsn@sentry.io/12345" },
          'frontend' => { 'dsn' => "https://example-dsn@sentry.io/67890" }
        }
      }

      # Should NOT require sentry
      expect(Kernel).not_to receive(:require).with('sentry-ruby')
      expect(Kernel).not_to receive(:require).with('stackprof')
      expect(Sentry).not_to receive(:init)

      Onetime.instance_variable_set(:@conf, config)
      Onetime.setup_diagnostics

      expect(Onetime.d9s_enabled).to be false
    end
  end

  context "when diagnostics are enabled but DSN is missing" do
    it "disables diagnostics and does not initialize Sentry" do
      config = loaded_config.dup
      config['diagnostics'] = {
        'enabled' => true,
        'sentry' => {
          'backend' => { 'dsn' => nil },
          'frontend' => { 'dsn' => nil }
        }
      }

      # The method should check for DSN before requiring sentry
      expect(Kernel).not_to receive(:require).with('sentry-ruby')
      expect(Kernel).not_to receive(:require).with('stackprof')
      expect(Sentry).not_to receive(:init)

      Onetime.instance_variable_set(:@conf, config)
      Onetime.setup_diagnostics

      expect(Onetime.d9s_enabled).to be false
    end
  end

  context "when site host is missing" do
    it "initializes Sentry with a default host name" do
      config = loaded_config.dup
      config['diagnostics'] = {
        'enabled' => true,
        'sentry' => {
          'backend' => { 'dsn' => "https://example-dsn@sentry.io/12345" }
        }
      }
      config['site'] = {} # No host

      # Should still require sentry since we have a DSN
      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered
      expect(Sentry).to receive(:init).and_yield(mock_config)

      Onetime.instance_variable_set(:@conf, config)
      Onetime.setup_diagnostics

      expect(Onetime.d9s_enabled).to be true
    end
  end

  context "when using the Sentry init block" do
    it "configures Sentry with correct environment and release values" do
      config = loaded_config.dup
      config['diagnostics'] = {
        'enabled' => true,
        'sentry' => {
          'backend' => { 'dsn' => "https://example-dsn@sentry.io/12345" },
          'frontend' => { 'dsn' => nil }
        }
      }
      config['site'] = { 'host' => "test.example.com" }

      # Test the config block passed to Sentry.init
      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered
      expect(Sentry).to receive(:init).and_yield(mock_config)

      # Execute the method under test
      Onetime.instance_variable_set(:@conf, config)
      Onetime.setup_diagnostics

      # Verify the config using our mock config object
      expect(mock_config.dsn).to eq("https://example-dsn@sentry.io/12345")
      expect(mock_config.environment).to include("test.example.com")
      expect(mock_config.environment).to include(OT.env.to_s)
      expect(mock_config.release).to eq(OT::VERSION.inspect)
      expect(mock_config.breadcrumbs_logger).to eq([:sentry_logger])
      expect(mock_config.traces_sample_rate).to eq(0.1)
      expect(mock_config.profiles_sample_rate).to eq(0.1)
      expect(mock_config.before_send).to be_a(Proc)
    end
  end

  context "when testing the before_send hook" do
    it "filters out invalid events" do
      config = loaded_config.dup
      config['diagnostics'] = {
        'enabled' => true,
        'sentry' => {
          'backend' => { 'dsn' => "https://example-dsn@sentry.io/12345" },
          'frontend' => { 'dsn' => nil }
        }
      }
      config['site'] = { 'host' => "test.example.com" }

      before_send_proc = nil

      # Ensure sentry is required first
      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered
      expect(Sentry).to receive(:init).and_yield(mock_config)

      # Execute setup_diagnostics and then examine the before_send hook
      Onetime.instance_variable_set(:@conf, config)
      Onetime.setup_diagnostics

      # Get the before_send proc from our mock config
      before_send_proc = mock_config.before_send

      # Ensure the hook was captured
      expect(before_send_proc).not_to be_nil

      # Test nil event
      expect(before_send_proc.call(nil, {})).to be_nil

      # Test event with nil request
      invalid_event = EventStruct.new(request: nil)
      expect(before_send_proc.call(invalid_event, {})).to be_nil

      # Test event with request but nil headers
      invalid_event2 = EventStruct.new(request: RequestStruct.new(headers: nil))
      expect(before_send_proc.call(invalid_event2, {})).to be_nil

      # Test valid event
      valid_event = EventStruct.new(
        request: RequestStruct.new(
          headers: { "User-Agent" => "test" }
        )
      )
      expect(before_send_proc.call(valid_event, {})).to eq(valid_event)
    end
  end

  # Add the test for integration with boot process
  context "when integrated with Onetime.boot!" do
    before do
      # Reset the state
      Onetime.instance_variable_set(:@conf, nil)
      Onetime.instance_variable_set(:@d9s_enabled, nil)
      Onetime.instance_variable_set(:@mode, :test)
      Onetime.instance_variable_set(:@env, 'test')
    end

    after do
      # Clean up after tests
      Onetime.instance_variable_set(:@d9s_enabled, nil)
    end

    it "properly initializes diagnostics when enabled in config", allow_redis: true do
      modified_config = loaded_config.dup
      modified_config['diagnostics'] = {
        'enabled' => true,
        'sentry' => {
          'backend' => { 'dsn' => "https://example-dsn@sentry.io/12345" },
          'frontend' => { 'dsn' => nil }
        }
      }
      allow(Onetime::Config).to receive(:load).and_return(modified_config)

      # Expect sentry to be required and init to be called
      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered
      expect(Sentry).to receive(:init).and_yield(mock_config)

      # Call boot! which should in turn call setup_diagnostics
      Onetime.boot!(:test)

      expect(Onetime.d9s_enabled).to be true
    end

    it "does not initialize Sentry when diagnostics are disabled in config", allow_redis: true do
      modified_config = loaded_config.dup
      modified_config['diagnostics'] = {
        'enabled' => false,
        'sentry' => {
          'backend' => { 'dsn' => "https://example-dsn@sentry.io/12345" },
          'frontend' => { 'dsn' => nil }
        }
      }
      allow(Onetime::Config).to receive(:load).and_return(modified_config)

      # Should NOT require sentry
      expect(Kernel).not_to receive(:require).with('sentry-ruby')
      expect(Kernel).not_to receive(:require).with('stackprof')
      expect(Sentry).not_to receive(:init)

      # Call boot! which should in turn skip Sentry init
      Onetime.boot!(:test)

      expect(Onetime.d9s_enabled).to be false
    end
  end
end
