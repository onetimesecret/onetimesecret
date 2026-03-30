# spec/unit/onetime/mail/sender_strategies/lettermint_sender_strategy_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'lettermint'
require 'onetime/mail/sender_strategies/lettermint_sender_strategy'

RSpec.describe Onetime::Mail::SenderStrategies::LettermintSenderStrategy do
  let(:strategy) { described_class.new }
  let(:credentials) { { api_token: 'lm-test-token-example', base_url: 'https://api.lettermint.com' } }
  let(:mailer_config) do
    double('MailerConfig', from_address: 'sender@example.com')
  end
  let(:mock_client) { instance_double('Lettermint::HttpClient') }

  before do
    allow(strategy).to receive(:build_client).and_return(mock_client)
    allow(strategy).to receive(:log_info)
    allow(strategy).to receive(:log_error)
  end

  describe '#provision_dns_records' do
    context 'with valid from_address' do
      let(:api_response) do
        {
          'domain' => 'example.com',
          'status' => 'pending',
          'created_at' => '2026-03-30T00:00:00Z',
          'dns_records' => [
            { 'type' => 'CNAME', 'name' => 'lm1._domainkey.example.com', 'value' => 'lm1.dkim.lettermint.com' },
            { 'type' => 'CNAME', 'name' => 'lm2._domainkey.example.com', 'value' => 'lm2.dkim.lettermint.com' },
            { 'type' => 'TXT', 'name' => 'example.com', 'value' => 'v=spf1 include:lettermint.com ~all' },
          ],
        }
      end

      before do
        allow(mock_client).to receive(:post)
          .with(path: '/api/v1/domains', data: { domain: 'example.com' })
          .and_return(api_response)
      end

      it 'returns success with DNS records' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be true
        expect(result[:dns_records]).to eq([
          { type: 'CNAME', name: 'lm1._domainkey.example.com', value: 'lm1.dkim.lettermint.com' },
          { type: 'CNAME', name: 'lm2._domainkey.example.com', value: 'lm2.dkim.lettermint.com' },
          { type: 'TXT', name: 'example.com', value: 'v=spf1 include:lettermint.com ~all' },
        ])
      end

      it 'includes provider_data with domain info' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:provider_data][:domain]).to eq('example.com')
        expect(result[:provider_data][:status]).to eq('pending')
        expect(result[:provider_data][:created_at]).to eq('2026-03-30T00:00:00Z')
      end

      it 'includes identity_id from response domain' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:identity_id]).to eq('example.com')
      end
    end

    context 'when domain already exists (409 conflict)' do
      let(:get_response) do
        {
          'domain' => 'example.com',
          'status' => 'verified',
          'created_at' => '2026-03-01T00:00:00Z',
          'dns_records' => [
            { 'type' => 'CNAME', 'name' => 'lm1._domainkey.example.com', 'value' => 'lm1.dkim.lettermint.com' },
          ],
        }
      end

      before do
        allow(mock_client).to receive(:post)
          .and_raise(Lettermint::HttpRequestError.new(message: 'Conflict', status_code: 409))
        allow(mock_client).to receive(:get)
          .with(path: '/api/v1/domains/example.com')
          .and_return(get_response)
      end

      it 'falls back to GET and returns existing domain data' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be true
        expect(result[:dns_records].size).to eq(1)
        expect(result[:provider_data][:status]).to eq('verified')
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

    context 'with missing api_token' do
      let(:credentials) { { api_token: nil } }

      it 'returns error for missing token' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('missing_api_token')
      end
    end

    context 'with empty api_token' do
      let(:credentials) { { api_token: '' } }

      it 'returns error for empty token' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('missing_api_token')
      end
    end

    context 'when Lettermint API fails (HttpRequestError)' do
      before do
        allow(mock_client).to receive(:post)
          .and_raise(Lettermint::HttpRequestError.new(message: 'Internal Server Error', status_code: 500))
      end

      it 'returns error with status code' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('http_500')
        expect(result[:message]).to include('Lettermint API error')
        expect(result[:dns_records]).to eq([])
      end
    end

    context 'when ValidationError is raised' do
      before do
        allow(mock_client).to receive(:post)
          .and_raise(Lettermint::ValidationError.new(message: 'Invalid domain format', error_type: 'validation'))
      end

      it 'returns validation error' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('validation_error')
        expect(result[:message]).to include('Validation error')
        expect(result[:dns_records]).to eq([])
      end
    end

    context 'when AuthenticationError is raised' do
      before do
        allow(mock_client).to receive(:post)
          .and_raise(Lettermint::AuthenticationError.new(message: 'Invalid token', status_code: 401))
      end

      it 'returns authentication error' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('authentication_error')
        expect(result[:message]).to include('Authentication failed')
        expect(result[:dns_records]).to eq([])
      end
    end

    context 'when RateLimitError is raised' do
      before do
        allow(mock_client).to receive(:post)
          .and_raise(Lettermint::RateLimitError.new(message: 'Too many requests'))
      end

      it 'returns rate limit error' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('rate_limited')
        expect(result[:message]).to include('Rate limited')
        expect(result[:dns_records]).to eq([])
      end
    end

    context 'when TimeoutError is raised' do
      before do
        allow(mock_client).to receive(:post)
          .and_raise(Lettermint::TimeoutError, 'Connection timed out')
      end

      it 'returns timeout error' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('timeout')
        expect(result[:message]).to include('timed out')
        expect(result[:dns_records]).to eq([])
      end
    end

    context 'when unexpected error occurs' do
      before do
        allow(mock_client).to receive(:post)
          .and_raise(StandardError, 'Network failure')
      end

      it 'returns error with exception message' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:message]).to include('Network failure')
        expect(result[:dns_records]).to eq([])
      end
    end
  end

  describe '#check_verification_status' do
    context 'when domain is verified' do
      let(:api_response) do
        {
          'domain' => 'example.com',
          'status' => 'verified',
          'verified' => true,
          'dns_records' => [
            { 'type' => 'CNAME', 'name' => 'lm1._domainkey.example.com', 'value' => 'lm1.dkim.lettermint.com' },
          ],
        }
      end

      before do
        allow(mock_client).to receive(:get)
          .with(path: '/api/v1/domains/example.com')
          .and_return(api_response)
      end

      it 'returns verified status' do
        result = strategy.check_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be true
        expect(result[:status]).to eq('verified')
        expect(result[:message]).to include('ready for sending')
      end
    end

    context 'when domain is pending' do
      let(:api_response) do
        {
          'domain' => 'example.com',
          'status' => 'pending',
          'verified' => false,
          'dns_records' => [],
        }
      end

      before do
        allow(mock_client).to receive(:get)
          .with(path: '/api/v1/domains/example.com')
          .and_return(api_response)
      end

      it 'returns pending status' do
        result = strategy.check_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be false
        expect(result[:status]).to eq('pending')
        expect(result[:message]).to include('awaiting propagation')
      end
    end

    context 'when domain is not found (404)' do
      before do
        allow(mock_client).to receive(:get)
          .and_raise(Lettermint::HttpRequestError.new(message: 'Not Found', status_code: 404))
      end

      it 'returns not_found status' do
        result = strategy.check_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be false
        expect(result[:status]).to eq('not_found')
        expect(result[:message]).to include('not found')
      end
    end

    context 'when API returns error' do
      before do
        allow(mock_client).to receive(:get)
          .and_raise(Lettermint::HttpRequestError.new(message: 'Server Error', status_code: 500))
      end

      it 'returns error status' do
        result = strategy.check_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be false
        expect(result[:status]).to eq('error')
        expect(result[:message]).to include('Verification check failed')
      end
    end

    context 'with invalid from_address' do
      let(:mailer_config) { double('MailerConfig', from_address: 'invalid') }

      it 'returns invalid status' do
        result = strategy.check_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be false
        expect(result[:status]).to eq('invalid')
      end
    end

    context 'with missing api_token' do
      let(:credentials) { { api_token: nil } }

      it 'returns error status' do
        result = strategy.check_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be false
        expect(result[:status]).to eq('error')
        expect(result[:message]).to include('API token is required')
      end
    end
  end

  describe '#delete_sender_identity' do
    context 'when deletion succeeds' do
      before do
        allow(mock_client).to receive(:delete)
          .with(path: '/api/v1/domains/example.com')
          .and_return({})
      end

      it 'returns deleted true' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be true
        expect(result[:message]).to include('removed')
      end
    end

    context 'when domain not found (404, idempotent)' do
      before do
        allow(mock_client).to receive(:delete)
          .and_raise(Lettermint::HttpRequestError.new(message: 'Not Found', status_code: 404))
      end

      it 'returns deleted true' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be true
        expect(result[:message]).to include('already deleted')
      end
    end

    context 'when API returns error' do
      before do
        allow(mock_client).to receive(:delete)
          .and_raise(Lettermint::HttpRequestError.new(message: 'Forbidden', status_code: 403))
      end

      it 'returns deleted false with error' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be false
        expect(result[:message]).to include('Deletion failed')
      end
    end

    context 'when unexpected error occurs' do
      before do
        allow(mock_client).to receive(:delete)
          .and_raise(StandardError, 'Connection reset')
      end

      it 'returns deleted false' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be false
        expect(result[:message]).to include('Deletion failed')
      end
    end

    context 'with invalid from_address' do
      let(:mailer_config) { double('MailerConfig', from_address: '') }

      it 'returns deleted false' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be false
      end
    end

    context 'with missing api_token' do
      let(:credentials) { { api_token: nil } }

      it 'returns deleted false' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be false
        expect(result[:message]).to include('required')
      end
    end
  end

  describe '#strategy_name' do
    it 'returns lettermint' do
      expect(strategy.strategy_name).to eq('lettermint')
    end
  end

  describe '#supports_provisioning?' do
    it 'returns true' do
      expect(strategy.supports_provisioning?).to be true
    end
  end

  describe 'normalize_dns_records (private)' do
    it 'normalizes string-keyed records to symbol keys' do
      records = [
        { 'type' => 'cname', 'name' => 'lm1._domainkey.example.com', 'value' => 'lm1.dkim.lettermint.com' },
      ]

      normalized = strategy.send(:normalize_dns_records, records)

      expect(normalized).to eq([
        { type: 'CNAME', name: 'lm1._domainkey.example.com', value: 'lm1.dkim.lettermint.com' },
      ])
    end

    it 'handles empty array' do
      expect(strategy.send(:normalize_dns_records, [])).to eq([])
    end

    it 'handles nil input' do
      expect(strategy.send(:normalize_dns_records, nil)).to eq([])
    end

    it 'skips records missing required fields' do
      records = [
        { 'type' => 'CNAME', 'name' => 'valid.example.com', 'value' => 'target.example.com' },
        { 'type' => 'CNAME', 'name' => 'missing-value.example.com' },
        { 'not_a_record' => true },
      ]

      normalized = strategy.send(:normalize_dns_records, records)

      expect(normalized.size).to eq(1)
      expect(normalized.first[:name]).to eq('valid.example.com')
    end

    it 'skips non-Hash entries' do
      records = [
        { 'type' => 'CNAME', 'name' => 'valid.example.com', 'value' => 'target.example.com' },
        'not a hash',
        42,
      ]

      normalized = strategy.send(:normalize_dns_records, records)

      expect(normalized.size).to eq(1)
    end
  end
end
