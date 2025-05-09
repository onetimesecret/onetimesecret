# tests/unit/ruby/rspec/onetime/config/onetime_boot_global_state_spec.rb

require_relative '../../spec_helper'
require 'fileutils'
require 'yaml'
require 'erb'

RSpec.describe "Onetime global state after boot" do
  let(:source_config_path) { File.join(Onetime::HOME, 'tests', 'unit', 'ruby', 'config.test.yaml') }
  let(:redis_mock) { double("Redis") }

  before(:each) do
    # Reset environment variables
    ENV['RACK_ENV'] = 'test'
    ENV['ONETIME_DEBUG'] = nil

    # Reset global state to avoid test pollution
    Onetime.instance_variable_set(:@conf, nil)
    Onetime.instance_variable_set(:@mode, :test)
    Onetime.instance_variable_set(:@env, 'test')
    Onetime.instance_variable_set(:@d9s_enabled, nil)
    Onetime.instance_variable_set(:@debug, nil)
    Onetime.instance_variable_set(:@locale, nil)
    Onetime.instance_variable_set(:@locales, nil)
    Onetime.instance_variable_set(:@default_locale, nil)
    Onetime.instance_variable_set(:@global_banner, nil)
    Onetime.instance_variable_set(:@instance, nil)
    Onetime.instance_variable_set(:@sysinfo, nil)
    OT::Utils.instance_variable_set(:@fortunes, nil)

    # Setup mocks for external dependencies
    allow(Onetime::Config).to receive(:path).and_return(source_config_path)
    allow(Onetime).to receive(:connect_databases).and_return(true)
    allow(Onetime).to receive(:print_log_banner).and_return(nil)

    # Mock Redis
    allow(Familia).to receive(:redis).and_return(redis_mock)
    allow(redis_mock).to receive(:get).with('global_banner').and_return(nil)

    # Mock Sentry if defined
    if defined?(Sentry)
      allow(Sentry).to receive(:init).and_return(true)
    end
  end

  describe "after Onetime.boot! completes" do
    it "loads and sets configuration" do
      Onetime.boot!(:test)

      expect(Onetime.conf).to be_a(Hash)
      expect(Onetime.conf[:site][:host]).to eq('127.0.0.1:3000')
    end

    it "sets diagnostics enabled state based on configuration" do
      Onetime.boot!(:test)

      # We can't know the exact expected value without seeing the test config,
      # so we test the consistency between config and the enabled state
      config = Onetime.conf
      has_dsn = config.dig(:diagnostics, :dsn).to_s.strip != '' # currently false
      is_enabled = config.dig(:diagnostics, :enabled) # currently false also

      expected = has_dsn && is_enabled # so this is false
      expect(Onetime.d9s_enabled).to eq(expected) # and this fails b/c OT.d9s_enabled reports true
    end

    context "regarding debug mode" do
      it "sets debug=false by default" do
        ENV['ONETIME_DEBUG'] = nil
        Onetime.boot!(:test)
        expect(Onetime.debug).to eq(false)
      end

      it "sets debug=true when ONETIME_DEBUG=true" do
        ENV['ONETIME_DEBUG'] = 'true'
        Onetime.boot!(:test)
        expect(Onetime.debug).to eq(true)
      end

      it "sets debug=true when ONETIME_DEBUG=1" do
        ENV['ONETIME_DEBUG'] = '1'
        Onetime.boot!(:test)
        expect(Onetime.debug).to eq(true)
      end

      it "sets debug=false when ONETIME_DEBUG=false" do
        ENV['ONETIME_DEBUG'] = 'false'
        Onetime.boot!(:test)
        expect(Onetime.debug).to eq(false)
      end

      it "sets debug=false for other ONETIME_DEBUG values" do
        ENV['ONETIME_DEBUG'] = 'invalid'
        Onetime.boot!(:test)
        expect(Onetime.debug).to eq(false)
      end
    end

    it "initializes and sets system information" do
      Onetime.boot!(:test)

      expect(Onetime.sysinfo).not_to be_nil
    end

    it "generates a unique instance identifier" do
      Onetime.boot!(:test)

      expect(Onetime.instance).not_to be_nil
      expect(Onetime.instance).to be_a(String)
      expect(Onetime.instance).to match(/^[a-f0-9]+$/)
    end

    it "configures internationalization from settings" do
      Onetime.boot!(:test)

      # Check that various i18n-related methods return something sensible
      # This handles different versions where implementation might change
      if Onetime.respond_to?(:locale)
        expect(Onetime.locale).not_to be_nil
      end

      if Onetime.respond_to?(:default_locale)
        expect(Onetime.default_locale).not_to be_nil
        expect(Onetime.default_locale).to be_a(String)
      end

      if Onetime.respond_to?(:locales)
        expect(Onetime.locales).not_to be_nil
        # Could be either a hash or array depending on implementation
        expect(Onetime.locales).to respond_to(:each)
      end
    end

    context "regarding global banner" do
      it "sets global_banner from Redis when present" do
        banner_text = "System maintenance scheduled"
        allow(redis_mock).to receive(:get).with('global_banner').and_return(banner_text)

        Onetime.boot!(:test)
        expect(Onetime.global_banner).to eq(banner_text)
      end

      it "sets global_banner to nil when not in Redis" do
        allow(redis_mock).to receive(:get).with('global_banner').and_return(nil)

        Onetime.boot!(:test)
        expect(Onetime.global_banner).to be_nil
      end
    end

    context "regarding database connections" do
      it "calls connect_databases during boot" do
        expect(Onetime).to receive(:connect_databases)
        Onetime.boot!(:test)
      end
    end

    context "regarding log banner" do
      it "suppresses print_log_banner in test mode" do
        expect(Onetime).not_to receive(:print_log_banner)
        Onetime.boot!(:test)
      end

      it "calls print_log_banner in other modes" do
        expect(Onetime).to receive(:print_log_banner)
        Onetime.boot!(:development)
      end
    end

    context "with error handling" do
      before(:each) do
        allow(Onetime).to receive(:exit)
      end
      
      it "handles configuration errors gracefully" do
        allow(Onetime::Config).to receive(:load).and_raise(StandardError.new("Test error"))
        expect(Onetime).to receive(:exit)
        Onetime.boot!(:test)
      end
      
      it "handles Redis connection errors gracefully" do
        allow(Familia).to receive(:uri=).and_raise(Redis::CannotConnectError.new("Connection refused"))
        expect(Onetime).to receive(:exit)
        Onetime.boot!(:test)
      end
      
      it "enables diagnostics when DSN is provided" do
        # Known behavior when DSN is present and enabled is true
        # This test documents the expected correct behavior
        
        # Mock the configuration to include a valid DSN
        allow(Onetime::Config).to receive(:load) do
          config = YAML.load(ERB.new(File.read(source_config_path)).result)
          config[:diagnostics][:sentry][:defaults][:dsn] = "https://valid-dsn@sentry.example.com/123"
          config[:diagnostics][:enabled] = true
          config
        end
        
        # Sentry should be initialized with the DSN
        if defined?(Sentry)
          expect(Sentry).to receive(:init)
        end
        
        Onetime.boot!(:test)
        
        # Diagnostics should be enabled with a valid DSN and enabled=true
        expect(Onetime.d9s_enabled).to eq(true)
      end
    end
  end
end
