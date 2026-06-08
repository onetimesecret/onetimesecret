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
      'access_key_id' => 'AKIAIOSFODNN7EXAMPLE',
      'secret_access_key' => 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
      'region' => 'us-east-1',
    }
  end
  let(:mailer_config) do
    double('MailerConfig', from_address: 'sender@example.com')
  end
  let(:mock_client) { instance_double('Aws::SESV2::Client') }

  before do
    allow(strategy).to receive(:build_ses_client).and_return(mock_client)
    allow(strategy).to receive(:log_info)
    allow(strategy).to receive(:log_warn)
    allow(strategy).to receive(:log_error)
    # MAIL FROM configuration succeeds by default; individual contexts override.
    allow(mock_client).to receive(:put_email_identity_mail_from_attributes)
      .and_return(double('MailFromResponse'))
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

      it 'returns success with fully-qualified DKIM and MAIL FROM records' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be true
        expect(result[:dns_records]).to eq([
          { type: 'CNAME', name: 'abc123._domainkey.example.com', value: 'abc123.dkim.amazonses.com' },
          { type: 'CNAME', name: 'def456._domainkey.example.com', value: 'def456.dkim.amazonses.com' },
          { type: 'CNAME', name: 'ghi789._domainkey.example.com', value: 'ghi789.dkim.amazonses.com' },
          { type: 'MX', name: 'mail.example.com', value: 'feedback-smtp.us-east-1.amazonses.com' },
          { type: 'TXT', name: 'mail.example.com', value: 'v=spf1 include:amazonses.com ~all' },
        ])
        expect(result[:provider_data][:dkim_tokens]).to eq(%w[abc123 def456 ghi789])
        expect(result[:provider_data][:region]).to eq('us-east-1')
        expect(result[:provider_data][:identity]).to eq('example.com')
        expect(result[:provider_data][:mail_from_domain]).to eq('mail.example.com')
      end

      it 'configures a custom MAIL FROM domain on the identity' do
        strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(mock_client).to have_received(:put_email_identity_mail_from_attributes)
          .with(
            email_identity: 'example.com',
            mail_from_domain: 'mail.example.com',
            behavior_on_mx_failure: 'USE_DEFAULT_VALUE',
          )
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

    context 'with a non-default region' do
      let(:credentials) do
        { 'access_key_id' => 'AKIA', 'secret_access_key' => 'secret', 'region' => 'eu-west-1' }
      end
      let(:dkim_attrs) { double('DkimAttributes', tokens: ['t1'], status: 'PENDING') }

      before do
        allow(mock_client).to receive(:create_email_identity)
          .and_return(double('Resp', dkim_attributes: dkim_attrs))
      end

      it 'emits the MAIL FROM MX for that region' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        mx = result[:dns_records].find { |r| r[:type] == 'MX' }
        expect(mx[:value]).to eq('feedback-smtp.eu-west-1.amazonses.com')
        expect(result[:provider_data][:region]).to eq('eu-west-1')
      end
    end

    context 'when MAIL FROM configuration is rejected' do
      let(:dkim_attrs) { double('DkimAttributes', tokens: %w[abc def], status: 'PENDING') }

      before do
        allow(mock_client).to receive(:create_email_identity)
          .and_return(double('Resp', dkim_attributes: dkim_attrs))
        allow(mock_client).to receive(:put_email_identity_mail_from_attributes)
          .and_raise(Aws::SESV2::Errors::ServiceError.new(nil, 'mail from rejected'))
      end

      it 'still succeeds with DKIM records but omits MAIL FROM records' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be true
        expect(result[:dns_records].map { |r| r[:type] }).to eq(%w[CNAME CNAME])
        expect(result[:dns_records].any? { |r| r[:type] == 'MX' }).to be false
        expect(result[:provider_data][:mail_from_domain]).to be_nil
      end
    end

    context 'with missing AWS credentials' do
      let(:credentials) { { 'region' => 'us-east-1' } }

      it 'returns a missing_credentials error without calling SES' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('missing_credentials')
        expect(result[:dns_records]).to eq([])
        expect(mock_client).not_to have_received(:put_email_identity_mail_from_attributes)
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

    context 'when a non-SES error occurs' do
      before do
        allow(mock_client).to receive(:create_email_identity)
          .and_raise(StandardError.new('network down'))
      end

      it 'wraps the error in a failure result' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:message]).to include('Provisioning failed')
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
      let(:mail_from_attrs) do
        double('MailFromAttributes',
          mail_from_domain: 'mail.example.com',
          mail_from_domain_status: 'SUCCESS')
      end
      let(:get_response) do
        double('GetEmailIdentityResponse',
          dkim_attributes: dkim_attrs,
          mail_from_attributes: mail_from_attrs,
          identity_type: 'DOMAIN')
      end

      before do
        allow(mock_client).to receive(:get_email_identity)
          .with(email_identity: 'example.com')
          .and_return(get_response)
      end

      it 'returns verified status with MAIL FROM details' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be true
        expect(result[:status]).to eq('success')
        expect(result[:message]).to include('ready for sending')
        expect(result[:details][:mail_from_domain]).to eq('mail.example.com')
        expect(result[:details][:mail_from_status]).to eq('SUCCESS')
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
          mail_from_attributes: nil,
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

    context 'when an unexpected error occurs' do
      before do
        allow(mock_client).to receive(:get_email_identity)
          .and_raise(StandardError.new('boom'))
      end

      it 'returns error status' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be false
        expect(result[:status]).to eq('error')
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

    context 'when an unexpected error occurs' do
      before do
        allow(mock_client).to receive(:delete_email_identity)
          .and_raise(StandardError.new('boom'))
      end

      it 'returns deleted false' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be false
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
        'access_key_id' => 'AKIAIOSFODNN7EXAMPLE',
        'secret_access_key' => 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
      }
    end

    it 'uses us-east-1 as default region in provider_data' do
      dkim_attrs = double('DkimAttributes', tokens: ['token1'], status: 'PENDING')
      response = double('Response', dkim_attributes: dkim_attrs)
      allow(mock_client).to receive(:create_email_identity).and_return(response)

      result = strategy.provision_dns_records(mailer_config, credentials: credentials_no_region)

      expect(result[:provider_data][:region]).to eq('us-east-1')
    end

    it 'uses us-east-1 in the MAIL FROM MX endpoint' do
      dkim_attrs = double('DkimAttributes', tokens: ['token1'], status: 'PENDING')
      response = double('Response', dkim_attributes: dkim_attrs)
      allow(mock_client).to receive(:create_email_identity).and_return(response)

      result = strategy.provision_dns_records(mailer_config, credentials: credentials_no_region)

      mx = result[:dns_records].find { |r| r[:type] == 'MX' }
      expect(mx[:value]).to eq('feedback-smtp.us-east-1.amazonses.com')
    end
  end
end
