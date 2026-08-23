# spec/unit/onetime/operations/email/config_summary_spec.rb
#
# frozen_string_literal: true

# Regression guard for the provider-omission bug class: config_summary once
# shipped without a lettermint arm and nobody noticed. masked_provider_config
# now dispatches on Mail::ProviderRegistry descriptors, so every registered
# provider MUST produce the six-key superset with a live has_credentials
# boolean — enumerated here over the registry itself, so a future provider
# cannot be silently absent from the summary.

require 'spec_helper'
require 'onetime/operations/email/config_summary'

RSpec.describe Onetime::Operations::Email::ConfigSummary do
  superset_keys = %i[domain has_credentials host port region tls].sort.freeze

  describe '.masked_provider_config covers every registry provider' do
    Onetime::Mail::ProviderRegistry.descriptors.each do |descriptor|
      context "for #{descriptor.name}" do
        let(:full_creds) do
          # All keys from every summary credential group present -> credentialed.
          descriptor.summary_credential_groups.flatten.to_h { |key| [key, 'configured-value'] }
        end

        it 'emits the six-key superset with has_credentials true when credentials are configured' do
          allow(Onetime::Mail::Mailer)
            .to receive(descriptor.provider_config_method).and_return(full_creds)

          summary = described_class.masked_provider_config(descriptor.name, {})

          expect(summary.keys.sort).to eq(superset_keys)
          expect(summary[:has_credentials]).to be(true),
            "#{descriptor.name} must report has_credentials from the summary — " \
            'a provider missing from ConfigSummary is the lettermint-omission bug'
        end

        it 'reports has_credentials false when no credentials are configured' do
          allow(Onetime::Mail::Mailer)
            .to receive(descriptor.provider_config_method).and_return({})

          summary = described_class.masked_provider_config(descriptor.name, {})
          expect(summary[:has_credentials]).to be false
        end

        it 'never emits a raw credential value' do
          allow(Onetime::Mail::Mailer)
            .to receive(descriptor.provider_config_method).and_return(full_creds)

          summary = described_class.masked_provider_config(descriptor.name, {})
          expect(summary.values.map(&:to_s)).not_to include('configured-value')
        end
      end
    end

    it 'yields the bare superset for non-provider transports (logger)' do
      summary = described_class.masked_provider_config('logger', {})
      expect(summary).to eq(
        host: nil, port: nil, domain: nil, tls: nil, region: nil, has_credentials: false,
      )
    end
  end

  describe 'provider-specific masking behavior (unstubbed builders)' do
    it 'smtp: emits host/port/domain/tls, coerces port, and requires user AND pass' do
      raw = {
        'host' => 'smtp.example.com', 'port' => '587', 'domain' => 'example.com',
        'tls' => true, 'user' => 'smtp-user', 'pass' => 'super-secret-pw',
      }
      summary = described_class.masked_provider_config('smtp', raw)
      expect(summary).to include(
        host: 'smtp.example.com', port: 587, domain: 'example.com',
        tls: true, has_credentials: true,
      )
      expect(summary.values).not_to include('smtp-user', 'super-secret-pw')
    end

    it 'lettermint: sending api_token OR provisioning team_token each count' do
      with_token = described_class.masked_provider_config(
        'lettermint', { 'lettermint_api_token' => 'lm_token' }
      )
      with_team = described_class.masked_provider_config(
        'lettermint', { 'lettermint_team_token' => 'lm_team' }
      )
      expect(with_token[:has_credentials]).to be true
      expect(with_team[:has_credentials]).to be true
    end

    it 'smtp2go: baked-in subdomain defaults do NOT count as credentials' do
      # smtp2go_provider_config always emits returnpath/tracking subdomains,
      # so an emptiness test would wrongly report credentials present.
      summary = described_class.masked_provider_config('smtp2go', {})
      expect(summary[:has_credentials]).to be false
    end
  end
end
