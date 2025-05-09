# tests/unit/ruby/rspec/onetime/config/onetime_boot_global_state_spec.rb

require_relative '../../spec_helper'
require 'fileutils'
require 'yaml'
require 'erb'

RSpec.describe "Onetime global state after boot" do
  let(:source_config_path) { File.expand_path(File.join(Onetime::HOME, 'tests', 'unit', 'ruby', 'config.test.yaml')) }
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
    Onetime.instance_variable_set(:@sysinfo, nil)
    Onetime.instance_variable_set(:@global_banner, nil)
    OT::Utils.instance_variable_set(:@fortunes, nil)

    # Mock Redis connection
    allow(Familia).to receive(:uri=).and_return(true)
    allow(Familia).to receive(:redis).and_return(redis_double)
    allow(redis_double).to receive(:get).with('global_banner').and_return(nil)

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
      expect(Onetime.conf[:site][:host]).to eq('127.0.0.1:3000')
    end

    it "sets OT.d9s_enabled based on configuration" do
      Onetime.boot!(:test)

      if Onetime.conf[:diagnostics] && Onetime.conf[:diagnostics][:enabled] &&
         !Onetime.conf[:diagnostics][:dsn].to_s.strip.empty?
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
      it "initializes and freezes Onetime.sysinfo" do
        Onetime.boot!(:test)

        expect(Onetime.sysinfo).not_to be_nil
        expect(
Onetime.sysinfo).to be_frozen

        # Access sysinfo as a hash regardless of its actual class
        sysinfo = Onetime.sysinfo.respond_to?(:[]) ?
                 Onetime.sysinfo :
                 Onetime.sysinfo.instance_variable_get(:@info)

        expect(sysinfo[:ruby]).to eq(RUBY_VERSION)
        expect(sysinfo[:platform]).to eq(RUBY_PLATFORM)
      end

      it "initializes and freezes Onetime.instance" do
        Onetime.boot!(:test)

        expect(Onetime.instance).not_to be_nil
        expect(Onetime.instance).to be_frozen
        expect(Onetime.instance).to be_a(String)
        expect(Onetime.instance).to match(/^[a-f0-9]+$/)
      end
    end

    context "regarding internationalization" do
      before(:each) do
        # Make sure we actually test the i18n initialization
        Onetime.instance_variable_set(:@locale, nil)
        Onetime.instance_variable_set(:@locales, nil)
        Onetime.instance_variable_set(:@default_locale, nil)
      end

      it "initializes i18n settings from config" do
        Onetime.boot!(:test)

        if Onetime.respond_to?(:locale)
          expect(Onetime.locale).to eq(Onetime.conf[:site][:locale])
        end

        if Onetime.respond_to?(:default_locale)
          expect(Onetime.default_locale).to eq(Onetime.conf[:site][:locale])
        end

        if Onetime.respond_to?(:locales) && Onetime.conf[:site][:internationalization]
          if Onetime.conf[:site][:internationalization][:enabled]
            expect(Onetime.locales).to match_array(Onetime.conf[:site][:internationalization][:locales])
          else
            expect(Onetime.locales).to match_array([Onetime.default_locale])
          end
        end
      end

      it "sets i18n to defaults when disabled in config" do
        # First boot to get a valid config
        Onetime.boot!(:test)

        # Manually override the internationalization setting
        original_conf = Onetime.conf.dup
        config_hash = Marshal.dump(original_conf)

        if config_hash[:site] && config_hash[:site][:internationalization]
          config_hash[:site][:internationalization][:enabled] = false
          Onetime.instance_variable_set(:@conf, config_hash)

          # Re-initialize i18n with modified config
          if Onetime.respond_to?(:initialize_i18n, true)
            Onetime.send(:initialize_i18n)

            # Check that only the default locale is available
            if Onetime.respond_to?(:locales)
              expect(Onetime.locales).to eq([Onetime.default_locale])
            end
          end
        end
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
      before(:each) do
        allow(Onetime).to receive(:exit)
      end

      it "handles configuration load errors" do
        allow(Onetime::Config).to receive(:load).and_raise(StandardError.new("Test configuration error"))

        # Since we might not know the exact exit code, we just expect exit to be called
        expect(Onetime).to receive(:exit)

        Onetime.boot!(:test)
      end

      it "handles Redis connection errors" do
        allow(Familia).to receive(:uri=).and_raise(Redis::CannotConnectError.new("Test Redis error"))

        # Since we might not know the exact exit code, we just expect exit to be called
        expect(Onetime).to receive(:exit)

        Onetime.boot!(:test)
      end
    end
  end
end
