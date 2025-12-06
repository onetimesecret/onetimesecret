# spec/onetime/initializers/boot_part2_spec.rb
#
# frozen_string_literal: true

require_relative '../../spec_helper'
require 'fileutils'
require 'yaml'
require 'erb'

RSpec.describe "Onetime global state after boot", :allow_redis do
  let(:source_config_path) { File.expand_path(File.join(Onetime::HOME, 'spec', 'config.test.yaml')) }
  let(:loaded_config) { YAML.load(ERB.new(File.read(source_config_path)).result) }

  before(:each) do
    # Reset environment variables
    ENV['ONETIME_DEBUG'] = nil
    ENV['DEFAULT_TTL'] = nil
    ENV['TTL_OPTIONS'] = nil
    ENV['FRONTEND_HOST'] = nil
    ENV['EMAILER_MODE'] = nil

    # Reset Onetime module state
    Onetime.instance_variable_set(:@conf, nil)
    Onetime.instance_variable_set(:@mode, :test)
    Onetime.instance_variable_set(:@env, 'test')
    Onetime.instance_variable_set(:@d9s_enabled, nil)
    Onetime.instance_variable_set(:@debug, nil)
    Onetime.instance_variable_set(:@i18n_enabled, nil)
    Onetime.instance_variable_set(:@supported_locales, nil)
    Onetime.instance_variable_set(:@default_locale, nil)
    Onetime.instance_variable_set(:@fallback_locale, nil)
    Onetime.instance_variable_set(:@locale, nil)
    Onetime.instance_variable_set(:@locales, nil)
    Onetime.instance_variable_set(:@instance, nil)
    Onetime.instance_variable_set(:@global_banner, nil)
    OT::Utils.instance_variable_set(:@fortunes, nil)

    # NOTE: Tests that call boot! rely on a real database connection.
    # The VALKEY_URL environment variable should be set to the test database.
    # We only stub Familia.uri= to track that it's called with the right config.
    allow(Familia).to receive(:uri=)

    # NOTE: The boot process now uses InitializerRegistry with initializer classes.
    # These methods no longer exist as direct module methods on Onetime:
    # - detect_legacy_data_and_warn (now in DetectLegacyDataAndWarn initializer)
    # - connect_databases (now in ConfigureFamilia initializer)
    # - print_log_banner (now in PrintLogBanner initializer)
    # Initializers run automatically via InitializerRegistry during boot!
    # and are designed to work in test mode.

    # Reset registry and Onetime ready state before each test
    Onetime::Boot::InitializerRegistry.reset!
    Onetime.not_ready

    # Mock Truemail configuration
    truemail_config_double = double("Truemail::Configuration").as_null_object
    allow(Truemail).to receive(:configure).and_yield(truemail_config_double)

    # Mock Sentry if it exists
    if defined?(Sentry)
      allow(Sentry).to receive(:init).and_return(true)
    end

    # Ensure we use test config
    Onetime::Config.path = source_config_path
  end

  after(:each) do
    # Reset ready state so subsequent tests can boot properly
    Onetime.reset_ready!
  end

  describe "When Onetime.boot! completes" do
    it "sets and freezes OT.conf" do
      Onetime.boot!(:test)

      expect(Onetime.conf).to be_a(Hash)
      expect(Onetime.conf).to be_frozen
      expect(Onetime.conf['site']['host']).to eq('127.0.0.1:3000')
    end

    it "sets OT.d9s_enabled based on configuration" do
      Onetime.boot!(:test)
      diagnostics_enabled =  Onetime.conf.dig('diagnostics', 'enabled')
      diagnostics_dsn = Onetime.conf.dig('diagnostics', 'sentry', 'backend', 'dsn') || ''
      if diagnostics_enabled && !diagnostics_dsn.to_s.strip.empty?
        expect(Onetime.d9s_enabled).to be true
      else
        expect(Onetime.d9s_enabled).to be false
      end
    end

    context "regarding debug mode" do
      it "is false by default" do
        ENV['ONETIME_DEBUG'] = nil
        Onetime.boot!(:test)
        expect(Onetime.debug).to be false
      end

      it "is true when ONETIME_DEBUG is 'true'" do
        ENV['ONETIME_DEBUG'] = 'true'
        Onetime.boot!(:test)
        expect(Onetime.debug).to be true
      end

      it "is true when ONETIME_DEBUG is '1'" do
        ENV['ONETIME_DEBUG'] = '1'
        Onetime.boot!(:test)
        expect(Onetime.debug).to be true
      end

      it "is false when ONETIME_DEBUG is 'false'" do
        ENV['ONETIME_DEBUG'] = 'false'
        Onetime.boot!(:test)
        expect(Onetime.debug).to be false
      end

      it "is false when ONETIME_DEBUG is an arbitrary string" do
        ENV['ONETIME_DEBUG'] = 'not_a_boolean'
        Onetime.boot!(:test)
        expect(Onetime.debug).to be false
      end
    end

    context "regarding system information" do
      it "initializes and freezes Onetime.instance" do
        Onetime.boot!(:test)

        expect(Onetime.instance).not_to be_nil
        expect(Onetime.instance).to be_frozen
        expect(Onetime.instance).to be_a(String)
        expect(Onetime.instance).to match(/^[a-z0-9]+$/)
      end
    end

    context "regarding i18n" do
      before(:each) do
        # Make sure we actually test the i18n initialization
        Onetime.instance_variable_set(:@locale, nil)
        Onetime.instance_variable_set(:@locales, nil)
        Onetime.instance_variable_set(:@default_locale, nil)
      end

      it "initializes i18n settings from config" do
        Onetime.boot!(:test)
        expect(Onetime.conf['internationalization']['enabled']).to be(true)
        expect(Onetime.conf['internationalization']['fallback_locale']).to be_a(Hash)

        expect(Onetime.supported_locales).to match_array(Onetime.conf['internationalization']['locales'])
        expect(Onetime.supported_locales).to include(Onetime.default_locale)
        expect(Onetime.i18n_enabled).to be(true)
        expect(Onetime.fallback_locale).to be_a(Hash)
      end
    end

    context "regarding global banner" do
      let(:test_banner) { "Test system maintenance notice" }

      it "sets Onetime.global_banner from the database if present" do
        # Do a first boot to set up Familia, then set banner and re-test
        Onetime.boot!(:test)

        # Set the banner after boot (Familia is now connected)
        Familia.dbclient.set('global_banner', test_banner)

        # Reset and boot again to pick up the banner
        Onetime::Boot::InitializerRegistry.reset!
        Onetime.not_ready
        Onetime.boot!(:test)

        expect(Onetime.global_banner).to eq(test_banner)

        # Clean up
        Familia.dbclient.del('global_banner')
      end

      it "sets Onetime.global_banner to nil if not present in Redis" do
        Onetime.boot!(:test)

        # Ensure no banner is set and check the runtime state
        Familia.dbclient.del('global_banner')

        # Reset and boot again
        Onetime::Boot::InitializerRegistry.reset!
        Onetime.not_ready
        Onetime.boot!(:test)

        expect(Onetime.global_banner).to be_nil
      end
    end

    context "regarding print_log_banner" do
      it "runs PrintLogBanner initializer during boot" do
        # The PrintLogBanner initializer runs in all modes (including test).
        # It logs system information to help with debugging.
        Onetime.boot!(:test)

        initializer = Onetime::Boot::InitializerRegistry.initializers.find do |i|
          i.name == :"onetime.initializers.print_log_banner"
        end
        expect(initializer).not_to be_nil
        expect(initializer.completed?).to be true
      end
    end

    context "regarding database connections" do
      it "runs the ConfigureFamilia initializer (database connection)" do
        # The boot process now uses InitializerRegistry with initializer classes.
        # ConfigureFamilia replaces the old Onetime.connect_databases method.
        Onetime.boot!(:test)

        # Check that the ConfigureFamilia initializer completed successfully
        initializer = Onetime::Boot::InitializerRegistry.initializers.find do |i|
          i.name == :"onetime.initializers.configure_familia"
        end
        expect(initializer).not_to be_nil
        expect(initializer.completed?).to be true
      end
    end

    context "regarding error handling" do
      # The before(:each) block that previously stubbed `Onetime.exit`
      # is no longer necessary for these specific tests, as we are directly
      # asserting that an exception is raised.

      it "handles configuration load errors by re-raising the error when not in CLI mode" do
        # This simulates an error during OT::Config.load
        config_error = StandardError.new("Test configuration error")
        allow(Onetime::Config).to receive(:load).and_raise(config_error)

        # Onetime.boot! is called with :test mode.
        # The rescue block for StandardError in boot! should re-raise the error.
        expect {
          Onetime.boot!(:test)
        }.to raise_error(StandardError, "Test configuration error")
      end

      it "handles Redis connection errors by re-raising the error when not in CLI mode" do
        # Simulate that setting the Familia URI (which happens inside ConfigureFamilia initializer)
        # results in a connection error. This ensures the error is raised
        # before any actual network connection to a database server is attempted by Familia.
        redis_error = Redis::CannotConnectError.new("Test Redis error")
        allow(Familia).to receive(:uri=).and_raise(redis_error)

        # Onetime.boot! will run the ConfigureFamilia initializer.
        # The call to Familia.uri= will trigger our stubbed redis_error.
        # This error should then propagate up because the mode is :test (not :cli).
        expect {
          Onetime.boot!(:test)
        }.to raise_error(Redis::CannotConnectError, "Test Redis error")
      end
    end
  end
end
