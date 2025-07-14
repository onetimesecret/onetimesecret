# tests/unit/ruby/rspec/onetime/config/apply_defaults_to_peers_spec.rb

require_relative '../../../spec_helper'

RSpec.describe Onetime::Configurator::Utils do
  describe '.apply_defaults_to_peers' do
    let(:basic_config) do
      {
        'defaults' => { 'timeout' => 5, 'enabled' => true },
        'api' => { 'timeout' => 10 },
        'web' => {},
      }
    end

    let(:sentry_config) do
      {
        'defaults' => {
          'dsn' => 'default-dsn',
          'environment' => 'test',
          'enabled' => true
        },
        'backend' => {
          'dsn' => 'backend-dsn',
          'traces_sample_rate' => 0.1
        },
        'frontend' => {
          'path' => '/web',
          'profiles_sample_rate' => 0.2
        }
      }
    end

    let(:service_config) do
      {
        'defaults' => { 'dsn' => 'default-dsn', 'environment' => 'test' },
        'backend' => { 'dsn' => 'backend-dsn' },
        'frontend' => { 'path' => '/web' }
      }
    end

    context 'with valid inputs' do
      it 'merges defaults into sections' do
        result = described_class.apply_defaults_to_peers(basic_config)
        expect(result['api']).to eq({ 'timeout' => 10, 'enabled' => true })
        expect(result['web']).to eq({ 'timeout' => 5, 'enabled' => true })
      end

      it 'handles sentry-specific configuration' do
        result = described_class.apply_defaults_to_peers(sentry_config)

        expect(result['backend']).to eq({
          'dsn' => 'backend-dsn',
          'environment' => 'test',
          'enabled' => true,
          'traces_sample_rate' => 0.1
        })

        expect(result['frontend']).to eq({
          'dsn' => 'default-dsn',
          'environment' => 'test',
          'enabled' => true,
          'path' => '/web',
          'profiles_sample_rate' => 0.2
        })
      end

      it 'correctly applies defaults to a typical service configuration with multiple sections' do
        result = described_class.apply_defaults_to_peers(service_config)

        expect(result['backend']).to eq({
          'dsn' => 'backend-dsn',
          'environment' => 'test'
        })

        expect(result['frontend']).to eq({
          'dsn' => 'default-dsn',
          'environment' => 'test',
          'path' => '/web'
        })
      end
    end

    context 'with edge cases' do
      it 'handles no arguments' do
        expect(described_class.apply_defaults_to_peers()).to eq({})
      end

      it 'handles nil config' do
        expect(described_class.apply_defaults_to_peers(nil)).to eq({})
      end

      it 'handles empty config' do
        expect(described_class.apply_defaults_to_peers({'defaults' => {}})).to eq({})
      end

      it 'handles empty defaults' do
        expect(described_class.apply_defaults_to_peers({})).to eq({})
      end

      it 'handles missing defaults section' do
        config = { 'api' => { 'timeout' => 10 } }
        result = described_class.apply_defaults_to_peers(config)
        expect(result).to eq({ 'api' => { 'timeout' => 10 } })
      end

      it 'skips non-hash section values' do
        config = {
          'defaults' => { 'timeout' => 5 },
          'api' => "invalid",
          'web' => { 'port' => 3000 }
        }
        result = described_class.apply_defaults_to_peers(config)
        expect(result.keys).to contain_exactly('web')
      end

      it 'preserves original defaults' do
        original = sentry_config['defaults'].dup
        described_class.apply_defaults_to_peers(sentry_config)
        expect(sentry_config['defaults']).to eq(original)
      end

      it "applies default values when a section's corresponding key is present but has a nil value" do
        config = {
          'defaults' => { 'dsn' => 'default-dsn' },
          'backend' => { 'dsn' => nil },
          'frontend' => { 'dsn' => nil }
        }
        result = described_class.apply_defaults_to_peers(config)
        expect(result['backend']['dsn']).to eq('default-dsn')
        expect(result['frontend']['dsn']).to eq('default-dsn')
      end

      it 'does not modify the original defaults hash passed as an argument' do
        original_defaults = service_config['defaults'].dup
        described_class.apply_defaults_to_peers(service_config)

        expect(service_config['defaults']).to eq(original_defaults)
      end
    end

    context 'with complex configurations' do
      let(:config_with_defaults) do
        {
          'defaults' => { 'timeout' => 5, 'enabled' => true },
          'api' => { 'timeout' => 10 },
          'web' => {}
        }
      end

      it 'merges defaults into sections, allowing section-specific values to override defaults' do
        result = described_class.apply_defaults_to_peers(config_with_defaults)

        expect(result['api']).to eq({ 'timeout' => 10, 'enabled' => true })
        expect(result['web']).to eq({ 'timeout' => 5, 'enabled' => true })
      end

      it 'handles nested hash structures properly' do
        config = {
          'defaults' => {
            'database' => { 'timeout' => 5 },
            'cache' => { 'ttl' => 3600 }
          },
          'production' => {
            'database' => { 'host' => 'prod-db' }
          },
          'staging' => {
            'cache' => { 'ttl' => 1800 }
          }
        }

        result = described_class.apply_defaults_to_peers(config)

        expect(result['production']).to eq({
          'database' => { 'timeout' => 5, 'host' => 'prod-db' },
          'cache' => { 'ttl' => 3600 }
        })

        expect(result['staging']).to eq({
          'database' => { 'timeout' => 5 },
          'cache' => { 'ttl' => 1800 }
        })
      end

      it 'normalizes all keys to strings consistently' do
        config = {
          'defaults' => { 'timeout' => 5, 'enabled' => true },
          'api' => { 'timeout' => 10 },
          'web' => {},
        }

        result = described_class.apply_defaults_to_peers(config)

        # Results are normalized to string keys
        expect(result.keys).to all(be_a(String))
        expect(result['api'].keys).to all(be_a(String))
        expect(result['web'].keys).to all(be_a(String))

        # Verify structure is correct
        expect(result['api']['timeout']).to eq(10)
        expect(result['web']['enabled']).to eq(true)
      end

      it 'handles mixed symbol/string input keys consistently' do
        mixed_config = {
          'defaults' => { 'timeout' => 5, 'enabled' => true },
          :api => { 'timeout' => 10 },
          'web' => {},
        }

        result = described_class.apply_defaults_to_peers(mixed_config)

        # All keys should be normalized to strings
        expect(result.keys).to all(be_a(String))
        expect(result['api'].keys).to all(be_a(String))
        expect(result['web'].keys).to all(be_a(String))
      end
    end
  end
end
