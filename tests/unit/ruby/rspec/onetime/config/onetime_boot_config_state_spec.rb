# tests/unit/ruby/rspec/onetime/config/onetime_boot_config_state_spec.rb

require_relative '../../spec_helper'
require 'fileutils' # For managing temp config files
require 'yaml'      # For parsing YAML strings
require 'erb'       # For processing ERB in YAML strings

RSpec.describe "Onetime::Config during Onetime.boot!" do
  let(:source_config_path) { File.expand_path(File.join(Onetime::HOME, 'tests', 'unit', 'ruby', 'config.test.yaml')) }

  before(:all) do
    # Ensure Onetime module is in a clean state for these tests
  end

  before(:each) do
    # Mock Onetime::Config.path to use the actual test config file
    allow(Onetime::Config).to receive(:path).and_return(source_config_path)
    allow(Onetime::Config).to receive(:find_configs).and_return([source_config_path])

    # Reset Onetime main module state
    Onetime.instance_variable_set(:@conf, nil)
    Onetime.instance_variable_set(:@mode, :app)
    Onetime.instance_variable_set(:@env, 'test')
    Onetime.instance_variable_set(:@d9s_enabled, false)
    Onetime.instance_variable_set(:@i18n_enabled, false)
    Onetime.instance_variable_set(:@supported_locales, ['en'])
    Onetime.instance_variable_set(:@default_locale, 'en')
    Onetime.instance_variable_set(:@fallback_locale, nil)
    Onetime.instance_variable_set(:@locales, nil)
    Onetime.instance_variable_set(:@instance, nil)
    Onetime.instance_variable_set(:@sysinfo, nil)
    Onetime.instance_variable_set(:@emailer, nil)
    Onetime.instance_variable_set(:@global_secret, nil)
    Onetime.instance_variable_set(:@global_banner, nil)
    Onetime.instance_variable_set(:@debug, nil) # Reset debug state

    # Mock dependencies of Onetime.boot!
    allow(OT::Config).to receive(:load).and_call_original
    allow(OT::Config).to receive(:after_load).and_call_original

    allow(Familia).to receive(:uri=)
    sysinfo_double = instance_double(SysInfo, hostname: 'testhost', user: 'testuser', platform: 'testplatform').as_null_object
    allow(SysInfo).to receive(:new).and_return(sysinfo_double)
    allow(Gibbler).to receive(:secret).and_return(nil) # See related TODO in set_global_secret
    allow(Gibbler).to receive(:secret=)

    allow(Onetime).to receive(:load_locales)
    allow(Onetime).to receive(:set_global_secret).and_call_original
    allow(Onetime).to receive(:prepare_emailers).and_call_original
    allow(Onetime).to receive(:prepare_rate_limits).and_call_original
    allow(Onetime).to receive(:load_fortunes)
    allow(Onetime).to receive(:load_plans)
    allow(Onetime).to receive(:connect_databases).and_call_original
    allow(Onetime).to receive(:check_global_banner)
    allow(Onetime).to receive(:print_log_banner)

    redis_double = double("Redis").as_null_object
    allow(Familia).to receive(:redis).and_return(redis_double)
    allow(redis_double).to receive(:ping).and_return("PONG")
    allow(redis_double).to receive(:get).with('global_banner').and_return(nil)
    allow(redis_double).to receive(:info).and_return({'redis_version' => 'test_version'})

    allow(Onetime::App::Mail::SMTPMailer).to receive(:setup)
    # Add other mailers if they could be chosen by config
    allow(Onetime::App::Mail::SendGridMailer).to receive(:setup)
    allow(Onetime::App::Mail::AmazonSESMailer).to receive(:setup)

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
      conf = Onetime::Config.load(source_config_path)

      OT.instance_variable_set(:'@conf', conf) # To mimic the logic in OT.boot! at v0.20.5

      Onetime::Config.after_load(conf)

      expect(conf.dig(:site, :secret_options, :default_ttl)).to eq('43200'.to_i) # 12 hours
      expect(conf.dig(:site, :secret_options, :ttl_options)).to eq(['1800', '43200', '604800'].map(&:to_i))
    end

    it "ensures required keys are present and defaults applied" do
      conf = Onetime::Config.load(source_config_path)

      OT.instance_variable_set(:'@conf', conf) # To mimic the logic in OT.boot! at v0.20.5

      Onetime::Config.after_load(conf)

      expect(conf.dig(:development, :enabled)).to be(false)
      expect(conf.dig(:development, :frontend_host)).to eq('http://localhost:5173')
      expect(conf.dig(:site, :authentication, :enabled)).to be(true)
      expect(conf.dig(:site, :secret_options)).to have_key(:default_ttl)
      expect(conf.dig(:site, :secret_options)).to have_key(:ttl_options)
      expect(conf.dig(:diagnostics, :sentry)).to be_a(Hash)

      # In after_load, when we call `merged = apply_defaults(diagnostics[:sentry])`
      # :default is nil and no longer a hash. Details:
      # Notice that line with `next if section == :defaults` - this
      # explicitly skips adding the `:defaults` section to the result hash.
      # This is intentional as the `:defaults` section has fulfilled its
      # purpose once merged with the other sections.
      expect(conf.dig(:diagnostics, :sentry, :defaults)).to be_nil
      #expect(conf.dig(:diagnostics, :sentry, :defaults)).to be_a(Hash)

      expect(conf.dig(:diagnostics, :sentry, :backend)).to be_a(Hash)
      expect(conf.dig(:diagnostics, :sentry, :frontend)).to be_a(Hash)
    end

    context "when we set OT.conf manually" do

      before do
        conf = Onetime::Config.load(source_config_path)
        OT.instance_variable_set(:'@conf', conf) # To mimic the logic in OT.boot! at v0.20.5
      end

      it "ensures diagnostics are disabled when there is no dsn" do
        OT.conf[:diagnostics][:sentry][:backend][:dsn] = nil
        conf = OT.conf
        Onetime::Config.after_load(conf)

        d9s_conf = conf.fetch(:diagnostics)

        expect(d9s_conf.dig(:sentry, :backend, :dsn)).to be_nil
        expect(conf.dig(:diagnostics, :enabled)).to eq(false)
        expect(OT.d9s_enabled).to be(false)

      end


      it "handles :autoverify correctly based on config" do
        conf = OT.conf
        Onetime::Config.after_load(conf)
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
        conf = YAML.load(auth_disabled_config_content)

        OT.instance_variable_set(:'@conf', conf) # To mimic the logic in OT.boot! at v0.20.5

        Onetime::Config.after_load(conf)

        auth_config = conf.dig(:site, :authentication)
        expect(auth_config[:enabled]).to be(false)
        expect(auth_config[:signup]).to be(false)
        expect(auth_config[:signin]).to be(false)
        expect(auth_config[:autoverify]).to be(false)
      end
    end
  end

  describe "State of Onetime.conf at the end of Onetime.boot!" do
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
    end

    it "reflects the loaded and processed configuration" do
      Onetime.boot!(:test)
      conf = Onetime.conf

      expect(conf).not_to be_nil
      expect(conf.dig(:site, :host)).to eq('127.0.0.1:3000')
      expect(conf.dig(:site, :secret_options, :default_ttl)).to eq('43200'.to_i)
      expect(conf.dig(:site, :secret_options, :ttl_options)).to eq(['1800', '43200', '604800'].map(&:to_i))
      expect(conf.dig(:redis, :uri)).to eq('redis://CHANGEME@127.0.0.1:6379/0')
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
      expect(Onetime.emailer).to eq(Onetime::App::Mail::SMTPMailer)
      expect(Onetime::App::Mail::SMTPMailer).to have_received(:setup)
    end

    it "configures rate limits based on @conf" do
      allow(OT::RateLimit).to receive(:register_events)
      Onetime.boot!(:test)
      expect(OT::RateLimit).to have_received(:register_events).with(Onetime.conf[:limits])
    end

  end
end
