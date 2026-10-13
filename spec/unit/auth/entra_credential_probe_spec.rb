# spec/unit/auth/entra_credential_probe_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::SsoProvider::EntraCredentialProbe: one
# client-credentials token request that reports whether Entra accepted a
# stored client_id / client_secret pair, without exposing the secret, the
# token, or Entra's error_description.
#
# Hermetic: the token endpoint is stubbed with WebMock (spec_helper disables
# real connections).
#
# Run:
#   tests/lanes/run unit --only spec/unit/auth/entra_credential_probe_spec.rb

require 'spec_helper'
require 'onetime/models/custom_domain/sso_config'
require 'onetime/sso_provider/entra_credential_probe'

RSpec.describe Onetime::SsoProvider::EntraCredentialProbe do
  let(:tenant_id) { '12345678-1234-1234-1234-123456789abc' }
  let(:client_id) { 'stored-client-id' }
  let(:secret) { 'stored+secret%with:punctuation' }
  let(:token_url) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token" }
  let(:private_description) { 'private description Trace ID: 11111111-aaaa Correlation ID: 22222222-bbbb' }

  before do
    allow(OT).to receive(:le)
  end

  def probe(overrides = {})
    described_class.call(**{ tenant_id: tenant_id, client_id: client_id, client_secret: secret }.merge(overrides))
  end

  def refuse_with(aadsts, status: 401)
    stub_request(:post, token_url).to_return(
      status: status,
      headers: { 'Content-Type' => 'application/json' },
      body: JSON.generate(error: 'invalid_client', error_description: "#{aadsts}: #{private_description} #{secret}"),
    )
  end

  def accept
    stub_request(:post, token_url).to_return(
      status: 200,
      headers: { 'Content-Type' => 'application/json' },
      body: JSON.generate(token_type: 'Bearer', expires_in: 3599, access_token: 'private-access-token'),
    )
  end

  describe 'auth scheme' do
    # The probe must send the secret the way sign-in sends it, or a passing
    # probe says nothing about sign-in (docs/runbooks/sso-credential-health.md).
    it 'is the auth_scheme SsoConfig#build_entra_id_options emits' do
      # build_entra_id_options is private (to_omniauth_options is the public
      # face) and names the strategy after the owning CustomDomain, which a
      # record without one cannot load; neither matters for the auth scheme.
      config = Onetime::CustomDomain::SsoConfig.new
      allow(config).to receive(:strategy_name).and_return('ext-domain123')
      options = config.send(:build_entra_id_options)

      expect(described_class::AUTH_SCHEME).to eq(options[:client_options][:auth_scheme])
    end

    it 'sends the credentials in the request body with the client-credentials grant, never in a Basic header' do
      request = accept

      probe

      expect(request.with do |wire|
        params = URI.decode_www_form(wire.body).to_h
        params == {
          'grant_type' => 'client_credentials',
          'scope' => described_class::SCOPE,
          'client_id' => client_id,
          'client_secret' => secret,
        } && wire.headers['Authorization'].nil?
      end).to have_been_requested.once
    end
  end

  describe 'result mapping' do
    it 'passes on HTTP 200 with an access_token and exposes neither the token nor the secret' do
      accept

      result = probe

      expect(result.status).to eq(:passed)
      expect(result.error_code).to be_nil
      expect(result.http_status).to eq(200)
      expect(result.inspect).not_to include('private-access-token')
      expect(result.inspect).not_to include(secret)
    end

    it 'fails with invalid_client_secret on AADSTS7000215' do
      refuse_with('AADSTS7000215')

      result = probe

      expect(result.status).to eq(:failed)
      expect(result.error_code).to eq('invalid_client_secret')
      expect(result.http_status).to eq(401)
      expect(result.aadsts_code).to eq('AADSTS7000215')
    end

    it 'fails with client_secret_expired on AADSTS7000222' do
      refuse_with('AADSTS7000222')

      expect(probe).to have_attributes(status: :failed, error_code: 'client_secret_expired', aadsts_code: 'AADSTS7000222')
    end

    it 'fails with app_not_found_in_tenant on AADSTS700016' do
      refuse_with('AADSTS700016', status: 400)

      expect(probe).to have_attributes(status: :failed, error_code: 'app_not_found_in_tenant', http_status: 400)
    end

    it 'is inconclusive with provider_error and the bare code on any other AADSTS code' do
      refuse_with('AADSTS50059', status: 400)

      result = probe

      expect(result).to have_attributes(status: :inconclusive, error_code: 'provider_error', aadsts_code: 'AADSTS50059')
      expect(result.inspect).not_to include('private description')
      expect(result.inspect).not_to include('Correlation ID')
      expect(result.inspect).not_to include(secret)
    end

    it 'is inconclusive with invalid_response on an error body without an AADSTS code' do
      stub_request(:post, token_url).to_return(
        status: 400,
        headers: { 'Content-Type' => 'application/json' },
        body: JSON.generate(error: 'invalid_request'),
      )

      expect(probe).to have_attributes(status: :inconclusive, error_code: 'invalid_response', http_status: 400)
    end

    it 'is inconclusive with invalid_response on a non-JSON error body' do
      stub_request(:post, token_url).to_return(status: 502, headers: { 'Content-Type' => 'text/html' }, body: '<html>bad gateway</html>')

      expect(probe).to have_attributes(status: :inconclusive, error_code: 'invalid_response', http_status: 502)
    end

    it 'is inconclusive with invalid_response on a 200 without a token' do
      stub_request(:post, token_url).to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: JSON.generate(token_type: 'Bearer'),
      )

      expect(probe).to have_attributes(status: :inconclusive, error_code: 'invalid_response')
    end

    it 'is inconclusive with timeout when the endpoint does not answer' do
      stub_request(:post, token_url).to_timeout

      expect(probe).to have_attributes(status: :inconclusive, error_code: 'timeout', http_status: nil)
    end

    it 'is inconclusive with connection_failed when the endpoint refuses the connection' do
      stub_request(:post, token_url).to_raise(Errno::ECONNREFUSED)

      expect(probe).to have_attributes(status: :inconclusive, error_code: 'connection_failed')
    end

    it 'is inconclusive with ssl_error on a TLS failure' do
      stub_request(:post, token_url).to_raise(OpenSSL::SSL::SSLError.new('certificate verify failed'))

      expect(probe).to have_attributes(status: :inconclusive, error_code: 'ssl_error')
    end
  end

  describe 'tenant_id guard' do
    it 'fails with invalid_tenant_id and never builds a request for a tenant_id outside the UUID shape' do
      stub = stub_request(:post, %r{\Ahttps://login\.microsoftonline\.com/})

      result = probe(tenant_id: 'common/../evil')

      expect(result).to have_attributes(status: :failed, error_code: 'invalid_tenant_id', http_status: nil)
      expect(stub).not_to have_been_requested
    end
  end
end
