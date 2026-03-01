# spec/integration/all/initializers/boot_part1_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils' # For managing temp config files
require 'yaml'      # For parsing YAML strings
require 'erb'       # For processing ERB in YAML strings

RSpec.describe "Onetime::Config during Onetime.boot!", type: :integration do
  let(:source_config_path) { File.expand_path(File.join(Onetime::HOME, 'spec', 'config.test.yaml')) }

  before(:all) do
    # Ensure Onetime module is in a clean state for these tests
  end

  before(:each) do
    # Set test database URL before any config loading
    # This must be set BEFORE config is loaded via ERB since config.test.yaml
    # uses ENV['VALKEY_URL'] || ENV['REDIS_URL'] || 'redis://127.0.0.1:6379/0'

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
    Onetime.instance_variable_set(:@emailer, nil)
    Onetime.instance_variable_set(:@global_secret, nil)
    Onetime.instance_variable_set(:@global_banner, nil) # Reset global_banner state
    Onetime.instance_variable_set(:@debug, nil) # Reset debug state

    # Mock dependencies of Onetime.boot!
    allow(OT::Config).to receive(:load).and_call_original
    allow(OT::Config).to receive(:after_load).and_call_original

    allow(Familia).to receive(:uri=)

    # NOTE: The boot process now uses InitializerRegistry with initializer classes.
    # These methods no longer exist as direct module methods on Onetime.
    # Initializers run automatically via InitializerRegistry during boot!.
    #
    # To skip specific initializers in tests, you can:
    # 1. Let them run (they're designed to work in test mode)
    # 2. Stub the initializer class's execute method directly
    # 3. Create a fresh registry instance with explicit load([classes]) calls (pure DI)

    # Reset registry and Onetime ready state before each test
    Onetime.not_ready

    # NOTE: Tests that call boot! rely on a real database connection.
    # The VALKEY_URL environment variable should be set to the test database.
    # We only stub things that would cause side effects or output.
    #
    # If VALKEY_URL is not set, tests will fail - this is intentional to
    # ensure test infrastructure is properly configured.

    # Mailer classes have been refactored to Onetime::Mail::Delivery::*
    # They no longer have a setup class method - they're instantiated with config.
    # No mocking needed for boot tests.

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

    # Reset ready state so subsequent tests can boot properly
    Onetime.reset_ready!
  end

  describe "State of @conf after OT::Config.load and OT::Config.after_load" do
    it "has correctly processed ttl_options and default_ttl" do
      test_config = Onetime::Config.load(source_config_path)

      conf = Onetime::Config.after_load(test_config)

      expect(conf.dig('site', 'secret_options', 'default_ttl')).to eq('43200'.to_i) # 12 hours
      expect(conf.dig('site', 'secret_options', 'ttl_options')).to eq(%w[1800 43200 604800].map(&:to_i))
    end
    it "ensures required keys are present and defaults applied" do
      test_config = Onetime::Config.load(source_config_path)

      conf = Onetime::Config.after_load(test_config)

      expect(conf.dig('development', 'enabled')).to be(false)
      expect(conf.dig('development', 'frontend_host')).to eq('http://localhost:5173')
      expect(conf.dig('site', 'authentication', 'enabled')).to be(true)
      expect(conf.dig('site', 'secret_options')).to have_key('default_ttl')
      expect(conf.dig('site', 'secret_options')).to have_key('ttl_options')
      expect(conf.dig('diagnostics', 'sentry')).to be_a(Hash)
      # In after_load, when we call `merged = apply_defaults_to_peers(diagnostics[:sentry])`
      # :default is nil and no longer a hash. Details:
      # Notice that line with `next if section == :defaults` - this
      # explicitly skips adding the `:defaults` section to the result hash.
      # This is intentional as the 'defaults' section has fulfilled its
      # purpose once merged with the other sections.
      expect(conf.dig('diagnostics', 'sentry', 'defaults')).to be_nil
      expect(test_config.dig('diagnostics', 'sentry', 'defaults')).to be_a(Hash)

      expect(conf.dig('diagnostics', 'sentry', 'backend')).to be_a(Hash)
      expect(conf.dig('diagnostics', 'sentry', 'frontend')).to be_a(Hash)
    end

    context "when we set OT.conf manually" do
      let(:loaded_config) { Onetime::Config.load(source_config_path) }

      before do

      end

      it "ensures diagnostics are disabled when there is no dsn" do
        loaded_config['diagnostics']['sentry']['backend']['dsn'] = nil
        # Frontend DSN might also need to be nil if it alone can enable diagnostics
        loaded_config['diagnostics']['sentry']['frontend']['dsn'] = nil

        conf = Onetime::Config.after_load(loaded_config)

        diagnostics_config = conf.fetch('diagnostics')
        expect(diagnostics_config.dig('sentry', 'backend', 'dsn')).to be_nil
        expect(diagnostics_config['enabled']).to be(true) # matches what is in test_config
        expect(Onetime.d9s_enabled).to be(false) # after_load makes it false
      end

      it "handles :autoverify correctly based on config" do
        conf = Onetime::Config.after_load(loaded_config)

        expect(conf.dig('site', 'authentication', 'autoverify')).to be(false)
      end
    end

    context "when site.authentication.enabled is false" do
      let(:auth_disabled_config_content) do
        <<~YAML
        ---
        site:
          host: 'localhost:7171'
          secret: 'securesecret'
          authentication:
            enabled: false
            signup: true # Should be overridden
            signin: true # Should be overridden
            autoverify: true # Should be overridden
          domains: {enabled: false}
          regions: {enabled: false}
          secret_options: {}
        redis:
          uri: 'redis://127.0.0.1:6379/15'
          dbs: {session: 15}
        emailer:
          mode: 'smtp'
          from: 'x@y.z'
          from_name: 'N'
          host: 'h'
          port: 1
          user: ''
          pass: ''
          auth: false
          tls: false
        development: {enabled: false, frontend_host: ''}
        billing: {enabled: false}
        mail:
          truemail:
            default_validation_type: :regex
            verifier_email: 'v@e.c'
        internationalization: {enabled: false, default_locale: 'en', locales: ['en']}
        diagnostics:
          enabled: false
          sentry:
            defaults:
              dsn:
            backend:
              dsn:
            frontend:
              dsn:
        YAML
      end

      it "forces all auth sub-features to false" do
        test_config = YAML.load(auth_disabled_config_content)

        # OT.instance_variable_set(:'@conf', conf) # To mimic the logic in OT.boot! at v0.20.5

        conf = Onetime::Config.after_load(test_config)

        auth_config = conf.dig('site', 'authentication')
        expect(auth_config['enabled']).to be(false)
        expect(auth_config['signup']).to be(false)
        expect(auth_config['signin']).to be(false)
        expect(auth_config['autoverify']).to be(false)
      end
    end
  end

  describe "State of Onetime.conf at the end of Onetime.boot!" do
    let(:loaded_config) { Onetime::Config.load(source_config_path) }

    before(:each) do
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
      OT::Utils.instance_variable_set(:@fortunes, nil) # Reset fortunes for each test
    end

    it "reflects the loaded and processed configuration" do
      Onetime.boot!(:test)
      conf = Onetime.conf

      expect(conf).not_to be_nil
      expect(conf.dig('site', 'host')).to eq('127.0.0.1:3000')
      expect(conf.dig('site', 'secret_options', 'default_ttl')).to eq('43200'.to_i)
      expect(conf.dig('site', 'secret_options', 'ttl_options')).to eq(%w[1800 43200 604800].map(&:to_i))

      # Run with the env var set:
      #    VALKEY_URL=redis://127.0.0.1:2121/0 pnpm test:rspec
      expect(conf.dig('redis', 'uri')).to eq('redis://127.0.0.1:2121/0')
      expect(conf.dig('development', 'enabled')).to be(false)
      expect(Onetime.env).to eq('testing')
    end

    it "configures emailer based on @conf" do
      Onetime.boot!(:test)
      # The emailer is now configured via OT.conf['emailer'] and accessed
      # through Onetime::Mail::Mailer.send_email or similar methods.
      # Verify the config is set correctly (test config uses 'logger' mode):
      expect(Onetime.conf.dig('emailer', 'mode')).to eq('logger')
    end

    it "sets Familia.uri from the configuration" do
      Onetime.boot!(:test)
      expect(Familia).to have_received(:uri=).with(loaded_config.dig('redis', 'uri'))
    end

    it "loads fortunes into Onetime::Runtime.features" do
      # The fortunes are loaded during boot from etc/fortunes file
      Onetime.boot!(:test)

      # Fortunes should be loaded (non-empty array) after boot
      # NOTE: Fortunes are now stored in Runtime.features, not OT::Utils.fortunes
      features = Onetime::Runtime.features
      expect(features).not_to be_nil
      expect(features.fortunes).to be_an(Array)
      expect(features.fortunes).not_to be_empty
    end

    context "when checking global banner" do
      let(:test_banner_text) { "Attention all planets of the Solar Federation: We have assumed control." }

      it "sets Onetime.global_banner to the banner from the database if present" do
        # Do a first boot to set up Familia, then set banner and re-test
        Onetime.boot!(:test)

        # Set the banner after boot (Familia is now connected)
        Familia.dbclient.set('global_banner', test_banner_text)

        # Reset and boot again to pick up the banner
        Onetime.not_ready
        Onetime.boot!(:test)

        expect(Onetime.global_banner).to eq(test_banner_text)

        # Clean up
        Familia.dbclient.del('global_banner')
      end

      it "sets Onetime.global_banner to nil if not present in Redis" do
        Onetime.boot!(:test)

        # Ensure no banner is set and check the runtime state
        Familia.dbclient.del('global_banner')

        # Reset and boot again
        Onetime.not_ready
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
        modified_config['internationalization']['enabled'] = false

        # Write modified config to temp file for the Configurator pipeline to load
        Tempfile.create(['test_config_i18n_disabled', '.yaml']) do |f|
          f.write(YAML.dump(modified_config))
          f.flush
          allow(Onetime::Config).to receive(:path).and_return(f.path)

          Onetime.boot!(:test)
        end

        expect(Onetime.i18n_enabled).to be false
        expect(Onetime.default_locale).to eq('en')
        expect(Onetime.supported_locales).to eq(['en'])
        expect(Onetime.locales.keys).to eq(['en']) # Only default locale 'en' should be loaded
        expect(Onetime.fallback_locale).to be_nil
      end
    end

    it "initializes Onetime.instance and freezes it" do
      Onetime.boot!(:test)
      expect(Onetime.instance).not_to be_nil
      expect(Onetime.instance).to be_a(String)
      expect(Onetime.instance.length).to be_between(12, 17).inclusive
      expect(Onetime.instance).to be_frozen
    end

    it "runs the ConfigureFamilia initializer (database connection)" do
      # The boot process now uses InitializerRegistry with initializer classes.
      # ConfigureFamilia replaces the old Onetime.connect_databases method.
      Onetime.boot!(:test)

      # Check that the ConfigureFamilia initializer completed successfully
      initializer = Onetime.boot_registry.initializers.find do |i|
        i.name == :"onetime.initializers.configure_familia"
      end
      expect(initializer).not_to be_nil
      expect(initializer.completed?).to be true
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
      it "runs PrintLogBanner initializer during boot" do
        # The PrintLogBanner initializer runs in all modes (including test).
        # It logs system information to help with debugging.
        Onetime.boot!(:test)

        initializer = Onetime.boot_registry.initializers.find do |i|
          i.name == :"onetime.initializers.print_log_banner"
        end
        expect(initializer).not_to be_nil
        expect(initializer.completed?).to be true
      end
    end
  end
end
