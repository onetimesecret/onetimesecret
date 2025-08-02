# spec/onetime/initializers/boot_part2_spec.rb

require_relative '../../spec_helper'
require 'fileutils'
require 'yaml'
require 'erb'

RSpec.describe "Onetime global state after boot" do
  let(:source_config_path) { File.expand_path(File.join(Onetime::HOME, 'spec', 'config.test.yaml')) }
  let(:loaded_config) { YAML.load(ERB.new(File.read(source_config_path)).result) }

  # This simulates Redis for our tests
  let(:redis_double) { double('redis') }

  before(:each) do
    # Reset all environment variables
    ENV['RACK_ENV'] = 'test'
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

    # Mock Redis connection
    allow(Familia).to receive(:uri=).and_return(true)
    allow(Familia).to receive(:redis).and_return(redis_double)
    allow(redis_double).to receive(:get).with('global_banner').and_return(nil)
    allow(redis_double).to receive(:scan_each).and_return([])

    # Mock V2 model Redis connections and methods used in detect_first_boot
    allow(V2::Metadata).to receive(:redis).and_return(redis_double)
    allow(V2::Customer).to receive(:values).and_return(double('Values', element_count: 0))
    allow(V2::Session).to receive(:values).and_return(double('Values', element_count: 0))

    # Mock system settings setup methods
    allow(V2::SystemSettings).to receive(:current).and_raise(OT::RecordNotFound.new("No config found"))
    # allow(V2::SystemSettings).to receive(:extract_colonel_config).and_return({})
    allow(V2::SystemSettings).to receive(:create).and_return(double('SystemSettings', rediskey: 'test:config'))

    # Other common mocks
    allow(Onetime).to receive(:connect_databases).and_return(true)
    allow(Onetime).to receive(:print_log_banner).and_return(nil)

    # Mock Sentry if it exists
    if defined?(Sentry)
      allow(Sentry).to receive(:init).and_return(true)
    end

    # Ensure we use test config
    Onetime::Config.path = source_config_path
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
        expect(Onetime.instance).to match(/^[a-f0-9]+$/)
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
      it "sets Onetime.global_banner from Redis if present" do
        test_banner = "Test system maintenance notice"
        allow(redis_double).to receive(:get).with('global_banner').and_return(test_banner)

        Onetime.boot!(:test)

        expect(Onetime.global_banner).to eq(test_banner)
      end

      it "sets Onetime.global_banner to nil if not present in Redis" do
        allow(redis_double).to receive(:get).with('global_banner').and_return(nil)

        Onetime.boot!(:test)

        expect(Onetime.global_banner).to be_nil
      end
    end

    context "regarding print_log_banner" do
      it "does not call print_log_banner when mode is :test" do
        expect(Onetime).not_to receive(:print_log_banner)

        Onetime.boot!(:test)
      end

      it "calls print_log_banner when mode is not :test" do
        expect(Onetime).to receive(:print_log_banner)

        Onetime.boot!(:development)
      end
    end

    context "regarding database connections" do
      it "calls Onetime.connect_databases" do
        expect(Onetime).to receive(:connect_databases)

        Onetime.boot!(:test)
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
        # Ensure the actual Onetime.connect_databases method is called for this test,
        # overriding the general stub from the main before(:each) block.
        # This allows us to test the error handling within Onetime.boot!
        # when connect_databases itself encounters an issue.
        allow(Onetime).to receive(:connect_databases).and_call_original

        # Simulate that setting the Familia URI (which happens inside connect_databases)
        # results in a connection error. This ensures the error is raised
        # before any actual network connection to a Redis server is attempted by Familia.
        redis_error = Redis::CannotConnectError.new("Test Redis error")
        allow(Familia).to receive(:uri=).and_raise(redis_error)

        # Onetime.boot! will call the original connect_databases.
        # Within connect_databases, the call to Familia.uri= will trigger our stubbed redis_error.
        # This error should then be caught by the rescue block in Onetime.boot!
        # and re-raised because the mode is :test (not :cli).
        expect {
          Onetime.boot!(:test)
        }.to raise_error(Redis::CannotConnectError, "Test Redis error")
      end
    end
  end
end
