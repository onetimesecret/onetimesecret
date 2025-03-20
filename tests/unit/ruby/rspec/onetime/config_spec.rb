# tests/unit/ruby/rspec/onetime/config_spec.rb

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

  describe '#before_load' do
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

          described_class.before_load

          expect(ENV['REGIONS_ENABLED']).to eq('TESTA')
        end
      end

      context 'when REGIONS_ENABLE is set but REGIONS_ENABLED is not' do
        it 'copies REGIONS_ENABLE value to REGIONS_ENABLED' do
          ENV.delete('REGIONS_ENABLED')
          ENV['REGIONS_ENABLE'] = 'TESTB'

          described_class.before_load

          expect(ENV['REGIONS_ENABLED']).to eq('TESTB')
        end
      end

      context 'when both REGIONS_ENABLED and REGIONS_ENABLE are set' do
        it 'prioritizes REGIONS_ENABLED' do
          ENV['REGIONS_ENABLED'] = 'TESTA'
          ENV['REGIONS_ENABLE'] = 'TESTB'

          described_class.before_load

          expect(ENV['REGIONS_ENABLED']).to eq('TESTA')
        end
      end

      context 'when neither REGIONS_ENABLED nor REGIONS_ENABLE are set' do
        it 'sets REGIONS_ENABLED to false' do
          ENV.delete('REGIONS_ENABLED')
          ENV.delete('REGIONS_ENABLE')

          described_class.before_load

          expect(ENV['REGIONS_ENABLED']).to eq('false')
        end
      end
    end
  end

  describe '#after_load' do
    context 'colonels backwards compatibility' do
      it 'moves colonels from root level to site.authentication when not present in site.authentication' do
        # Config with colonels at root level only
        config = {
          colonels: ['root@example.com', 'admin@example.com'],
          site: {
            authentication: {
              enabled: true # Set authentication as enabled
            }
          },
          development: {},
          mail: {
            truemail: {}
          }
        }

        described_class.after_load(config)

        expect(config[:site][:authentication][:colonels]).to eq(['root@example.com', 'admin@example.com'])
      end

      it 'keeps colonels in site.authentication when present' do
        # Config with colonels in site.authentication
        config = {
          site: {
            authentication: {
              enabled: true, # Set authentication as enabled
              colonels: ['site@example.com']
            }
          },
          development: {},
          mail: {
            truemail: {}
          }
        }

        described_class.after_load(config)

        expect(config[:site][:authentication][:colonels]).to eq(['site@example.com'])
      end

      it 'prioritizes site.authentication colonels when defined in both places' do
        # Config with colonels in both places
        config = {
          colonels: ['root@example.com', 'admin@example.com'],
          site: {
            authentication: {
              enabled: true, # Set authentication as enabled
              colonels: ['site@example.com', 'auth@example.com']
            }
          },
          development: {},
          mail: {
            truemail: {}
          }
        }

        described_class.after_load(config)

        # Should not change the existing site.authentication.colonels
        expect(config[:site][:authentication][:colonels]).to eq(['site@example.com', 'auth@example.com'])
      end

      it 'initializes empty colonels array when not defined anywhere' do
        # Config with no colonels defined
        config = {
          site: {
            authentication: {
              enabled: true # Set authentication as enabled
            }
          },
          development: {},
          mail: {
            truemail: {}
          }
        }

        described_class.after_load(config)

        expect(config[:site][:authentication][:colonels]).to eq([])
      end

      it 'handles missing site.authentication section' do
        # Config without site.authentication section
        config = {
          colonels: ['root@example.com'],
          site: {},
          development: {},
          mail: {
            truemail: {}
          }
        }

        expect {
          described_class.after_load(config)
        }.to raise_error(OT::Problem, /No `site.authentication` config found/)
      end

      it 'sets authentication colonels to false when authentication is disabled' do
        # Config with authentication disabled
        config = {
          colonels: ['root@example.com', 'admin@example.com'],
          site: {
            authentication: {
              enabled: false,
              colonels: ['site@example.com']
            }
          },
          development: {},
          mail: {
            truemail: {}
          }
        }

        described_class.after_load(config)

        # When authentication is disabled, all authentication settings are set to false
        expect(config[:site][:authentication][:colonels]).to eq(false)
      end
    end
  end
end
