# spec/unit/onetime/mail/provider_registry_spec.rb
#
# frozen_string_literal: true

# Contract tests for the single authoritative provider descriptor registry,
# plus parity pins: every legacy constant (PROVIDER_STRATEGIES, PROVIDER_MAP,
# PROVIDER_TYPES, ProviderConfig::DEFAULTS, feedback PROVIDERS) is now a
# derivation of the registry, and these tests pin the derived content to the
# exact pre-refactor values so the rewiring cannot have changed behavior.

require 'spec_helper'
require 'onetime/mail/provider_registry'
require 'onetime/mail/sender_strategies'
require 'onetime/domain_validation/sender_strategies/strategy'
require 'onetime/operations/email/sync_provider_feedback'
require 'onetime/operations/email/provider_status'
require 'onetime/operations/email/recipient_lookup'

RSpec.describe Onetime::Mail::ProviderRegistry do
  describe '.providers' do
    it 'lists every provider in detection-precedence order' do
      expect(described_class.providers).to eq(%w[ses sendgrid lettermint smtp2go smtp])
    end
  end

  describe 'descriptors' do
    it 'declares required and optional credential keys for every provider' do
      described_class.descriptors.each do |descriptor|
        expect(descriptor.required_credential_keys).to all(be_a(String)),
          "#{descriptor.name} required keys"
        expect(descriptor.required_credential_keys).not_to be_empty,
          "#{descriptor.name} must declare required credential keys"
        expect(descriptor.optional_credential_keys).to all(be_a(String))
      end
    end

    it 'pins the required credential keys per provider' do
      required = described_class.descriptors.to_h { |d| [d.name, d.required_credential_keys] }
      expect(required).to eq(
        'ses' => %w[access_key_id secret_access_key region],
        'sendgrid' => %w[api_key],
        'lettermint' => %w[team_token],
        'smtp2go' => %w[api_key],
        'smtp' => %w[host],
      )
    end

    it 'resolves every sender strategy class name to a real class' do
      described_class.descriptors.each do |descriptor|
        expect(descriptor.sender_strategy_class).to be_a(Class), descriptor.name
        expect(descriptor.sender_strategy_class.name).to eq(descriptor.sender_strategy_class_name)
      end
    end

    it 'resolves every validation strategy class name to a real class (smtp has none)' do
      described_class.descriptors.each do |descriptor|
        if descriptor.name == 'smtp'
          expect(descriptor.validation_strategy_class).to be_nil
        else
          expect(descriptor.validation_strategy_class).to be_a(Class), descriptor.name
        end
      end
    end

    it 'resolves every delivery class name to a real class' do
      described_class.descriptors.each do |descriptor|
        expect(descriptor.delivery_class).to be_a(Class), descriptor.name
      end
    end

    it 'names a Mailer config-builder method that exists for every provider' do
      mailer = Onetime::Mail::Mailer.singleton_class
      described_class.descriptors.each do |descriptor|
        expect(mailer.private_method_defined?(descriptor.provider_config_method))
          .to be(true), "Mailer must define #{descriptor.provider_config_method}"
      end
    end

    it 'declares summary credential groups drawn from known credential keys' do
      described_class.descriptors.each do |descriptor|
        known = descriptor.required_credential_keys + descriptor.optional_credential_keys
        descriptor.summary_credential_groups.flatten.each do |key|
          expect(known).to include(key),
            "#{descriptor.name} summary group key '#{key}' is not a declared credential key"
        end
      end
    end
  end

  describe '.descriptor / .descriptor!' do
    it 'normalizes case, whitespace, and symbols' do
      expect(described_class.descriptor(:SES)&.name).to eq('ses')
      expect(described_class.descriptor(' SendGrid ')&.name).to eq('sendgrid')
    end

    it 'returns nil for unknown or blank providers' do
      expect(described_class.descriptor('logger')).to be_nil
      expect(described_class.descriptor(nil)).to be_nil
      expect(described_class.descriptor('')).to be_nil
    end

    it 'descriptor! raises naming the supported providers' do
      expect { described_class.descriptor!('mailchimp') }
        .to raise_error(ArgumentError, /mailchimp.*ses, sendgrid, lettermint, smtp2go, smtp/)
    end
  end

  describe '.provisioning_providers' do
    it 'excludes smtp (manual DNS)' do
      expect(described_class.provisioning_providers).to eq(%w[ses sendgrid lettermint smtp2go])
    end

    it 'provisioning_provider? is false for smtp, unknown, and nil' do
      expect(described_class.provisioning_provider?('smtp2go')).to be true
      expect(described_class.provisioning_provider?('smtp')).to be false
      expect(described_class.provisioning_provider?('logger')).to be false
      expect(described_class.provisioning_provider?(nil)).to be false
    end
  end

  describe '.feedback_providers' do
    it 'lists the providers with a pollable feedback API' do
      expect(described_class.feedback_providers).to eq(%w[ses lettermint smtp2go])
    end
  end

  describe '.missing_required_credentials' do
    it 'names the missing keys' do
      expect(described_class.missing_required_credentials('ses', { 'region' => 'us-east-1' }))
        .to eq(%w[access_key_id secret_access_key])
    end

    it 'accepts string or symbol credential keys' do
      creds = { 'access_key_id' => 'a', secret_access_key: 'b', region: 'us-east-1' }
      expect(described_class.missing_required_credentials('ses', creds)).to eq([])
    end

    it 'treats blank strings as missing' do
      expect(described_class.missing_required_credentials('smtp2go', { 'api_key' => '' }))
        .to eq(%w[api_key])
    end

    it 'tolerates a nil credentials hash (everything missing)' do
      expect(described_class.missing_required_credentials('sendgrid', nil)).to eq(%w[api_key])
    end

    it 'returns [] for unknown providers (no known requirements)' do
      expect(described_class.missing_required_credentials('logger', {})).to eq([])
    end

    it 'is NOT fooled by smtp2go baked-in subdomain defaults (the emptiness-test defect)' do
      # Mailer.smtp2go_provider_config now signals a missing api_key with an
      # empty hash, but the key-level check must stay robust to a builder
      # that bakes non-secret defaults into an otherwise keyless hash.
      creds = { 'returnpath_subdomain' => 'bounce', 'tracking_subdomain' => 'track' }
      expect(described_class.missing_required_credentials('smtp2go', creds)).to eq(%w[api_key])
    end
  end

  describe '.detect_provider' do
    it 'requires BOTH region and user for ses (precedence over smtp host)' do
      expect(described_class.detect_provider('region' => 'r', 'user' => 'u', 'host' => 'h')).to eq('ses')
      expect(described_class.detect_provider('region' => 'r', 'host' => 'h')).to eq('smtp')
    end

    it 'detects each single-key provider' do
      expect(described_class.detect_provider('sendgrid_api_key' => 'k')).to eq('sendgrid')
      expect(described_class.detect_provider('lettermint_api_token' => 't')).to eq('lettermint')
      expect(described_class.detect_provider('smtp2go_api_key' => 'k')).to eq('smtp2go')
      expect(described_class.detect_provider('host' => 'h')).to eq('smtp')
    end

    it 'returns nil when nothing matches (caller falls back to logger)' do
      expect(described_class.detect_provider({})).to be_nil
      expect(described_class.detect_provider(nil)).to be_nil
    end
  end

  # ==========================================================================
  # Parity pins: derived legacy constants must carry the exact pre-refactor
  # content. If a registry edit changes any of these, the change is visible
  # here, not discovered in production.
  # ==========================================================================

  describe 'derived constant parity' do
    it 'Mail::SenderStrategies::PROVIDER_STRATEGIES matches the pre-refactor map' do
      strategies = Onetime::Mail::SenderStrategies
      expect(strategies::PROVIDER_STRATEGIES).to eq(
        'ses' => strategies::SESSenderStrategy,
        'sendgrid' => strategies::SendGridSenderStrategy,
        'lettermint' => strategies::LettermintSenderStrategy,
        'smtp2go' => strategies::Smtp2goSenderStrategy,
        'smtp' => strategies::SMTPSenderStrategy,
      )
    end

    it 'Mail::SenderStrategies::PROVISIONING_PROVIDERS matches the pre-refactor list' do
      expect(Onetime::Mail::SenderStrategies::PROVISIONING_PROVIDERS)
        .to eq(%w[ses sendgrid lettermint smtp2go])
    end

    it 'DomainValidation SenderStrategy::PROVIDER_MAP matches the pre-refactor map' do
      validation = Onetime::DomainValidation::SenderStrategies
      expect(validation::SenderStrategy::PROVIDER_MAP).to eq(
        'ses' => validation::SesValidation,
        'sendgrid' => validation::SendgridValidation,
        'lettermint' => validation::LettermintValidation,
        'smtp2go' => validation::Smtp2goValidation,
      )
    end

    it 'MailerConfig::PROVIDER_TYPES keeps its historical content and ordering' do
      expect(Onetime::CustomDomain::MailerConfig::PROVIDER_TYPES)
        .to eq(%w[smtp ses sendgrid lettermint smtp2go])
      expect(Onetime::CustomDomain::MailerConfig::PROVIDER_TYPES).to be_frozen
    end

    it 'ProviderConfig::DEFAULTS matches the pre-refactor content exactly' do
      expect(Onetime::DomainValidation::SenderStrategies::ProviderConfig::DEFAULTS).to eq(
        'ses' => {
          region: 'us-east-1',
          dkim_selector_count: 3,
          spf_include: 'amazonses.com',
        },
        'sendgrid' => {
          subdomain: 'em',
          dkim_selectors: %w[s1 s2],
          spf_include: 'sendgrid.net',
        },
        'lettermint' => {
          dkim_selectors: %w[lm1 lm2],
          spf_cname_prefix: 'lm-bounces',
          spf_cname_target: 'bounces.lmta.net',
          api_base_url: 'https://api.lettermint.co/v1',
        },
        'smtp2go' => {
          api_base_url: 'https://api.smtp2go.com/v3',
          returnpath_subdomain: 'bounce',
          tracking_subdomain: 'track',
        },
      )
    end

    it 'feedback PROVIDERS constants derive the registry list (incl. smtp2go)' do
      expect(Onetime::Operations::Email::SyncProviderFeedback::PROVIDERS).to eq(%w[ses lettermint smtp2go])
      expect(Onetime::Operations::Email::ProviderStatus::PROVIDERS).to eq(%w[ses lettermint smtp2go])
      expect(Onetime::Operations::Email::RecipientLookup::PROVIDERS).to eq(%w[ses lettermint smtp2go])
    end
  end
end
