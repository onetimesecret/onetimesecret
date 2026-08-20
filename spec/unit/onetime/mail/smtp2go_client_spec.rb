# spec/unit/onetime/mail/smtp2go_client_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/mail/smtp2go_client'

RSpec.describe Onetime::Mail::Smtp2goClient do
  let(:api_key) { 'api-0123456789abcdef0123456789abcdef' }
  let(:client) { described_class.new(api_key: api_key) }
  let(:endpoint) { 'https://api.smtp2go.com/v3/email/send' }

  describe '#post' do
    context 'with a 2xx response' do
      it 'unwraps the {request_id, data} envelope and returns the data hash' do
        stub_request(:post, endpoint)
          .to_return(
            status: 200,
            body: {
              'request_id' => 'aa253464-0bd0-467a-b24b-6159dcd7be60',
              'data' => { 'succeeded' => 1, 'failed' => 0, 'failures' => [], 'email_id' => '1er8bV-6Sw0i9-6ci1pC' },
            }.to_json,
          )

        data = client.post('/email/send', { 'sender' => 'a@example.com' })

        expect(data).to eq(
          'succeeded' => 1, 'failed' => 0, 'failures' => [], 'email_id' => '1er8bV-6Sw0i9-6ci1pC',
        )
      end

      it 'sends the API key and JSON headers with the JSON-encoded payload' do
        stub = stub_request(:post, endpoint)
          .with(
            headers: {
              'X-Smtp2go-Api-Key' => api_key,
              'Content-Type' => 'application/json',
              'Accept' => 'application/json',
            },
            body: { 'sender' => 'a@example.com', 'to' => ['b@example.com'] }.to_json,
          )
          .to_return(status: 200, body: { 'request_id' => 'r1', 'data' => {} }.to_json)

        client.post('/email/send', { 'sender' => 'a@example.com', 'to' => ['b@example.com'] })

        expect(stub).to have_been_requested
      end

      it 'returns an empty hash when the envelope has no data key' do
        stub_request(:post, endpoint)
          .to_return(status: 200, body: { 'request_id' => 'r1' }.to_json)

        expect(client.post('/email/send')).to eq({})
      end

      it 'returns an empty hash for an empty body' do
        stub_request(:post, endpoint).to_return(status: 200, body: '')

        expect(client.post('/email/send')).to eq({})
      end

      it 'returns an empty hash when the body is JSON but not an object' do
        stub_request(:post, endpoint).to_return(status: 200, body: '[1, 2, 3]')

        expect(client.post('/email/send')).to eq({})
      end

      it 'raises APIError when a 200 envelope carries an error payload' do
        stub_request(:post, endpoint)
          .to_return(
            status: 200,
            body: {
              'request_id' => 'aa253464-0bd0-467a-b24b-6159dcd7be60',
              'data' => {
                'error_code' => 'E_ApiResponseCodes.NON_VALIDATING_IN_PAYLOAD',
                'error' => 'The payload provided for sending was not valid',
              },
            }.to_json,
          )

        expect { client.post('/email/send') }.to raise_error(described_class::APIError) do |err|
          expect(err.message).to eq('The payload provided for sending was not valid')
          expect(err.status_code).to eq(200)
          expect(err.error_code).to eq('E_ApiResponseCodes.NON_VALIDATING_IN_PAYLOAD')
          expect(err.response_body).to include('NON_VALIDATING_IN_PAYLOAD')
        end
      end

      it 'raises APIError for a non-JSON success body' do
        stub_request(:post, endpoint).to_return(status: 200, body: '<html>gateway page</html>')

        expect { client.post('/email/send') }.to raise_error(described_class::APIError) do |err|
          expect(err.message).to include('Invalid JSON response from SMTP2GO')
          expect(err.status_code).to eq(200)
          expect(err.response_body).to include('<html>')
        end
      end
    end

    context 'with an error response' do
      it 'raises APIError carrying status_code, error_code and message from the envelope' do
        stub_request(:post, endpoint)
          .to_return(
            status: 403,
            body: {
              'request_id' => 'r1',
              'data' => {
                'error_code' => 'E_ApiResponseCodes.ENDPOINT_PERMISSION_DENIED',
                'error' => 'You do not have permission to access this API endpoint',
              },
            }.to_json,
          )

        expect { client.post('/email/send') }.to raise_error(described_class::APIError) do |err|
          expect(err.message).to eq('You do not have permission to access this API endpoint')
          expect(err.status_code).to eq(403)
          expect(err.error_code).to eq('E_ApiResponseCodes.ENDPOINT_PERMISSION_DENIED')
          expect(err.response_body).to include('ENDPOINT_PERMISSION_DENIED')
        end
      end

      it 'raises APIError with an HTTP fallback message for non-JSON error bodies' do
        stub_request(:post, endpoint).to_return(status: 502, body: 'Bad Gateway')

        expect { client.post('/email/send') }.to raise_error(described_class::APIError) do |err|
          expect(err.message).to eq('HTTP 502')
          expect(err.status_code).to eq(502)
          expect(err.error_code).to be_nil
          expect(err.response_body).to eq('Bad Gateway')
        end
      end

      it 'truncates response_body to 500 characters' do
        stub_request(:post, endpoint).to_return(status: 500, body: 'x' * 2000)

        expect { client.post('/email/send') }.to raise_error(described_class::APIError) do |err|
          expect(err.response_body.length).to eq(500)
        end
      end
    end

    context 'with a custom base_url' do
      it 'targets the custom host and tolerates a trailing slash' do
        custom = described_class.new(api_key: api_key, base_url: 'https://smtp2go.internal/v3/')
        stub = stub_request(:post, 'https://smtp2go.internal/v3/domain/view')
          .to_return(status: 200, body: { 'request_id' => 'r1', 'data' => { 'domains' => [] } }.to_json)

        expect(custom.post('/domain/view', { 'domain' => 'example.com' })).to eq('domains' => [])
        expect(stub).to have_been_requested
      end

      it 'falls back to the default base URL when base_url is nil' do
        fallback = described_class.new(api_key: api_key, base_url: nil)
        stub_request(:post, endpoint)
          .to_return(status: 200, body: { 'request_id' => 'r1', 'data' => {} }.to_json)

        expect(fallback.post('/email/send')).to eq({})
      end
    end

    context 'with network-level failures' do
      it 'propagates timeouts raw (no APIError wrapping)' do
        stub_request(:post, endpoint).to_timeout

        expect { client.post('/email/send') }.to raise_error(Net::OpenTimeout)
      end

      it 'propagates socket errors raw' do
        stub_request(:post, endpoint).to_raise(SocketError.new('getaddrinfo failed'))

        expect { client.post('/email/send') }.to raise_error(SocketError)
      end
    end
  end

  describe 'APIError' do
    it 'exposes status_code, error_code and response_body' do
      err = described_class::APIError.new(
        'boom', status_code: 429, error_code: 'E_X', response_body: '{"data":{}}',
      )

      expect(err.message).to eq('boom')
      expect(err.status_code).to eq(429)
      expect(err.error_code).to eq('E_X')
      expect(err.response_body).to eq('{"data":{}}')
    end
  end
end
