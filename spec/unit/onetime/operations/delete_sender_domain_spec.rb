# spec/unit/onetime/operations/delete_sender_domain_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/operations/delete_sender_domain'

RSpec.describe Onetime::Operations::DeleteSenderDomain do
  let(:mock_credentials) { { 'team_token' => 'fake-test-token' } }

  # Real strategy classes, used for verifying doubles so a signature drift
  # in #delete_sender_identity would fail these tests.
  strategy_classes = {
    'ses'        => Onetime::Mail::SenderStrategies::SESSenderStrategy,
    'sendgrid'   => Onetime::Mail::SenderStrategies::SendGridSenderStrategy,
    'lettermint' => Onetime::Mail::SenderStrategies::LettermintSenderStrategy,
    'smtp2go'    => Onetime::Mail::SenderStrategies::Smtp2goSenderStrategy,
  }.freeze

  # MailerConfig stand-in. effective_provider is the single input the
  # operation dispatches on (already normalized by the real model).
  def mailer_config_for(provider)
    double(
      'MailerConfig',
      domain_id: 'cd:test123',
      effective_provider: provider,
      from_address: 'sender@example.com',
    )
  end

  # ==========================================================================
  # Result object
  # ==========================================================================

  describe 'Result' do
    it 'implements success? / failed?' do
      ok  = described_class::Result.new(success: true, message: 'done', error: nil, outcome: :deleted)
      bad = described_class::Result.new(success: false, message: nil, error: 'boom', outcome: :failed)

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

    strategy_classes.each do |provider, klass|
      it "dispatches deletion to the #{provider} strategy" do
        config   = mailer_config_for(provider)
        strategy = instance_double(klass)

        allow(Onetime::Mail::SenderStrategies).to receive(:for_provider)
          .with(provider).and_return(strategy)
        expect(strategy).to receive(:delete_sender_identity)
          .with(config, credentials: mock_credentials)
          .and_return({ outcome: :deleted, deleted: true, message: "#{provider} identity deleted", error: nil })

        result = described_class.new(mailer_config: config).call

        expect(result.success?).to be true
        expect(result.message).to eq("#{provider} identity deleted")
        expect(result.error).to be_nil
      end
    end

    it 'loads credentials for the resolved provider' do
      config   = mailer_config_for('ses')
      strategy = instance_double(
        Onetime::Mail::SenderStrategies::SESSenderStrategy,
        delete_sender_identity: { outcome: :deleted, deleted: true, message: 'ok', error: nil },
      )

      allow(Onetime::Mail::SenderStrategies).to receive(:for_provider)
        .with('ses').and_return(strategy)
      expect(Onetime::Mail::Mailer).to receive(:provider_credentials)
        .with('ses').and_return(mock_credentials)

      described_class.new(mailer_config: config).call
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

    it 'logs a no-op rather than a deletion (result[:deleted] is false)' do
      config        = mailer_config_for('smtp')
      smtp_strategy = Onetime::Mail::SenderStrategies::SMTPSenderStrategy.new

      logged = []
      log    = double('logger')
      allow(log).to receive(:info) { |*args, **_kw| logged << args.first }
      allow(log).to receive(:error)
      allow(Onetime).to receive(:get_logger).and_return(log)
      allow(Onetime::Mail::Mailer).to receive(:provider_credentials)
        .and_return({ 'host' => 'smtp.example.com' })
      allow(Onetime::Mail::SenderStrategies).to receive(:for_provider)
        .with('smtp').and_return(smtp_strategy)

      described_class.new(mailer_config: config).call

      expect(logged).to include('Sender domain deletion skipped (no-op)')
      expect(logged).not_to include('Sender domain deleted')
    end
  end

  # ==========================================================================
  # #call — skip paths (no dispatch, no error)
  # ==========================================================================

  describe '#call skip paths' do
    let(:log) { double('logger', info: nil, error: nil) }

    before do
      allow(Onetime).to receive(:get_logger).and_return(log)
    end

    after do
      expect(log).to have_received(:info).with(
        'Sender domain deletion skipped (no-op)', hash_including(outcome: :skipped, message: /skipped:/),
      )
      expect(log).not_to have_received(:error)
      expect(log).not_to have_received(:info).with('Sender domain deleted', anything)
    end

    it 'skips when mailer_config is nil' do
      result = described_class.new(mailer_config: nil).call

      expect(result.success?).to be true
      expect(result.outcome).to eq(:skipped)
      expect(result.message).to eq('skipped: no mailer config')
    end

    it 'skips when no provider resolves' do
      config = double('MailerConfig', domain_id: 'cd:x', effective_provider: '', from_address: 'a@b.com')
      expect(Onetime::Mail::SenderStrategies).not_to receive(:for_provider)

      result = described_class.new(mailer_config: config).call

      expect(result.success?).to be true
      expect(result.message).to eq('skipped: no effective provider')
    end

    it 'skips a provider that has no sender strategy (e.g. logger)' do
      config = double('MailerConfig', domain_id: 'cd:x', effective_provider: 'logger', from_address: 'a@b.com')
      expect(Onetime::Mail::SenderStrategies).not_to receive(:for_provider)
      expect(Onetime::Mail::Mailer).not_to receive(:provider_credentials)

      result = described_class.new(mailer_config: config).call

      expect(result.success?).to be true
      expect(result.message).to eq("skipped: unsupported provider 'logger'")
    end
  end

  # ==========================================================================
  # #call — error handling (never raises; wraps failures in Result)
  # ==========================================================================

  describe '#call result validation' do
    let(:config) { mailer_config_for('ses') }
    let(:strategy) { instance_double(Onetime::Mail::SenderStrategies::SESSenderStrategy) }
    let(:log) { double('logger', info: nil, error: nil) }
    let(:valid_result) { { outcome: :deleted, deleted: true, message: 'identity deleted', error: nil } }

    before do
      allow(Onetime).to receive(:get_logger).and_return(log)
      allow(Onetime::Mail::Mailer).to receive(:provider_credentials).and_return(mock_credentials)
      allow(Onetime::Mail::SenderStrategies).to receive(:for_provider).with('ses').and_return(strategy)
    end

    malformed_results = {
      'nil' => nil,
      'an empty hash' => {},
      'an array' => [],
      'a string' => 'deleted',
      'an unknown outcome' => { outcome: :unknown },
      'a string outcome' => { outcome: 'deleted' },
      'a nil outcome' => { outcome: nil },
      'a false deletion flag for deleted' => { deleted: false },
      'a nil deletion flag' => { deleted: nil },
      'a truthy deletion flag' => { deleted: 'true' },
      'a missing message' => { message: nil },
      'an empty message' => { message: '' },
      'a whitespace message' => { message: " \n\t" },
      'a non-string message' => { message: :done },
      'an error on a deletion' => { error: 'provider failed' },
      'a blank error on a deletion' => { error: '' },
      'a false error on a deletion' => { error: false },
    }
    malformed_results.each do |label, fields|
      it "fails closed for #{label}" do
        payload = fields.is_a?(Hash) && !fields.empty? ? valid_result.merge(fields) : fields
        allow(strategy).to receive(:delete_sender_identity).and_return(payload)

        result = described_class.new(mailer_config: config).call

        expect(result.failed?).to be true
        expect(result.outcome).to eq(:failed)
        expect(result.error).to include('Invalid sender deletion result')
        expect(log).to have_received(:error).with('Sender domain deletion failed', hash_including(error: result.error))
        expect(log).not_to have_received(:info)
      end
    end

    %i[outcome deleted message error].each do |key|
      it "fails closed when the #{key} key is absent" do
        allow(strategy).to receive(:delete_sender_identity).and_return(valid_result.reject { |k, _| k == key })

        result = described_class.new(mailer_config: config).call

        expect(result.failed?).to be true
        expect(result.error).to include('Invalid sender deletion result')
        expect(log).not_to have_received(:info)
      end
    end

    %i[absent skipped failed].each do |outcome|
      it "rejects deleted: true for #{outcome}" do
        error = outcome == :failed ? 'provider failed' : nil
        allow(strategy).to receive(:delete_sender_identity).and_return(valid_result.merge(outcome: outcome, error: error))

        expect(described_class.new(mailer_config: config).call.failed?).to be true
        expect(log).not_to have_received(:info)
      end
    end

    %i[absent skipped].each do |outcome|
      it "rejects an error for #{outcome}" do
        allow(strategy).to receive(:delete_sender_identity)
          .and_return(valid_result.merge(outcome: outcome, deleted: false, error: 'provider failed'))

        expect(described_class.new(mailer_config: config).call.failed?).to be true
        expect(log).not_to have_received(:info)
      end
    end

    [nil, '', " \n", false, :failure].each do |error|
      it "rejects a failed outcome with error #{error.inspect}" do
        allow(strategy).to receive(:delete_sender_identity)
          .and_return(valid_result.merge(outcome: :failed, deleted: false, error: error))

        expect(described_class.new(mailer_config: config).call.failed?).to be true
        expect(log).not_to have_received(:info)
      end
    end

    {
      deleted: 'Sender domain deleted',
      absent: 'Sender domain already absent',
      skipped: 'Sender domain deletion skipped (no-op)',
      failed: 'Sender domain deletion failed',
    }.each do |outcome, event|
      it "reports and logs a valid #{outcome} outcome" do
        error = outcome == :failed ? 'provider failed' : nil
        payload = { outcome: outcome, deleted: outcome == :deleted, message: 'provider result', error: error }
        allow(strategy).to receive(:delete_sender_identity).and_return(payload)

        result = described_class.new(mailer_config: config).call

        expect(result.success?).to eq(outcome != :failed)
        expect(result.outcome).to eq(outcome)
        expect(result.message).to eq(payload[:message])
        expect(result.error).to eq(error)
        level = outcome == :failed ? :error : :info
        expect(log).to have_received(level).with(event, hash_including(provider: 'ses', domain_id: 'cd:test123', outcome: outcome))
        expect(log).not_to have_received(outcome == :failed ? :info : :error)
      end
    end

    ['', " \n\t"].each do |message|
      it "uses a nonempty error for an exception with message #{message.inspect}" do
        allow(strategy).to receive(:delete_sender_identity).and_raise(StandardError, message)

        result = described_class.new(mailer_config: config).call

        expect(result.failed?).to be true
        expect(result.error).to eq('StandardError')
        expect(log).to have_received(:error).with('Sender domain deletion failed', hash_including(error: 'StandardError'))
        expect(log).not_to have_received(:info)
      end
    end
  end

  describe '#call error handling' do
    it 'reports a SendGrid lookup failure after a successful preflight as an error, not a no-op' do
      config      = mailer_config_for('sendgrid')
      strategy    = Onetime::Mail::SenderStrategies::SendGridSenderStrategy.new
      log         = double('logger', info: nil, error: nil)
      credentials = { 'api_key' => 'SG.test-key' }

      allow(Onetime).to receive(:get_logger).and_return(log)
      allow(Onetime::Mail::Mailer).to receive(:provider_credentials).and_return(credentials)
      allow(Onetime::Mail::SenderStrategies).to receive(:for_provider).with('sendgrid').and_return(strategy)
      stub_request(:get, 'https://api.sendgrid.com/v3/whitelabel/domains?limit=50&offset=0')
        .to_return(status: 200, body: [{ id: 123, domain: 'example.com' }].to_json)
        .then.to_return(status: 429, body: { errors: [{ message: 'Rate limited' }] }.to_json)
      # The preflight walk ends on an empty page after the short first page.
      stub_request(:get, 'https://api.sendgrid.com/v3/whitelabel/domains?limit=50&offset=1')
        .to_return(status: 200, body: '[]')

      expect(strategy.send(:domain_authentications, api_key: credentials['api_key']))
        .to eq([{ 'id' => 123, 'domain' => 'example.com' }])

      result = described_class.new(mailer_config: config).call

      expect(result.failed?).to be true
      expect(result.error).to include('Rate limited')
      expect(log).to have_received(:error).with('Sender domain deletion failed', hash_including(error: /Rate limited/))
      expect(log).not_to have_received(:info).with('Sender domain deletion skipped (no-op)', anything)
      expect(a_request(:delete, 'https://api.sendgrid.com/v3/whitelabel/domains/123')).not_to have_been_made
    end

    it 'keeps a confirmed missing SendGrid identity as a no-op' do
      config   = mailer_config_for('sendgrid')
      strategy = Onetime::Mail::SenderStrategies::SendGridSenderStrategy.new
      log      = double('logger', info: nil, error: nil)

      allow(Onetime).to receive(:get_logger).and_return(log)
      allow(Onetime::Mail::Mailer).to receive(:provider_credentials).and_return({ 'api_key' => 'SG.test-key' })
      allow(Onetime::Mail::SenderStrategies).to receive(:for_provider).with('sendgrid').and_return(strategy)
      stub_request(:get, 'https://api.sendgrid.com/v3/whitelabel/domains?limit=50&offset=0')
        .to_return(status: 200, body: '[]')

      result = described_class.new(mailer_config: config).call

      expect(result.success?).to be true
      expect(result.outcome).to eq(:absent)
      expect(result.error).to be_nil
      expect(result.message).to include('not found')
      expect(log).to have_received(:info).with('Sender domain already absent', anything)
      expect(log).not_to have_received(:error)
    end

    it 'swallows strategy errors into a failure Result' do
      config   = mailer_config_for('lettermint')
      strategy = instance_double(Onetime::Mail::SenderStrategies::LettermintSenderStrategy)

      allow(Onetime::Mail::Mailer).to receive(:provider_credentials).and_return(mock_credentials)
      allow(Onetime::Mail::SenderStrategies).to receive(:for_provider).and_return(strategy)
      allow(strategy).to receive(:delete_sender_identity).and_raise(StandardError, 'provider API timeout')

      result = described_class.new(mailer_config: config).call

      expect(result.success?).to be false
      expect(result.failed?).to be true
      expect(result.outcome).to eq(:failed)
      expect(result.error).to eq('provider API timeout')
    end
  end
end
