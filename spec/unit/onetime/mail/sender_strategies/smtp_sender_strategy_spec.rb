# spec/unit/onetime/mail/sender_strategies/smtp_sender_strategy_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/mail/sender_strategies/smtp_sender_strategy'

RSpec.describe Onetime::Mail::SenderStrategies::SMTPSenderStrategy do
  let(:strategy) { described_class.new }
  let(:mailer_config) do
    double('MailerConfig', from_address: 'sender@example.com')
  end

  before do
    allow(strategy).to receive(:log_info)
    allow(strategy).to receive(:log_error)
  end

  describe '#supports_provisioning?' do
    it 'returns false' do
      expect(strategy.supports_provisioning?).to be false
    end
  end

  describe '#provision_dns_records' do
    it 'returns error indicating provisioning not supported' do
      result = strategy.provision_dns_records(mailer_config)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('provisioning_not_supported')
      expect(result[:dns_records]).to eq([])
      expect(result[:message]).to include('manual')
    end

    it 'works with nil credentials' do
      result = strategy.provision_dns_records(mailer_config, credentials: nil)

      expect(result[:success]).to be false
      expect(result[:dns_records]).to eq([])
    end
  end

  describe '#check_verification_status' do
    it 'returns not_supported status' do
      result = strategy.check_verification_status(mailer_config)

      expect(result[:verified]).to be false
      expect(result[:status]).to eq('not_supported')
      expect(result[:message]).to include('manual')
    end
  end

  describe '#delete_sender_identity' do
    it 'returns not applicable' do
      result = strategy.delete_sender_identity(mailer_config)

      expect(result[:deleted]).to be false
      expect(result[:message]).to include('do not have sender identities')
    end
  end

  describe '#strategy_name' do
    it 'returns smtp' do
      expect(strategy.strategy_name).to eq('smtp')
    end
  end
end
