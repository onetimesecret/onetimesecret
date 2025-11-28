# tests/unit/ruby/rspec/onetime/config/apply_defaults_to_peers.rb

require_relative '../../spec_helper'

RSpec.describe Onetime::Config do
  describe '#apply_defaults_to_peers' do
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
            enabled: true
          },
          backend: {
            dsn: 'backend-dsn',
            traces_sample_rate: 0.1
          },
          frontend: {
            path: '/web',
            profiles_sample_rate: 0.2
          }
        }
      end

      context 'with valid inputs' do
        it 'merges defaults into sections' do
          result = described_class.apply_defaults_to_peers(basic_config)
          # Use indifferent access - result is IndifferentHash
          expect(result[:api][:timeout]).to eq(10)
          expect(result[:api][:enabled]).to eq(true)
          expect(result[:web][:timeout]).to eq(5)
          expect(result[:web][:enabled]).to eq(true)
        end

        it 'handles sentry-specific configuration' do
          result = described_class.apply_defaults_to_peers(sentry_config)

          expect(result[:backend][:dsn]).to eq('backend-dsn')
          expect(result[:backend][:environment]).to eq('test')
          expect(result[:backend][:enabled]).to eq(true)
          expect(result[:backend][:traces_sample_rate]).to eq(0.1)

          expect(result[:frontend][:dsn]).to eq('default-dsn')
          expect(result[:frontend][:environment]).to eq('test')
          expect(result[:frontend][:enabled]).to eq(true)
          expect(result[:frontend][:path]).to eq('/web')
          expect(result[:frontend][:profiles_sample_rate]).to eq(0.2)
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
          expect(described_class.apply_defaults_to_peers({defaults: {}})).to eq({})
        end

        it 'handles empty defaults' do
          expect(described_class.apply_defaults_to_peers({})).to eq({})
        end

        it 'handles missing defaults section' do
          config = { api: { timeout: 10 } }
          result = described_class.apply_defaults_to_peers(config)
          # Result is IndifferentHash, use value access
          expect(result[:api][:timeout]).to eq(10)
        end

        it 'skips non-hash section values' do
          config = {
            defaults: { timeout: 5 },
            api: "invalid",
            web: { port: 3000 }
          }
          result = described_class.apply_defaults_to_peers(config)
          # Check that only web key exists (api was skipped)
          expect(result.keys.map(&:to_s)).to contain_exactly('web')
        end

        it 'preserves original defaults' do
          original = sentry_config[:defaults].dup
          described_class.apply_defaults_to_peers(sentry_config)
          expect(sentry_config[:defaults]).to eq(original)
        end
      end
    end

  describe '#apply_defaults_to_peers' do
    let(:config_with_defaults) do
      {
        defaults: { timeout: 5, enabled: true },
        api: { timeout: 10 },
        web: {}
      }
    end

    let(:empty_config) { {} }
    let(:nil_config) { nil }

    let(:service_config) do
      {
        defaults: { dsn: 'default-dsn', environment: 'test' },
        backend: { dsn: 'backend-dsn' },
        frontend: { path: '/web' }
      }
    end

    it 'merges defaults into sections, allowing section-specific values to override defaults' do
      result = described_class.apply_defaults_to_peers(config_with_defaults)

      # Use indifferent access
      expect(result[:api][:timeout]).to eq(10)
      expect(result[:api][:enabled]).to eq(true)
      expect(result[:web][:timeout]).to eq(5)
      expect(result[:web][:enabled]).to eq(true)
    end

    it "applies default values when a section's corresponding key is present but has a nil value" do
      config = {
        defaults: { dsn: 'default-dsn' },
        backend: { dsn: nil },
        frontend: { dsn: nil }
      }
      result = described_class.apply_defaults_to_peers(config)
      expect(result[:backend][:dsn]).to eq('default-dsn')
      expect(result[:frontend][:dsn]).to eq('default-dsn')
    end

    it 'correctly applies defaults to a typical service configuration with multiple sections' do
      result = described_class.apply_defaults_to_peers(service_config)

      # Use indifferent access
      expect(result[:backend][:dsn]).to eq('backend-dsn')
      expect(result[:backend][:environment]).to eq('test')

      expect(result[:frontend][:dsn]).to eq('default-dsn')
      expect(result[:frontend][:environment]).to eq('test')
      expect(result[:frontend][:path]).to eq('/web')
    end

    it 'does not modify the original defaults hash passed as an argument' do
      original_defaults = service_config[:defaults].dup
      described_class.apply_defaults_to_peers(service_config)

      expect(service_config[:defaults]).to eq(original_defaults)
    end
  end
end
