# spec/unit/onetime/config_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::Config do
  describe '#apply_defaults' do
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
            'enabled' => true,
          },
          'backend' => {
            'dsn' => 'backend-dsn',
            'traces_sample_rate' => 0.1,
          },
          'frontend' => {
            'path' => '/web',
            'profiles_sample_rate' => 0.2,
          },
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
          expect(described_class.apply_defaults_to_peers(nil)).to eq({})
        end

        it 'handles empty config' do
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
            'web' => { 'port' => 3000 },
          }
          result = described_class.apply_defaults_to_peers(config)
          expect(result.keys).to contain_exactly('web')
        end

        it 'preserves original defaults' do
          original = sentry_config['defaults'].dup
          described_class.apply_defaults_to_peers(sentry_config)
          expect(sentry_config['defaults']).to eq(original)
        end
      end

      # Contract relied on by Onetime::Initializers::SetupDiagnostics, which
      # reads diagnostics.sentry.backend.org_id (and equivalently workers/
      # frontend) at runtime. If this propagation ever regresses, strict
      # trace continuation silently turns off — this is the bug fixed in
      # commit af8bd0243 / PR #3007.
      context 'sentry org_id propagation contract' do
        let(:sentry_with_org_id) do
          {
            'defaults' => {
              'org_id' => 'org-abc-123',
              'environment' => 'test',
            },
            'backend'  => { 'dsn' => 'backend-dsn' },
            'frontend' => { 'dsn' => 'frontend-dsn' },
            'workers'  => { 'dsn' => 'workers-dsn' },
          }
        end

        it 'propagates org_id from defaults to every peer hash' do
          result = described_class.apply_defaults_to_peers(sentry_with_org_id)

          expect(result['backend']['org_id']).to  eq('org-abc-123')
          expect(result['frontend']['org_id']).to eq('org-abc-123')
          expect(result['workers']['org_id']).to  eq('org-abc-123')
        end

        it 'lets a peer override org_id from defaults' do
          sentry_with_org_id['workers']['org_id'] = 'org-workers-override'
          result = described_class.apply_defaults_to_peers(sentry_with_org_id)

          expect(result['backend']['org_id']).to eq('org-abc-123')
          expect(result['workers']['org_id']).to eq('org-workers-override')
        end

        it 'leaves org_id absent on peers when defaults omit it' do
          sentry_with_org_id['defaults'].delete('org_id')
          result = described_class.apply_defaults_to_peers(sentry_with_org_id)

          expect(result['backend']).not_to have_key('org_id')
          expect(result['frontend']).not_to have_key('org_id')
          expect(result['workers']).not_to have_key('org_id')
        end
      end
  end

  describe '#apply_defaults' do
    let(:config_with_defaults) do
      {
        'defaults' => { 'timeout' => 5, 'enabled' => true },
        'api' => { 'timeout' => 10 },
        'web' => {},
      }
    end

    let(:empty_config) { {} }
    let(:nil_config) { nil }

    let(:service_config) do
      {
        'defaults' => { 'dsn' => 'default-dsn', 'environment' => 'test' },
        'backend' => { 'dsn' => 'backend-dsn' },
        'frontend' => { 'path' => '/web' },
      }
    end

    it 'merges defaults into sections while preserving overrides' do
      result = described_class.apply_defaults_to_peers(config_with_defaults)

      expect(result['api']).to eq({ 'timeout' => 10, 'enabled' => true })
      expect(result['web']).to eq({ 'timeout' => 5, 'enabled' => true })
    end

    it 'handles empty config' do
      result = described_class.apply_defaults_to_peers(empty_config)
      expect(result).to eq({})
    end

    it 'handles nil config' do
      result = described_class.apply_defaults_to_peers(nil_config)
      expect(result).to eq({})
    end

    it 'preserves defaults when section value is nil' do
      config = {
        'defaults' => { 'dsn' => 'default-dsn' },
        'backend' => { 'dsn' => nil },
        'frontend' => { 'dsn' => nil },
      }
      result = described_class.apply_defaults_to_peers(config)
      expect(result['backend']['dsn']).to eq('default-dsn')
      expect(result['frontend']['dsn']).to eq('default-dsn')
    end

    it 'processes real world service config correctly' do
      result = described_class.apply_defaults_to_peers(service_config)

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
      original_defaults = service_config['defaults'].dup
      described_class.apply_defaults_to_peers(service_config)

      expect(service_config['defaults']).to eq(original_defaults)
    end
  end

  describe '#load (layered defaults)' do
    it 'merges defaults file as base layer under environment config' do
      defaults_path = Onetime::Utils::ConfigResolver.defaults_path('config')
      skip 'No config.defaults.yaml found' unless defaults_path

      config = described_class.load

      # email_providers is defined in config.defaults.yaml but not in
      # config.test.yaml — layered loading makes it visible (#3322)
      expect(config).to have_key('email_providers')
    end

    it 'lets environment config override defaults' do
      config = described_class.load

      # config.test.yaml sets emailer.mode to 'logger', which should
      # override whatever config.defaults.yaml sets
      expect(config.dig('emailer', 'mode')).to eq('logger')
    end

    it 'preserves defaults for sections not in environment config' do
      defaults_path = Onetime::Utils::ConfigResolver.defaults_path('config')
      skip 'No config.defaults.yaml found' unless defaults_path

      config = described_class.load

      # compatibility section exists in defaults but not in test config;
      # after layered merge it should be present
      expect(config).to have_key('compatibility')
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
    context 'jurisdiction parsing from JURISDICTIONS env var' do
      # Use 'silent' to bypass deprecation check - we're testing parsing, not deprecation
      def build_config(jurisdictions_value)
        {
          'site' => { 'secret' => 'test-secret' },
          'mail' => { 'truemail' => {} },
          'features' => { 'regions' => { 'jurisdictions' => jurisdictions_value } },
          'compatibility' => { 'deprecated_config_mode' => 'silent' },
        }
      end

      it 'parses single jurisdiction from env format with i18n key' do
        config = build_config('EU:eu.example.com')

        result = described_class.after_load(config)
        jurisdictions = result.dig('features', 'regions', 'jurisdictions')

        expect(jurisdictions).to eq([
          {
            'identifier' => 'EU',
            'domain' => 'eu.example.com',
            'display_name_i18n_key' => 'web.regions.jurisdictions.eu.name',
          },
        ])
      end

      it 'parses multiple jurisdictions from env format with i18n keys' do
        config = build_config('EU:eu.example.com,CA:ca.example.com,US:us.example.com')

        result = described_class.after_load(config)
        jurisdictions = result.dig('features', 'regions', 'jurisdictions')

        expect(jurisdictions).to eq([
          {
            'identifier' => 'EU',
            'domain' => 'eu.example.com',
            'display_name_i18n_key' => 'web.regions.jurisdictions.eu.name',
          },
          {
            'identifier' => 'CA',
            'domain' => 'ca.example.com',
            'display_name_i18n_key' => 'web.regions.jurisdictions.ca.name',
          },
          {
            'identifier' => 'US',
            'domain' => 'us.example.com',
            'display_name_i18n_key' => 'web.regions.jurisdictions.us.name',
          },
        ])
      end

      it 'handles empty string as empty array' do
        config = build_config('')

        result = described_class.after_load(config)
        jurisdictions = result.dig('features', 'regions', 'jurisdictions')

        expect(jurisdictions).to eq([])
      end

      it 'handles nil as empty array' do
        config = build_config(nil)

        result = described_class.after_load(config)
        jurisdictions = result.dig('features', 'regions', 'jurisdictions')

        expect(jurisdictions).to eq([])
      end

      it 'trims whitespace around entries' do
        config = build_config(' EU:eu.example.com , CA:ca.example.com ')

        result = described_class.after_load(config)
        jurisdictions = result.dig('features', 'regions', 'jurisdictions')

        expect(jurisdictions[0]['identifier']).to eq('EU')
        expect(jurisdictions[0]['domain']).to eq('eu.example.com')
        expect(jurisdictions[1]['identifier']).to eq('CA')
        expect(jurisdictions[1]['domain']).to eq('ca.example.com')
      end

      it 'handles trailing comma gracefully' do
        config = build_config('EU:eu.example.com,CA:ca.example.com,')

        result = described_class.after_load(config)
        jurisdictions = result.dig('features', 'regions', 'jurisdictions')

        expect(jurisdictions.length).to eq(2)
        expect(jurisdictions[0]['identifier']).to eq('EU')
        expect(jurisdictions[1]['identifier']).to eq('CA')
      end

      it 'raises OT::Problem when domain is missing' do
        config = build_config('EU:')

        expect {
          described_class.after_load(config)
        }.to raise_error(OT::Problem, /Invalid JURISDICTIONS format:.*EU:.*expected ID:domain/)
      end

      it 'raises OT::Problem when identifier is missing' do
        config = build_config(':domain.com')

        expect {
          described_class.after_load(config)
        }.to raise_error(OT::Problem, /Invalid JURISDICTIONS format:.*:domain.com.*expected ID:domain/)
      end

      it 'raises OT::Problem for entry with only colon' do
        config = build_config(':')

        expect {
          described_class.after_load(config)
        }.to raise_error(OT::Problem, /Invalid JURISDICTIONS format/)
      end

      it 'handles entry with multiple colons (domain with port)' do
        config = build_config('EU:eu.example.com:8443')

        result = described_class.after_load(config)
        jurisdictions = result.dig('features', 'regions', 'jurisdictions')

        # split(':', 2) preserves the port in domain
        expect(jurisdictions).to eq([
          {
            'identifier' => 'EU',
            'domain' => 'eu.example.com:8443',
            'display_name_i18n_key' => 'web.regions.jurisdictions.eu.name',
          },
        ])
      end

      it 'preserves existing array format and adds i18n key' do
        config = build_config([{ 'identifier' => 'AT', 'domain' => 'at.example.com' }])

        result = described_class.after_load(config)
        jurisdictions = result.dig('features', 'regions', 'jurisdictions')

        expect(jurisdictions).to eq([
          {
            'identifier' => 'AT',
            'domain' => 'at.example.com',
            'display_name_i18n_key' => 'web.regions.jurisdictions.at.name',
          },
        ])
      end
    end

    context 'deprecation detection for YAML jurisdictions array' do
      def build_deprecated_config
        {
          'site' => { 'secret' => 'test-secret' },
          'mail' => { 'truemail' => {} },
          'features' => {
            'regions' => {
              'jurisdictions' => [
                { 'identifier' => 'EU', 'domain' => 'eu.example.com' },
              ],
            },
          },
        }
      end

      it 'raises ConfigError in strict mode (default) when YAML array is present' do
        config = build_deprecated_config
        # strict is the default when not specified

        expect {
          described_class.after_load(config)
        }.to raise_error(OT::ConfigError, /jurisdictions array format is deprecated/)
      end

      it 'logs warning in warn mode when YAML array is present' do
        config = build_deprecated_config.merge(
          'compatibility' => { 'deprecated_config_mode' => 'warn' }
        )

        expect(OT).to receive(:le).with(/CONFIG DEPRECATION:.*jurisdictions array format/)

        expect {
          described_class.after_load(config)
        }.not_to raise_error
      end

      it 'ignores deprecation in silent mode' do
        config = build_deprecated_config.merge(
          'compatibility' => { 'deprecated_config_mode' => 'silent' }
        )

        expect {
          described_class.after_load(config)
        }.not_to raise_error
      end
    end

    context 'soft deprecations (severity: :warn) for legacy brand config (#3612)' do
      def stub_env(env)
        # Strip the legacy brand env vars from the base env so ambient values
        # (e.g. from .env) don't bleed into cases.
        base = ENV.to_h.reject { |k, _| %w[SITE_NAME LOGO_URL LOGO_ALT].include?(k) }
        stub_const('ENV', base.merge(env))
      end

      def build_config(mode = nil)
        conf = {
          'site' => { 'secret' => 'test-secret' },
          'mail' => { 'truemail' => {} },
        }
        conf['compatibility'] = { 'deprecated_config_mode' => mode } if mode
        conf
      end

      it 'logs SITE_NAME under strict mode (default) and boot continues' do
        stub_env('SITE_NAME' => 'Legacy Brand')

        expect(OT).to receive(:le).with(/CONFIG DEPRECATION:.*SITE_NAME is deprecated/)

        result = nil
        expect {
          result = described_class.after_load(build_config)
        }.not_to raise_error
        # The legacy value still works: normalize_brand adopts it as fallback.
        expect(result.dig('brand', 'product_name')).to eq('Legacy Brand')
      end

      it 'logs the header.branding path under strict mode and strips the subtree' do
        stub_env({})
        config = build_config
        config['site']['interface'] = {
          'ui' => { 'header' => { 'branding' => { 'site_name' => 'Legacy' } } },
        }

        expect(OT).to receive(:le).with(/CONFIG DEPRECATION:.*header\.branding is deprecated/)

        result = described_class.after_load(config)
        expect(result.dig('site', 'interface', 'ui', 'header')).not_to have_key('branding')
        expect(result.dig('brand', 'product_name')).to eq('Legacy')
      end

      it 'logs LOGO_URL and LOGO_ALT under strict mode and boot continues' do
        stub_env('LOGO_URL' => 'https://cdn.example.com/legacy.svg',
                 'LOGO_ALT' => 'Legacy mark')

        expect(OT).to receive(:le).with(/CONFIG DEPRECATION:.*LOGO_URL is deprecated/)
        expect(OT).to receive(:le).with(/CONFIG DEPRECATION:.*LOGO_ALT is deprecated/)

        result = nil
        expect {
          result = described_class.after_load(build_config)
        }.not_to raise_error
        expect(result.dig('brand', 'logo_url')).to eq('https://cdn.example.com/legacy.svg')
        expect(result.dig('brand', 'logo_alt')).to eq('Legacy mark')
      end

      it 'still raises for removed keys (site.domains) under strict mode' do
        stub_env({})
        config = build_config
        config['site']['domains'] = { 'enabled' => true }

        expect {
          described_class.after_load(config)
        }.to raise_error(OT::ConfigError, /site\.domains is ignored/)
      end

      it 'logs soft entries even when a hard entry raises under strict mode' do
        stub_env('SITE_NAME' => 'Legacy Brand')
        config = build_config
        config['site']['domains'] = { 'enabled' => true }

        expect(OT).to receive(:le).with(/CONFIG DEPRECATION:.*SITE_NAME is deprecated/)

        expect {
          described_class.after_load(config)
        }.to raise_error(OT::ConfigError, /site\.domains is ignored/)
      end

      it 'logs both soft and hard entries under warn mode without raising' do
        stub_env('SITE_NAME' => 'Legacy Brand')
        config = build_config('warn')
        config['site']['domains'] = { 'enabled' => true }

        expect(OT).to receive(:le).with(/CONFIG DEPRECATION:.*SITE_NAME is deprecated/)
        expect(OT).to receive(:le).with(/CONFIG DEPRECATION:.*site\.domains is ignored/)

        expect {
          described_class.after_load(config)
        }.not_to raise_error
      end

      it 'suppresses soft warnings under silent mode' do
        stub_env('SITE_NAME' => 'Legacy Brand')

        expect(OT).not_to receive(:le).with(/CONFIG DEPRECATION/)

        result = nil
        expect {
          result = described_class.after_load(build_config('silent'))
        }.not_to raise_error
        # Silent only mutes the report; the fallback shim still applies.
        expect(result.dig('brand', 'product_name')).to eq('Legacy Brand')
      end
    end

    context 'site configuration validation' do
      it 'uses default values when site has minimal config' do
        raw_config = {
          'site' => {
            'secret' => 'anyvaluewilldo',
          },
          'mail' => {
            'truemail' => {},
          },
        }

        expect {
          described_class.after_load(raw_config)
        }.not_to raise_error
      end

      it 'raises heck when site.secret is nil' do
        config = {
          'site' => { 'secret' => nil },
          'development' => {},
          'mail' => {
            'truemail' => {},
          },
        }

        expect {
          described_class.after_load(config)
        }.to raise_error(OT::Problem, /Global secret cannot be nil/)
      end

      it 'raises heck when site.secret is CHANGEME (same behaviour as nil)' do
        config = {
          'site' => { 'secret' => 'CHANGEME' },
          'development' => {},
          'mail' => {
            'truemail' => {},
          },
        }

        expect {
          described_class.after_load(config)
        }.to raise_error(OT::Problem, /Global secret cannot be nil/)
      end

      it 'handles missing site.authentication section' do
        config = {
          'site' => { 'secret' => '1234' },
          'mail' => {
            'truemail' => {},
          },
        }

        expect {
          described_class.after_load(config)
        }.not_to raise_error
      end
    end
  end
end
