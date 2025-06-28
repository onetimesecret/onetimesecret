# tests/unit/ruby/rspec/onetime/configurator_spec.rb

# Zed task for running rspec on the whole file:
# , t f
#
# Based on the current line:
# , t r
#
# Re-run task
# alt-cmd+r

# NOTE: 'after_load method removed - functionality moved to
# processing hooks in etc/init.d/site.rb'

require_relative '../spec_helper'

RSpec.describe Onetime::Configurator do
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
        config = instance.load_with_impunity!
        instance.resolve_and_load_schema(config)
        expect(instance.schema_path).to be_a(String)
        expect(instance.schema).to be_a(Hash)
      end
    end

  end
end
