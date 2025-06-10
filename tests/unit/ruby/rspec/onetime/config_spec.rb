# tests/unit/ruby/rspec/onetime/config_spec.rb

# Zed task for running rspec on the whole file:
# , t f
#
# Based on the current line:
# , t r
#
# Re-run task
# alt-cmd+r

require_relative '../spec_helper'

RSpec.describe Onetime::Config do
  let(:test_config_path) { File.join(Onetime::HOME, 'tests', 'unit', 'ruby', 'config.test.yaml') }
  let(:test_schema_path) { File.join(Onetime::HOME, 'etc', 'config.schema.yml') }

  describe '::Utils.apply_defaults_to_peers' do
    let(:basic_config) do
      {
        defaults: { timeout: 5, enabled: true },
        api: { timeout: 10 },
        web: {},
      }
    end

    let(:sentry_config) do
      {
        defaults: {
          dsn: 'default-dsn',
          environment: 'test',
          enabled: true,
        },
        backend: {
          dsn: 'backend-dsn',
          traces_sample_rate: 0.1,
        },
        frontend: {
          path: '/web',
          profiles_sample_rate: 0.2,
        },
      }
    end

    context 'with valid inputs' do
      it 'merges defaults into sections' do
        result = described_class::Utils.apply_defaults_to_peers(basic_config)
        expect(result['api']).to eq({ 'timeout' => 10, 'enabled' => true })
        expect(result['web']).to eq({ 'timeout' => 5, 'enabled' => true })
      end

      it 'handles sentry-specific configuration' do
        result = described_class::Utils.apply_defaults_to_peers(sentry_config)

        expect(result['backend']).to eq({
          'dsn' => 'backend-dsn',
          'environment' => 'test',
          'enabled' => true,
          'traces_sample_rate' => 0.1,
        })

        expect(result['frontend']).to eq({
          'dsn' => 'default-dsn',
          'environment' => 'test',
          'enabled' => true,
          'path' => '/web',
          'profiles_sample_rate' => 0.2,
        })
      end
    end

    context 'with edge cases' do
      it 'handles nil config' do
        expect(described_class::Utils.apply_defaults_to_peers(nil)).to eq({})
      end

      it 'handles empty config' do
        expect(described_class::Utils.apply_defaults_to_peers({})).to eq({})
      end

      it 'handles missing defaults section' do
        config = { api: { timeout: 10 } }
        result = described_class::Utils.apply_defaults_to_peers(config)
        expect(result).to eq({ 'api' => { 'timeout' => 10 } })
      end

      it 'skips non-hash section values' do
        config = {
          defaults: { timeout: 5 },
          api: "invalid",
          web: { port: 3000 },
        }
        result = described_class::Utils.apply_defaults_to_peers(config)
        expect(result.keys).to contain_exactly('web')
      end

      it 'preserves original defaults' do
        original = sentry_config[:defaults].dup
        described_class::Utils.apply_defaults_to_peers(sentry_config)
        expect(sentry_config[:defaults]).to eq(original)
      end
    end

    context 'additional edge cases' do
      let(:config_with_defaults) do
        {
          defaults: { timeout: 5, enabled: true },
          api: { timeout: 10 },
          web: {},
        }
      end

      let(:service_config) do
        {
          defaults: { dsn: 'default-dsn', environment: 'test' },
          backend: { dsn: 'backend-dsn' },
          frontend: { path: '/web' },
        }
      end

      it 'merges defaults into sections while preserving overrides' do
        result = described_class::Utils.apply_defaults_to_peers(config_with_defaults)

        expect(result['api']).to eq({ 'timeout' => 10, 'enabled' => true })
        expect(result['web']).to eq({ 'timeout' => 5, 'enabled' => true })
      end

      it 'preserves defaults when section value is nil' do
        config = {
          defaults: { dsn: 'default-dsn' },
          backend: { dsn: nil },
          frontend: { dsn: nil },
        }
        result = described_class::Utils.apply_defaults_to_peers(config)
        expect(result['backend']['dsn']).to eq('default-dsn')
        expect(result['frontend']['dsn']).to eq('default-dsn')
      end

      it 'processes real world service config correctly' do
        result = described_class::Utils.apply_defaults_to_peers(service_config)

        expect(result['backend']).to eq({
          'dsn' => 'backend-dsn',
          'environment' => 'test',
        })

        expect(result['frontend']).to eq({
          'dsn' => 'default-dsn',
          'environment' => 'test',
          'path' => '/web',
        })
      end

      it 'preserves original defaults hash' do
        original_defaults = service_config[:defaults].dup
        described_class::Utils.apply_defaults_to_peers(service_config)

        expect(service_config[:defaults]).to eq(original_defaults)
      end
    end

    context 'indifferent access support' do
      let(:config_with_symbol_keys) do
        {
          defaults: { timeout: 5, enabled: true },
          api: { timeout: 10 },
          web: {},
        }
      end

      it 'supports symbol key access on string-normalized results' do
        result = described_class::Utils.apply_defaults_to_peers(config_with_symbol_keys)

        # Results are normalized to string keys
        expect(result['api']['timeout']).to eq(10)
        expect(result['web']['enabled']).to eq(true)

        # But should support symbol access via IndifferentHashAccess
        # This will be handled by the refinement in the actual config system
        expect(result.keys).to all(be_a(String))
      end

      it 'handles mixed symbol/string input keys consistently' do
        mixed_config = {
          'defaults' => { timeout: 5, 'enabled' => true },
          :api => { 'timeout' => 10 },
          'web' => {},
        }

        result = described_class::Utils.apply_defaults_to_peers(mixed_config)

        # All keys should be normalized to strings
        expect(result.keys).to all(be_a(String))
        expect(result['api'].keys).to all(be_a(String))
        expect(result['web'].keys).to all(be_a(String))
      end
    end
  end

  describe '.before_load' do
    before do
      # Store original environment variables
      @original_env = ENV.to_hash
    end

    after do
      # Restore original environment variables
      ENV.clear
      @original_env.each { |k, v| ENV[k] = v }
    end

    context 'backwards compatability in v0.20.6' do
      context 'when REGIONS_ENABLED is set' do
        it 'keeps the REGIONS_ENABLED value' do
          ENV['REGIONS_ENABLED'] = 'TESTA'
          ENV.delete('REGIONS_ENABLE')

          described_class.new.before_load

          expect(ENV['REGIONS_ENABLED']).to eq('TESTA')
        end
      end

      context 'when REGIONS_ENABLE is set but REGIONS_ENABLED is not' do
        it 'copies REGIONS_ENABLE value to REGIONS_ENABLED' do
          ENV.delete('REGIONS_ENABLED')
          ENV['REGIONS_ENABLE'] = 'TESTB'

          described_class.new.before_load

          expect(ENV['REGIONS_ENABLED']).to eq('TESTB')
        end
      end

      context 'when both REGIONS_ENABLED and REGIONS_ENABLE are set' do
        it 'prioritizes REGIONS_ENABLED' do
          ENV['REGIONS_ENABLED'] = 'TESTA'
          ENV['REGIONS_ENABLE'] = 'TESTB'

          described_class.new.before_load

          expect(ENV['REGIONS_ENABLED']).to eq('TESTA')
        end
      end

      context 'when neither REGIONS_ENABLED nor REGIONS_ENABLE are set' do
        it 'sets REGIONS_ENABLED to false' do
          ENV.delete('REGIONS_ENABLED')
          ENV.delete('REGIONS_ENABLE')

          described_class.new.before_load

          expect(ENV['REGIONS_ENABLED']).to eq('false')
        end
      end
    end
  end

  # , t r
  describe '#after_load' do
    let(:config_instance) { described_class.new }

    before do
      # Set up config instance with minimal unprocessed config
      allow(config_instance).to receive(:unprocessed_config).and_return(raw_config)
    end

    context 'colonels backwards compatibility' do
      let(:raw_config) do
        {
          colonels: ['root@example.com', 'admin@example.com'],
          site: {
            secret: 'notnil',
            authentication: {
              enabled: true,
            },
          },
          development: {},
          mail: {
            truemail: {},
          },
        }
      end

      it 'moves colonels from root level to site.authentication when not present in site.authentication' do
        processed_config = config_instance.send(:after_load)
        expect(processed_config['site']['authentication']['colonels']).to eq(['root@example.com', 'admin@example.com'])
      end

      context 'when colonels exist in site.authentication' do
        let(:raw_config) do
          {
            site: {
              secret: 'notnil',
              authentication: {
                enabled: true,
                colonels: ['site@example.com'],
              },
            },
            development: {},
            mail: {
              truemail: {},
            },
          }
        end

        it 'keeps colonels in site.authentication when present' do
          processed_config = config_instance.send(:after_load)
          expect(processed_config['site']['authentication']['colonels']).to eq(['site@example.com'])
        end
      end

      context 'when colonels are defined in both places' do
        let(:raw_config) do
          {
            colonels: ['root@example.com', 'admin@example.com'],
            site: {
              secret: 'notnil',
              authentication: {
                enabled: true,
                colonels: ['site@example.com', 'auth@example.com'],
              },
            },
            development: {},
            mail: {
              truemail: {},
            },
          }
        end

        it 'prioritizes site.authentication colonels when defined in both places' do
          processed_config = config_instance.send(:after_load)
          expect(processed_config['site']['authentication']['colonels']).to eq(['site@example.com', 'auth@example.com', 'root@example.com', 'admin@example.com'])
        end
      end

      context 'when no colonels are defined' do
        let(:raw_config) do
          {
            site: {
              secret: 'notnil',
              authentication: {
                enabled: true,
              },
            },
            development: {},
            mail: {
              truemail:
 {},
            },
          }
        end

        it 'initializes empty colonels array when not defined anywhere' do
          processed_config = config_instance.send(:after_load)
          expect(processed_config['site']['authentication']['colonels']).to eq([])
        end
      end

      context 'when site is minimal' do
        let(:raw_config) do
          {
            site: {
              secret: 'anyvaluewilldo',
            },
            mail: {
              truemail: {},
            },
          }
        end

        it 'uses default values when site is minimal' do
          expect {
            config_instance.send(:after_load)
          }.not_to raise_error
        end
      end

      context 'when site.secret is nil' do
        let(:raw_config) do
          {
            colonels: ['root@example.com'],
            site: {secret: nil},
            development: {},
            mail: {
              truemail: {},
            },
          }
        end

        it 'raises heck when site.secret is nil' do
          expect {
            config_instance.send(:after_load)
          }.to raise_error(OT::Problem, /Global secret cannot be nil/)
        end
      end

      context 'when site.secret is CHANGEME' do
        let(:raw_config) do
          {
            colonels: ['root@example.com'],
            site: {secret: 'CHANGEME'},
            development: {},
            mail: {
              truemail: {},
            },
          }
        end

        it 'raises heck when site.secret is CHANGEME (same behaviour as nil)' do
          expect {
            config_instance.send(:after_load)
          }.to raise_error(OT::Problem, /Global secret cannot be nil/)
        end
      end

      context 'when missing site.authentication section' do
        let(:raw_config) do
          {
            site: {secret: '1234'},
            mail: {
              truemail: {},
            },
          }
        end

        it 'handles missing site.authentication section' do
          expect {
            config_instance.send(:after_load)
          }.not_to raise_error
        end
      end

      context 'when authentication is disabled' do
        let(:raw_config) do
          {
            site: {
              secret: 'notnil',
              authentication: {
                enabled: false,
                colonels: ['site@example.com'],
              },
            },
            development: {},
            mail: {
              truemail: {},
            },
          }
        end

        it 'sets authentication colonels to false when authentication is disabled' do
          processed_config = config_instance.send(:after_load)
          expect(processed_config['site']['authentication']['colonels']).to eq(false)
        end
      end

      context 'indifferent access in after_load results' do
        let(:raw_config) do
          {
            colonels: ['root@example.com'],
            site: {
              secret: 'test-secret',
              authentication: {
                enabled: true,
              },
            },
            development: {},
            mail: {
              truemail: {},
            },
          }
        end

        it 'produces string-keyed results that work with IndifferentHashAccess' do
          processed_config = config_instance.send(:after_load)

          # Verify string keys are used
          expect(processed_config.keys).to all(be_a(String))
          expect(processed_config['site'].keys).to all(be_a(String))
          expect(processed_config['site']['authentication'].keys).to all(be_a(String))

          # Verify the structure is correct
          expect(processed_config['site']['authentication']['colonels']).to eq(['root@example.com'])
        end
      end
    end
  end

  describe 'class methods' do
    describe '.find_configs' do
      it 'returns array of config paths' do
        configs = described_class.find_configs('config')
        expect(configs).to be_an(Array)
      end

      it 'finds existing config files' do
        configs = described_class.find_configs('config')
        expect(configs).not_to be_empty
      end
    end

    describe '.find_config' do
      it 'returns first config path' do
        config_path = described_class.find_config('config')
        expect(config_path).to be_a(String)
        expect(File.exist?(config_path)).to be true
      end
    end

    describe '.load!' do
      it 'creates and loads a config instance' do
        # Mock the config loading to avoid validation issues with test config
        mock_config = {
          site: { secret: 'test-secret' },
          development: {},
          mail: { truemail: {} },
        }

        allow_any_instance_of(described_class).to receive(:load_config).and_return(mock_config)
        allow_any_instance_of(described_class).to receive(:load_schema).and_return({})
        allow_any_instance_of(described_class).to receive(:validate).and_return(mock_config)

        config = described_class.load!
        expect(config).to be_a(described_class)
        expect(config.config).to be_a(Hash)
      end
    end
  end

  describe 'instance methods' do
    let(:config_instance) { described_class.new }

    describe '#initialize' do
      it 'sets config_path when provided' do
        instance = described_class.new(config_path: '/custom/path')
        expect(instance.config_path).to eq('/custom/path')
      end

      it 'finds config_path when not provided' do
        instance = described_class.new
        expect(instance.config_path).to be_a(String)
      end

      it 'sets schema_path when provided' do
        instance = described_class.new(schema_path: '/custom/schema')
        expect(instance.schema_path).to eq('/custom/schema')
      end

      it 'finds schema_path when not provided' do
        instance = described_class.new
        expect(instance.schema_path).to be_a(String)
      end
    end

    describe '#load!' do
      it 'calls before_load, load, and after_load in sequence' do
        expect(config_instance).to receive(:before_load).ordered
        expect(config_instance).to receive(:load).ordered
        expect(config_instance).to receive(:after_load).ordered

        config_instance.load!
      end
    end

    describe '#load' do
      before do
        allow(config_instance).to receive(:load_schema).and_return({})
        allow(config_instance).to receive(:load_config).and_return({})
        allow(config_instance).to receive(:validate).and_return({})
      end

      it 'loads schema, config, and validates' do
        expect(config_instance).to receive(:load_schema)
        expect(config_instance).to receive(:load_config)
        expect(config_instance).to receive(:validate)

        config_instance.load
      end

      it 'sets instance variables' do
        config_instance.load

        expect(config_instance.schema).to eq({})
        expect(config_instance.unprocessed_config).to eq({})
        expect(config_instance.validated_config).to eq({})
      end
    end

    describe '#validate' do
      let(:mock_config) { { test: 'value' } }
      let(:mock_schema) { { type: 'object' } }

      before do
        allow(config_instance).to receive(:unprocessed_config).and_return(mock_config)
        allow(config_instance).to receive(:schema).and_return(mock_schema)
      end

      it 'calls Utils.validate_with_schema' do
        expect(described_class::Utils).to receive(:validate_with_schema)
          .with(mock_config, mock_schema)
          .and_return(mock_config)

        config_instance.validate
      end
    end

    describe '#load_config', :allow_redis do
      let(:yaml_config) { "test:\n  value: 123" }
      let(:erb_config) { "test:\n  value: <%= 456 %>" }

      before do
        allow(OT::Config::Load).to receive(:file_read).and_return(yaml_config)
        allow(OT::Config::Load).to receive(:yaml_load).and_return({ test: { value: 123 } })
      end

      it 'reads and processes config file' do
        result = config_instance.send(:load_config)

        expect(result).to eq({ test: { value: 123 } })
        expect(config_instance.config_template_str).to eq(yaml_config)
        expect(config_instance.rendered_yaml).to be_a(String)
      end

      context 'with ERB template' do
        before do
          allow(OT::Config::Load).to receive(:file_read).and_return(erb_config)
          allow(OT::Config::Load).to receive(:yaml_load).and_return({ test: { value: 456 } })
        end

        it 'processes ERB templates' do
          result = config_instance.send(:load_config)

          expect(result).to eq({ test: { value: 456 } })
          expect(config_instance.rendered_yaml).to include('456')
        end
      end
    end

    describe '#load_schema' do
      before do
        allow(OT::Config::Load).to receive(:yaml_load_file).and_return({ type: 'object' })
      end

      it 'loads schema from file' do
        result = config_instance.send(:load_schema)

        expect(result).to eq({ type: 'object' })
      end
    end
  end
end
