# tests/unit/ruby/rspec/onetime/config/example_spec.rb

require_relative '../spec_helper'

RSpec.describe Onetime::Config do
  describe '#apply_defaults' do
      let(:basic_config) do
        {
          defaults: { timeout: 5, enabled: true },
          api: { timeout: 10 },
          web: {}
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
          result = described_class.apply_defaults(basic_config)
          expect(result[:api]).to eq({ timeout: 10, enabled: true })
          expect(result[:web]).to eq({ timeout: 5, enabled: true })
        end

        it 'handles sentry-specific configuration' do
          result = described_class.apply_defaults(sentry_config)

          expect(result[:backend]).to eq({
            dsn: 'backend-dsn',
            environment: 'test',
            enabled: true,
            traces_sample_rate: 0.1
          })

          expect(result[:frontend]).to eq({
            dsn: 'default-dsn',
            environment: 'test',
            enabled: true,
            path: '/web',
            profiles_sample_rate: 0.2
          })
        end
      end

      context 'with edge cases' do
        it 'handles nil config' do
          expect(described_class.apply_defaults(nil)).to eq({})
        end

        it 'handles empty config' do
          expect(described_class.apply_defaults({})).to eq({})
        end

        it 'handles missing defaults section' do
          config = { api: { timeout: 10 } }
          result = described_class.apply_defaults(config)
          expect(result).to eq({ api: { timeout: 10 } })
        end

        it 'skips non-hash section values' do
          config = {
            defaults: { timeout: 5 },
            api: "invalid",
            web: { port: 3000 }
          }
          result = described_class.apply_defaults(config)
          expect(result.keys).to contain_exactly(:web)
        end

        it 'preserves original defaults' do
          original = sentry_config[:defaults].dup
          described_class.apply_defaults(sentry_config)
          expect(sentry_config[:defaults]).to eq(original)
        end
      end
    end

  describe '#apply_defaults' do
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

    it 'merges defaults into sections while preserving overrides' do
      result = described_class.apply_defaults(config_with_defaults)

      expect(result[:api]).to eq({ timeout: 10, enabled: true })
      expect(result[:web]).to eq({ timeout: 5, enabled: true })
    end

    it 'handles empty config' do
      result = described_class.apply_defaults(empty_config)
      expect(result).to eq({})
    end

    it 'handles nil config' do
      result = described_class.apply_defaults(nil_config)
      expect(result).to eq({})
    end

    it 'preserves defaults when section value is nil' do
      config = {
        defaults: { dsn: 'default-dsn' },
        backend: { dsn: nil },
        frontend: { dsn: nil }
      }
      result = described_class.apply_defaults(config)
      expect(result[:backend][:dsn]).to eq('default-dsn')
      expect(result[:frontend][:dsn]).to eq('default-dsn')
    end

    it 'processes real world service config correctly' do
      result = described_class.apply_defaults(service_config)

      expect(result[:backend]).to eq({
        dsn: 'backend-dsn',
        environment: 'test'
      })

      expect(result[:frontend]).to eq({
        dsn: 'default-dsn',
        environment: 'test',
        path: '/web'
      })
    end

    it 'preserves original defaults hash' do
      original_defaults = service_config[:defaults].dup
      described_class.apply_defaults(service_config)

      expect(service_config[:defaults]).to eq(original_defaults)
    end
  end
end
