# spec/unit/onetime/mail/sender_strategies_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/mail/sender_strategies'

RSpec.describe Onetime::Mail::SenderStrategies do
  # ==========================================================================
  # .supported? — "has a strategy" (the predicate DeleteSenderDomain dispatches
  # on). The defining contrast with supports_provisioning? is that it INCLUDES
  # smtp, whose strategy is a deliberate no-op.
  # ==========================================================================

  describe '.supported?' do
    it 'is true for every provider with a registered strategy' do
      %w[ses sendgrid lettermint smtp].each do |provider|
        expect(described_class.supported?(provider)).to be(true), "expected '#{provider}' to be supported"
      end
    end

    it 'includes smtp, where supports_provisioning? deliberately does not' do
      expect(described_class.supported?('smtp')).to be true
      expect(described_class.supports_provisioning?('smtp')).to be false
    end

    it 'is false for transports/providers without a strategy' do
      %w[logger mailchimp postmark].each do |provider|
        expect(described_class.supported?(provider)).to be false
      end
    end

    it 'is false for blank/nil input' do
      expect(described_class.supported?('')).to be false
      expect(described_class.supported?(nil)).to be false
    end

    it 'normalizes case and accepts symbols' do
      expect(described_class.supported?(:SES)).to be true
      expect(described_class.supported?('LetterMint')).to be true
    end
  end

  # ==========================================================================
  # .for_provider
  # ==========================================================================

  describe '.for_provider' do
    it 'returns the matching strategy instance for known providers' do
      expect(described_class.for_provider('ses')).to be_a(described_class::SESSenderStrategy)
      expect(described_class.for_provider('smtp')).to be_a(described_class::SMTPSenderStrategy)
    end

    it 'is case-insensitive' do
      expect(described_class.for_provider('SendGrid')).to be_a(described_class::SendGridSenderStrategy)
    end

    it 'raises ArgumentError for unknown providers' do
      expect { described_class.for_provider('mailchimp') }
        .to raise_error(ArgumentError, /Unknown sender strategy/)
    end
  end

  # ==========================================================================
  # .supports_provisioning? / .supported_providers
  # ==========================================================================

  describe '.supports_provisioning?' do
    it 'is true for API-provisionable providers' do
      %w[ses sendgrid lettermint].each do |provider|
        expect(described_class.supports_provisioning?(provider)).to be true
      end
    end

    it 'is false for smtp (manual DNS configuration)' do
      expect(described_class.supports_provisioning?('smtp')).to be false
    end
  end

  describe '.supported_providers' do
    it 'lists every provider that has a strategy' do
      expect(described_class.supported_providers).to contain_exactly('ses', 'sendgrid', 'lettermint', 'smtp')
    end
  end

  # ==========================================================================
  # Cross-layer invariant: the strategy registry (what we can dispatch to)
  # and MailerConfig::PROVIDER_TYPES (what a config may store) are maintained
  # independently but must hold the same set. Reconcile validates against
  # PROVIDER_TYPES, DeleteSenderDomain dispatches via .supported? — if they
  # drift, one path accepts a provider the other rejects. This guards it.
  # ==========================================================================

  describe 'consistency with MailerConfig::PROVIDER_TYPES' do
    it 'covers exactly the providers a MailerConfig may store' do
      expect(described_class.supported_providers.sort)
        .to eq(Onetime::CustomDomain::MailerConfig::PROVIDER_TYPES.sort)
    end
  end
end
