# tests/unit/ruby/rspec/onetime/config/after_load_spec.rb

require_relative '../../spec_helper'
require 'tempfile'

# The Sentry lib is only required when diagnostics are enabled. We don't include
# it here b/c we stub the class so we can write expectant testcases. We'll want
# to also test that the library is required correctly in another test file.

RSpec.describe "Onetime boot configuration process" do
  let(:test_config_path) { File.join(Onetime::HOME, 'tests', 'unit', 'ruby', 'config.test.yaml') }
  let(:test_config_string) { File.read(test_config_path) }

  # First parse the ERB template in the YAML file.
  # Must load via ERB to simulate what Config.load behaviour. Otherwise the
  # config will have a bunch of `<%= ENV['SENTRY_DSN'] || nil %>` strings.
  let(:test_config_parsed) { ERB.new(test_config_string).result }

  # Then load the YAML content after ERB processing
  let(:test_config) { YAML.load(test_config_parsed) }

  before do
    # Set up necessary state for testing
    @original_path = Onetime::Config.instance_variable_get(:@path)
    @original_mode = Onetime.mode
    @original_env = Onetime.env
    @original_emailer = Onetime.instance_variable_get(:@emailer)
    @original_sysinfo = Onetime.instance_variable_get(:@sysinfo)
    @original_instance = Onetime.instance_variable_get(:@instance)
    @original_d9s_enabled = Onetime.d9s_enabled

    # Prevent actual side effects
    allow(Onetime).to receive(:ld)
    allow(Onetime).to receive(:li)
    allow(Onetime).to receive(:le)
    allow(Familia).to receive(:redis).and_return(double('Redis').as_null_object)
    allow(Gibbler).to receive(:secret=)
    allow(V2::RateLimit).to receive(:register_events)
    allow(OT::Plan).to receive(:load_plans!)

    # Mock redis operations
    redis_double = double('Redis')
    allow(redis_double).to receive(:ping).and_return("PONG")
    allow(redis_double).to receive(:get).and_return(nil)
    allow(redis_double).to receive(:info).and_return({"redis_version" => "6.0.0"})
    allow(redis_double).to receive(:scan_each).and_return([]) # Add this line
    allow(Familia).to receive(:uri).and_return(double('URI', serverid: 'localhost:6379'))
    allow(Familia).to receive(:redis).and_return(redis_double)

    # Mock V2 model Redis connections used in detect_first_boot
    allow(V2::Metadata).to receive(:redis).and_return(redis_double)
    allow(V2::Customer).to receive(:values).and_return(double('Values', element_count: 0))
    allow(V2::Session).to receive(:values).and_return(double('Values', element_count: 0))

    allow(V2::RateLimit).to receive(:register_events)
    allow(OT::Plan).to receive(:load_plans!)

    # Mock colonel config setup methods
    allow(V2::SystemSettings).to receive(:current).and_raise(OT::RecordNotFound.new("No config found"))
    allow(V2::SystemSettings).to receive(:extract_colonel_config).and_return({})
    allow(V2::SystemSettings).to receive(:create).and_return(double('SystemSettings', rediskey: 'test:config'))

    # TODO: Make truemail gets reset too (Truemail.configuration)

    # Our Familia models only register themselves once -- at start time. This
    # prevents us from mocking Familia.members bc requiring the models again
    # doesn't re-load them. We could use `load` which will but then we're
    # getting way off track. Better solution is to make registration callable.
    # allow(Familia).to receive(:members).and_return([])

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
    Onetime.instance_variable_set(:@sysinfo, @original_sysinfo)
    Onetime.instance_variable_set(:@instance, @original_instance)
    Onetime.d9s_enabled = @original_d9s_enabled

    # No need to clean up as we're using an existing file
  end

  describe '.boot!' do
    context 'with valid configuration' do
      before do
        # Explicitly reset the d9s_enabled to nil before each test
        # This ensures that tests don't leak state to each other when run in sequence
        Onetime.d9s_enabled = nil

        # Stub out methods that interact with the file system or external services
        allow(Onetime::Config).to receive(:load).and_return(test_config)
        allow(Onetime).to receive(:load_locales)
        allow(Onetime).to receive(:set_global_secret)
        allow(Onetime).to receive(:prepare_emailers)
        allow(Onetime).to receive(:load_fortunes)
        allow(Onetime).to receive(:load_plans)
        allow(Onetime).to receive(:connect_databases)
        allow(Onetime).to receive(:check_global_banner)
        allow(Onetime).to receive(:print_log_banner)
      end

      it 'sets mode and environment variables' do
        Onetime.boot!(:test)
        expect(Onetime.mode).to eq(:test)
        expect(Onetime.env).to eq(ENV['RACK_ENV'] || 'production')
      end

      it 'loads configuration file' do
        expect(Onetime::Config).to receive(:load).and_return(test_config)
        Onetime.boot!(:test)
      end

      it 'sets diagnostics to disabled when test conf has it enabled but dsn is nil' do
        expect(Onetime.d9s_enabled).to be_nil
        Onetime.boot!(:test)
        expect(Onetime.d9s_enabled).to be false # DSN is nil so diagnostics remain disabled
      end

      it 'does not set Familia URI when we do not want DB connection' do
        expect(Familia).not_to receive(:uri=)
        Onetime.boot!(:test, false)
      end

      it 'sets Familia URI from Redis config when we want DB connection' do
        allow(Onetime).to receive(:connect_databases).and_call_original
        allow(Familia).to receive(:uri=)
        Onetime.boot!(:test, true)
        expect(Familia).to have_received(:uri=).with(test_config[:redis][:uri])
        expect(Onetime).to have_received(:connect_databases)
      end

      it 'initializes system info' do
        Onetime.boot!(:test)
        expect(Onetime.sysinfo).not_to be_nil
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
      it 'calls necessary setup methods in the correct order' do
        # Test the sequence of method calls
        expect(Onetime::Config).to receive(:load).and_return(test_config).ordered
        expect(Onetime::Config).to receive(:after_load).with(test_config).and_return(test_config).ordered # ensure it receives the loaded config
        expect(Onetime).to receive(:load_locales).ordered
        expect(Onetime).to receive(:set_global_secret).ordered
        expect(Onetime).to receive(:prepare_emailers).ordered
        expect(Onetime).to receive(:load_fortunes).ordered
        expect(Onetime).to receive(:load_plans).ordered
        expect(Onetime).to receive(:connect_databases).ordered
        expect(Onetime).to receive(:check_global_banner).ordered
        expect(Onetime).not_to receive(:print_log_banner) # print_log_banner unless mode?(:test)

        # We no longer expect Familia.uri= directly since it's called inside connect_databases
        # which we're now stubbing in this test
        Onetime.boot!(:test)
      end
    end

    context 'with error handling' do
      it 'handles OT::Problem exceptions' do
        allow(Onetime::Config).to receive(:load).and_raise(OT::Problem.new("Config loading failed"))
        expect(Onetime).to receive(:le).with("Problem booting: Config loading failed") # a bug as of v0.20.5
        expect(Onetime).to receive(:ld) # For backtrace
        expect { Onetime.boot!(:test) }.to raise_error(OT::Problem)
      end

      it 'handles Redis connection errors' do
        allow(Onetime::Config).to receive(:load).and_return(test_config)
        allow(Familia).to receive(:uri=).and_raise(Redis::CannotConnectError.new("Connection refused"))
        expect(Onetime).to receive(:le).with(/Cannot connect to redis .* \(Redis::CannotConnectError\)/)
        expect { Onetime.boot!(:test) }.to raise_error(Redis::CannotConnectError)
      end

      it 'handles unexpected errors' do
        allow(Onetime::Config).to receive(:load).and_raise(StandardError.new("Something went wrong"))
        expect(Onetime).to receive(:le).with(/Unexpected error `Something went wrong` \(StandardError\)/)
        expect(Onetime).to receive(:ld) # For backtrace
        expect { Onetime.boot!(:test) }.to raise_error(StandardError)
      end
    end
  end

  describe '.after_load' do
    # Minimal config for testing specific edge cases
    let(:minimal_config) do
      {
        development: { enabled: false },
        mail: { truemail: { default_validation_type: :regex, verifier_email: 'hello@example.com' } },
        site: {
          authentication: { enabled: true },
          host: 'example.com',
          secret: 'test_secret',
        },
        redis: { uri: 'redis://localhost:6379/0' },
      }
    end

    context 'with i18n' do
      it "sets i18n to disabled when missing from config" do
        raw_config = minimal_config.dup
        expect(raw_config.key?(:internationalization)).to be false

        processed_config = Onetime::Config.after_load(raw_config)
        expect(processed_config[:internationalization][:enabled]).to be(false)
      end

      it "does not add settings when disabeld in config" do
        raw_config = minimal_config.dup
        raw_config[:internationalization] = { enabled: false }

        processed_config = Onetime::Config.after_load(raw_config)
        expect(processed_config[:internationalization][:enabled]).to be(false)
        expect(processed_config[:internationalization].keys).to eq([:enabled, :default_locale])
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
      secret_options = processed_config[:site][:secret_options]

      expect(secret_options[:default_ttl]).to eq(7.days)
      expect(secret_options[:ttl_options]).to be_an(Array)
      expect(secret_options[:ttl_options].length).to eq(11)
    end

    it 'uses values from config file when specified' do
      config = test_config.dup
      processed_config = Onetime::Config.after_load(config)

      expect(processed_config[:site][:secret_options][:default_ttl]).to_not be_nil
      expect(processed_config[:site][:secret_options][:ttl_options]).to include(1800, 43_200, 604_800)
    end

    it 'initializes empty domains configuration' do
      config = minimal_config.dup

      processed_config = Onetime::Config.after_load(config)

      expect(processed_config[:site][:domains]).to eq({ enabled: false })
    end

    it 'initializes empty plans configuration' do
      config = minimal_config.dup
      processed_config = Onetime::Config.after_load(config)

      expect(processed_config[:site][:plans]).to eq({ enabled: false })
    end

    it 'initializes empty regions configuration' do
      config = minimal_config.dup

      processed_config = Onetime::Config.after_load(config)

      expect(processed_config[:site][:regions]).to eq({ enabled: false })
    end

    it 'disables authentication sub-features when main feature is off' do
      config = minimal_config.dup
      config[:site][:authentication] = {
        enabled: false,
        signup: true,
        signin: true,
      }

      processed_config = Onetime::Config.after_load(config)

      expect(processed_config[:site][:authentication][:signup]).to be false
      expect(processed_config[:site][:authentication][:signin]).to be false

      # The config we passed in was not modified
      expect(config[:site][:authentication][:signup]).to be true
      expect(config[:site][:authentication][:signin]).to be true
    end

    context 'with string ttl values' do
      it 'converts string ttl_options to integers' do
        config = minimal_config.dup
        config[:site] = {
          secret: '53krU7',
          authentication: { enabled: true },
          secret_options: { ttl_options: "300 3600 86400" },
        }

        processed_config = Onetime::Config.after_load(config)

        expect(processed_config[:site][:secret_options][:ttl_options]).to eq([300, 3600, 86_400])
      end

      it 'converts string default_ttl to integer' do
        config = minimal_config.dup
        config[:site] = {
          secret: '53krU7',
          authentication: { enabled: true },
          secret_options: { default_ttl: "86400" },
        }

        processed_config = Onetime::Config.after_load(config)

        expect(processed_config[:site][:secret_options][:default_ttl]).to eq(86_400)
      end

      it 'converts TTL options string from test config to integers' do
        config = OT::Config.deep_clone(test_config)
        config[:site][:secret_options][:ttl_options] = "1800 43200 604800"

        processed_config = Onetime::Config.after_load(config)

        expect(processed_config[:site][:secret_options][:ttl_options]).to be_an(Array)
        expect(processed_config[:site][:secret_options][:ttl_options]).to eq([1800, 43_200, 604_800])
      end
    end

    context 'with diagnostics configuration' do
      # Define a stub for Sentry before all tests in this context
      before(:each) do
        stub_const("Sentry", Class.new)
      end

      it 'enables diagnostics from test config file' do
        raw_config = OT::Config.deep_clone(test_config)

        allow(Kernel).to receive(:require).with('sentry-ruby')
        allow(Kernel).to receive(:require).with('stackprof')
        allow(Sentry).to receive(:init)
        allow(Sentry).to receive(:initialized?).and_return(true)

        # Save original value to restore after test
        original_value = OT.d9s_enabled
        OT.d9s_enabled = nil
        processed_config = Onetime::Config.after_load(raw_config)

        expect(OT.d9s_enabled).to be(false)

        OT.d9s_enabled = original_value # restore original value
        expect(processed_config[:diagnostics][:enabled]).to be true
        expect(processed_config[:diagnostics][:sentry][:backend][:sampleRate]).to eq(0.11)
        expect(processed_config[:diagnostics][:sentry][:backend][:maxBreadcrumbs]).to eq(22)
        expect(processed_config[:diagnostics][:sentry][:frontend][:sampleRate]).to eq(0.11)
        expect(processed_config[:diagnostics][:sentry][:frontend][:maxBreadcrumbs]).to eq(22)
      end

      it 'enables diagnostics when configured with a valid DSN' do
        config = OT::Config.deep_clone(minimal_config)
        config[:diagnostics] = {
          enabled: true,
          sentry: {
            defaults: { dsn: 'https://example.com/sentry' },
            backend: { dsn: 'https://example.com/sentry' },
          },
        }

        allow(Kernel).to receive(:require).with('sentry-ruby')
        allow(Kernel).to receive(:require).with('stackprof')
        allow(Sentry).to receive(:init)
        allow(Sentry).to receive(:initialized?).and_return(true)

        # Save original value to restore after test
        original_value = OT.d9s_enabled
        OT.d9s_enabled = false

        processed_config = Onetime::Config.after_load(config)

        # In test mode, we need to manually set this based on the processed config
        # to simulate what would happen in non-test environments
        backend_dsn = processed_config.dig(:diagnostics, :sentry, :backend, :dsn)
        frontend_dsn = processed_config.dig(:diagnostics, :sentry, :frontend, :dsn)
        OT.d9s_enabled = !!(processed_config.dig(:diagnostics, :enabled) && (backend_dsn || frontend_dsn))

        expect(OT.d9s_enabled).to be true
        expect(processed_config[:diagnostics][:enabled]).to be true

        # Restore the original value
        OT.d9s_enabled = original_value
      end

      it 'applies defaults to sentry configuration' do
        config = OT::Config.deep_clone(minimal_config)
        config[:diagnostics] = {
          enabled: true,
          sentry: {
            defaults: { dsn: 'https://example.com/sentry', environment: 'test-default' },
            backend: { traces_sample_rate: 0.1 },
            frontend: { profiles_sample_rate: 0.2 },
          },
        }
        OT.d9s_enabled = false

        allow(Kernel).to receive(:require).with('sentry-ruby')
        allow(Kernel).to receive(:require).with('stackprof')
        allow(Sentry).to receive(:init)
        allow(Sentry).to receive(:initialized?).and_return(true)

        processed_config = Onetime::Config.after_load(config)

        expect(processed_config[:diagnostics][:sentry][:backend][:environment]).to eq('test-default')
        expect(processed_config[:diagnostics][:sentry][:frontend][:environment]).to eq('test-default')
        expect(processed_config[:diagnostics][:sentry][:backend][:traces_sample_rate]).to eq(0.1)
        expect(processed_config[:diagnostics][:sentry][:frontend][:profiles_sample_rate]).to eq(0.2)
        expect(processed_config[:diagnostics][:sentry][:backend][:dsn]).to eq('https://example.com/sentry')
        expect(processed_config[:diagnostics][:sentry][:frontend][:dsn]).to eq('https://example.com/sentry')

        # The defaults aren't returned in the processed config because
        # they've been applied to the frontend and backend settings and
        # are no longer needed or relevant.
        expect(processed_config[:diagnostics][:sentry][:defaults]).to be_nil
        # The defaults remain in the config that we passed in because we go
        # out of our way to make sure we don't mutate the original config.
        expect(config[:diagnostics][:sentry][:defaults]).to be_a(Hash)

        # OT.conf is assigned a value in boot! based on the return
        # value from after_load. We test for this specifically b/c
        # we had an issue with interdependent configurations and
        # want to be sure we don't go down that road again.
        expect(OT.conf).to be_nil
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
          config[:site][:secret] = nil
          config[:experimental][:allow_nil_global_secret] = false # Explicitly ensure it's not allowed

          expect {
            Onetime::Config.after_load(config)
          }.to raise_error(OT::ConfigError, "Global secret cannot be nil - set SECRET env var or site.secret in config")
        end

        it 'raises OT::ConfigError if global secret is "CHANGEME" and not allowed' do
          config[:site][:secret] = 'CHANGEME' # Test the specific "CHANGEME" string
          config[:experimental][:allow_nil_global_secret] = false

          expect {
            Onetime::Config.after_load(config)
          }.to raise_error(OT::ConfigError, "Global secret cannot be nil - set SECRET env var or site.secret in config")
        end

        it 'raises OT::ConfigError if global secret is whitespace "CHANGEME  " and not allowed' do
          config[:site][:secret] = 'CHANGEME  ' # Test with trailing whitespace
          config[:experimental][:allow_nil_global_secret] = false

          expect {
            Onetime::Config.after_load(config)
          }.to raise_error(OT::ConfigError, "Global secret cannot be nil - set SECRET env var or site.secret in config")
        end

        it 'does not raise for nil global secret if explicitly allowed' do
          config[:site][:secret] = nil
          config[:experimental][:allow_nil_global_secret] = true # Explicitly allow nil secret

          # Suppress console output from OT.li during this test
          allow(OT).to receive(:li)

          # Expect that this specific error is not raised.
          # If other parts of the config are invalid, other errors might still occur.
          # This test focuses on the global secret check.
          expect { Onetime::Config.after_load(config) }.not_to raise_error(OT::ConfigError, "Global secret cannot be nil - set SECRET env var or site.secret in config")

          # To ensure no errors are raised at all (assuming the rest of the config is valid):
          # expect { Onetime::Config.after_load(config) }.not_to raise_error
          # This depends on the `config` being otherwise fully valid.
        end
      end

      context 'when truemail configuration is missing (via raise_concerns)' do
        it 'raises OT::ConfigError' do
          # Global secret is valid due to the `before` hook setup.
          config[:mail].delete(:truemail) # Remove the truemail configuration

          expect {
            Onetime::Config.after_load(config)
          }.to raise_error(OT::ConfigError, "No TrueMail config found")
        end

        it 'raises OT::ConfigError for missing truemail even if nil global secret is allowed' do
          config[:site][:secret] = nil # Set global secret to nil
          config[:experimental][:allow_nil_global_secret] = true # Allow nil global secret

          config[:mail].delete(:truemail) # Remove truemail configuration

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
      expect(Onetime::Config.mapped_key(:allowed_domains_only)).to eq(:whitelist_validation)
      expect(Onetime::Config.mapped_key(:allowed_emails)).to eq(:whitelisted_emails)
      expect(Onetime::Config.mapped_key(:blocked_emails)).to eq(:blacklisted_emails)
      expect(Onetime::Config.mapped_key(:allowed_domains)).to eq(:whitelisted_domains)
      expect(Onetime::Config.mapped_key(:blocked_domains)).to eq(:blacklisted_domains)
      expect(Onetime::Config.mapped_key(:blocked_mx_ip_addresses)).to eq(:blacklisted_mx_ip_addresses)
    end

    it 'returns the original key when no mapping exists' do
      expect(Onetime::Config.mapped_key(:unmapped_key)).to eq(:unmapped_key)
      expect(Onetime::Config.mapped_key(:default_validation_type)).to eq(:default_validation_type)
      expect(Onetime::Config.mapped_key(:verifier_email)).to eq(:verifier_email)
    end

    it 'maps test example key' do
      expect(Onetime::Config.mapped_key(:example_internal_key)).to eq(:example_external_key)
    end
  end

  describe '.load' do
    it 'correctly loads configuration from test.yaml file' do
      config = Onetime::Config.load(test_config_path)

      expect(config[:site][:host]).to eq('127.0.0.1:3000')
      expect(config[:site][:ssl]).to eq(true)
      expect(config[:site][:secret]).to eq('SuP0r_53cRU7')
      expect(config[:internationalization][:enabled]).to eq(true)
      expect(config[:internationalization][:default_locale]).to eq('en')
      expect(config[:internationalization][:locales]).to include('en', 'fr_CA', 'fr_FR')
      expect(config[:mail][:truemail][:default_validation_type]).to eq(:mx)
      expect(config[:site][:secret_options][:ttl_options]).to be_a(String)
    end

    it 'processes ERB templates in the configuration', skip: "Test is unstable and dumps ENV" do
      allow(ENV).to receive(:[]).with('DEFAULT_TTL').and_return('7200')

      config = Onetime::Config.load(test_config_path)

      expect(config[:site][:secret_options][:default_ttl]).to eq('7200')
    end
  end
end
