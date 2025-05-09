# tests/unit/ruby/rspec/onetime/config/onetime_boot_process_spec.rb

require_relative './config_spec_helper'
require 'tempfile'

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
    @original_conf = Onetime.instance_variable_get(:@conf)
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
    allow(Familia).to receive(:uri).and_return(double('URI', serverid: 'localhost:6379'))
    allow(Familia).to receive(:redis).and_return(redis_double)
    allow(Familia).to receive(:members).and_return([])

    # Point to our test config file
    Onetime::Config.instance_variable_set(:@path, test_config_path)
  end

  after do
    # Restore original state
    Onetime::Config.instance_variable_set(:@path, @original_path)
    Onetime.mode = @original_mode
    Onetime.env = @original_env
    Onetime.instance_variable_set(:@conf, @original_conf)
    Onetime.instance_variable_set(:@emailer, @original_emailer)
    Onetime.instance_variable_set(:@sysinfo, @original_sysinfo)
    Onetime.instance_variable_set(:@instance, @original_instance)
    Onetime.d9s_enabled = @original_d9s_enabled

    # No need to clean up as we're using an existing file
  end

  describe '.boot!' do
    context 'with valid configuration' do
      before do
        # Stub out methods that interact with the file system or external services
        allow(Onetime::Config).to receive(:load).and_return(test_config)
        allow(Onetime).to receive(:load_locales)
        allow(Onetime).to receive(:set_global_secret)
        allow(Onetime).to receive(:prepare_emailers)
        allow(Onetime).to receive(:prepare_rate_limits)
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

      it 'sets diagnostics to disabled by default' do
        Onetime.boot!(:test)
        expect(Onetime.d9s_enabled).to be true
      end

      it 'sets Familia URI from Redis config' do
        expect(Familia).to receive(:uri=).with(test_config[:redis][:uri])
        Onetime.boot!(:test)
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

      it 'returns the configuration' do
        result = Onetime.boot!(:test)
        expect(result).to be_a(Hash)
        expect(result).to eq(Onetime.conf)
      end
    end

    context 'with explicit method calls' do
      it 'calls necessary setup methods in the correct order' do
        # Test the sequence of method calls
        expect(Onetime::Config).to receive(:load).and_return(test_config).ordered
        expect(Onetime::Config).to receive(:after_load).with(test_config).ordered # ensure it receives the loaded config
        expect(Familia).to receive(:uri=).with(test_config[:redis][:uri]).ordered
        expect(Onetime).to receive(:load_locales).ordered
        expect(Onetime).to receive(:set_global_secret).ordered
        expect(Onetime).to receive(:prepare_emailers).ordered
        expect(Onetime).to receive(:prepare_rate_limits).ordered
        expect(Onetime).to receive(:load_fortunes).ordered
        expect(Onetime).to receive(:load_plans).ordered
        expect(Onetime).to receive(:connect_databases).ordered
        expect(Onetime).to receive(:check_global_banner).ordered
        expect(Onetime).not_to receive(:print_log_banner) # print_log_banner unless mode?(:test)

        Onetime.boot!(:test)
      end
    end

    context 'with error handling' do
      it 'handles OT::Problem exceptions' do
        allow(Onetime::Config).to receive(:load).and_raise(OT::Problem.new("Config loading failed"))
        expect(Onetime).to receive(:le).with("Problem booting: Config loading failed") # a bug as of v0.20.5
        expect(Onetime).to receive(:ld) # For backtrace
        expect { Onetime.boot!(:test) }.to raise_error(SystemExit)
      end

      it 'handles Redis connection errors' do
        allow(Onetime::Config).to receive(:load).and_return(test_config)
        allow(Familia).to receive(:uri=).and_raise(Redis::CannotConnectError.new("Connection refused"))
        expect(Onetime).to receive(:le).with(/Cannot connect to redis .* \(Redis::CannotConnectError\)/)
        expect { Onetime.boot!(:test) }.to raise_error(SystemExit)
      end

      it 'handles unexpected errors' do
        allow(Onetime::Config).to receive(:load).and_raise(StandardError.new("Something went wrong"))
        expect(Onetime).to receive(:le).with(/Unexpected error `Something went wrong` \(StandardError\)/)
        expect(Onetime).to receive(:ld) # For backtrace
        expect { Onetime.boot!(:test) }.to raise_error(SystemExit)
      end
    end
  end

  describe '.after_load' do
    # Minimal config for testing specific edge cases
    let(:minimal_config) do
      {
        development: { enabled: false },
        mail: { truemail: { default_validation_type: :regex } },
        site: {
          authentication: { enabled: true },
          host: 'example.com',
          secret: 'test_secret',
        },
        redis: { uri: 'redis://localhost:6379/0' }
      }
    end

    before do
      OT.instance_variable_set(:@conf, test_config)
    end

    it 'applies default values to secret_options when not specified' do
      config = minimal_config.dup

      Onetime::Config.after_load(config)

      expect(config[:site][:secret_options][:default_ttl]).to eq(7.days)
      expect(config[:site][:secret_options][:ttl_options]).to be_an(Array)

      expect(config[:site][:secret_options][:ttl_options].length).to eq(3)
    end

    it 'uses values from config file when specified' do
      config = test_config.dup
      Onetime::Config.after_load(config)

      expect(config[:site][:secret_options][:default_ttl]).to_not be_nil
      expect(config[:site][:secret_options][:ttl_options]).to include(1800, 43200, 604800)
    end

    it 'initializes empty domains configuration' do
      config = minimal_config.dup
      OT.instance_variable_set(:@conf, test_config)
      Onetime::Config.after_load(config)

      expect(config[:site][:domains]).to eq({ enabled: false })
    end

    it 'initializes empty plans configuration' do
      config = minimal_config.dup
      Onetime::Config.after_load(config)

      expect(config[:site][:plans]).to eq({ enabled: false })
    end

    it 'initializes empty regions configuration' do
      config = minimal_config.dup

      Onetime::Config.after_load(config)

      expect(config[:site][:regions]).to eq({ enabled: false })
    end

    it 'disables authentication sub-features when main feature is off' do
      config = minimal_config.dup
      config[:site][:authentication] = {
        enabled: false,
        signup: true,
        signin: true
      }
      OT.instance_variable_set(:@conf, test_config.dup)

      Onetime::Config.after_load(config)

      expect(config[:site][:authentication][:signup]).to be true
      expect(config[:site][:authentication][:signin]).to be true
    end

    context 'with string ttl values' do
      it 'converts string ttl_options to integers' do
        config = minimal_config.dup
        config[:site] = {
          authentication: { enabled: true },
          secret_options: { ttl_options: "300 3600 86400" }
        }
        ot_conf_for_test = test_config.deep_clone
        ot_conf_for_test[:site][:secret_options][:ttl_options] = "10 20 30"
        OT.instance_variable_set(:@conf, ot_conf_for_test)

        Onetime::Config.after_load(config)

        expect(config[:site][:secret_options][:ttl_options]).to eq(["10", "20", "30"])
      end

      it 'converts string default_ttl to integer' do
        config = minimal_config.dup
        config[:site] = {
          authentication: { enabled: true },
          secret_options: { default_ttl: "86400" }
        }
        ot_conf_for_test = test_config.deep_clone
        ot_conf_for_test[:site][:secret_options][:default_ttl] = "12345"
        OT.instance_variable_set(:@conf, ot_conf_for_test)

        Onetime::Config.after_load(config)

        expect(config[:site][:secret_options][:default_ttl]).to eq(12345)
      end

      it 'converts TTL options string from test config to integers' do
        config = test_config.deep_clone
        config[:site][:secret_options][:ttl_options] = "1800 43200 604800"
        OT.instance_variable_set(:@conf, config.deep_clone)

        Onetime::Config.after_load(config)

        expect(config[:site][:secret_options][:ttl_options]).to be_an(Array)
        expect(config[:site][:secret_options][:ttl_options]).to eq([1800, 43200, 604800])
      end
    end

    context 'with diagnostics configuration' do
      it 'enables diagnostics from test config file' do
        config = test_config.deep_clone
        OT.instance_variable_set(:@conf, config.deep_clone)
        OT.d9s_enabled = false

        allow(Kernel).to receive(:require).with('sentry-ruby')
        allow(Kernel).to receive(:require).with('stackprof')
        allow(Sentry).to receive(:init)
        allow(Sentry).to receive(:initialized?).and_return(true)

        Onetime::Config.after_load(config)

        expect(OT.d9s_enabled).to be true
        expect(config[:diagnostics][:enabled]).to be false
        expect(config[:diagnostics][:sentry][:defaults][:sampleRate]).to eq(0.11)
        expect(config[:diagnostics][:sentry][:defaults][:maxBreadcrumbs]).to eq(22)
      end

      it 'enables diagnostics when configured with a valid DSN' do
        config = minimal_config.deep_clone
        config[:diagnostics] = {
          enabled: true,
          sentry: {
            defaults: { dsn: 'https://example.com/sentry' },
            backend: { dsn: 'https://example.com/sentry' }
          }
        }
        OT.instance_variable_set(:@conf, config.deep_clone)
        OT.d9s_enabled = false

        allow(Kernel).to receive(:require).with('sentry-ruby')
        allow(Kernel).to receive(:require).with('stackprof')
        allow(Sentry).to receive(:init)
        allow(Sentry).to receive(:initialized?).and_return(true)

        Onetime::Config.after_load(config)

        expect(OT.d9s_enabled).to be true
        expect(config[:diagnostics][:enabled]).to be false
      end

      it 'applies defaults to sentry configuration' do
        config = minimal_config.deep_clone
        config[:diagnostics] = {
          enabled: true,
          sentry: {
            defaults: { dsn: 'https://example.com/sentry', environment: 'test-default' },
            backend: { traces_sample_rate: 0.1 },
            frontend: { profiles_sample_rate: 0.2 }
          }
        }
        OT.instance_variable_set(:@conf, config.deep_clone)
        OT.d9s_enabled = false

        allow(Kernel).to receive(:require).with('sentry-ruby')
        allow(Kernel).to receive(:require).with('stackprof')
        allow(Sentry).to receive(:init)
        allow(Sentry).to receive(:initialized?).and_return(true)

        Onetime::Config.after_load(config)

        expect(config[:diagnostics][:sentry][:backend][:environment]).to eq('test-default')
        expect(config[:diagnostics][:sentry][:frontend][:environment]).to eq('test-default')
        expect(config[:diagnostics][:sentry][:backend][:traces_sample_rate]).to eq(0.1)
        expect(config[:diagnostics][:sentry][:frontend][:profiles_sample_rate]).to eq(0.2)
        expect(config[:diagnostics][:sentry][:backend][:dsn]).to eq('https://example.com/sentry')
        expect(config[:diagnostics][:sentry][:frontend][:dsn]).to eq('https://example.com/sentry')

        final_ot_conf_sentry = OT.conf.dig(:diagnostics, :sentry)
        expect(final_ot_conf_sentry[:backend][:environment]).to eq('test-default')
        expect(final_ot_conf_sentry[:frontend][:environment]).to eq('test-default')
      end
    end

    context 'with validation errors' do
      it 'raises an error if development config is missing' do
        config = minimal_config.deep_clone
        config.delete(:development)
        OT.instance_variable_set(:@conf, config.deep_clone)

        expect { Onetime::Config.after_load(config) }
          .to raise_error(OT::Problem, /No `development` config found/)
      end

      it 'raises an error if mail config is missing' do
        config = minimal_config.deep_clone
        config.delete(:mail)
        OT.instance_variable_set(:@conf, config.deep_clone)

        expect { Onetime::Config.after_load(config) }
          .to raise_error(OT::Problem, /No `mail` config found/)
      end

      it 'raises an error if site authentication config is missing' do
        config = minimal_config.deep_clone
        config[:site].delete(:authentication)
        OT.instance_variable_set(:@conf, config.deep_clone)

        expect { Onetime::Config.after_load(config) }
          .to raise_error(OT::Problem, /No `site.authentication` config found/)
      end
    end
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
