# spec/unit/onetime/mail/delivery/smtp2go_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/mail'
require 'onetime/mail/delivery/smtp2go'

RSpec.describe Onetime::Mail::Delivery::Smtp2go do
  let(:config) { { 'api_key' => 'api-0123456789abcdef0123456789abcdef' } }
  let(:backend) { described_class.new(config) }
  let(:email) do
    {
      to: 'recipient@example.com',
      from: 'sender@example.com',
      subject: 'Test email',
      text_body: 'Hello',
    }
  end

  # Realistic /email/send success data (per-recipient accounting)
  let(:success_data) { { 'succeeded' => 1, 'failed' => 0, 'failures' => [], 'email_id' => '1er8bV-6Sw0i9-6ci1pC' } }
  let(:mock_client) { instance_double(Onetime::Mail::Smtp2goClient) }

  def api_error(message, status_code:, error_code: nil)
    Onetime::Mail::Smtp2goClient::APIError.new(message, status_code: status_code, error_code: error_code)
  end

  before do
    allow(mock_client).to receive(:post).and_return(success_data)
    allow(backend).to receive(:client).and_return(mock_client)
    allow(backend).to receive(:log_delivery)
    allow(backend).to receive(:log_error)
  end

  describe '#deliver success' do
    it 'delivers and logs on success' do
      result = backend.deliver(email)
      expect(result).to eq(success_data)
      expect(backend).to have_received(:log_delivery)
    end

    it 'defaults fastaccept to false when not specified in config' do
      backend.deliver(email)

      expect(mock_client).to have_received(:post).with(
        '/email/send',
        hash_including(
          'sender' => 'sender@example.com',
          'to' => ['recipient@example.com'],
          'subject' => 'Test email',
          'text_body' => 'Hello',
          'fastaccept' => false,
        ),
      )
    end

    context 'with fastaccept: false configured' do
      let(:backend) { described_class.new(config.merge('fastaccept' => false)) }

      before do
        allow(backend).to receive(:client).and_return(mock_client)
        allow(backend).to receive(:log_delivery)
        allow(backend).to receive(:log_error)
      end

      it 'posts fastaccept: false in payload' do
        backend.deliver(email)

        expect(mock_client).to have_received(:post).with(
          '/email/send',
          hash_including('fastaccept' => false),
        )
      end
    end

    it 'sets Reply-To via custom_headers when present' do
      backend.deliver(email.merge(reply_to: 'reply@example.com'))

      expect(mock_client).to have_received(:post).with(
        '/email/send',
        hash_including(
          'custom_headers' => [{ 'header' => 'Reply-To', 'value' => 'reply@example.com' }],
        ),
      )
    end

    it 'omits custom_headers when reply_to is absent' do
      payload = nil
      allow(mock_client).to receive(:post) { |_path, body| payload = body; success_data }

      backend.deliver(email)

      expect(payload).not_to have_key('custom_headers')
    end

    it 'includes html_body when present' do
      backend.deliver(email.merge(html_body: '<p>Hello</p>'))

      expect(mock_client).to have_received(:post).with(
        '/email/send',
        hash_including('html_body' => '<p>Hello</p>'),
      )
    end

    it 'omits html_body when absent' do
      payload = nil
      allow(mock_client).to receive(:post) { |_path, body| payload = body; success_data }

      backend.deliver(email)

      expect(payload).not_to have_key('html_body')
      expect(payload['text_body']).to eq('Hello')
    end

    it 'accepts fastaccept response with email_id only (no succeeded key)' do
      # When fastaccept: true, SMTP2GO may omit succeeded/failed keys
      fastaccept_data = { 'email_id' => '1er8bV-6Sw0i9-6ci1pC' }
      allow(mock_client).to receive(:post).and_return(fastaccept_data)

      result = backend.deliver(email)
      expect(result).to eq(fastaccept_data)
      expect(backend).to have_received(:log_delivery)
    end
  end

  describe '#deliver with missing accounting (fail-closed)' do
    it 'raises E_MissingAccounting when response lacks both succeeded and email_id' do
      # Empty response or malformed data without accounting keys
      allow(mock_client).to receive(:post).and_return({})

      expect { backend.deliver(email) }
        .to raise_error(Onetime::Mail::DeliveryError) do |err|
          expect(err.transient?).to be false
          expect(err.original_error).to be_a(Onetime::Mail::Smtp2goClient::APIError)
          expect(err.original_error.status_code).to eq(200)
          expect(err.original_error.error_code).to eq('E_MissingAccounting')
          expect(err.message).to include('missing delivery accounting')
        end
    end

    it 'raises E_MissingAccounting when email_id is nil and succeeded is absent' do
      allow(mock_client).to receive(:post).and_return({ 'email_id' => nil })

      expect { backend.deliver(email) }
        .to raise_error(Onetime::Mail::DeliveryError) do |err|
          expect(err.original_error.error_code).to eq('E_MissingAccounting')
        end
    end

    it 'raises E_MissingAccounting when email_id is empty string and succeeded is absent' do
      allow(mock_client).to receive(:post).and_return({ 'email_id' => '' })

      expect { backend.deliver(email) }
        .to raise_error(Onetime::Mail::DeliveryError) do |err|
          expect(err.original_error.error_code).to eq('E_MissingAccounting')
        end
    end

    it 'does NOT raise when succeeded key is present (even if zero)' do
      # succeeded: 0, failed: 0 is valid (empty batch, edge case)
      data = { 'succeeded' => 0, 'failed' => 0, 'failures' => [] }
      allow(mock_client).to receive(:post).and_return(data)

      result = backend.deliver(email)
      expect(result).to eq(data)
    end
  end

  describe '#deliver with per-recipient failures in a 200 response' do
    it 'raises fatal DeliveryError when failed > 0' do
      allow(mock_client).to receive(:post).and_return(
        { 'succeeded' => 0, 'failed' => 1, 'failures' => ['unable to verify sender'], 'email_id' => nil },
      )

      expect { backend.deliver(email) }
        .to raise_error(Onetime::Mail::DeliveryError) do |err|
          expect(err.transient?).to be false
          expect(err.original_error).to be_a(Onetime::Mail::Smtp2goClient::APIError)
          expect(err.original_error.status_code).to eq(200)
          expect(err.original_error.error_code).to eq('E_DeliveryFailures')
          expect(err.message).to include('1 failed recipient')
          expect(err.message).to include('unable to verify sender')
        end
    end

    it 'redacts recipient addresses in the error message and response_body' do
      allow(mock_client).to receive(:post).and_return(
        { 'succeeded' => 0, 'failed' => 1, 'failures' => ['recipient@example.com: unable to verify sender'], 'email_id' => nil },
      )

      expect { backend.deliver(email) }
        .to raise_error(Onetime::Mail::DeliveryError) do |err|
          original = err.original_error
          # The raw address never reaches the wrapped message, the APIError
          # message, or its response_body — but the obscured form and the
          # failure reason text survive for diagnostics.
          expect(err.message).not_to include('recipient@example.com')
          expect(err.message).to include('re***@')
          expect(err.message).to include('unable to verify sender')
          expect(original.message).not_to include('recipient@example.com')
          expect(original.response_body).not_to include('recipient@example.com')
          expect(original.response_body).to include('unable to verify sender')
        end
    end
  end

  describe '#deliver error classification' do
    context 'when API returns 429 (rate limit)' do
      it 'raises transient DeliveryError' do
        allow(mock_client).to receive(:post)
          .and_raise(api_error('too many requests', status_code: 429))

        expect { backend.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be true
            expect(err.original_error).to be_a(Onetime::Mail::Smtp2goClient::APIError)
          end
      end
    end

    context 'when API returns 5xx' do
      [500, 502, 503].each do |code|
        it "raises transient DeliveryError for #{code}" do
          allow(mock_client).to receive(:post)
            .and_raise(api_error('server error', status_code: code))

          expect { backend.deliver(email) }
            .to raise_error(Onetime::Mail::DeliveryError) do |err|
              expect(err.transient?).to be true
            end
        end
      end
    end

    context 'when API returns 4xx (generic)' do
      [400, 401, 404].each do |code|
        it "raises fatal DeliveryError for #{code}" do
          allow(mock_client).to receive(:post)
            .and_raise(api_error('client error', status_code: code))

          expect { backend.deliver(email) }
            .to raise_error(Onetime::Mail::DeliveryError) do |err|
              expect(err.transient?).to be false
              expect(err.original_error).to be_a(Onetime::Mail::Smtp2goClient::APIError)
            end
        end
      end
    end

    context 'network errors (inherited from Base)' do
      it 'classifies Errno::ECONNREFUSED as transient' do
        allow(mock_client).to receive(:post)
          .and_raise(Errno::ECONNREFUSED, 'Connection refused')

        expect { backend.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be true
          end
      end

      it 'classifies Net::OpenTimeout as transient' do
        allow(mock_client).to receive(:post)
          .and_raise(Net::OpenTimeout, 'timed out')

        expect { backend.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be true
          end
      end
    end

    context 'unknown errors' do
      it 'classifies generic StandardError as non-transient' do
        allow(mock_client).to receive(:post)
          .and_raise(StandardError, 'unexpected')

        expect { backend.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be false
          end
      end
    end

    context 'DeliveryError pass-through' do
      it 'does not double-wrap DeliveryError' do
        original = Onetime::Mail::DeliveryError.new(
          'already wrapped',
          original_error: RuntimeError.new('inner'),
          transient: true,
        )
        allow(mock_client).to receive(:post).and_raise(original)

        expect { backend.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err).to equal(original)
          end
      end
    end
  end

  describe '#classify_error' do
    it 'classifies 429 as transient' do
      expect(backend.classify_error(api_error('rate limited', status_code: 429))).to eq(:transient)
    end

    it 'classifies 5xx as transient' do
      expect(backend.classify_error(api_error('boom', status_code: 500))).to eq(:transient)
      expect(backend.classify_error(api_error('boom', status_code: 599))).to eq(:transient)
    end

    it 'classifies other API errors as fatal' do
      expect(backend.classify_error(api_error('bad', status_code: 400))).to eq(:fatal)
      expect(backend.classify_error(api_error('auth', status_code: 401))).to eq(:fatal)
      expect(backend.classify_error(api_error('gone', status_code: 404))).to eq(:fatal)
      expect(backend.classify_error(api_error('failures', status_code: 200))).to eq(:fatal)
    end

    it 'defers to Base for non-API errors' do
      expect(backend.classify_error(Net::OpenTimeout.new('timed out'))).to eq(:transient)
      expect(backend.classify_error(StandardError.new('unexpected'))).to eq(:unknown)
    end
  end

  describe '#validate_config!' do
    it 'raises ArgumentError when api_key is missing' do
      allow(ENV).to receive(:fetch).with('SMTP2GO_API_KEY', nil).and_return(nil)
      expect { described_class.new({}) }
        .to raise_error(ArgumentError, /SMTP2GO API key must be configured/)
    end

    it 'raises ArgumentError when api_key is empty' do
      expect { described_class.new({ 'api_key' => '' }) }
        .to raise_error(ArgumentError, /SMTP2GO API key must be configured/)
    end

    it 'accepts key from ENV' do
      allow(ENV).to receive(:fetch).with('SMTP2GO_API_KEY', nil).and_return('api-env-key')
      expect { described_class.new({}) }.not_to raise_error
    end

    it 'accepts a symbol-keyed api_key without falling back to ENV (Base stringifies keys)' do
      allow(ENV).to receive(:fetch).with('SMTP2GO_API_KEY', nil).and_return(nil)
      expect { described_class.new(api_key: 'api-byok-key') }.not_to raise_error
    end
  end

  describe '#provider_name' do
    it 'returns Smtp2go' do
      expect(backend.provider_name).to eq('Smtp2go')
    end
  end

  describe 'client construction' do
    it 'passes api_key, base_url and timeout through to Smtp2goClient' do
      fresh_backend = described_class.new(
        { 'api_key' => 'api-test-key', 'base_url' => 'https://custom.api.example.com/v3', 'timeout' => 45 },
      )

      expect(Onetime::Mail::Smtp2goClient).to receive(:new).with(
        api_key: 'api-test-key',
        base_url: 'https://custom.api.example.com/v3',
        read_timeout: 45,
      ).and_return(mock_client)

      fresh_backend.send(:client)
    end
  end
end
