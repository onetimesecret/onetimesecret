# spec/unit/onetime/mail/sender_strategies/ses_sender_strategy_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/mail/sender_strategies/ses_sender_strategy'
require 'aws-sdk-sesv2'

RSpec.describe Onetime::Mail::SenderStrategies::SESSenderStrategy do
  let(:strategy) { described_class.new }
  let(:credentials) do
    {
      access_key_id: 'AKIAIOSFODNN7EXAMPLE',
      secret_access_key: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
      region: 'us-east-1',
    }
  end
  let(:mailer_config) do
    double('MailerConfig', from_address: 'sender@example.com')
  end
  let(:mock_client) { instance_double('Aws::SESV2::Client') }

  before do
    allow(strategy).to receive(:build_ses_client).and_return(mock_client)
    allow(strategy).to receive(:log_info)
    allow(strategy).to receive(:log_error)
  end

  describe '#provision_dns_records' do
    context 'with valid from_address' do
      let(:dkim_attrs) do
        double('DkimAttributes',
          tokens: %w[abc123 def456 ghi789],
          status: 'PENDING')
      end
      let(:create_response) do
        double('CreateEmailIdentityResponse', dkim_attributes: dkim_attrs)
      end

      before do
        allow(mock_client).to receive(:create_email_identity)
          .with(email_identity: 'example.com')
          .and_return(create_response)
      end

      it 'returns success with DNS records' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be true
        expect(result[:dns_records]).to eq([
          { type: 'CNAME', name: 'abc123._domainkey', value: 'abc123.dkim.amazonses.com' },
          { type: 'CNAME', name: 'def456._domainkey', value: 'def456.dkim.amazonses.com' },
          { type: 'CNAME', name: 'ghi789._domainkey', value: 'ghi789.dkim.amazonses.com' },
        ])
        expect(result[:provider_data][:dkim_tokens]).to eq(%w[abc123 def456 ghi789])
        expect(result[:provider_data][:region]).to eq('us-east-1')
        expect(result[:provider_data][:identity]).to eq('example.com')
      end
    end

    context 'when identity already exists' do
      let(:dkim_attrs) do
        double('DkimAttributes',
          tokens: %w[existing1 existing2 existing3],
          status: 'SUCCESS')
      end
      let(:get_response) do
        double('GetEmailIdentityResponse', dkim_attributes: dkim_attrs)
      end

      before do
        allow(mock_client).to receive(:create_email_identity)
          .and_raise(Aws::SESV2::Errors::AlreadyExistsException.new(nil, 'already exists'))
        allow(mock_client).to receive(:get_email_identity)
          .with(email_identity: 'example.com')
          .and_return(get_response)
      end

      it 'retrieves existing identity' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be true
        expect(result[:provider_data][:dkim_tokens]).to eq(%w[existing1 existing2 existing3])
      end
    end

    context 'with invalid from_address' do
      let(:mailer_config) { double('MailerConfig', from_address: 'invalid-email') }

      it 'returns error for missing domain' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('invalid_from_address')
        expect(result[:dns_records]).to eq([])
      end
    end

    context 'with empty from_address' do
      let(:mailer_config) { double('MailerConfig', from_address: '') }

      it 'returns error for empty address' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('invalid_from_address')
      end
    end

    context 'when SES API fails' do
      before do
        allow(mock_client).to receive(:create_email_identity)
          .and_raise(Aws::SESV2::Errors::ServiceError.new(nil, 'API error'))
      end

      it 'returns error with message' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:message]).to include('SES provisioning failed')
        expect(result[:dns_records]).to eq([])
      end
    end
  end

  describe '#check_provider_verification_status' do
    context 'when DKIM is verified' do
      let(:dkim_attrs) do
        double('DkimAttributes',
          tokens: %w[abc123 def456 ghi789],
          status: 'SUCCESS',
          signing_enabled: true)
      end
      let(:get_response) do
        double('GetEmailIdentityResponse',
          dkim_attributes: dkim_attrs,
          identity_type: 'DOMAIN')
      end

      before do
        allow(mock_client).to receive(:get_email_identity)
          .with(email_identity: 'example.com')
          .and_return(get_response)
      end

      it 'returns verified status' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be true
        expect(result[:status]).to eq('success')
        expect(result[:message]).to include('ready for sending')
      end
    end

    context 'when DKIM is pending' do
      let(:dkim_attrs) do
        double('DkimAttributes',
          tokens: %w[abc123 def456 ghi789],
          status: 'PENDING',
          signing_enabled: false)
      end
      let(:get_response) do
        double('GetEmailIdentityResponse',
          dkim_attributes: dkim_attrs,
          identity_type: 'DOMAIN')
      end

      before do
        allow(mock_client).to receive(:get_email_identity)
          .with(email_identity: 'example.com')
          .and_return(get_response)
      end

      it 'returns pending status' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be false
        expect(result[:status]).to eq('pending')
        expect(result[:message]).to include('awaiting propagation')
      end
    end

    context 'when identity not found' do
      before do
        allow(mock_client).to receive(:get_email_identity)
          .and_raise(Aws::SESV2::Errors::NotFoundException.new(nil, 'not found'))
      end

      it 'returns not_found status' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be false
        expect(result[:status]).to eq('not_found')
      end
    end

    context 'with invalid from_address' do
      let(:mailer_config) { double('MailerConfig', from_address: 'invalid') }

      it 'returns invalid status' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be false
        expect(result[:status]).to eq('invalid')
      end
    end
  end

  describe '#delete_sender_identity' do
    context 'when deletion succeeds' do
      before do
        allow(mock_client).to receive(:delete_email_identity)
          .with(email_identity: 'example.com')
          .and_return(double('DeleteResponse'))
      end

      it 'returns deleted true' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be true
        expect(result[:message]).to include('Deleted sender identity')
      end
    end

    context 'when identity not found' do
      before do
        allow(mock_client).to receive(:delete_email_identity)
          .and_raise(Aws::SESV2::Errors::NotFoundException.new(nil, 'not found'))
      end

      it 'returns deleted true (idempotent)' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be true
        expect(result[:message]).to include('already deleted')
      end
    end

    context 'when SES API fails' do
      before do
        allow(mock_client).to receive(:delete_email_identity)
          .and_raise(Aws::SESV2::Errors::ServiceError.new(nil, 'API error'))
      end

      it 'returns deleted false with error' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be false
        expect(result[:message]).to include('deletion failed')
      end
    end

    context 'with invalid from_address' do
      let(:mailer_config) { double('MailerConfig', from_address: '') }

      it 'returns deleted false' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be false
      end
    end
  end

  describe '#strategy_name' do
    it 'returns ses' do
      expect(strategy.strategy_name).to eq('ses')
    end
  end

  describe '#supports_provisioning?' do
    it 'returns true' do
      expect(strategy.supports_provisioning?).to be true
    end
  end

  describe 'default region' do
    let(:credentials_no_region) do
      {
        access_key_id: 'AKIAIOSFODNN7EXAMPLE',
        secret_access_key: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
      }
    end

    it 'uses us-east-1 as default region in provider_data' do
      dkim_attrs = double('DkimAttributes', tokens: ['token1'], status: 'PENDING')
      response = double('Response', dkim_attributes: dkim_attrs)
      allow(mock_client).to receive(:create_email_identity).and_return(response)

      result = strategy.provision_dns_records(mailer_config, credentials: credentials_no_region)

      expect(result[:provider_data][:region]).to eq('us-east-1')
    end
  end
end
