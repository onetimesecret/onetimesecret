# tests/unit/ruby/rspec/onetime/initializers/setup_diagnostics_spec.rb

require '../../spec_helper'

describe "Onetime::Initializers#setup_diagnostics" do
  let(:source_config_path) { File.join(SPEC_ROOT, 'config', 'config.test.yaml') }
  let(:loaded_config) { Onetime::Config.load(source_config_path) }

  before do
    # Reset global state before each test
    Onetime.instance_variable_set(:@conf, nil)
    Onetime.instance_variable_set(:@d9s_enabled, nil)

    # Stub Kernel.require for Sentry
    allow(Kernel).to receive(:require).and_call_original
    allow(Kernel).to receive(:require).with('sentry-ruby').and_return(true)
    allow(Kernel).to receive(:require).with('stackprof').and_return(true)

    # Mock Sentry's class methods
    # Ensure Sentry constant is available for mocking
    if defined?(Sentry)
      allow(Sentry).to receive(:init)
      allow(Sentry).to receive(:initialized?).and_return(false)  # Default to not initialized
      allow(Sentry).to receive(:close)
    else
      # If Sentry is not defined (e.g. not in Gemfile for test env or not yet loaded)
      # create a stub for it.
      sentry_stub = class_double("Sentry").as_null_object
      stub_const("Sentry", sentry_stub)
      allow(Sentry).to receive(:init) # ensure it can be called on the stub
      allow(Sentry).to receive(:initialized?).and_return(false)
      allow(Sentry).to receive(:close)
    end
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

      # Set expectations
      allow(Sentry).to receive(:initialized?).and_return(true)
      expect(Sentry).to receive(:init)

      # Execute
      Onetime.conf = config
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

      expect(Sentry).not_to receive(:init)

      Onetime.conf = config
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

      expect(Sentry).not_to receive(:init)

      Onetime.conf = config
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

      expect(Sentry).to receive(:init)

      Onetime.conf = config
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
          backend: { dsn: "https://example-dsn@sentry.io/12345" }
        }
      }
      config[:site] = { host: "test.example.com" }

      # Test the config block passed to Sentry.init
      expect(Sentry).to receive(:init) do |&block|
        sentry_config = OpenStruct.new(
          dsn: nil,
          environment: nil,
          release: nil,
          breadcrumbs_logger: nil,
          traces_sample_rate: nil,
          profiles_sample_rate: nil,
          before_send: nil
        )
        block.call(sentry_config)

        expect(sentry_config.dsn).to eq("https://example-dsn@sentry.io/12345")
        expect(sentry_config.environment).to include("test.example.com")
        expect(sentry_config.environment).to include(OT.env.to_s)
        expect(sentry_config.release).to eq(OT::VERSION.inspect)
        expect(sentry_config.breadcrumbs_logger).to eq([:sentry_logger])
        expect(sentry_config.traces_sample_rate).to eq(0.1)
        expect(sentry_config.profiles_sample_rate).to eq(0.1)
        expect(sentry_config.before_send).to be_a(Proc)
      end

      Onetime.conf = config
      Onetime.setup_diagnostics
    end
  end

  context "when testing the before_send hook" do
    it "filters out invalid events" do
      config = loaded_config.dup
      config[:diagnostics] = {
        enabled: true,
        sentry: {
          backend: { dsn: "https://example-dsn@sentry.io/12345" }
        }
      }
      config[:site] = { host: "test.example.com" }

      before_send_proc = nil

      expect(Sentry).to receive(:init) do |&block|
        sentry_config = OpenStruct.new
        block.call(sentry_config)
        before_send_proc = sentry_config.before_send
      end

      Onetime.conf = config
      Onetime.setup_diagnostics

      # Test nil event
      expect(before_send_proc.call(nil, {})).to be_nil

      # Test event with nil request
      invalid_event = OpenStruct.new(request: nil)
      expect(before_send_proc.call(invalid_event, {})).to be_nil

      # Test valid event
      valid_event = OpenStruct.new(
        request: OpenStruct.new(
          headers: { "User-Agent" => "test" }
        )
      )
      expect(before_send_proc.call(valid_event, {})).to eq(valid_event)
    end
  end
end
