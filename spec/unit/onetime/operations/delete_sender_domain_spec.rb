# spec/unit/onetime/operations/delete_sender_domain_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/operations/delete_sender_domain'

RSpec.describe Onetime::Operations::DeleteSenderDomain do
  let(:mock_credentials) { { 'team_token' => 'fake-test-token' } }

  # Build a MailerConfig stand-in. effective_provider drives dispatch;
  # from_address is only consulted on the back-compat fallback path.
  def mailer_config_for(provider, from_address: 'sender@example.com')
    double(
      'MailerConfig',
      domain_id: 'cd:test123',
      provider: provider,
      effective_provider: provider,
      from_address: from_address,
    )
  end

  # ==========================================================================
  # Result object
  # ==========================================================================

  describe 'Result' do
    it 'implements success? / failed?' do
      ok  = described_class::Result.new(success: true, message: 'done', error: nil)
      bad = described_class::Result.new(success: false, message: nil, error: 'boom')

      expect(ok.success?).to be true
      expect(ok.failed?).to be false
      expect(bad.success?).to be false
      expect(bad.failed?).to be true
    end
  end

  # ==========================================================================
  # #call — per-provider dispatch (the core generalization)
  # ==========================================================================

  describe '#call dispatch' do
    before do
      allow(Onetime::Mail::Mailer).to receive(:provider_credentials).and_return(mock_credentials)
    end

    %w[ses sendgrid lettermint].each do |provider|
      it "dispatches deletion to the #{provider} strategy" do
        config   = mailer_config_for(provider)
        strategy = double("#{provider}_strategy")

        allow(Onetime::Mail::SenderStrategies).to receive(:for_provider)
          .with(provider).and_return(strategy)
        expect(strategy).to receive(:delete_sender_identity)
          .with(config, credentials: mock_credentials)
          .and_return({ deleted: true, message: "#{provider} identity deleted" })

        result = described_class.new(mailer_config: config).call

        expect(result.success?).to be true
        expect(result.message).to eq("#{provider} identity deleted")
        expect(result.error).to be_nil
      end
    end

    it 'loads credentials for the resolved provider' do
      config   = mailer_config_for('ses')
      strategy = double('ses_strategy', delete_sender_identity: { deleted: true, message: 'ok' })

      allow(Onetime::Mail::SenderStrategies).to receive(:for_provider)
        .with('ses').and_return(strategy)
      expect(Onetime::Mail::Mailer).to receive(:provider_credentials)
        .with('ses').and_return(mock_credentials)

      described_class.new(mailer_config: config).call
    end

    it 'downcases the effective provider before dispatch' do
      config   = mailer_config_for('Lettermint')
      strategy = double('lm_strategy', delete_sender_identity: { deleted: true, message: 'ok' })

      allow(Onetime::Mail::Mailer).to receive(:provider_credentials)
        .with('lettermint').and_return(mock_credentials)
      expect(Onetime::Mail::SenderStrategies).to receive(:for_provider)
        .with('lettermint').and_return(strategy)

      result = described_class.new(mailer_config: config).call

      expect(result.success?).to be true
    end
  end

  # ==========================================================================
  # #call — SMTP no-op (acceptance: makes no provider API call)
  # ==========================================================================

  describe '#call with SMTP provider' do
    it 'returns the SMTP no-op without making any provider API call' do
      config        = mailer_config_for('smtp')
      smtp_strategy = Onetime::Mail::SenderStrategies::SMTPSenderStrategy.new

      allow(Onetime::Mail::Mailer).to receive(:provider_credentials)
        .and_return({ 'host' => 'smtp.example.com' })
      # Use the real strategy so the genuine no-op path runs.
      allow(Onetime::Mail::SenderStrategies).to receive(:for_provider)
        .with('smtp').and_return(smtp_strategy)

      result = described_class.new(mailer_config: config).call

      expect(result.success?).to be true
      expect(result.message).to eq('SMTP providers do not have sender identities to delete.')
      # WebMock (disable_net_connect!) would have flagged any HTTP attempt.
      expect(a_request(:any, /.*/)).not_to have_been_made
    end
  end

  # ==========================================================================
  # #call — skip / back-compat paths
  # ==========================================================================

  describe '#call skip paths' do
    it 'skips when mailer_config is nil' do
      result = described_class.new(mailer_config: nil).call

      expect(result.success?).to be true
      expect(result.message).to eq('skipped: no mailer config')
    end

    it 'skips when neither a provider nor a from_address resolves' do
      config = double('MailerConfig', domain_id: 'cd:x', provider: '', effective_provider: '', from_address: '')

      result = described_class.new(mailer_config: config).call

      expect(result.success?).to be true
      expect(result.message).to eq('skipped: no effective provider')
    end

    it 'falls back to lettermint for legacy configs (address present, provider unresolvable)' do
      config   = double('MailerConfig', domain_id: 'cd:x', provider: '', effective_provider: '', from_address: 'a@b.com')
      strategy = double('lm_strategy')

      allow(Onetime::Mail::Mailer).to receive(:provider_credentials)
        .with('lettermint').and_return(mock_credentials)
      allow(Onetime::Mail::SenderStrategies).to receive(:for_provider)
        .with('lettermint').and_return(strategy)
      expect(strategy).to receive(:delete_sender_identity)
        .and_return({ deleted: true, message: 'legacy lettermint deleted' })

      result = described_class.new(mailer_config: config).call

      expect(result.success?).to be true
      expect(result.message).to eq('legacy lettermint deleted')
    end
  end

  # ==========================================================================
  # #call — error handling (never raises; wraps failures in Result)
  # ==========================================================================

  describe '#call error handling' do
    it 'swallows strategy errors into a failure Result' do
      config   = mailer_config_for('lettermint')
      strategy = double('lm_strategy')

      allow(Onetime::Mail::Mailer).to receive(:provider_credentials).and_return(mock_credentials)
      allow(Onetime::Mail::SenderStrategies).to receive(:for_provider).and_return(strategy)
      allow(strategy).to receive(:delete_sender_identity).and_raise(StandardError, 'provider API timeout')

      result = described_class.new(mailer_config: config).call

      expect(result.success?).to be false
      expect(result.failed?).to be true
      expect(result.error).to eq('provider API timeout')
    end
  end
end
