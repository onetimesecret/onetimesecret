# spec/unit/onetime/initializers/setup_diagnostics_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Create top-level Struct definitions to prevent "already initialized constant" warnings
MockConfig = Struct.new(:dsn, :environment, :release, :breadcrumbs_logger,
                       :traces_sample_rate, :profiles_sample_rate, :before_send,
                       :org_id, :strict_trace_continuation,
                       keyword_init: true) unless defined?(MockConfig)
EventStruct = Struct.new(:request, :contexts, keyword_init: true) unless defined?(EventStruct)
RequestStruct = Struct.new(:headers, :url, keyword_init: true) unless defined?(RequestStruct)

RSpec.describe Onetime::Initializers::SetupDiagnostics do
  let(:source_config_path) { File.expand_path(File.join(Onetime::HOME, 'spec', 'config.test.yaml')) }
  let(:loaded_config) { Onetime::Config.load(source_config_path) }
  let(:mock_config) { MockConfig.new }
  let(:captured_tags) { {} }
  let(:original_infrastructure) { Onetime::Runtime.infrastructure }

  # Helper to execute the initializer with given config
  def execute_diagnostics_initializer
    initializer = described_class.new
    initializer.execute({})
  end

  before do
    # Reset global state before each test
    Onetime.instance_variable_set(:@conf, nil)

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

        def self.set_tags(tags)
          # Default implementation for stubbing
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
    mock_config.org_id = nil
    mock_config.strict_trace_continuation = nil

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
    allow(Sentry).to receive(:set_tags) do |tags|
      captured_tags.merge!(tags)
    end
  end

  after do
    # Restore original infrastructure state
    Onetime::Runtime.infrastructure = original_infrastructure
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
      execute_diagnostics_initializer

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
      execute_diagnostics_initializer

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
      execute_diagnostics_initializer

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
      execute_diagnostics_initializer

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
      execute_diagnostics_initializer

      # Verify the config using our mock config object
      expect(mock_config.dsn).to eq("https://example-dsn@sentry.io/12345")
      expect(mock_config.environment).to eq(OT.env)
      # Release follows priority: ENV['SENTRY_RELEASE'] > .commit_hash.txt > OT::VERSION.details
      # In test environment, .commit_hash.txt typically exists with the commit hash
      expect(mock_config.release).to be_a(String)
      expect(mock_config.release).not_to be_empty
      expect(mock_config.breadcrumbs_logger).to eq([:sentry_logger])
      expect(mock_config.traces_sample_rate).to eq(0.1)
      expect(mock_config.profiles_sample_rate).to eq(0.1)
      expect(mock_config.before_send).to be_a(Proc)
    end

    it "enables strict_trace_continuation and sets org_id when org_id is configured" do
      config = loaded_config.dup
      config['diagnostics'] = {
        'enabled' => true,
        'sentry' => {
          'org_id' => 'test-org-123',
          'backend' => { 'dsn' => "https://example-dsn@sentry.io/12345" },
          'frontend' => { 'dsn' => nil }
        }
      }
      config['site'] = { 'host' => "test.example.com" }

      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered
      expect(Sentry).to receive(:init).and_yield(mock_config)

      Onetime.instance_variable_set(:@conf, config)
      execute_diagnostics_initializer

      expect(mock_config.org_id).to eq('test-org-123')
      expect(mock_config.strict_trace_continuation).to eq(true)
    end

    it "leaves strict_trace_continuation off and org_id nil when org_id is not configured" do
      config = loaded_config.dup
      config['diagnostics'] = {
        'enabled' => true,
        'sentry' => {
          'backend' => { 'dsn' => "https://example-dsn@sentry.io/12345" },
          'frontend' => { 'dsn' => nil }
        }
      }
      config['site'] = { 'host' => "test.example.com" }

      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered
      expect(Sentry).to receive(:init).and_yield(mock_config)

      Onetime.instance_variable_set(:@conf, config)
      execute_diagnostics_initializer

      expect(mock_config.org_id).to be_nil
      expect(mock_config.strict_trace_continuation).to eq(false)
    end
  end

  context "when configuring Sentry tags" do
    it "sets site_host tag from configuration" do
      config = loaded_config.dup
      config['diagnostics'] = {
        'enabled' => true,
        'sentry' => {
          'backend' => { 'dsn' => "https://example-dsn@sentry.io/12345" }
        }
      }
      config['site'] = { 'host' => "prod.example.com" }

      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered
      expect(Sentry).to receive(:init).and_yield(mock_config)

      Onetime.instance_variable_set(:@conf, config)
      execute_diagnostics_initializer

      expect(captured_tags).to include(site_host: "prod.example.com")
    end

    it "sets jurisdiction tag as lowercase" do
      config = loaded_config.dup
      config['diagnostics'] = {
        'enabled' => true,
        'sentry' => {
          'backend' => { 'dsn' => "https://example-dsn@sentry.io/12345" }
        }
      }
      config['site'] = { 'host' => "eu.example.com" }
      config['features'] = {
        'regions' => {
          'current_jurisdiction' => 'EU'
        }
      }

      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered
      expect(Sentry).to receive(:init).and_yield(mock_config)

      Onetime.instance_variable_set(:@conf, config)
      execute_diagnostics_initializer

      expect(captured_tags).to include(jurisdiction: "eu")
    end

    it "normalizes mixed-case jurisdiction to lowercase" do
      config = loaded_config.dup
      config['diagnostics'] = {
        'enabled' => true,
        'sentry' => {
          'backend' => { 'dsn' => "https://example-dsn@sentry.io/12345" }
        }
      }
      config['site'] = { 'host' => "us.example.com" }
      config['features'] = {
        'regions' => {
          'current_jurisdiction' => 'Us'  # Mixed case: capital U, lowercase s
        }
      }

      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered
      expect(Sentry).to receive(:init).and_yield(mock_config)

      Onetime.instance_variable_set(:@conf, config)
      execute_diagnostics_initializer

      expect(captured_tags).to include(jurisdiction: "us")
    end

    it "omits jurisdiction tag when not configured" do
      config = loaded_config.dup
      config['diagnostics'] = {
        'enabled' => true,
        'sentry' => {
          'backend' => { 'dsn' => "https://example-dsn@sentry.io/12345" }
        }
      }
      config['site'] = { 'host' => "test.example.com" }
      # Explicitly set nil jurisdiction to override test config default
      config['features'] = {
        'regions' => {
          'current_jurisdiction' => nil
        }
      }

      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered
      expect(Sentry).to receive(:init).and_yield(mock_config)

      Onetime.instance_variable_set(:@conf, config)
      execute_diagnostics_initializer

      expect(captured_tags).to include(site_host: "test.example.com")
      expect(captured_tags).not_to have_key(:jurisdiction)
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

      # Execute and then examine the before_send hook
      Onetime.instance_variable_set(:@conf, config)
      execute_diagnostics_initializer

      # Get the before_send proc from our mock config
      before_send_proc = mock_config.before_send

      # Ensure the hook was captured
      expect(before_send_proc).not_to be_nil

      # Test nil event
      expect(before_send_proc.call(nil, {})).to be_nil

      # Test event with nil request - should pass through for background jobs/CLI
      event_nil_request = EventStruct.new(request: nil)
      expect(before_send_proc.call(event_nil_request, {})).to eq(event_nil_request)

      # Test event with request but nil headers - should pass through
      # (background jobs and non-HTTP contexts may have nil headers)
      event_nil_headers = EventStruct.new(
        request: RequestStruct.new(headers: nil, url: 'https://example.com/api/status'),
        contexts: {}
      )
      result = before_send_proc.call(event_nil_headers, {})
      expect(result).not_to be_nil
      expect(result.request.url).to eq('https://example.com/api/status')

      # Test valid event with headers
      valid_event = EventStruct.new(
        request: RequestStruct.new(
          headers: { "User-Agent" => "test" },
          url: 'https://example.com/api/status'
        ),
        contexts: {}
      )
      expect(before_send_proc.call(valid_event, {})).to eq(valid_event)
    end
  end

  # NOTE: Full boot! integration tests are skipped because boot! requires a complete,
  # valid config with all keys properly initialized. Testing individual initializers
  # via execute() is more reliable and still validates the core functionality.
  # The boot! process is tested in boot_part2_spec.rb with proper setup.

  # Tests for SENTRY_RELEASE environment variable override (GitHub #2971)
  # When SENTRY_RELEASE is set (e.g., by CI), it should be used instead of
  # OT::VERSION.details to ensure frontend and backend report the same release.
  describe "SENTRY_RELEASE environment variable override" do
    before do
      # Store original env value to restore later
      @original_sentry_release = ENV.fetch('SENTRY_RELEASE', nil)
    end

    after do
      # Restore original env value
      if @original_sentry_release.nil?
        ENV.delete('SENTRY_RELEASE')
      else
        ENV['SENTRY_RELEASE'] = @original_sentry_release
      end
    end

    def setup_diagnostics_config
      config = loaded_config.dup
      config['diagnostics'] = {
        'enabled' => true,
        'sentry' => {
          'backend' => { 'dsn' => "https://example-dsn@sentry.io/12345" },
          'frontend' => { 'dsn' => nil }
        }
      }
      config['site'] = { 'host' => "test.example.com" }
      Onetime.instance_variable_set(:@conf, config)
    end

    it "uses SENTRY_RELEASE env var when set" do
      ENV['SENTRY_RELEASE'] = 'abc1234'
      setup_diagnostics_config

      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered
      expect(Sentry).to receive(:init).and_yield(mock_config)

      execute_diagnostics_initializer

      expect(mock_config.release).to eq('abc1234')
    end

    it "uses OT::VERSION.get_build_info when SENTRY_RELEASE is not set" do
      ENV.delete('SENTRY_RELEASE')
      allow(OT::VERSION).to receive(:get_build_info).and_return('abc1234')
      setup_diagnostics_config

      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered
      expect(Sentry).to receive(:init).and_yield(mock_config)

      execute_diagnostics_initializer

      expect(mock_config.release).to eq('abc1234')
    end

    it "uses OT::VERSION.get_build_info when SENTRY_RELEASE is empty string" do
      ENV['SENTRY_RELEASE'] = ''
      allow(OT::VERSION).to receive(:get_build_info).and_return('def5678')
      setup_diagnostics_config

      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered
      expect(Sentry).to receive(:init).and_yield(mock_config)

      execute_diagnostics_initializer

      expect(mock_config.release).to eq('def5678')
    end

    it "uses OT::VERSION.get_build_info when SENTRY_RELEASE is whitespace only" do
      ENV['SENTRY_RELEASE'] = '   '
      allow(OT::VERSION).to receive(:get_build_info).and_return('ghi9012')
      setup_diagnostics_config

      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered
      expect(Sentry).to receive(:init).and_yield(mock_config)

      execute_diagnostics_initializer

      expect(mock_config.release).to eq('ghi9012')
    end

    it "trims whitespace from SENTRY_RELEASE value" do
      ENV['SENTRY_RELEASE'] = '  def5678  '
      setup_diagnostics_config

      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered
      expect(Sentry).to receive(:init).and_yield(mock_config)

      execute_diagnostics_initializer

      expect(mock_config.release).to eq('def5678')
    end

    it "accepts version-style SENTRY_RELEASE values" do
      ENV['SENTRY_RELEASE'] = 'v0.24.2'
      setup_diagnostics_config

      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered
      expect(Sentry).to receive(:init).and_yield(mock_config)

      execute_diagnostics_initializer

      expect(mock_config.release).to eq('v0.24.2')
    end

    it "accepts commit hash style SENTRY_RELEASE values" do
      ENV['SENTRY_RELEASE'] = 'a1b2c3d'
      setup_diagnostics_config

      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered
      expect(Sentry).to receive(:init).and_yield(mock_config)

      execute_diagnostics_initializer

      expect(mock_config.release).to eq('a1b2c3d')
    end

    context "with OT::VERSION.get_build_info fallback" do
      before do
        ENV.delete('SENTRY_RELEASE')
      end

      it "uses OT::VERSION.get_build_info when SENTRY_RELEASE env var is not set" do
        allow(OT::VERSION).to receive(:get_build_info).and_return('abc1234')
        setup_diagnostics_config

        expect(Kernel).to receive(:require).with('sentry-ruby').ordered
        expect(Kernel).to receive(:require).with('stackprof').ordered
        expect(Sentry).to receive(:init).and_yield(mock_config)

        execute_diagnostics_initializer

        expect(mock_config.release).to eq('abc1234')
      end

      it "falls back to 'dev' when no commit hash is available" do
        allow(OT::VERSION).to receive(:get_build_info).and_return('dev')
        setup_diagnostics_config

        expect(Kernel).to receive(:require).with('sentry-ruby').ordered
        expect(Kernel).to receive(:require).with('stackprof').ordered
        expect(Sentry).to receive(:init).and_yield(mock_config)

        execute_diagnostics_initializer

        expect(mock_config.release).to eq('dev')
      end

      it "SENTRY_RELEASE env var takes precedence over get_build_info" do
        ENV['SENTRY_RELEASE'] = 'env-override'
        # Should not be called when env var is set
        expect(OT::VERSION).not_to receive(:get_build_info)
        setup_diagnostics_config

        expect(Kernel).to receive(:require).with('sentry-ruby').ordered
        expect(Kernel).to receive(:require).with('stackprof').ordered
        expect(Sentry).to receive(:init).and_yield(mock_config)

        execute_diagnostics_initializer

        expect(mock_config.release).to eq('env-override')
      end
    end
  end

  # Tests for execution_mode-aware DSN selection (GitHub #2973)
  # Workers and schedulers can use a separate Sentry DSN to isolate
  # background job errors from web/CLI errors.
  describe "execution_mode-aware DSN selection" do
    let(:backend_dsn) { "https://backend-dsn@sentry.io/12345" }
    let(:workers_dsn) { "https://workers-dsn@sentry.io/67890" }

    before do
      # Stub Kernel.require to avoid loading the real gem
      allow(Kernel).to receive(:require).and_call_original
      allow(Kernel).to receive(:require).with('sentry-ruby').and_return(true)
      allow(Kernel).to receive(:require).with('stackprof').and_return(true)
    end

    def setup_config_with_workers_dsn(workers_dsn_value)
      config = loaded_config.dup
      config['diagnostics'] = {
        'enabled' => true,
        'sentry' => {
          'backend' => { 'dsn' => backend_dsn },
          'workers' => { 'dsn' => workers_dsn_value },
          'frontend' => { 'dsn' => nil }
        }
      }
      config['site'] = { 'host' => "test.example.com" }
      config['features'] = { 'regions' => { 'current_jurisdiction' => 'US' } }
      Onetime.instance_variable_set(:@conf, config)
    end

    context "when OT.execution_mode is :worker" do
      before do
        skip "Awaiting OT.execution_mode implementation" unless OT.respond_to?(:execution_mode)
      end

      it "uses workers DSN when workers DSN is configured" do
        setup_config_with_workers_dsn(workers_dsn)
        allow(OT).to receive(:execution_mode).and_return(:worker)

        expect(Sentry).to receive(:init).and_yield(mock_config)
        execute_diagnostics_initializer

        expect(mock_config.dsn).to eq(workers_dsn)
      end

      it "falls back to backend DSN when workers DSN is nil" do
        setup_config_with_workers_dsn(nil)
        allow(OT).to receive(:execution_mode).and_return(:worker)

        expect(Sentry).to receive(:init).and_yield(mock_config)
        execute_diagnostics_initializer

        expect(mock_config.dsn).to eq(backend_dsn)
      end

      it "falls back to backend DSN when workers DSN is empty string" do
        setup_config_with_workers_dsn("")
        allow(OT).to receive(:execution_mode).and_return(:worker)

        expect(Sentry).to receive(:init).and_yield(mock_config)
        execute_diagnostics_initializer

        expect(mock_config.dsn).to eq(backend_dsn)
      end

      it "falls back to backend DSN when workers DSN is whitespace only" do
        setup_config_with_workers_dsn("   ")
        allow(OT).to receive(:execution_mode).and_return(:worker)

        expect(Sentry).to receive(:init).and_yield(mock_config)
        execute_diagnostics_initializer

        expect(mock_config.dsn).to eq(backend_dsn)
      end
    end

    context "when OT.execution_mode is :scheduler" do
      before do
        skip "Awaiting OT.execution_mode implementation" unless OT.respond_to?(:execution_mode)
      end

      it "uses workers DSN when workers DSN is configured" do
        setup_config_with_workers_dsn(workers_dsn)
        allow(OT).to receive(:execution_mode).and_return(:scheduler)

        expect(Sentry).to receive(:init).and_yield(mock_config)
        execute_diagnostics_initializer

        expect(mock_config.dsn).to eq(workers_dsn)
      end

      it "falls back to backend DSN when workers DSN is not configured" do
        setup_config_with_workers_dsn(nil)
        allow(OT).to receive(:execution_mode).and_return(:scheduler)

        expect(Sentry).to receive(:init).and_yield(mock_config)
        execute_diagnostics_initializer

        expect(mock_config.dsn).to eq(backend_dsn)
      end
    end

    context "when OT.execution_mode is :web" do
      before do
        skip "Awaiting OT.execution_mode implementation" unless OT.respond_to?(:execution_mode)
      end

      it "uses backend DSN even when workers DSN is configured" do
        setup_config_with_workers_dsn(workers_dsn)
        allow(OT).to receive(:execution_mode).and_return(:web)

        expect(Sentry).to receive(:init).and_yield(mock_config)
        execute_diagnostics_initializer

        expect(mock_config.dsn).to eq(backend_dsn)
      end
    end

    context "when OT.execution_mode is :cli" do
      before do
        skip "Awaiting OT.execution_mode implementation" unless OT.respond_to?(:execution_mode)
      end

      it "uses backend DSN even when workers DSN is configured" do
        setup_config_with_workers_dsn(workers_dsn)
        allow(OT).to receive(:execution_mode).and_return(:cli)

        expect(Sentry).to receive(:init).and_yield(mock_config)
        execute_diagnostics_initializer

        expect(mock_config.dsn).to eq(backend_dsn)
      end
    end

    context "when OT.execution_mode is not defined" do
      it "uses backend DSN by default" do
        # This tests backward compatibility when execution_mode is not implemented
        setup_config_with_workers_dsn(workers_dsn)

        # Do not stub execution_mode - let it use default behavior
        expect(Sentry).to receive(:init).and_yield(mock_config)
        execute_diagnostics_initializer

        expect(mock_config.dsn).to eq(backend_dsn)
      end
    end

    context "release version and jurisdiction tags" do
      before do
        skip "Awaiting OT.execution_mode implementation" unless OT.respond_to?(:execution_mode)
      end

      it "sets same release version regardless of execution mode" do
        setup_config_with_workers_dsn(workers_dsn)
        allow(OT).to receive(:execution_mode).and_return(:worker)

        expect(Sentry).to receive(:init).and_yield(mock_config)
        execute_diagnostics_initializer

        # Release follows priority: ENV['SENTRY_RELEASE'] > .commit_hash.txt > OT::VERSION.details
        expect(mock_config.release).to be_a(String)
        expect(mock_config.release).not_to be_empty
      end

      it "sets same jurisdiction tag regardless of execution mode" do
        setup_config_with_workers_dsn(workers_dsn)
        allow(OT).to receive(:execution_mode).and_return(:scheduler)

        expect(Sentry).to receive(:init).and_yield(mock_config)
        execute_diagnostics_initializer

        expect(captured_tags).to include(jurisdiction: "us")
      end

      it "sets same site_host tag regardless of execution mode" do
        setup_config_with_workers_dsn(workers_dsn)
        allow(OT).to receive(:execution_mode).and_return(:worker)

        expect(Sentry).to receive(:init).and_yield(mock_config)
        execute_diagnostics_initializer

        expect(captured_tags).to include(site_host: "test.example.com")
      end
    end

    # Tests for service tag based on execution mode (GitHub #2964, #2970)
    # Service tags enable filtering by entry point in Sentry.
    context "service tag based on execution mode" do
      before do
        skip "Awaiting OT.execution_mode implementation" unless OT.respond_to?(:execution_mode)
      end

      it "sets service tag to 'worker' for :worker execution mode" do
        setup_config_with_workers_dsn(workers_dsn)
        allow(OT).to receive(:execution_mode).and_return(:worker)

        expect(Sentry).to receive(:init).and_yield(mock_config)
        execute_diagnostics_initializer

        expect(captured_tags).to include(service: 'worker')
      end

      it "sets service tag to 'worker' for :scheduler execution mode" do
        setup_config_with_workers_dsn(workers_dsn)
        allow(OT).to receive(:execution_mode).and_return(:scheduler)

        expect(Sentry).to receive(:init).and_yield(mock_config)
        execute_diagnostics_initializer

        expect(captured_tags).to include(service: 'worker')
      end

      it "sets service tag to 'web' for :backend execution mode" do
        setup_config_with_workers_dsn(workers_dsn)
        allow(OT).to receive(:execution_mode).and_return(:backend)

        expect(Sentry).to receive(:init).and_yield(mock_config)
        execute_diagnostics_initializer

        expect(captured_tags).to include(service: 'web')
      end

      it "sets service tag to 'web' for :cli execution mode" do
        setup_config_with_workers_dsn(workers_dsn)
        allow(OT).to receive(:execution_mode).and_return(:cli)

        expect(Sentry).to receive(:init).and_yield(mock_config)
        execute_diagnostics_initializer

        expect(captured_tags).to include(service: 'web')
      end
    end
  end
end
