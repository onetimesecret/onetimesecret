# spec/integration/all/config/after_load_spec.rb
#
# frozen_string_literal: true

require 'sentry-ruby'
require 'tempfile'

require 'spec_helper'

# We require sentry-ruby here to test configuration processing, but stub its
# methods to prevent actual initialization during tests.

RSpec.describe "Onetime boot configuration process", type: :integration do
  using Familia::Refinements::TimeLiterals

  let(:test_config_path) { File.join(Onetime::HOME, 'spec', 'config.test.yaml') }
  let(:test_config_string) { File.read(test_config_path) }

  # First parse the ERB template in the YAML file.
  # Must load via ERB to simulate what Config.load behaviour. Otherwise the
  # config will have a bunch of `<%= ENV['SENTRY_DSN'] || nil %>` strings.
  let(:test_config_parsed) { ERB.new(test_config_string).result }

  # Then load the YAML content after ERB processing
  let(:test_config) { YAML.load(test_config_parsed) }

  # Shared setup for mocking Familia when database is not needed
  # Use this in contexts that don't call boot! with real database
  shared_context 'with mocked familia' do
    let(:redis_double) do
      double('Redis').tap do |rd|
        allow(rd).to receive(:ping).and_return("PONG")
        allow(rd).to receive(:get).and_return(nil)
        allow(rd).to receive(:info).and_return({"redis_version" => "6.0.0"})
        allow(rd).to receive(:scan_each).and_return([])
        allow(rd).to receive(:scan).and_return(["0", []])
        allow(rd).to receive(:setnx).and_return(true)
        allow(rd).to receive(:set).and_return("OK")
      end
    end

    before do
      # Mock Familia 2 API for tests that don't need real database
      allow(Familia).to receive(:uri=)
      allow(Familia).to receive(:dbclient).and_return(redis_double)
      uri_double = double('URI', serverid: 'localhost:6379')
      allow(uri_double).to receive(:db=)
      allow(uri_double).to receive(:db).and_return(0)
      allow(uri_double).to receive(:dup).and_return(uri_double)
      allow(Familia).to receive(:uri).and_return(uri_double)
      allow(Familia).to receive(:with_isolated_dbclient).and_yield(redis_double)

      # Mock V2 model Redis connections
      allow(Onetime::Receipt).to receive(:dbclient).and_return(redis_double)
      allow(Onetime::Customer).to receive(:values).and_return(double('Values', element_count: 0))

      # Mock system settings
      system_settings_stub = Class.new do
        def self.current
          raise OT::RecordNotFound.new("No config found")
        end
        def self.create
          double('SystemSettings', dbkey: 'test:config')
        end
      end
      stub_const('V2::SystemSettings', system_settings_stub)
    end
  end

  before do
    # Set test database URL before any config loading
    # This must be set BEFORE config is loaded via ERB since config.test.yaml
    # uses ENV['VALKEY_URL'] || ENV['REDIS_URL'] || 'redis://127.0.0.1:6379/0'

    # Set up necessary state for testing
    @original_path = Onetime::Config.instance_variable_get(:@path)
    @original_mode = Onetime.mode
    @original_env = Onetime.env
    @original_emailer = Onetime.instance_variable_get(:@emailer)
    @original_instance = Onetime.instance_variable_get(:@instance)
    @original_d9s_enabled = Onetime.d9s_enabled

    # Prevent actual side effects (logging)
    allow(Onetime).to receive(:ld)
    allow(Onetime).to receive(:li)
    allow(Onetime).to receive(:le)

    # Point to our test config file
    Onetime::Config.instance_variable_set(:@path, test_config_path)
  end

  after do
    # Restore original state
    Onetime::Config.instance_variable_set(:@path, @original_path)
    Onetime.mode = @original_mode
    Onetime.env = @original_env
    Onetime.instance_variable_set(:@conf, nil)
    Onetime.instance_variable_set(:@emailer, @original_emailer)
    Onetime.instance_variable_set(:@instance, @original_instance)
    Onetime.d9s_enabled = @original_d9s_enabled

    # No need to clean up as we're using an existing file
  end

  describe '.boot!' do
    # NOTE: These tests call boot! which runs the full initializer registry.
    # They require VALKEY_URL to be set to a real database connection.
    # The boot process now uses InitializerRegistry with initializer classes,
    # not the old module methods (load_locales, set_global_secret, etc.).

    context 'with valid configuration' do
      around do |example|
        # Set RACK_ENV=test to skip billing initializer's Stripe calls
        original_rack_env = ENV['RACK_ENV']
        example.run
        ENV['RACK_ENV'] = original_rack_env
      end

      before do
        # Explicitly reset the d9s_enabled to nil before each test
        Onetime.d9s_enabled = nil

        # Reset boot state so boot! can run fresh each test
        # Uses reset_ready! which sets @boot_state = nil (defaults to BOOT_NOT_STARTED)
        Onetime.reset_ready!

        # Boot now uses Configurator.load! pipeline instead of Config.load/after_load.
        # Config.path is set to test_config_path in the outer before block (line 89),
        # so the Configurator will read the test config file directly.

        # Stub Familia.uri= to track calls but still set the real URI from ENV
        allow(Familia).to receive(:uri=).and_call_original
      end

      it 'sets mode and environment variables' do
        Onetime.boot!(:test)
        expect(Onetime.mode).to eq(:test)
      end

      it 'loads configuration via Configurator pipeline' do
        Onetime.boot!(:test)
        expect(Onetime.conf).to be_a(Hash)
        expect(Onetime.conf).not_to be_empty
      end

      it 'sets diagnostics to disabled when test conf has it enabled but dsn is nil' do
        Onetime.boot!(:test)
        # Diagnostics disabled because DSN is nil in test config
        expect(Onetime.d9s_enabled).to be false
      end

      it 'completes boot without database connection when connect_to_db=false' do
        # When connect_to_db=false, boot should complete without requiring database
        # Database-related initializers are skipped
        expect { Onetime.boot!(:test, false) }.not_to raise_error
        expect(Onetime.ready?).to be true
      end

      it 'sets Familia URI from the database config when we want DB connection' do
        Onetime.boot!(:test, true)
        # Familia.uri= should be called with the config's redis URI
        expect(Familia).to have_received(:uri=).with(test_config['redis']['uri'])
      end

      it 'generates a unique instance identifier' do
        Onetime.boot!(:test)
        expect(Onetime.instance).not_to be_nil
        expect(Onetime.instance).to be_frozen
      end

      it 'returns nil and makes configuration available through Onetime.conf' do
        result = Onetime.boot!(:test)
        expect(result).to be_nil
        expect(Onetime.conf).to be_a(Hash)
      end
    end

    context 'with explicit method calls' do
      around do |example|
        original_rack_env = ENV['RACK_ENV']
        example.run
        ENV['RACK_ENV'] = original_rack_env
      end

      before do
        Onetime.not_ready
        allow(Familia).to receive(:uri=).and_call_original
      end

      after do
        # Reset ready state so subsequent tests can boot properly
        Onetime.reset_ready!
      end

      it 'loads config through Configurator pipeline' do
        expect(Onetime::Configurator).to receive(:load!).with(strict: false).and_call_original

        Onetime.boot!(:test)
      end
    end

    context 'with error handling' do
      before(:each) do
        # Fully reset global state to ensure boot! runs from scratch
        Onetime.instance_variable_set(:@conf, nil)
        Onetime.instance_variable_set(:@mode, nil)
        Onetime.instance_variable_set(:@env, nil)
        Onetime.reset_ready! # Reset boot state machine (sets @boot_state = nil)
        Onetime.instance_variable_set(:@instance, nil)
      end

      after(:each) do
        # Re-run boot! to restore proper state for subsequent tests
        Onetime.instance_variable_set(:@conf, nil)
        Onetime.instance_variable_set(:@mode, nil)
        Onetime.instance_variable_set(:@env, nil)
        Onetime.reset_ready! # Reset boot state machine (sets @boot_state = nil)
        Onetime.instance_variable_set(:@instance, nil)
        Onetime.boot!(:test) rescue nil
      end

      around do |example|
        original_rack_env = ENV['RACK_ENV']
        example.run
        ENV['RACK_ENV'] = original_rack_env
      end

      it 'handles OT::Problem exceptions' do
        allow(Onetime::Configurator).to receive(:load!).and_raise(OT::Problem.new("Config loading failed"))
        expect(Onetime).to receive(:le).with("Problem booting: Config loading failed") # a bug as of v0.20.5
        expect(Onetime).to receive(:ld) # For backtrace
        expect { Onetime.boot!(:test) }.to raise_error(OT::Problem)
      end

      it 'handles Redis connection errors' do
        # Create config with port 2121 to pass test environment safety check
        config_with_test_port = test_config.dup
        config_with_test_port['redis'] = { 'uri' => 'redis://127.0.0.1:2121/0' }
        allow(Onetime::Config).to receive(:load).and_return(config_with_test_port)
        allow(Familia).to receive(:uri=).and_raise(Redis::CannotConnectError.new("Connection refused"))
        expect(Onetime).to receive(:le).with(/Cannot connect to the database .* \(Redis::CannotConnectError\)/)
        expect { Onetime.boot!(:test) }.to raise_error(Redis::CannotConnectError)
      end

      it 'propagates unexpected errors' do
        allow(Onetime::Configurator).to receive(:load!).and_raise(StandardError.new("Something went wrong"))
        # Unlike OT::Problem and Redis::CannotConnectError, generic StandardError
        # is not caught and logged - it propagates directly
        expect { Onetime.boot!(:test) }.to raise_error(StandardError, "Something went wrong")
      end
    end
  end

  describe '.after_load' do
    # Minimal config for testing specific edge cases
    let(:minimal_config) do
      {
        'development' => { 'enabled' => false },
        'mail' => { 'truemail' => { 'default_validation_type' => :regex, 'verifier_email' => 'hello@example.com' } },
        'site' => {
          'authentication' => { 'enabled' => true },
          'host' => 'example.com',
          'secret' => 'test_secret',
        },
        'redis' => { 'uri' => 'redis://localhost:6379/0' },
      }
    end

    context 'with i18n' do
      it "sets i18n to disabled when missing from config" do
        raw_config = minimal_config.dup
        expect(raw_config.key?('internationalization')).to be false

        processed_config = Onetime::Config.after_load(raw_config)
        expect(processed_config['internationalization']['enabled']).to be(false)
      end

      it "does not add settings when disabeld in config" do
        raw_config = minimal_config.dup
        raw_config['internationalization'] = { 'enabled' => false }

        processed_config = Onetime::Config.after_load(raw_config)
        expect(processed_config['internationalization']['enabled']).to be(false)
        expect(processed_config['internationalization'].keys).to eq(['enabled', 'default_locale'])
      end
    end

    it 'applies default values to secret_options when not specified' do
      # The minimal config does not contain settings for secret_options so
      # OT::Config is going to supply its defaults. OT.conf is nil because
      # this testing code path starts each testcase with it nil on purpose
      # so there is no influence from the config.test.yaml. That's why
      # there are 11 ttl_options and not 3 (from the yaml).
      raw_config = minimal_config.dup

      processed_config = Onetime::Config.after_load(raw_config)
      secret_options = processed_config['site']['secret_options']

      expect(secret_options['default_ttl']).to eq(7.days)
      expect(secret_options['ttl_options']).to be_an(Array)
      expect(secret_options['ttl_options'].length).to eq(11)
    end

    it 'uses values from config file when specified' do
      config = test_config.dup
      processed_config = Onetime::Config.after_load(config)

      expect(processed_config['site']['secret_options']['default_ttl']).to_not be_nil
      expect(processed_config['site']['secret_options']['ttl_options']).to include(1800, 43_200, 604_800)
    end

    it 'initializes empty domains configuration' do
      config = minimal_config.dup

      processed_config = Onetime::Config.after_load(config)

      # Domains config moved from site.domains to features.domains
      expect(processed_config['features']['domains']).to eq({ 'enabled' => false })
    end

    it 'does not add billing configuration when not present' do
      config = minimal_config.dup
      processed_config = Onetime::Config.after_load(config)

      # Billing config comes from billing.yaml, not config.yaml
      expect(processed_config.key?('billing')).to be false
    end

    it 'initializes empty regions configuration' do
      config = minimal_config.dup

      processed_config = Onetime::Config.after_load(config)

      expect(processed_config['features']['regions']).to eq({ 'enabled' => false })
    end

    it 'disables authentication sub-features when main feature is off' do
      config = minimal_config.dup
      config['site']['authentication'] = {
        'enabled' => false,
        'signup' => true,
        'signin' => true,
      }

      processed_config = Onetime::Config.after_load(config)

      expect(processed_config['site']['authentication']['signup']).to be false
      expect(processed_config['site']['authentication']['signin']).to be false

      # The config we passed in was not modified
      expect(config['site']['authentication']['signup']).to be true
      expect(config['site']['authentication']['signin']).to be true
    end

    context 'with string ttl values' do
      it 'converts string ttl_options to integers' do
        config = minimal_config.dup
        config['site'] = {
          'secret' => '53krU7',
          'authentication' => { 'enabled' => true },
          'secret_options' => { 'ttl_options' => "300 3600 86400" },
        }

        processed_config = Onetime::Config.after_load(config)

        expect(processed_config['site']['secret_options']['ttl_options']).to eq([300, 3600, 86_400])
      end

      it 'converts string default_ttl to integer' do
        config = minimal_config.dup
        config['site'] = {
          'secret' => '53krU7',
          'authentication' => { 'enabled' => true },
          'secret_options' => { 'default_ttl' => "86400" },
        }

        processed_config = Onetime::Config.after_load(config)

        expect(processed_config['site']['secret_options']['default_ttl']).to eq(86_400)
      end

      it 'converts TTL options string from test config to integers' do
        config = OT::Config.deep_clone(test_config)
        config['site']['secret_options']['ttl_options'] = "1800 43200 604800"

        processed_config = Onetime::Config.after_load(config)

        expect(processed_config['site']['secret_options']['ttl_options']).to be_an(Array)
        expect(processed_config['site']['secret_options']['ttl_options']).to eq([1800, 43_200, 604_800])
      end
    end

    context 'with diagnostics configuration' do
      # Since we already require 'sentry-ruby' at the top of the file,
      # we just need to stub the methods we don't want to actually execute
      before(:each) do
        # Stub the Sentry methods to prevent actual initialization during tests
        allow(Sentry).to receive(:init)
        allow(Sentry).to receive(:initialized?).and_return(true)
      end

      it 'enables diagnostics from test config file' do
        raw_config = OT::Config.deep_clone(test_config)

        allow(Kernel).to receive(:require).with('sentry-ruby')
        allow(Kernel).to receive(:require).with('stackprof')

        # Save original value to restore after test
        original_value = OT.d9s_enabled
        OT.d9s_enabled = nil
        processed_config = Onetime::Config.after_load(raw_config)

        expect(OT.d9s_enabled).to be(false)

        OT.d9s_enabled = original_value # restore original value
        expect(processed_config['diagnostics']['enabled']).to be true
        expect(processed_config['diagnostics']['sentry']['backend']['sampleRate']).to eq(0.11)
        expect(processed_config['diagnostics']['sentry']['backend']['maxBreadcrumbs']).to eq(22)
        expect(processed_config['diagnostics']['sentry']['frontend']['sampleRate']).to eq(0.11)
        expect(processed_config['diagnostics']['sentry']['frontend']['maxBreadcrumbs']).to eq(22)
      end

      it 'enables diagnostics when configured with a valid DSN' do
        config = OT::Config.deep_clone(minimal_config)
        config['diagnostics'] = {
          'enabled' => true,
          'sentry' => {
            'defaults' => { 'dsn' => 'https://example.com/sentry' },
            'backend' => { 'dsn' => 'https://example.com/sentry' },
          },
        }

        allow(Kernel).to receive(:require).with('sentry-ruby')
        allow(Kernel).to receive(:require).with('stackprof')

        # Save original value to restore after test
        original_value = OT.d9s_enabled
        OT.d9s_enabled = false

        processed_config = Onetime::Config.after_load(config)

        # In test mode, we need to manually set this based on the processed config
        # to simulate what would happen in non-test environments
        backend_dsn = processed_config.dig('diagnostics', 'sentry', 'backend', 'dsn')
        frontend_dsn = processed_config.dig('diagnostics', 'sentry', 'frontend', 'dsn')
        OT.d9s_enabled = !!(processed_config.dig('diagnostics', 'enabled') && (backend_dsn || frontend_dsn))

        expect(OT.d9s_enabled).to be true
        expect(processed_config['diagnostics']['enabled']).to be true

        # Restore the original value
        OT.d9s_enabled = original_value
      end

      it 'applies defaults to sentry configuration' do
        config = OT::Config.deep_clone(minimal_config)
        config['diagnostics'] = {
          'enabled' => true,
          'sentry' => {
            'defaults' => { 'dsn' => 'https://example.com/sentry', 'environment' => 'test-default' },
            'backend' => { 'traces_sample_rate' => 0.1 },
            'frontend' => { 'profiles_sample_rate' => 0.2 },
          },
        }
        OT.d9s_enabled = false

        allow(Kernel).to receive(:require).with('sentry-ruby')
        allow(Kernel).to receive(:require).with('stackprof')

        # Explicitly set OT.conf to nil before calling after_load to verify
        # that after_load doesn't set it (only boot! should set OT.conf)
        original_conf = OT.conf
        OT.instance_variable_set(:@conf, nil)

        processed_config = Onetime::Config.after_load(config)

        expect(processed_config['diagnostics']['sentry']['backend']['environment']).to eq('test-default')
        expect(processed_config['diagnostics']['sentry']['frontend']['environment']).to eq('test-default')
        expect(processed_config['diagnostics']['sentry']['backend']['traces_sample_rate']).to eq(0.1)
        expect(processed_config['diagnostics']['sentry']['frontend']['profiles_sample_rate']).to eq(0.2)
        expect(processed_config['diagnostics']['sentry']['backend']['dsn']).to eq('https://example.com/sentry')
        expect(processed_config['diagnostics']['sentry']['frontend']['dsn']).to eq('https://example.com/sentry')

        # The defaults aren't returned in the processed config because
        # they've been applied to the frontend and backend settings and
        # are no longer needed or relevant.
        expect(processed_config['diagnostics']['sentry']['defaults']).to be_nil
        # The defaults remain in the config that we passed in because we go
        # out of our way to make sure we don't mutate the original config.
        expect(config['diagnostics']['sentry']['defaults']).to be_a(Hash)

        # OT.conf is assigned a value in boot! based on the return
        # value from after_load. We test for this specifically b/c
        # we had an issue with interdependent configurations and
        # want to be sure we don't go down that road again.
        expect(OT.conf).to be_nil

        # Restore for spec_helper's after hook
        OT.instance_variable_set(:@conf, original_conf)
      end
    end

    context 'with validation errors' do
      # Define a let block for a base configuration object.
      # This provides a fresh, deep-cloned copy of the loaded configuration
      # (typically from test.yaml) for each test example.
      let(:config) do
        Onetime::Config.deep_clone(test_config)
      end

      # Before each test in this context, reset global Onetime.conf
      # and ensure some baseline configuration properties are set on the
      # `config` object. This helps make tests more robust against
      # variations in `test.yaml`.
      before do
        # Onetime.instance_variable_set(:@conf, nil)
      end

      # New tests for `raise_concerns` validations:
      context 'when global secret is invalid (via raise_concerns)' do
        it 'raises OT::ConfigError if global secret is nil and not allowed' do
          config['site']['secret'] = nil
          config['development']['allow_nil_global_secret'] = false # Explicitly ensure it's not allowed

          expect {
            Onetime::Config.after_load(config)
          }.to raise_error(OT::ConfigError, "Global secret cannot be nil - set SECRET env var or site.secret in config")
        end

        it 'raises OT::ConfigError if global secret is "CHANGEME" and not allowed' do
          config['site']['secret'] = 'CHANGEME' # Test the specific "CHANGEME" string
          config['development']['allow_nil_global_secret'] = false

          expect {
            Onetime::Config.after_load(config)
          }.to raise_error(OT::ConfigError, "Global secret cannot be nil - set SECRET env var or site.secret in config")
        end

        it 'raises OT::ConfigError if global secret is whitespace "CHANGEME  " and not allowed' do
          config['site']['secret'] = 'CHANGEME  ' # Test with trailing whitespace
          config['development']['allow_nil_global_secret'] = false

          expect {
            Onetime::Config.after_load(config)
          }.to raise_error(OT::ConfigError, "Global secret cannot be nil - set SECRET env var or site.secret in config")
        end

        # RSpec Warning: Avoiding False Positives with `not_to raise_error`
        #
        # PROBLEM:
        # Using `expect { }.not_to raise_error(SpecificErrorClass, message)` is risky because
        # it can give false positives. If ANY other error occurs (NoMethodError, NameError,
        # ArgumentError, etc.), the test will still pass, even though your code might be broken.
        # This means the code you're trying to test might not even execute.
        #
        # AVOID THIS PATTERN:
        # expect { some_method }.not_to raise_error(OT::ConfigError, "specific message")
        #
        # BETTER PATTERNS:
        #
        # 1. Test that NO errors occur (most common):
        #    expect { some_method }.not_to raise_error
        #
        # 2. Test for a different specific error if that's what you expect:
        #    expect { some_method }.to raise_error(DifferentErrorClass)
        #
        # 3. Hybrid approach - test both positive and negative cases:
        #    # Test the success case
        #    expect { valid_config_method }.not_to raise_error
        #
        #    # Test the failure case to ensure your test is meaningful
        #    expect { invalid_config_method }.to raise_error(OT::ConfigError, /expected message/)
        #
        # 4. If you must test for absence of a specific error, be explicit about it:
        #    begin
        #      some_method
        #      # If we get here, no error was raised (good)
        #    rescue OT::ConfigError => e
        #      fail "Expected no ConfigError, but got: #{e.message}"
        #    rescue => e
        #      # Other errors are also failures, but we can see what they are
        #      fail "Unexpected error: #{e.class}: #{e.message}"
        #    end
        #
        # WHY THIS MATTERS:
        # The goal is to write tests that fail when your code is broken, not tests that
        # accidentally pass when your code doesn't even run due to unrelated errors.

        it 'does not raise ConfigError for nil global secret when explicitly allowed' do
          config['site']['secret'] = nil
          config['development']['enabled'] = true
          config['development']['allow_nil_global_secret'] = true

          allow(OT).to receive(:li)

          # GOOD: Test that no errors at all are raised
          expect { Onetime::Config.after_load(config) }.not_to raise_error

          # GOOD: Test the negative case to ensure our test is meaningful
          config['development']['allow_nil_global_secret'] = false
          expect { Onetime::Config.after_load(config) }.to raise_error(OT::ConfigError, /Global secret cannot be nil/)
        end

        it 'does not raise for nil global secret when explicitly allowed' do
          config['site']['secret'] = nil
          config['development']['enabled'] = true
          config['development']['allow_nil_global_secret'] = true

          allow(OT).to receive(:li)

          # GOOD: Simple, safe pattern
          expect { Onetime::Config.after_load(config) }.not_to raise_error
        end

        it 'normalizes allow_nil_global_secret to false when development.enabled is false' do
          config['site']['secret'] = nil
          config['development']['enabled'] = false
          config['development']['allow_nil_global_secret'] = true

          # The normalization should force allow_nil to false, then raise ConfigError
          # because nil secret is not allowed
          expect {
            Onetime::Config.after_load(config)
          }.to raise_error(OT::ConfigError, /Global secret cannot be nil/)
        end
      end

      context 'when truemail configuration is missing (via raise_concerns)' do
        it 'raises OT::ConfigError' do
          # Global secret is valid due to the `before` hook setup.
          config['mail'].delete('truemail') # Remove the truemail configuration

          expect {
            Onetime::Config.after_load(config)
          }.to raise_error(OT::ConfigError, "No TrueMail config found")
        end

        it 'raises OT::ConfigError for missing truemail even if nil global secret is allowed' do
          config['site']['secret'] = nil # Set global secret to nil
          config['development']['enabled'] = true # Required for allow_nil to take effect
          config['development']['allow_nil_global_secret'] = true # Allow nil global secret

          config['mail'].delete('truemail') # Remove truemail configuration

          allow(OT).to receive(:li) # Suppress warnings for allowed nil secret

          # The check for truemail comes after the global secret check in `raise_concerns`.
          # So, if nil secret is allowed, it proceeds to check truemail.
          expect {
            Onetime::Config.after_load(config)
          }.to raise_error(OT::ConfigError, "No TrueMail config found")
        end
      end
    end # This closes the `context 'with validation errors'`
  end

  describe '.mapped_key' do
    it 'maps custom keys to TrueMail keys' do
      expect(Onetime::Config.mapped_key('allowed_domains_only')).to eq('whitelist_validation')
      expect(Onetime::Config.mapped_key('allowed_emails')).to eq('whitelisted_emails')
      expect(Onetime::Config.mapped_key('blocked_emails')).to eq('blacklisted_emails')
      expect(Onetime::Config.mapped_key('allowed_domains')).to eq('whitelisted_domains')
      expect(Onetime::Config.mapped_key('blocked_domains')).to eq('blacklisted_domains')
      expect(Onetime::Config.mapped_key('blocked_mx_ip_addresses')).to eq('blacklisted_mx_ip_addresses')
    end

    it 'returns the original key when no mapping exists' do
      expect(Onetime::Config.mapped_key('unmapped_key')).to eq('unmapped_key')
      expect(Onetime::Config.mapped_key('default_validation_type')).to eq('default_validation_type')
      expect(Onetime::Config.mapped_key('verifier_email')).to eq('verifier_email')
    end

    it 'maps test example key' do
      expect(Onetime::Config.mapped_key('example_internal_key')).to eq('example_external_key')
    end
  end

  describe '.load' do
    it 'correctly loads configuration from test.yaml file' do
      config = Onetime::Config.load(test_config_path)

      expect(config['site']['host']).to eq('127.0.0.1:3000')
      expect(config['site']['ssl']).to eq(true)
      expect(config['site']['secret']).to eq('SuP0r_53cRU7_t3st_0nly')
      expect(config['internationalization']['enabled']).to eq(true)
      expect(config['internationalization']['default_locale']).to eq('en')
      expect(config['internationalization']['locales']).to include('en', 'fr_CA', 'fr_FR')
      # Test config uses :regex to avoid MX lookups for test domains
      expect(config['mail']['truemail']['default_validation_type']).to eq(:regex)
      expect(config['site']['secret_options']['ttl_options']).to be_a(String)
    end
  end
end
