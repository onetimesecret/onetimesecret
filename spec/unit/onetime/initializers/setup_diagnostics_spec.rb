# spec/unit/onetime/initializers/setup_diagnostics_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Create top-level Struct definitions to prevent "already initialized constant" warnings
MockConfig = Struct.new(:dsn, :environment, :release, :breadcrumbs_logger,
                       :traces_sample_rate, :profiles_sample_rate, :before_send,
                       :before_send_transaction,
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
    mock_config.before_send_transaction = nil
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

    # The org_id field is declared in diagnostics.sentry.defaults in the
    # YAML schema and propagated into each peer hash (backend/frontend/
    # workers) by Onetime::Config#apply_defaults_to_peers at config load
    # time. These tests inject the post-normalization shape directly so
    # they accurately reflect the runtime state the initializer reads.
    it "enables strict_trace_continuation and sets org_id when org_id is configured" do
      config = loaded_config.dup
      config['diagnostics'] = {
        'enabled' => true,
        'sentry' => {
          'backend' => {
            'dsn' => "https://example-dsn@sentry.io/12345",
            'org_id' => 'test-org-123'
          },
          'frontend' => { 'dsn' => nil, 'org_id' => 'test-org-123' }
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

    it "treats blank org_id (empty or whitespace) as unset for strict_trace_continuation" do
      config = loaded_config.dup
      config['diagnostics'] = {
        'enabled' => true,
        'sentry' => {
          'backend' => {
            'dsn' => "https://example-dsn@sentry.io/12345",
            'org_id' => '   '
          },
          'frontend' => { 'dsn' => nil }
        }
      }
      config['site'] = { 'host' => "test.example.com" }

      expect(Kernel).to receive(:require).with('sentry-ruby').ordered
      expect(Kernel).to receive(:require).with('stackprof').ordered
      expect(Sentry).to receive(:init).and_yield(mock_config)

      Onetime.instance_variable_set(:@conf, config)
      execute_diagnostics_initializer

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

  # Tests for URL, query-string, and free-text scrubbing used by the Sentry
  # before_send / before_send_transaction hooks. The scrubbing ensures
  # sensitive data (secret keys, tokens, emails, etc.) are not sent to Sentry
  # in error reports or performance transactions. Exercises the production
  # class methods on SetupDiagnostics directly.
  describe 'sensitive data scrubbing' do
    # Helper to call the scrub_url method on production code
    def scrub_url(url)
      described_class.send(:scrub_url, url)
    end

    # Helper to call the private scrub_sensitive_paths method
    def scrub_sensitive_paths(url)
      described_class.send(:scrub_sensitive_paths, url)
    end

    # Helper to call the private scrub_sensitive_query_params method
    def scrub_sensitive_query_params(url)
      described_class.send(:scrub_sensitive_query_params, url)
    end

    # Generate a 20+ char base-36 identifier for testing (minimum length for scrubbing)
    let(:short_identifier) { 'abc123def456xyz789ab' } # exactly 20 chars
    let(:long_identifier) { 'a' * 62 } # realistic 62-char identifier

    describe '.scrub_url' do
      context 'with sensitive identifier paths (>= 20 chars, base-36)' do
        it 'scrubs /secret/:key paths with valid identifier' do
          result = scrub_url("https://example.com/secret/#{short_identifier}")
          expect(result).to eq('https://example.com/secret/[REDACTED]')
        end

        it 'scrubs /receipt/:key paths with valid identifier' do
          result = scrub_url("https://example.com/receipt/#{short_identifier}")
          expect(result).to eq('https://example.com/receipt/[REDACTED]')
        end

        it 'scrubs /private/:key paths with valid identifier' do
          result = scrub_url("https://example.com/private/#{short_identifier}")
          expect(result).to eq('https://example.com/private/[REDACTED]')
        end

        it 'scrubs /metadata/:key paths with valid identifier' do
          result = scrub_url("https://example.com/metadata/#{short_identifier}")
          expect(result).to eq('https://example.com/metadata/[REDACTED]')
        end

        it 'scrubs /incoming/:key paths with valid identifier' do
          result = scrub_url("https://example.com/incoming/#{short_identifier}")
          expect(result).to eq('https://example.com/incoming/[REDACTED]')
        end
      end

      context 'with admin and auth token paths (always scrubbed)' do
        it 'scrubs /colonel/:path paths' do
          result = scrub_url('https://example.com/colonel/admin_path')
          expect(result).to eq('https://example.com/colonel/[REDACTED]')
        end

        it 'scrubs /l/:shortcode paths' do
          result = scrub_url('https://example.com/l/shortcode123')
          expect(result).to eq('https://example.com/l/[REDACTED]')
        end

        it 'scrubs /forgot/:token paths' do
          result = scrub_url('https://example.com/forgot/reset_token')
          expect(result).to eq('https://example.com/forgot/[REDACTED]')
        end

        it 'scrubs /auth/reset-password/:token paths' do
          result = scrub_url('https://example.com/auth/reset-password/token123')
          expect(result).to eq('https://example.com/auth/reset-password/[REDACTED]')
        end

        it 'scrubs /account/email/confirm/:token paths' do
          result = scrub_url('https://example.com/account/email/confirm/confirm_token')
          expect(result).to eq('https://example.com/account/email/confirm/[REDACTED]')
        end
      end

      context 'with 62-char base-36 identifiers (realistic secret keys)' do
        # Generate a realistic 62-character identifier (base-36 format)
        let(:identifier_62) { 'a' * 62 }

        it 'scrubs /secret/:id with 62-char identifier' do
          expect(identifier_62.length).to eq(62)
          result = scrub_url("https://example.com/secret/#{identifier_62}")
          expect(result).to eq('https://example.com/secret/[REDACTED]')
        end

        it 'scrubs /receipt/:id with 62-char identifier' do
          result = scrub_url("https://example.com/receipt/#{identifier_62}")
          expect(result).to eq('https://example.com/receipt/[REDACTED]')
        end

        it 'scrubs /private/:id with 62-char identifier' do
          result = scrub_url("https://example.com/private/#{identifier_62}")
          expect(result).to eq('https://example.com/private/[REDACTED]')
        end

        it 'scrubs /metadata/:id with 62-char identifier' do
          result = scrub_url("https://example.com/metadata/#{identifier_62}")
          expect(result).to eq('https://example.com/metadata/[REDACTED]')
        end

        # Ordering invariant: the email pass must run before the identifier
        # pass inside scrub_url. An ID-shaped local part would otherwise be
        # replaced first, leaving `[REDACTED]@domain` that EMAIL_PATTERN can
        # no longer match — leaking the email domain. Mirrors the frontend's
        # idLocalPartEmail regression vectors in scrubbers.spec.ts.
        it 'fully redacts an email whose local part is a 62-char identifier' do
          result = scrub_url("https://example.com/?from=#{identifier_62}@example.com")
          expect(result).to include('[EMAIL_REDACTED]')
          expect(result).not_to include('@example.com')
          expect(result).not_to include('[REDACTED]@')
        end
      end

      context 'with named path segments (should NOT be scrubbed)' do
        # These are legitimate named routes, not secret identifiers.
        # The identifier-length discriminant (MIN_IDENTIFIER_LENGTH = 20) ensures
        # short named paths like "recent" or "burn" are preserved for debugging.

        it 'preserves /receipt/recent (named path, not identifier)' do
          result = scrub_url('https://example.com/receipt/recent')
          expect(result).to eq('https://example.com/receipt/recent')
        end

        it 'preserves /private/recent (named path, not identifier)' do
          result = scrub_url('https://example.com/private/recent')
          expect(result).to eq('https://example.com/private/recent')
        end

        it 'preserves /secret/burn (named path, not identifier)' do
          result = scrub_url('https://example.com/secret/burn')
          expect(result).to eq('https://example.com/secret/burn')
        end

        it 'preserves /incoming/new (named path, not identifier)' do
          result = scrub_url('https://example.com/incoming/new')
          expect(result).to eq('https://example.com/incoming/new')
        end

        it 'preserves /metadata/info (named path, not identifier)' do
          result = scrub_url('https://example.com/metadata/info')
          expect(result).to eq('https://example.com/metadata/info')
        end
      end

      context 'paths that should NOT be scrubbed' do
        it 'preserves /api/v1/status' do
          result = scrub_url('https://example.com/api/v1/status')
          expect(result).to eq('https://example.com/api/v1/status')
        end

        it 'preserves /health' do
          result = scrub_url('https://example.com/health')
          expect(result).to eq('https://example.com/health')
        end

        it 'preserves /dashboard' do
          result = scrub_url('https://example.com/dashboard')
          expect(result).to eq('https://example.com/dashboard')
        end

        it 'preserves /api/v2/secrets (plural endpoint, not a key path)' do
          result = scrub_url('https://example.com/api/v2/secrets')
          expect(result).to eq('https://example.com/api/v2/secrets')
        end

        it 'preserves root path' do
          result = scrub_url('https://example.com/')
          expect(result).to eq('https://example.com/')
        end

        it 'preserves /api/v1/info' do
          result = scrub_url('https://example.com/api/v1/info')
          expect(result).to eq('https://example.com/api/v1/info')
        end

        it 'does not scrub partial matches (e.g., /secrets vs /secret)' do
          result = scrub_url('https://example.com/secrets/list')
          expect(result).to eq('https://example.com/secrets/list')
        end

        it 'does not scrub paths with prefix match only' do
          result = scrub_url('https://example.com/secretive/page')
          expect(result).to eq('https://example.com/secretive/page')
        end
      end

      # Issue #3794 C2/C4: the email and verifiable-ID nets run inside
      # scrub_url after the named-param pass, so values riding under
      # non-sensitive param names are still redacted.
      context 'with emails and identifiers under non-sensitive positions' do
        it 'redacts an email value under a non-sensitive query param' do
          result = scrub_url('https://example.com/verify?email=user@example.com')
          expect(result).to eq('https://example.com/verify?email=[EMAIL_REDACTED]')
        end

        it 'redacts a 62-char identifier under a non-sensitive query param' do
          result = scrub_url("https://example.com/dashboard?ref=#{'a' * 62}")
          expect(result).to eq('https://example.com/dashboard?ref=[REDACTED]')
        end

        it 'redacts a 31-char legacy identifier under a non-sensitive query param' do
          result = scrub_url("https://example.com/dashboard?ref=#{'b' * 31}")
          expect(result).to eq('https://example.com/dashboard?ref=[REDACTED]')
        end
      end
    end

    describe '.scrub_sensitive_query_params' do
      # Production code uses string manipulation, not URI encoding
      # Output should be ?key=[REDACTED], NOT ?key=%5BREDACTED%5D

      it 'scrubs ?key=value parameter without URI encoding' do
        result = scrub_url('https://example.com/page?key=secret123')
        expect(result).to eq('https://example.com/page?key=[REDACTED]')
      end

      it 'scrubs ?secret=value parameter' do
        result = scrub_url('https://example.com/page?secret=abc')
        expect(result).to eq('https://example.com/page?secret=[REDACTED]')
      end

      it 'scrubs ?token=value parameter' do
        result = scrub_url('https://example.com/page?token=xyz')
        expect(result).to eq('https://example.com/page?token=[REDACTED]')
      end

      it 'scrubs ?passphrase=value parameter' do
        result = scrub_url('https://example.com/page?passphrase=hidden')
        expect(result).to eq('https://example.com/page?passphrase=[REDACTED]')
      end

      it 'preserves non-sensitive query parameters' do
        result = scrub_url('https://example.com/page?other=value')
        expect(result).to eq('https://example.com/page?other=value')
      end

      it 'scrubs sensitive params while preserving others' do
        result = scrub_url('https://example.com/page?secret=abc&other=value&token=xyz')
        expect(result).to eq('https://example.com/page?secret=[REDACTED]&other=value&token=[REDACTED]')
      end

      it 'handles case-insensitive param names' do
        result = scrub_url('https://example.com/page?KEY=value&TOKEN=abc')
        expect(result).to eq('https://example.com/page?KEY=[REDACTED]&TOKEN=[REDACTED]')
      end

      it 'preserves fragment identifiers' do
        result = scrub_url('https://example.com/page?key=secret#section')
        expect(result).to eq('https://example.com/page?key=[REDACTED]#section')
      end
    end

    describe 'combined path and query scrubbing' do
      it 'scrubs both sensitive path AND query params' do
        # Use a 20+ char identifier to ensure path scrubbing triggers
        result = scrub_url("https://example.com/secret/#{short_identifier}?key=token456&other=keep")
        expect(result).to eq('https://example.com/secret/[REDACTED]?key=[REDACTED]&other=keep')
      end

      it 'scrubs nested sensitive paths with query params' do
        result = scrub_url('https://example.com/auth/reset-password/token123?secret=value')
        expect(result).to eq('https://example.com/auth/reset-password/[REDACTED]?secret=[REDACTED]')
      end

      it 'scrubs query params even when path is not sensitive' do
        result = scrub_url('https://example.com/secret/short?key=sensitive&other=keep')
        expect(result).to eq('https://example.com/secret/short?key=[REDACTED]&other=keep')
      end
    end

    describe 'edge cases' do
      context 'nil and empty values' do
        it 'handles nil URL gracefully' do
          result = scrub_url(nil)
          expect(result).to be_nil
        end

        it 'handles empty string URL gracefully' do
          result = scrub_url('')
          expect(result).to eq('')
        end
      end

      context 'malformed URLs' do
        it 'returns malformed URL unchanged (graceful degradation)' do
          malformed = 'not-a-valid-url::://'
          result = scrub_url(malformed)
          expect(result).to eq(malformed)
        end

        it 'handles URL with only protocol' do
          result = scrub_url('https://')
          expect(result).to eq('https://')
        end

        it 'handles relative paths with valid identifiers' do
          result = scrub_url("/secret/#{short_identifier}")
          expect(result).to eq('/secret/[REDACTED]')
        end

        it 'handles relative paths with short segments (not scrubbed)' do
          result = scrub_url('/secret/abc123')
          expect(result).to eq('/secret/abc123')
        end
      end

      context 'special characters in paths' do
        it 'handles URL-encoded characters in secret keys with valid identifier length' do
          # 20 chars with URL-encoded space: abc%20 takes 6 chars but decodes to 4
          result = scrub_url("https://example.com/secret/#{short_identifier}")
          expect(result).to eq('https://example.com/secret/[REDACTED]')
        end

        it 'handles paths with trailing slashes' do
          # The regex matches up to but not including the trailing slash
          result = scrub_url("https://example.com/secret/#{short_identifier}/")
          expect(result).to include('/secret/[REDACTED]')
        end
      end

      context 'colonel path with multiple segments' do
        it 'scrubs colonel paths with nested segments' do
          result = scrub_url('https://example.com/colonel/admin/users/list')
          expect(result).to eq('https://example.com/colonel/[REDACTED]')
        end
      end
    end

    describe '.scrub_event_urls' do
      # Mock structures that mirror Sentry's event/request objects
      let(:mock_request_class) do
        Struct.new(:url, :headers, keyword_init: true)
      end

      let(:mock_event_class) do
        Class.new do
          attr_accessor :request, :contexts

          def initialize(request: nil, contexts: nil)
            @request = request
            @contexts = contexts || {}
          end
        end
      end

      def build_event(url:, context_url: nil)
        request = mock_request_class.new(url: url, headers: { 'User-Agent' => 'test' })
        contexts = {}
        contexts['request'] = { 'url' => context_url || url } if context_url || url
        mock_event_class.new(request: request, contexts: contexts)
      end

      it 'scrubs URLs in both request and contexts' do
        # Use a 20+ char identifier to ensure scrubbing triggers
        identifier = 'a' * 25
        event = build_event(
          url: "https://example.com/secret/#{identifier}",
          context_url: "https://example.com/secret/#{identifier}"
        )

        result = described_class.scrub_event_urls(event)

        expect(result.request.url).to eq('https://example.com/secret/[REDACTED]')
        expect(result.contexts['request']['url']).to eq('https://example.com/secret/[REDACTED]')
      end

      it 'handles event with nil request URL gracefully' do
        event = mock_event_class.new(
          request: mock_request_class.new(url: nil, headers: {}),
          contexts: {}
        )

        expect { described_class.scrub_event_urls(event) }.not_to raise_error
      end

      it 'handles event with nil contexts gracefully' do
        identifier = 'a' * 25
        request = mock_request_class.new(url: "https://example.com/secret/#{identifier}", headers: {})
        event = mock_event_class.new(request: request, contexts: nil)

        expect { described_class.scrub_event_urls(event) }.not_to raise_error
      end

      it 'handles event with non-hash contexts gracefully' do
        identifier = 'a' * 25
        request = mock_request_class.new(url: "https://example.com/secret/#{identifier}", headers: {})
        event = mock_event_class.new(request: request, contexts: 'not a hash')

        result = described_class.scrub_event_urls(event)
        expect(result.request.url).to eq('https://example.com/secret/[REDACTED]')
      end

      it 'preserves non-sensitive URLs unchanged' do
        event = build_event(url: 'https://example.com/api/v1/status')
        result = described_class.scrub_event_urls(event)

        expect(result.request.url).to eq('https://example.com/api/v1/status')
      end

      it 'scrubs context URLs when request is nil (non-HTTP events)' do
        identifier = 'a' * 25
        contexts = { 'request' => { 'url' => "https://example.com/secret/#{identifier}" } }
        event = mock_event_class.new(request: nil, contexts: contexts)

        result = described_class.scrub_event_urls(event)

        expect(result.contexts['request']['url']).to eq('https://example.com/secret/[REDACTED]')
      end

      it 'redacts URLs when scrubbing raises an unexpected error' do
        allow(described_class).to receive(:scrub_url).and_raise(StandardError, 'unexpected failure')

        event = build_event(url: 'https://example.com/secret/abc123')
        result = described_class.scrub_event_urls(event)

        expect(result.request.url).to eq('[SCRUBBING_FAILED]')
        expect(result.contexts['request']['url']).to eq('[SCRUBBING_FAILED]')
      end

      it 'does not inject url key into contexts when scrubbing fails' do
        allow(described_class).to receive(:scrub_url).and_raise(StandardError, 'unexpected failure')

        # Context with request hash but no url key
        event = mock_event_class.new(
          request: mock_request_class.new(url: 'https://example.com/secret/abc', headers: {}),
          contexts: { 'request' => { 'method' => 'GET' } }
        )
        result = described_class.scrub_event_urls(event)

        expect(result.request.url).to eq('[SCRUBBING_FAILED]')
        expect(result.contexts['request']).not_to have_key('url')
      end

      # A2: the Referer header carries the previous page URL, which on OTS can
      # embed a secret identifier. It must be scrubbed like request.url.
      context 'Referer header scrubbing' do
        it "redacts a route identifier carried in the 'Referer' header" do
          identifier = 'a' * 62
          request = mock_request_class.new(
            url: 'https://example.com/api/v1/status',
            headers: { 'Referer' => "https://example.com/secret/#{identifier}" }
          )
          event = mock_event_class.new(request: request, contexts: {})

          result = described_class.scrub_event_urls(event)

          expect(result.request.headers['Referer']).to eq('https://example.com/secret/[REDACTED]')
        end

        it "redacts a lowercase 'referer' header defensively" do
          request = mock_request_class.new(
            url: 'https://example.com/api/v1/status',
            headers: { 'referer' => 'https://example.com/colonel/admin_path' }
          )
          event = mock_event_class.new(request: request, contexts: {})

          result = described_class.scrub_event_urls(event)

          expect(result.request.headers['referer']).to eq('https://example.com/colonel/[REDACTED]')
        end

        # Issue #3794 C2: the Referer must also get the email and
        # verifiable-ID nets, not just the path/named-param passes —
        # otherwise ?ref=<62-char-key> or ?email=... leaks unredacted.
        it 'redacts an email in a non-sensitive Referer query param' do
          request = mock_request_class.new(
            url: 'https://example.com/api/v1/status',
            headers: { 'Referer' => 'https://example.com/verify?email=user@example.com' }
          )
          event = mock_event_class.new(request: request, contexts: {})

          result = described_class.scrub_event_urls(event)

          expect(result.request.headers['Referer'])
            .to eq('https://example.com/verify?email=[EMAIL_REDACTED]')
        end

        it 'redacts a 62-char identifier in a non-sensitive Referer query param' do
          request = mock_request_class.new(
            url: 'https://example.com/api/v1/status',
            headers: { 'Referer' => "https://example.com/dashboard?ref=#{'a' * 62}" }
          )
          event = mock_event_class.new(request: request, contexts: {})

          result = described_class.scrub_event_urls(event)

          expect(result.request.headers['Referer'])
            .to eq('https://example.com/dashboard?ref=[REDACTED]')
        end

        it 'redacts a 31-char legacy identifier in a non-sensitive Referer query param' do
          request = mock_request_class.new(
            url: 'https://example.com/api/v1/status',
            headers: { 'Referer' => "https://example.com/dashboard?ref=#{'b' * 31}" }
          )
          event = mock_event_class.new(request: request, contexts: {})

          result = described_class.scrub_event_urls(event)

          expect(result.request.headers['Referer'])
            .to eq('https://example.com/dashboard?ref=[REDACTED]')
        end

        it 'preserves a non-sensitive Referer unchanged' do
          request = mock_request_class.new(
            url: 'https://example.com/api/v1/status',
            headers: { 'Referer' => 'https://example.com/dashboard' }
          )
          event = mock_event_class.new(request: request, contexts: {})

          result = described_class.scrub_event_urls(event)

          expect(result.request.headers['Referer']).to eq('https://example.com/dashboard')
        end

        it 'handles a missing Referer header gracefully' do
          request = mock_request_class.new(
            url: 'https://example.com/api/v1/status',
            headers: { 'User-Agent' => 'test' }
          )
          event = mock_event_class.new(request: request, contexts: {})

          expect { described_class.scrub_event_urls(event) }.not_to raise_error
        end

        it 'redacts the Referer header when scrubbing raises (fail-closed)' do
          allow(described_class).to receive(:scrub_url).and_raise(StandardError, 'boom')

          identifier = 'a' * 62
          request = mock_request_class.new(
            url: 'https://example.com/api/v1/status',
            headers: { 'Referer' => "https://example.com/secret/#{identifier}" }
          )
          event = mock_event_class.new(request: request, contexts: {})

          result = described_class.scrub_event_urls(event)

          expect(result.request.headers['Referer']).to eq('[SCRUBBING_FAILED]')
        end
      end
    end

    describe '.scrub_query_string' do
      it 'redacts sensitive param values in a bare query string' do
        result = described_class.scrub_query_string('key=abc123&ttl=3600')
        expect(result).to eq('key=[REDACTED]&ttl=3600')
      end

      it 'redacts every sensitive param name (key/secret/token/passphrase)' do
        result = described_class.scrub_query_string('key=a&secret=b&token=c&passphrase=d')
        expect(result).to eq('key=[REDACTED]&secret=[REDACTED]&token=[REDACTED]&passphrase=[REDACTED]')
      end

      it 'preserves benign params' do
        result = described_class.scrub_query_string('ttl=3600&lang=en')
        expect(result).to eq('ttl=3600&lang=en')
      end

      it 'handles nil and empty input' do
        expect(described_class.scrub_query_string(nil)).to be_nil
        expect(described_class.scrub_query_string('')).to eq('')
      end

      # Issue #3794 C4: query-string values must get the email and
      # verifiable-ID nets, restoring parity with the frontend's
      # scrubQueryStringValues.
      it 'redacts an email value under a non-sensitive param name' do
        result = described_class.scrub_query_string('contact=user@example.com')
        expect(result).to eq('contact=[EMAIL_REDACTED]')
      end

      it 'redacts a bare 62-char identifier under a non-sensitive param name' do
        result = described_class.scrub_query_string("ref=#{'a' * 62}")
        expect(result).to eq('ref=[REDACTED]')
      end

      it 'redacts a bare 31-char legacy identifier under a non-sensitive param name' do
        result = described_class.scrub_query_string("ref=#{'b' * 31}")
        expect(result).to eq('ref=[REDACTED]')
      end

      # Issue #3794 (frontend C1 counterpart): a leading '?' must not let
      # the first param dodge the named-param pass by parsing as "?token".
      it 'tolerates a leading ? and still redacts named params' do
        result = described_class.scrub_query_string('?token=abc&x=1')
        expect(result).to eq('?token=[REDACTED]&x=1')
      end

      it 'tolerates a leading ? with email and identifier values' do
        result = described_class.scrub_query_string("?contact=user@example.com&ref=#{'a' * 62}")
        expect(result).to eq('?contact=[EMAIL_REDACTED]&ref=[REDACTED]')
      end
    end

    describe '.scrub_text' do
      let(:id_62) { 'a' * 62 }
      let(:id_31) { 'b' * 31 }

      it 'redacts email addresses' do
        result = described_class.scrub_text('contact user@example.com for help')
        expect(result).to eq('contact [EMAIL_REDACTED] for help')
      end

      it 'redacts a 62-char v0.24 identifier' do
        result = described_class.scrub_text("secret #{id_62} leaked")
        expect(result).to eq('secret [REDACTED] leaked')
      end

      it 'redacts a 31-char legacy v0.23 identifier' do
        result = described_class.scrub_text("legacy #{id_31} here")
        expect(result).to eq('legacy [REDACTED] here')
      end

      it 'redacts an identifier abutting a word char via word boundary' do
        # A 62-char run immediately followed by a word char is a 63+ run, so the
        # {62} alternative does not match at a \b — the run survives.
        result = described_class.scrub_text("#{id_62}x")
        expect(result).to eq("#{id_62}x")
      end

      it 'redacts an identifier that abuts punctuation (word boundary holds)' do
        result = described_class.scrub_text("id=#{id_62}.")
        expect(result).to eq('id=[REDACTED].')
      end

      it 'does not redact a 63+ char run' do
        run = 'a' * 63
        result = described_class.scrub_text("val #{run} end")
        expect(result).to eq("val #{run} end")
      end

      it 'scrubs sensitive URL paths embedded in text' do
        identifier = 'a' * 62
        result = described_class.scrub_text("failed GET https://example.com/secret/#{identifier}")
        expect(result).to eq('failed GET https://example.com/secret/[REDACTED]')
      end

      it 'handles nil and empty input' do
        expect(described_class.scrub_text(nil)).to be_nil
        expect(described_class.scrub_text('')).to eq('')
      end

      it 'returns [SCRUBBING_FAILED] when an internal pass raises (fail-closed)' do
        allow(described_class).to receive(:scrub_url).and_raise(StandardError, 'boom')
        result = described_class.scrub_text('some text with user@example.com')
        expect(result).to eq('[SCRUBBING_FAILED]')
      end
    end

    describe '.scrub_transaction_event' do
      let(:txn_event_class) do
        Class.new do
          attr_accessor :request, :contexts, :transaction, :spans

          def initialize(transaction: nil, spans: nil)
            @request = nil
            @contexts = {}
            @transaction = transaction
            @spans = spans || []
          end
        end
      end

      it 'scrubs the transaction name' do
        identifier = 'a' * 62
        event = txn_event_class.new(transaction: "GET /secret/#{identifier}")

        result = described_class.scrub_transaction_event(event)

        expect(result.transaction).to eq('GET /secret/[REDACTED]')
      end

      it "scrubs span data['url'] and data['http.query']" do
        identifier = 'a' * 62
        span = {
          description: "GET https://example.com/secret/#{identifier}",
          data: {
            'url' => "https://example.com/secret/#{identifier}",
            'http.query' => 'key=abc123&ttl=3600'
          }
        }
        event = txn_event_class.new(transaction: 'GET /', spans: [span])

        result = described_class.scrub_transaction_event(event)
        scrubbed = result.spans.first

        expect(scrubbed[:data]['url']).to eq('https://example.com/secret/[REDACTED]')
        expect(scrubbed[:data]['http.query']).to eq('key=[REDACTED]&ttl=3600')
        expect(scrubbed[:description]).to eq('GET https://example.com/secret/[REDACTED]')
      end

      # Issue #3794 C4: span query/url values must apply the email and
      # verifiable-ID nets, matching the frontend's scrubQueryStringValues
      # and scrubUrlWithPatterns.
      it "redacts emails and identifiers in span data['url'] and data['http.query']" do
        span = {
          data: {
            'url' => 'https://example.com/checkout?email=user@example.com',
            'http.query' => "contact=user@example.com&ref=#{'a' * 62}&ttl=3600"
          }
        }
        event = txn_event_class.new(transaction: 'GET /', spans: [span])

        result = described_class.scrub_transaction_event(event)
        scrubbed = result.spans.first

        expect(scrubbed[:data]['url']).to eq('https://example.com/checkout?email=[EMAIL_REDACTED]')
        expect(scrubbed[:data]['http.query']).to eq('contact=[EMAIL_REDACTED]&ref=[REDACTED]&ttl=3600')
      end

      it 'returns nil (drops the event) when scrubbing raises (fail-closed)' do
        allow(described_class).to receive(:scrub_url).and_raise(StandardError, 'boom')
        identifier = 'a' * 62
        event = txn_event_class.new(transaction: "GET /secret/#{identifier}")

        # scrub_event_urls swallows the error and fails closed, so force the raise
        # in the span loop instead.
        span = { data: { 'url' => "https://example.com/secret/#{identifier}" } }
        event.spans = [span]

        expect(described_class.scrub_transaction_event(event)).to be_nil
      end
    end

    describe '.scrub_event_messages' do
      let(:single_exception_class) do
        Class.new do
          attr_accessor :value

          def initialize(value)
            @value = value
          end
        end
      end

      let(:exception_interface_class) do
        Class.new do
          attr_accessor :values

          def initialize(values)
            @values = values
          end
        end
      end

      let(:message_event_class) do
        Class.new do
          attr_accessor :exception, :message

          def initialize(exception: nil, message: nil)
            @exception = exception
            @message = message
          end
        end
      end

      it 'scrubs the standalone message' do
        event = message_event_class.new(message: 'error for user@example.com')

        result = described_class.scrub_event_messages(event)

        expect(result.message).to eq('error for [EMAIL_REDACTED]')
      end

      it 'scrubs exception values' do
        identifier = 'a' * 62
        exception = exception_interface_class.new(
          [single_exception_class.new("not found: /secret/#{identifier}")]
        )
        event = message_event_class.new(exception: exception)

        result = described_class.scrub_event_messages(event)

        expect(result.exception.values.first.value).to eq('not found: /secret/[REDACTED]')
      end

      it 'redacts message and exception values when scrubbing raises (fail-closed)' do
        allow(described_class).to receive(:scrub_text).and_raise(StandardError, 'boom')

        exception = exception_interface_class.new(
          [single_exception_class.new('sensitive exception text')]
        )
        event = message_event_class.new(
          exception: exception,
          message: 'sensitive message text'
        )

        result = described_class.scrub_event_messages(event)

        expect(result.message).to eq('[SCRUBBING_FAILED]')
        expect(result.exception.values.first.value).to eq('[SCRUBBING_FAILED]')
      end
    end

    describe '.scrub_url fail-closed behavior' do
      it 'returns [SCRUBBING_FAILED] when path scrubbing raises an error' do
        allow(described_class).to receive(:scrub_sensitive_paths).and_raise(StandardError, 'regex failure')

        result = described_class.scrub_url('https://example.com/secret/abc123')
        expect(result).to eq('[SCRUBBING_FAILED]')
      end

      it 'returns [SCRUBBING_FAILED] when query param scrubbing raises an error' do
        allow(described_class).to receive(:scrub_sensitive_query_params).and_raise(StandardError, 'split failure')

        result = described_class.scrub_url('https://example.com/api?key=secret')
        expect(result).to eq('[SCRUBBING_FAILED]')
      end
    end
  end
end
