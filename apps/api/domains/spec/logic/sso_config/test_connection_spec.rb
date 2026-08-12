# apps/api/domains/spec/logic/sso_config/test_connection_spec.rb
#
# frozen_string_literal: true

# Unit tests for TestConnection's SSRF-pinned discovery fetch.
#
# fetch_url resolves + validates the issuer host ONCE through the shared
# egress guard (Onetime::Http::Guard) and pins the dial to that exact IP via
# Net::HTTP#ipaddr=, closing the validate-then-reresolve DNS-rebinding
# window. valid_issuer_host? remains upstream as a cheap early rejection,
# but fetch_url is the enforcement point — it also covers
# test_entra_id_connection, which never passes through valid_issuer_host?.
#
# Hermetic: the guard's DNS seam (Guard.resolve_addresses) and Net::HTTP.new
# are stubbed; no live DNS or network.
#
# Run:
#   pnpm run test:rspec apps/api/domains/spec/logic/sso_config/test_connection_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../../../../apps/api/domains/application'

RSpec.describe DomainsAPI::Logic::SsoConfig::TestConnection do
  # The connection-test helpers under test are independent of the auth
  # plumbing exercised in base_spec, so allocate an instance and set only
  # the ivars the helpers read.
  let(:logic) do
    described_class.allocate.tap do |instance|
      instance.instance_variable_set(:@provider_type, provider_type)
      instance.instance_variable_set(:@issuer, issuer)
      instance.instance_variable_set(:@tenant_id, tenant_id)
    end
  end

  let(:provider_type) { 'oidc' }
  let(:issuer) { 'https://idp.example.com' }
  let(:tenant_id) { nil }

  let(:http_instance) { instance_double(Net::HTTP) }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:le)

    allow(Net::HTTP).to receive(:new).and_return(http_instance)
    allow(http_instance).to receive(:ipaddr=)
    allow(http_instance).to receive(:use_ssl=)
    allow(http_instance).to receive(:open_timeout=)
    allow(http_instance).to receive(:read_timeout=)
    allow(http_instance).to receive(:verify_mode=)
    allow(http_instance).to receive(:request)
  end

  # Stub the guard's DNS seam; validation and pinning logic stay real.
  def stub_issuer_resolution(addresses)
    allow(Onetime::Http::Guard).to receive(:resolve_addresses).and_return(addresses)
  end

  def success_response(body)
    Net::HTTPOK.new('1.1', '200', 'OK').tap do |response|
      allow(response).to receive(:body).and_return(body)
    end
  end

  describe '#test_oidc_connection' do
    context 'when the issuer resolves to a blocked address' do
      before { stub_issuer_resolution(['127.0.0.1']) }

      it 'returns a structured blocked_target failure without connecting' do
        result = logic.send(:test_oidc_connection)

        expect(result[:success]).to be false
        expect(result[:message]).to eq('OIDC issuer resolves to a blocked address')
        expect(result[:details][:error_code]).to eq('blocked_target')
        expect(Net::HTTP).not_to have_received(:new)
        expect(http_instance).not_to have_received(:request)
      end

      it 'does not echo the resolved IP anywhere in the result' do
        result = logic.send(:test_oidc_connection)

        expect(result.inspect).not_to include('127.0.0.1')
      end
    end

    context 'when the RRset mixes public and private answers' do
      before { stub_issuer_resolution(['203.0.113.10', '10.0.0.5']) }

      it 'blocks wholesale without connecting' do
        result = logic.send(:test_oidc_connection)

        expect(result[:details][:error_code]).to eq('blocked_target')
        expect(result.inspect).not_to include('10.0.0.5')
        expect(Net::HTTP).not_to have_received(:new)
      end
    end

    context 'when the issuer resolves to a public address' do
      let(:discovery_body) do
        {
          issuer: issuer,
          authorization_endpoint: "#{issuer}/authorize",
          token_endpoint: "#{issuer}/token",
          jwks_uri: "#{issuer}/jwks",
        }.to_json
      end

      before do
        stub_issuer_resolution(['203.0.113.10'])
        allow(http_instance).to receive(:request).and_return(success_response(discovery_body))
      end

      it 'pins the connection to the validated IP' do
        result = logic.send(:test_oidc_connection)

        expect(result[:success]).to be true
        # Explicit nil p_addr disables environment-proxy pickup (http_proxy),
        # which would otherwise silently bypass the IP pinning.
        expect(Net::HTTP).to have_received(:new).with('idp.example.com', 443, nil)
        expect(http_instance).to have_received(:ipaddr=).with('203.0.113.10')
      end
    end
  end

  describe '#test_entra_id_connection' do
    # Entra's discovery URL is built from the tenant, not the issuer, and
    # never passes through valid_issuer_host? — fetch_url's guard is the
    # only enforcement on this path.
    let(:provider_type) { 'entra_id' }
    let(:issuer) { nil }
    let(:tenant_id) { '11111111-2222-3333-4444-555555555555' }

    it 'still enforces the egress guard at fetch time' do
      stub_issuer_resolution(['192.168.1.10'])

      result = logic.send(:test_entra_id_connection)

      expect(result[:success]).to be false
      expect(result[:message]).to eq('Entra ID issuer resolves to a blocked address')
      expect(result[:details][:error_code]).to eq('blocked_target')
      expect(result.inspect).not_to include('192.168.1.10')
      expect(Net::HTTP).not_to have_received(:new)
    end

    it 'pins allowed resolutions to the validated IP' do
      stub_issuer_resolution(['203.0.113.20'])
      body = {
        issuer: 'https://login.microsoftonline.com/x/v2.0',
        authorization_endpoint: 'https://login.microsoftonline.com/x/authorize',
        token_endpoint: 'https://login.microsoftonline.com/x/token',
        jwks_uri: 'https://login.microsoftonline.com/x/jwks',
      }.to_json
      allow(http_instance).to receive(:request).and_return(success_response(body))

      result = logic.send(:test_entra_id_connection)

      expect(result[:success]).to be true
      expect(Net::HTTP).to have_received(:new).with('login.microsoftonline.com', 443, nil)
      expect(http_instance).to have_received(:ipaddr=).with('203.0.113.20')
    end
  end
end
