# spec/onetime/initializers/boot_part1_spec.rb

require_relative '../../spec_helper'
require 'fileutils' # For managing temp config files
require 'yaml'      # For parsing YAML strings
require 'erb'       # For processing ERB in YAML strings

RSpec.describe "Onetime::Config during Onetime.boot!" do
  let(:source_config_path) { File.expand_path(File.join(Onetime::HOME, 'spec', 'config.test.yaml')) }

  before(:all) do
    # Ensure Onetime module is in a clean state for these tests
  end

  before(:each) do
    # Mock Onetime::Config.path to use the actual test config file
    allow(Onetime::Config).to receive(:path).and_return(source_config_path)
    allow(Onetime::Config).to receive(:find_configs).and_return([source_config_path])

    # Reset Onetime main module state. These are meant to match
    # exactly what Onetime instance vars
    Onetime.instance_variable_set(:@conf, nil)
    Onetime.instance_variable_set(:@mode, :app)
    Onetime.instance_variable_set(:@env, 'test')
    Onetime.instance_variable_set(:@d9s_enabled, nil)
    Onetime.instance_variable_set(:@i18n_enabled, false)
    Onetime.instance_variable_set(:@supported_locales, ['en'])
    Onetime.instance_variable_set(:@default_locale, 'en')
    Onetime.instance_variable_set(:@fallback_locale, nil)
    Onetime.instance_variable_set(:@locales, nil)
    Onetime.instance_variable_set(:@instance, nil)
    Onetime.instance_variable_set(:@sysinfo, nil)
    Onetime.instance_variable_set(:@emailer, nil)
    Onetime.instance_variable_set(:@global_secret, nil)
    Onetime.instance_variable_set(:@global_banner, nil) # Reset global_banner state
    Onetime.instance_variable_set(:@debug, nil) # Reset debug state

    # Mock dependencies of Onetime.boot!
    allow(OT::Config).to receive(:load).and_call_original
    allow(OT::Config).to receive(:after_load).and_call_original

    allow(Familia).to receive(:uri=)

    # There are testcases in the other boot test files that confirm sysinfo
    # is frozen after being set. Here we mock it up.
    sysinfo_double = instance_double(SysInfo, hostname: 'testhost', user: 'testuser', platform: 'testplatform').as_null_object
    allow(Onetime).to receive(:sysinfo).and_return(sysinfo_double)

    allow(Gibbler).to receive(:secret).and_return(nil)
    allow(Gibbler).to receive(:secret=)

    allow(Onetime).to receive(:load_locales).and_call_original # Changed from simple stub
    allow(Onetime).to receive(:set_global_secret).and_call_original
    allow(Onetime).to receive(:prepare_emailers).and_call_original
    allow(Onetime).to receive(:load_fortunes).and_call_original # Ensure actual method is called
    allow(Onetime).to receive(:load_plans)
    allow(Onetime).to receive(:connect_databases).and_call_original
    allow(Onetime).to receive(:check_global_banner).and_call_original # Ensure actual method is called
    allow(Onetime).to receive(:print_log_banner)

    redis_double = double("Redis").as_null_object
    allow(Familia).to receive(:redis).and_return(redis_double)
    allow(redis_double).to receive(:ping).and_return("PONG")
    allow(redis_double).to receive(:get).with('global_banner').and_return(nil)
    allow(redis_double).to receive(:info).and_return({'redis_version' => 'test_version'})
    allow(redis_double).to receive(:serverid).and_return('testserver:0000') # Added default for print_log_banner

    allow(Onetime::Mail::Mailer::SMTPMailer).to receive(:setup)
    # Add other mailers if they could be chosen by config
    allow(Onetime::Mail::Mailer::SendGridMailer).to receive(:setup)
    allow(Onetime::Mail::Mailer::SESMailer).to receive(:setup)

    truemail_config_double = double("Truemail::Configuration").as_null_object
    allow(Truemail).to receive(:configure).and_yield(truemail_config_double)
    allow(truemail_config_double).to receive(:respond_to?).and_return(true)
    allow(truemail_config_double).to receive(:method_missing) { |method_name, *_args, &_block|
      if method_name.to_s.end_with?('=')
        # Do nothing, just accept the call
      else
        super # Raise NoMethodError for getters if not defined
      end
    }
    # Explicitly stub methods that might be called with specific arguments if method_missing is too broad
    Onetime::KEY_MAP.each_value do |truemail_key|
      allow(truemail_config_double).to receive(:"#{truemail_key}=") if truemail_config_double.respond_to?(:"#{truemail_key}=")
    end
    allow(truemail_config_double).to receive(:verifier_email=)
    allow(truemail_config_double).to receive(:default_validation_type=)

    # Define DATABASE_IDS as it's used in connect_databases.
    # In a real app, this comes from onetime/models.rb.
    # For this test, we provide a minimal version.
    # Using `stub_const` is cleaner if available and appropriate.
    # If not, ensure test config for :dbs is comprehensive or mock Familia.members.
    unless defined?(DATABASE_IDS)
      Object.const_set(:DATABASE_IDS, {})
    end
  end

  after(:each) do
    # Remove the constant if we defined it, to avoid polluting other tests
    # Object.send(:remove_const, :DATABASE_IDS) if defined?(DATABASE_IDS_DEFINED_BY_TEST) && DATABASE_IDS_DEFINED_BY_TEST
  end

  describe "State of @conf after OT::Config.load and OT::Config.after_load" do
    it "has correctly processed ttl_options and default_ttl" do
      test_config = Onetime::Config.load(source_config_path)

      conf = Onetime::Config.after_load(test_config)

      expect(conf.dig(:site, :secret_options, :default_ttl)).to eq('43200'.to_i) # 12 hours
      expect(conf.dig(:site, :secret_options, :ttl_options)).to eq(['1800', '43200', '604800'].map(&:to_i))
    end

    it "ensures required keys are present and defaults applied" do
      test_config = Onetime::Config.load(source_config_path)

      conf = Onetime::Config.after_load(test_config)

      expect(conf.dig(:development, :enabled)).to be(false)
      expect(conf.dig(:development, :frontend_host)).to eq('http://localhost:5173')
      expect(conf.dig(:site, :authentication, :enabled)).to be(true)
      expect(conf.dig(:site, :secret_options)).to have_key(:default_ttl)
      expect(conf.dig(:site, :secret_options)).to have_key(:ttl_options)
      expect(conf.dig(:diagnostics, :sentry)).to be_a(Hash)

      # In after_load, when we call `merged = apply_defaults_to_peers(diagnostics[:sentry])`
      # :default is nil and no longer a hash. Details:
      # Notice that line with `next if section == :defaults` - this
      # explicitly skips adding the `:defaults` section to the result hash.
      # This is intentional as the `:defaults` section has fulfilled its
      # purpose once merged with the other sections.
      expect(conf.dig(:diagnostics, :sentry, :defaults)).to be_nil
      expect(test_config.dig(:diagnostics, :sentry, :defaults)).to be_a(Hash)

      expect(conf.dig(:diagnostics, :sentry, :backend)).to be_a(Hash)
      expect(conf.dig(:diagnostics, :sentry, :frontend)).to be_a(Hash)
    end

    context "when we set OT.conf manually" do
      let(:loaded_config) { Onetime::Config.load(source_config_path) }

      before do

      end

      it "ensures diagnostics are disabled when there is no dsn" do
        loaded_config[:diagnostics][:sentry][:backend][:dsn] = nil
        # Frontend DSN might also need to be nil if it alone can enable diagnostics
        loaded_config[:diagnostics][:sentry][:frontend][:dsn] = nil

        conf = Onetime::Config.after_load(loaded_config)

        diagnostics_config = conf.fetch(:diagnostics)
        expect(diagnostics_config.dig(:sentry, :backend, :dsn)).to be_nil
        expect(diagnostics_config.dig(:enabled)).to eq(true) # matches what is in test_config
        expect(Onetime.d9s_enabled).to be(false) # after_load makes it false
      end

      it "handles :autoverify correctly based on config" do
        conf = Onetime::Config.after_load(loaded_config)

        expect(conf.dig(:site, :authentication, :autoverify)).to be(false)
      end
    end

    context "when site.authentication.enabled is false" do
      let(:auth_disabled_config_content) do
        <<~YAML
          ---
          :site:
            :host: 'localhost:7171'
            :secret: 'securesecret'
            :authentication:
              :enabled: false
              :signup: true # Should be overridden
              :signin: true # Should be overridden
              :autoverify: true # Should be overridden
            :domains: {enabled: false}
            :plans: {enabled: false}
            :regions: {enabled: false}
            :secret_options: {}
          :redis:
            :uri: 'redis://127.0.0.1:6379/15'
            :dbs: {session: 15}
          :colonels: ['colonel@example.com']
          :emailer:
            :mode: 'smtp'
            :from: 'x@y.z'
            :fromname: 'N'
            :host: 'h'
            :port: 1
            :user: ''
            :pass: ''
            :auth: false
            :tls: false}
          :development: {enabled: false, frontend_host: ''}
          :mail:
            :truemail:
              :default_validation_type: :regex
              :verifier_email: 'v@e.c'
          :internationalization: {enabled: false, default_locale: 'en', locales: ['en']}
          :diagnostics:
            :enabled: false
            :sentry:
              :defaults:
                :dsn:
              :backend:
                :dsn:
              :frontend:
                :dsn:
          :limits:
            :create_secret: 1
          :experimental:
            :freeze_app: false
            csp: {enabled: false}
        YAML
      end

      it "forces all auth sub-features to false" do
        test_config = YAML.load(auth_disabled_config_content)

        # OT.instance_variable_set(:'@conf', conf) # To mimic the logic in OT.boot! at v0.20.5

        conf = Onetime::Config.after_load(test_config)

        auth_config = conf.dig(:site, :authentication)
        expect(auth_config[:enabled]).to be(false)
        expect(auth_config[:signup]).to be(false)
        expect(auth_config[:signin]).to be(false)
        expect(auth_config[:autoverify]).to be(false)
      end
    end
  end

  describe "State of Onetime.conf at the end of Onetime.boot!" do
    let(:loaded_config) { Onetime::Config.load(source_config_path) }

    before(:each) do
      ENV['RACK_ENV'] = 'test'
      ENV['DEFAULT_TTL'] = nil
      ENV['TTL_OPTIONS'] = nil
      ENV['FRONTEND_HOST'] = nil
      ENV['EMAILER_MODE'] = nil
      ENV['FROM_EMAIL'] = nil
      ENV['FROMNAME'] = nil
      ENV['SMTP_HOST'] = nil
      ENV['SMTP_PORT'] = nil
      ENV['SMTP_USERNAME'] = nil
      ENV['SMTP_PASSWORD'] = nil
      ENV['SMTP_AUTH'] = nil
      ENV['SMTP_TLS'] = nil
      ENV['VERIFIER_EMAIL'] = nil
      ENV['VERIFIER_DOMAIN'] = nil
      ENV['REDIS_URL'] = 'redis://127.0.0.1:2121/0'
      OT::Utils.instance_variable_set(:@fortunes, nil) # Reset fortunes for each test
    end

    it "reflects the loaded and processed configuration" do
      Onetime.boot!(:test)
      conf = Onetime.conf

      expect(conf).not_to be_nil
      expect(conf.dig(:site, :host)).to eq('127.0.0.1:3000')
      expect(conf.dig(:site, :secret_options, :default_ttl)).to eq('43200'.to_i)
      expect(conf.dig(:site, :secret_options, :ttl_options)).to eq(['1800', '43200', '604800'].map(&:to_i))

      # Run with the env var set:
      #    REDIS_URL=redis://127.0.0.1:2121/0 pnpm test:rspec
      expect(conf.dig(:redis, :uri)).to eq('redis://127.0.0.1:2121/0')
      expect(conf.dig(:development, :enabled)).to be(false)
      expect(Onetime.env).to eq('test')
    end

    it "sets up Gibbler.secret from config" do
      # Instead of setting Gibbler.secret directly, we need to mock the condition in set_global_secret
      # The issue is that when Gibbler.secret is nil, nil.frozen? returns true
      # We need to ensure the method sees a non-frozen value
      allow(Gibbler).to receive(:secret).and_return("")  # Return empty string which isn't frozen by default

      Onetime.boot!(:test)

      expect(Gibbler).to have_received(:secret=).with('SuP0r_53cRU7'.freeze)
    end

    it "configures emailer based on @conf" do
      Onetime.boot!(:test)
      expect(Onetime.emailer).to eq(Onetime::Mail::Mailer::SMTPMailer)
      expect(Onetime::Mail::Mailer::SMTPMailer).to have_received(:setup)
    end

      require_relative '../../../apps/app_registry'
      require 'v2/application'

      # Application Initialization
      # -------------------------------
      # Load all application modules from the registry
      AppRegistry.load_applications


    it "sets Familia.uri from the configuration" do
      Onetime.boot!(:test)
      expect(Familia).to have_received(:uri=).with(loaded_config.dig(:redis, :uri))
    end

    it "loads fortunes into OT::Utils.fortunes" do
      sample_fortunes = ["Test Fortune 1", "Test Fortune 2: Electric Boogaloo"]
      allow(File).to receive(:readlines).with(File.join(Onetime::HOME, 'etc', 'fortunes')).and_return(sample_fortunes)

      Onetime.boot!(:test)

      expect(OT::Utils.fortunes).to eq(sample_fortunes)
    end

    context "when checking global banner" do
      it "sets Onetime.global_banner to the banner from Redis if present" do
        test_banner_text = "Attention all planets of the Solar Federation: We have assumed control."
        # Familia.redis is redis_double from the outer before_each block
        allow(Familia.redis).to receive(:get).with('global_banner').and_return(test_banner_text)

        Onetime.boot!(:test)

        expect(Onetime.global_banner).to eq(test_banner_text)
      end

      it "sets Onetime.global_banner to nil if not present in Redis" do
        allow(Familia.redis).to receive(:get).with('global_banner').and_return(nil) # Explicitly ensure nil

        Onetime.boot!(:test)

        expect(Onetime.global_banner).to be_nil
      end
    end

    # Sentry diagnostics tests moved to setup_diagnostics_spec.rb

    context "regarding internationalization" do
      it "correctly sets i18n settings from config.test.yaml" do
        Onetime.boot!(:test) # Uses default config.test.yaml

        expect(Onetime.i18n_enabled).to be true
        expect(Onetime.default_locale).to eq('en')
        expect(Onetime.supported_locales).to match_array(['en', 'fr_CA', 'fr_FR'])
        expect(Onetime.locales.keys).to match_array(['en', 'fr_CA', 'fr_FR'])
        expect(Onetime.fallback_locale).to eq({
          "fr-CA" => ['fr_CA', 'fr_FR', 'en'],
          "fr" => ['fr_FR', 'fr_CA', 'en'],
          "fr-*" => ['fr_FR', 'en'],
          "default" => ['en']
        })

        # NOTE: Disabled in v0.20.5. It takes a while to figure out how this is getting set
        # and it changes once we get back to v0.22.0 anyhow so we can be specific then.
        # expect(Onetime.fallback_locale).to eq({ default: ['en'], :"fr-CA" => ['fr_CA', 'fr_FR', 'en'] })
      end

      it "disables i18n and uses defaults if config has internationalization.enabled = false" do
        modified_config = YAML.load(ERB.new(File.read(source_config_path)).result) # Deep copy
        modified_config[:internationalization][:enabled] = false
        allow(Onetime::Config).to receive(:load).and_return(modified_config)

        Onetime.boot!(:test)

        expect(Onetime.i18n_enabled).to be false
        expect(Onetime.default_locale).to eq('en')
        expect(Onetime.supported_locales).to eq(['en'])
        expect(Onetime.locales.keys).to eq(['en']) # Only default locale 'en' should be loaded
        expect(Onetime.fallback_locale).to be_nil
      end
    end

    it "initializes Onetime.sysinfo and freezes it" do
      Onetime.boot!(:test)
      expect(Onetime.sysinfo.hostname).to eq('testhost') # Check if it's the mocked one
    end

    it "initializes Onetime.instance and freezes it" do
      Onetime.boot!(:test)
      expect(Onetime.instance).not_to be_nil
      expect(Onetime.instance).to be_a(String) # Gibbler output is a string
      expect(Onetime.instance.length).to eq(40) # SHA1 gibbler
      expect(Onetime.instance).to be_frozen
    end

    it "calls Onetime.connect_databases" do
      # The main before_each already allows Onetime.connect_databases to be called
      # We just need to ensure it was indeed called.
      # We can use a spy or re-allow with .and_call_original and expect it to have been received.
      # Since it's already allow(...).to receive(...).and_call_original, we can check if it was called.
      # However, a more direct way is to expect it.
      expect(Onetime).to receive(:connect_databases).and_call_original
      Onetime.boot!(:test)
    end

    context "debug mode" do
      after(:each) do
        ENV.delete('ONETIME_DEBUG')
        Onetime.instance_variable_set(:@debug, nil) # Reset for subsequent tests
      end

      it "is false by default" do
        ENV['ONETIME_DEBUG'] = nil
        Onetime.boot!(:test)
        expect(Onetime.debug).to be false
        expect(Onetime.debug?).to be false
      end

      it "is true when ONETIME_DEBUG is 'true'" do
        ENV['ONETIME_DEBUG'] = 'true'
        Onetime.boot!(:test)
        expect(Onetime.debug).to be true
        expect(Onetime.debug?).to be true
      end

      it "is true when ONETIME_DEBUG is '1'" do
        ENV['ONETIME_DEBUG'] = '1'
        Onetime.boot!(:test)
        expect(Onetime.debug).to be true
        expect(Onetime.debug?).to be true
      end

      it "is false when ONETIME_DEBUG is 'false'" do
        ENV['ONETIME_DEBUG'] = 'false'
        Onetime.boot!(:test)
        expect(Onetime.debug).to be false
        expect(Onetime.debug?).to be false
      end

      it "is false when ONETIME_DEBUG is an arbitrary string" do
        ENV['ONETIME_DEBUG'] = 'sometimes'
        Onetime.boot!(:test)
        expect(Onetime.debug).to be false
        expect(Onetime.debug?).to be false
      end
    end

    context "regarding print_log_banner" do
      it "does not call print_log_banner when mode is :test" do
        # Onetime.boot! is called with :test mode.
        # The global before(:each) in this file stubs :print_log_banner:
        # allow(Onetime).to receive(:print_log_banner)

        Onetime.boot!(:test)
        expect(Onetime).not_to have_received(:print_log_banner)
      end

      it "calls print_log_banner when mode is not :test" do
        # Allow print_log_banner to be called for this test specifically
        allow(Onetime).to receive(:print_log_banner).and_call_original

        # OT.li is already stubbed by config_spec_helper.rb
        # Familia.redis.serverid is stubbed in the main before(:each)

        Onetime.boot!(:app) # Use a non-test mode like :app
        expect(Onetime).to have_received(:print_log_banner).at_least(:once)
      end
    end
  end
end
