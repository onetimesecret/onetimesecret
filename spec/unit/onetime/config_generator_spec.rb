# spec/unit/onetime/config_generator_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::ConfigGenerator do
  describe '.descriptor' do
    it 'returns the option catalog with string keys' do
      descriptor = described_class.descriptor
      expect(descriptor.keys).to include('deployment_mode', 'email_provider', 'default_ttl')
      expect(descriptor['deployment_mode'][:choices].map { |c| c[:value] }).to contain_exactly('simple', 'full')
    end
  end

  describe '.build' do
    it 'falls back to defaults when given no selections' do
      result = described_class.build({})
      expect(result.config_yaml).to include('default_ttl: 604800')
      expect(result.auth_yaml).to include('mode: simple')
      expect(result.warnings).to be_empty
    end

    it 'reflects boolean and select overrides in the YAML fragments' do
      result = described_class.build(
        'deployment_mode' => 'full',
        'domains_enabled' => 'true',
        'regions_enabled' => 'true',
        'default_ttl' => '2592000',
        'passphrase_required' => 'true',
        'email_provider' => 'ses',
      )

      expect(result.auth_yaml).to include('mode: full')
      expect(result.config_yaml).to include('default_ttl: 2592000')
      expect(result.config_yaml).to include('required: true')
      expect(result.config_yaml).to include('mode: ses')

      config = YAML.safe_load(result.config_yaml)
      expect(config.dig('features', 'domains', 'enabled')).to be true
      expect(config.dig('features', 'regions', 'enabled')).to be true

      auth = YAML.safe_load(result.auth_yaml)
      expect(auth['mode']).to eq('full')
    end

    it 'ignores unknown selection keys' do
      result = described_class.build('not_a_real_option' => 'nonsense', 'deployment_mode' => 'full')
      auth = YAML.safe_load(result.auth_yaml)
      expect(auth['mode']).to eq('full')
    end

    it 'falls back to the default for an out-of-range select value' do
      result = described_class.build('email_provider' => 'not-a-provider')
      config = YAML.safe_load(result.config_yaml)
      expect(config.dig('emailer', 'mode')).to eq('smtp')
    end

    it 'resets a dependent selection and warns when its dependency is unmet' do
      result = described_class.build('deployment_mode' => 'simple', 'sso_enabled' => 'true')

      auth = YAML.safe_load(result.auth_yaml)
      expect(auth).not_to have_key('full')
      expect(result.warnings.join).to match(/SSO/i)
    end

    it 'includes the sso feature flag only in full mode' do
      result = described_class.build('deployment_mode' => 'full', 'sso_enabled' => 'true')
      auth = YAML.safe_load(result.auth_yaml)
      expect(auth.dig('full', 'features', 'sso')).to be true
    end

    it 'never bakes a secret value into the YAML fragments or env snippet' do
      result = described_class.build('deployment_mode' => 'full', 'email_provider' => 'smtp', 'diagnostics_enabled' => 'true')

      combined = "#{result.config_yaml}\n#{result.auth_yaml}\n#{result.env_snippet}"

      # Every secret-bearing ENV placeholder must be present but empty —
      # no generated/default value ever appears next to the key.
      expect(result.env_snippet).to match(/^SECRET=$/)
      expect(result.env_snippet).to match(/^AUTH_DATABASE_URL=$/)
      expect(result.env_snippet).to match(/^SMTP_PASSWORD=$/)
      expect(result.env_snippet).to match(/^SENTRY_DSN_BACKEND=$/)

      # And the YAML fragments themselves never mention secret-bearing keys
      # at all (they're only ever emitted as ENV placeholders).
      expect(combined).not_to match(/secret:\s*\S/)
      expect(result.config_yaml).not_to include('database_url')
    end

    it 'returns valid YAML for every documented choice combination' do
      described_class::OPTIONS.each do |key, spec|
        next unless spec[:choices]

        spec[:choices].each do |choice|
          result = described_class.build(key.to_s => choice[:value].to_s)
          expect { YAML.safe_load(result.config_yaml) }.not_to raise_error
          expect { YAML.safe_load(result.auth_yaml) }.not_to raise_error
        end
      end
    end
  end
end
