# tests/unit/ruby/rspec/onetime/initializers/setup_diagnostics_spec.rb

require_relative '../../spec_helper'
require 'ostruct'

RSpec.describe "Onetime::Initializers#setup_diagnostics" do
  let(:source_config_path) { File.expand_path(File.join(Onetime::HOME, 'tests', 'unit', 'ruby', 'config.test.yaml')) }
  let(:loaded_config) { Onetime::Config.load(source_config_path) }

  before do
    # Reset global state before each test
    Onetime.instance_variable_set(:@conf, nil)
    Onetime.instance_variable_set(:@d9s_enabled, nil)

    # Stub Kernel.require for Sentry - implement a dummy version that defines the constants
    allow(Kernel).to receive(:require).and_call_original
    allow(Kernel).to receive(:require).with('sentry-ruby') do
      # Create a mock Sentry module if it doesn't exist
      unless defined?(Sentry)
        module Sentry
          class << self
            attr_reader :last_config
          end

          def self.init(&block)
            # Store the config for testing with all expected properties
            @last_config = OpenStruct.new(
              dsn: nil,
              environment: nil,
              release: nil,
              breadcrumbs_logger: nil,
              traces_sample_rate: nil,
              profiles_sample_rate: nil,
              before_send: nil
            )
            block.call(@last_config) if block_given?
            true
          end

          def self.initialized?
            true
          end

          def self.close
            # Do nothing
          end

          def self.config
            @last_config ||= OpenStruct.new
          end

          # Mock the Breadcrumb module to prevent the error
          module Breadcrumb
            class SentryLogger
              def add_breadcrumb(*args)
                # Do nothing
              end
            end
          end

          # Mock the get_current_hub method
          def self.get_current_hub
            OpenStruct.new
          end
        end
      end
      true
    end
    allow(Kernel).to receive(:require).with('stackprof').and_return(true)
  end

  after do
    # Clean up global state after each test
    Onetime.instance_variable_set(:@d9s_enabled, nil)
  end

  context "when diagnostics are enabled with valid DSN" do
    it "enables diagnostics and initializes Sentry" do
      # Setup config with diagnostics enabled and valid DSN
      config = loaded_config.dup
      config[:diagnostics] = {
        enabled: true,
        sentry: {
          backend: { dsn: "https://example-dsn@sentry.io/12345" },
          frontend: { dsn: "https://example-dsn@sentry.io/67890" }
        }
      }
      config[:site] = { host: "test.example.com" }

      # Set expectations - we should require sentry-ruby when enabled with DSN
      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered

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
      config[:diagnostics] = {
        enabled: false,
        sentry: {
          backend: { dsn: "https://example-dsn@sentry.io/12345" },
          frontend: { dsn: "https://example-dsn@sentry.io/67890" }
        }
      }

      # Should NOT require sentry
      expect(Kernel).not_to receive(:require).with('sentry-ruby')
      expect(Kernel).not_to receive(:require).with('stackprof')

      Onetime.instance_variable_set(:@conf, config)
      Onetime.setup_diagnostics

      expect(Onetime.d9s_enabled).to be false
    end
  end

  context "when diagnostics are enabled but DSN is missing" do
    it "disables diagnostics and does not initialize Sentry" do
      config = loaded_config.dup
      config[:diagnostics] = {
        enabled: true,
        sentry: {
          backend: { dsn: nil },
          frontend: { dsn: nil }
        }
      }

      # The method should check for DSN before requiring sentry
      expect(Kernel).not_to receive(:require).with('sentry-ruby')
      expect(Kernel).not_to receive(:require).with('stackprof')

      Onetime.instance_variable_set(:@conf, config)
      Onetime.setup_diagnostics

      expect(Onetime.d9s_enabled).to be false
    end
  end

  context "when site host is missing" do
    it "initializes Sentry with a default host name" do
      config = loaded_config.dup
      config[:diagnostics] = {
        enabled: true,
        sentry: {
          backend: { dsn: "https://example-dsn@sentry.io/12345" }
        }
      }
      config[:site] = {} # No host

      # Should still require sentry since we have a DSN
      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered

      Onetime.instance_variable_set(:@conf, config)
      Onetime.setup_diagnostics

      expect(Onetime.d9s_enabled).to be true
    end
  end

  context "when using the Sentry init block" do
    it "configures Sentry with correct environment and release values" do
      config = loaded_config.dup
      config[:diagnostics] = {
        enabled: true,
        sentry: {
          backend: { dsn: "https://example-dsn@sentry.io/12345" },
          frontend: { dsn: nil }
        }
      }
      config[:site] = { host: "test.example.com" }

      # Set up test expectations
        # Test the config block passed to Sentry.init
        expect(Kernel).to receive(:require).with('sentry-ruby').ordered
        expect(Kernel).to receive(:require).with('stackprof').ordered

        # Execute the method under test
        Onetime.instance_variable_set(:@conf, config)
        Onetime.setup_diagnostics

        # Verify the config using the Sentry mock's captured config
        actual_config = Sentry.last_config
        expect(actual_config).not_to be_nil
        expect(actual_config.dsn).to eq("https://example-dsn@sentry.io/12345")
        expect(actual_config.environment).to include("test.example.com")
        expect(actual_config.environment).to include(OT.env.to_s)
        expect(actual_config.release).to eq(OT::VERSION.inspect)
        expect(actual_config.breadcrumbs_logger).to eq([:sentry_logger])
        expect(actual_config.traces_sample_rate).to eq(0.1)
        expect(actual_config.profiles_sample_rate).to eq(0.1)
        expect(actual_config.before_send).to be_a(Proc)
    end
  end

  context "when testing the before_send hook" do
    it "filters out invalid events" do
      config = loaded_config.dup
      config[:diagnostics] = {
        enabled: true,
        sentry: {
          backend: { dsn: "https://example-dsn@sentry.io/12345" },
          frontend: { dsn: nil }
        }
      }
      config[:site] = { host: "test.example.com" }

      before_send_proc = nil

      # Ensure sentry is required first
      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered

      # Execute setup_diagnostics and then examine the before_send hook
      Onetime.instance_variable_set(:@conf, config)
      Onetime.setup_diagnostics

      # Get the before_send proc from the Sentry mock
      before_send_proc = Sentry.last_config.before_send

      # Ensure the hook was captured
      expect(before_send_proc).not_to be_nil

      # Test nil event
      expect(before_send_proc.call(nil, {})).to be_nil

      # Test event with nil request
      invalid_event = OpenStruct.new(request: nil)
      expect(before_send_proc.call(invalid_event, {})).to be_nil

      # Test event with request but nil headers
      invalid_event2 = OpenStruct.new(request: OpenStruct.new(headers: nil))
      expect(before_send_proc.call(invalid_event2, {})).to be_nil

      # Test valid event
      valid_event = OpenStruct.new(
        request: OpenStruct.new(
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

    it "properly initializes diagnostics when enabled in config" do
      modified_config = loaded_config.dup
      modified_config[:diagnostics] = {
        enabled: true,
        sentry: {
          backend: { dsn: "https://example-dsn@sentry.io/12345" },
          frontend: { dsn: nil }
        }
      }
      allow(Onetime::Config).to receive(:load).and_return(modified_config)

      # Expect sentry to be required and init to be called
      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered

      # Call boot! which should in turn call setup_diagnostics
      Onetime.boot!(:test)

      expect(Onetime.d9s_enabled).to be true
    end

    it "does not initialize Sentry when diagnostics are disabled in config" do
      modified_config = loaded_config.dup
      modified_config[:diagnostics] = {
        enabled: false,
        sentry: {
          backend: { dsn: "https://example-dsn@sentry.io/12345" },
          frontend: { dsn: nil }
        }
      }
      allow(Onetime::Config).to receive(:load).and_return(modified_config)

      # Should NOT require sentry
      expect(Kernel).not_to receive(:require).with('sentry-ruby')
      expect(Kernel).not_to receive(:require).with('stackprof')

      # Call boot! which should in turn skip Sentry init
      Onetime.boot!(:test)

      expect(Onetime.d9s_enabled).to be false
    end
  end
end
