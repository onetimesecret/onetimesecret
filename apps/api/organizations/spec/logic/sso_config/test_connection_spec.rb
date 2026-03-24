# apps/api/organizations/spec/logic/sso_config/test_connection_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'organizations/logic'
require 'webmock/rspec'

RSpec.describe OrganizationAPI::Logic::SsoConfig::TestConnection do
  let(:customer) do
    instance_double(
      Onetime::Customer,
      objid: 'cust-123',
      custid: 'cust-123',
      extid: 'ext-cust-123',
      email: 'owner@example.com',
      anonymous?: false,
      role: 'customer',
    )
  end

  let(:organization) do
    instance_double(
      Onetime::Organization,
      objid: 'org-123',
      extid: 'ext-org-123',
      display_name: 'Test Organization',
    )
  end

  let(:session) { { 'csrf' => 'test-csrf-token' } }

  let(:strategy_result) do
    double('StrategyResult',
      session: session,
      user: customer,
      authenticated?: true,
      metadata: {},
    )
  end

  # Valid OIDC discovery document
  let(:valid_discovery_document) do
    {
      'issuer' => 'https://auth.example.com',
      'authorization_endpoint' => 'https://auth.example.com/authorize',
      'token_endpoint' => 'https://auth.example.com/token',
      'jwks_uri' => 'https://auth.example.com/.well-known/jwks.json',
      'userinfo_endpoint' => 'https://auth.example.com/userinfo',
      'scopes_supported' => %w[openid profile email],
    }.to_json
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(Onetime::Organization).to receive(:find_by_extid).with('ext-org-123').and_return(organization)
    allow(organization).to receive(:owner?).with(customer).and_return(true)
  end

  describe 'OIDC provider' do
    let(:params) do
      {
        'extid' => 'ext-org-123',
        'provider_type' => 'oidc',
        'client_id' => 'oidc-client-id',
        'issuer' => 'https://auth.example.com',
      }
    end

    subject(:logic) { described_class.new(strategy_result, params) }

    context 'when connection is successful' do
      before do
        stub_request(:get, 'https://auth.example.com/.well-known/openid-configuration')
          .to_return(
            status: 200,
            body: valid_discovery_document,
            headers: { 'Content-Type' => 'application/json' },
          )
        logic.raise_concerns
      end

      it 'returns success with discovery details' do
        result = logic.process

        expect(result[:success]).to be true
        expect(result[:provider_type]).to eq('oidc')
        expect(result[:message]).to eq('OIDC connection successful')
        expect(result[:details][:authorization_endpoint]).to eq('https://auth.example.com/authorize')
        expect(result[:details][:token_endpoint]).to eq('https://auth.example.com/token')
        expect(result[:details][:jwks_uri]).to eq('https://auth.example.com/.well-known/jwks.json')
      end
    end

    context 'when discovery document is not found' do
      before do
        stub_request(:get, 'https://auth.example.com/.well-known/openid-configuration')
          .to_return(status: 404)
        logic.raise_concerns
      end

      it 'returns failure with not_found error' do
        result = logic.process

        expect(result[:success]).to be false
        expect(result[:message]).to include('not found')
        expect(result[:details][:error_code]).to eq('discovery_not_found')
        expect(result[:details][:http_status]).to eq(404)
      end
    end

    context 'when discovery document is missing required fields' do
      before do
        incomplete_discovery = { 'issuer' => 'https://auth.example.com' }.to_json
        stub_request(:get, 'https://auth.example.com/.well-known/openid-configuration')
          .to_return(
            status: 200,
            body: incomplete_discovery,
            headers: { 'Content-Type' => 'application/json' },
          )
        logic.raise_concerns
      end

      it 'returns failure with missing fields' do
        result = logic.process

        expect(result[:success]).to be false
        expect(result[:message]).to include('missing required fields')
        expect(result[:details][:error_code]).to eq('invalid_discovery')
        expect(result[:details][:missing_fields]).to include('authorization_endpoint')
      end
    end

    context 'when response is not valid JSON' do
      before do
        stub_request(:get, 'https://auth.example.com/.well-known/openid-configuration')
          .to_return(
            status: 200,
            body: 'not json',
            headers: { 'Content-Type' => 'text/html' },
          )
        logic.raise_concerns
      end

      it 'returns failure with invalid_json error' do
        result = logic.process

        expect(result[:success]).to be false
        expect(result[:message]).to include('invalid JSON')
        expect(result[:details][:error_code]).to eq('invalid_json')
      end
    end

    context 'when connection times out' do
      before do
        stub_request(:get, 'https://auth.example.com/.well-known/openid-configuration')
          .to_timeout
        logic.raise_concerns
      end

      it 'returns failure with timeout error' do
        result = logic.process

        expect(result[:success]).to be false
        expect(result[:message]).to include('timed out')
        expect(result[:details][:error_code]).to eq('timeout')
      end
    end

    context 'when SSL certificate is invalid' do
      before do
        stub_request(:get, 'https://auth.example.com/.well-known/openid-configuration')
          .to_raise(OpenSSL::SSL::SSLError.new('certificate verify failed'))
        logic.raise_concerns
      end

      it 'returns failure with ssl_error' do
        result = logic.process

        expect(result[:success]).to be false
        expect(result[:message]).to include('SSL/TLS error')
        expect(result[:details][:error_code]).to eq('ssl_error')
      end
    end

    context 'when network connection fails' do
      before do
        stub_request(:get, 'https://auth.example.com/.well-known/openid-configuration')
          .to_raise(SocketError.new('getaddrinfo: nodename nor servname provided'))
        logic.raise_concerns
      end

      it 'returns failure with connection_failed error' do
        result = logic.process

        expect(result[:success]).to be false
        expect(result[:message]).to include('connection failed')
        expect(result[:details][:error_code]).to eq('connection_failed')
      end
    end
  end

  describe 'Entra ID provider' do
    let(:params) do
      {
        'extid' => 'ext-org-123',
        'provider_type' => 'entra_id',
        'client_id' => 'entra-client-id',
        'tenant_id' => '12345678-1234-1234-1234-123456789abc',
      }
    end

    let(:entra_discovery_document) do
      {
        'issuer' => 'https://login.microsoftonline.com/12345678-1234-1234-1234-123456789abc/v2.0',
        'authorization_endpoint' => 'https://login.microsoftonline.com/12345678-1234-1234-1234-123456789abc/oauth2/v2.0/authorize',
        'token_endpoint' => 'https://login.microsoftonline.com/12345678-1234-1234-1234-123456789abc/oauth2/v2.0/token',
        'jwks_uri' => 'https://login.microsoftonline.com/12345678-1234-1234-1234-123456789abc/discovery/v2.0/keys',
        'userinfo_endpoint' => 'https://graph.microsoft.com/oidc/userinfo',
        'scopes_supported' => %w[openid profile email],
      }.to_json
    end

    subject(:logic) { described_class.new(strategy_result, params) }

    context 'when connection is successful' do
      before do
        stub_request(:get, 'https://login.microsoftonline.com/12345678-1234-1234-1234-123456789abc/v2.0/.well-known/openid-configuration')
          .to_return(
            status: 200,
            body: entra_discovery_document,
            headers: { 'Content-Type' => 'application/json' },
          )
        logic.raise_concerns
      end

      it 'returns success with Entra ID discovery details' do
        result = logic.process

        expect(result[:success]).to be true
        expect(result[:provider_type]).to eq('entra_id')
        expect(result[:message]).to eq('Entra ID connection successful')
      end
    end

    context 'when tenant_id is not a valid UUID' do
      let(:params) do
        {
          'extid' => 'ext-org-123',
          'provider_type' => 'entra_id',
          'client_id' => 'entra-client-id',
          'tenant_id' => 'not-a-uuid',
        }
      end

      it 'raises validation error' do
        expect { logic.raise_concerns }.to raise_error(
          OT::FormError,
          'Tenant ID must be a valid UUID',
        )
      end
    end

    context 'when tenant does not exist (404)' do
      before do
        stub_request(:get, 'https://login.microsoftonline.com/12345678-1234-1234-1234-123456789abc/v2.0/.well-known/openid-configuration')
          .to_return(status: 404)
        logic.raise_concerns
      end

      it 'returns failure indicating tenant not found' do
        result = logic.process

        expect(result[:success]).to be false
        expect(result[:details][:error_code]).to eq('discovery_not_found')
      end
    end
  end

  describe 'Google provider' do
    let(:params) do
      {
        'extid' => 'ext-org-123',
        'provider_type' => 'google',
        'client_id' => '123456789.apps.googleusercontent.com',
      }
    end

    let(:google_discovery_document) do
      {
        'issuer' => 'https://accounts.google.com',
        'authorization_endpoint' => 'https://accounts.google.com/o/oauth2/v2/auth',
        'token_endpoint' => 'https://oauth2.googleapis.com/token',
        'jwks_uri' => 'https://www.googleapis.com/oauth2/v3/certs',
        'userinfo_endpoint' => 'https://openidconnect.googleapis.com/v1/userinfo',
        'scopes_supported' => %w[openid profile email],
      }.to_json
    end

    subject(:logic) { described_class.new(strategy_result, params) }

    context 'when connection is successful' do
      before do
        stub_request(:get, 'https://accounts.google.com/.well-known/openid-configuration')
          .to_return(
            status: 200,
            body: google_discovery_document,
            headers: { 'Content-Type' => 'application/json' },
          )
        logic.raise_concerns
      end

      it 'returns success with Google discovery details' do
        result = logic.process

        expect(result[:success]).to be true
        expect(result[:provider_type]).to eq('google')
        expect(result[:message]).to eq('Google connection successful')
      end
    end

    context 'when client_id format is invalid' do
      let(:params) do
        {
          'extid' => 'ext-org-123',
          'provider_type' => 'google',
          'client_id' => 'invalid-client-id',
        }
      end

      it 'raises validation error' do
        expect { logic.raise_concerns }.to raise_error(
          OT::FormError,
          'Google Client ID must end with .apps.googleusercontent.com',
        )
      end
    end
  end

  describe 'GitHub provider' do
    let(:params) do
      {
        'extid' => 'ext-org-123',
        'provider_type' => 'github',
        'client_id' => '12345678901234567890', # 20 chars
      }
    end

    subject(:logic) { described_class.new(strategy_result, params) }

    context 'when client_id format is valid' do
      before do
        logic.raise_concerns
      end

      it 'returns success without network request' do
        result = logic.process

        expect(result[:success]).to be true
        expect(result[:provider_type]).to eq('github')
        expect(result[:message]).to include('format validated')
        expect(result[:details][:note]).to include('does not support OIDC discovery')
      end
    end

    context 'when client_id format is invalid (too short)' do
      let(:params) do
        {
          'extid' => 'ext-org-123',
          'provider_type' => 'github',
          'client_id' => 'tooshort',
        }
      end

      it 'raises validation error' do
        expect { logic.raise_concerns }.to raise_error(
          OT::FormError,
          'GitHub Client ID must be exactly 20 alphanumeric characters',
        )
      end
    end

    context 'when client_id contains non-alphanumeric characters' do
      let(:params) do
        {
          'extid' => 'ext-org-123',
          'provider_type' => 'github',
          'client_id' => '1234567890123456789-', # 20 chars but with hyphen
        }
      end

      it 'raises validation error' do
        expect { logic.raise_concerns }.to raise_error(
          OT::FormError,
          'GitHub Client ID must be exactly 20 alphanumeric characters',
        )
      end
    end
  end

  describe 'authorization checks' do
    let(:params) do
      {
        'extid' => 'ext-org-123',
        'provider_type' => 'oidc',
        'client_id' => 'test-client',
        'issuer' => 'https://auth.example.com',
      }
    end

    subject(:logic) { described_class.new(strategy_result, params) }

    context 'when customer is anonymous' do
      let(:customer) do
        instance_double(
          Onetime::Customer,
          objid: 'anon-123',
          anonymous?: true,
        )
      end

      it 'raises unauthorized error' do
        expect { logic.raise_concerns }.to raise_error(
          OT::FormError,
          'Authentication required',
        )
      end
    end

    context 'when user is not organization owner' do
      before do
        allow(organization).to receive(:owner?).with(customer).and_return(false)
      end

      it 'raises forbidden error' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::Forbidden,
          'Only organization owner can perform this action',
        )
      end
    end

    context 'when organization does not exist' do
      before do
        allow(Onetime::Organization).to receive(:find_by_extid).with('ext-org-123').and_return(nil)
      end

      it 'raises not found error' do
        expect { logic.raise_concerns }.to raise_error(Onetime::RecordNotFound)
      end
    end
  end

  describe 'SSRF prevention' do
    let(:params) do
      {
        'extid' => 'ext-org-123',
        'provider_type' => 'oidc',
        'client_id' => 'test-client',
        'issuer' => issuer_url,
      }
    end

    subject(:logic) { described_class.new(strategy_result, params) }

    context 'when issuer is HTTP (not HTTPS)' do
      let(:issuer_url) { 'http://auth.example.com' }

      it 'rejects non-HTTPS URL during validation' do
        # The sanitize_url method returns empty string for non-HTTPS
        expect { logic.raise_concerns }.to raise_error(
          OT::FormError,
          'Issuer URL is required for OIDC provider',
        )
      end
    end

    context 'when issuer points to localhost' do
      let(:issuer_url) { 'https://localhost/auth' }

      before do
        logic.raise_concerns
      end

      it 'rejects localhost as invalid issuer' do
        result = logic.process

        expect(result[:success]).to be false
        expect(result[:details][:error_code]).to eq('invalid_issuer')
      end
    end

    context 'when issuer points to internal IP' do
      let(:issuer_url) { 'https://192.168.1.1/auth' }

      before do
        logic.raise_concerns
      end

      it 'rejects private IP as invalid issuer' do
        result = logic.process

        expect(result[:success]).to be false
        expect(result[:details][:error_code]).to eq('invalid_issuer')
      end
    end

    context 'when issuer has .local domain' do
      let(:issuer_url) { 'https://idp.local/auth' }

      before do
        logic.raise_concerns
      end

      it 'rejects .local domain as invalid issuer' do
        result = logic.process

        expect(result[:success]).to be false
        expect(result[:details][:error_code]).to eq('invalid_issuer')
      end
    end

    # DNS rebinding protection tests
    context 'when hostname resolves to loopback IP (DNS rebinding)' do
      let(:issuer_url) { 'https://rebind.example.com/auth' }

      before do
        # Simulate DNS rebinding service like nip.io resolving to 127.0.0.1
        allow(Resolv).to receive(:getaddresses).with('rebind.example.com').and_return(['127.0.0.1'])
        logic.raise_concerns
      end

      it 'rejects hostname that resolves to loopback' do
        result = logic.process

        expect(result[:success]).to be false
        expect(result[:details][:error_code]).to eq('invalid_issuer')
      end
    end

    context 'when hostname resolves to private IP (DNS rebinding)' do
      let(:issuer_url) { 'https://internal.attacker.com/auth' }

      before do
        # Simulate DNS rebinding service resolving to private IP
        allow(Resolv).to receive(:getaddresses).with('internal.attacker.com').and_return(['10.0.0.1'])
        logic.raise_concerns
      end

      it 'rejects hostname that resolves to private IP' do
        result = logic.process

        expect(result[:success]).to be false
        expect(result[:details][:error_code]).to eq('invalid_issuer')
      end
    end

    context 'when hostname resolves to link-local IP' do
      let(:issuer_url) { 'https://linklocal.attacker.com/auth' }

      before do
        # Simulate DNS rebinding service resolving to link-local address
        allow(Resolv).to receive(:getaddresses).with('linklocal.attacker.com').and_return(['169.254.169.254'])
        logic.raise_concerns
      end

      it 'rejects hostname that resolves to link-local (cloud metadata)' do
        result = logic.process

        expect(result[:success]).to be false
        expect(result[:details][:error_code]).to eq('invalid_issuer')
      end
    end

    context 'when hostname resolves to mixed public and private IPs' do
      let(:issuer_url) { 'https://mixed.attacker.com/auth' }

      before do
        # If any resolved IP is internal, block the request
        allow(Resolv).to receive(:getaddresses).with('mixed.attacker.com').and_return(['8.8.8.8', '192.168.1.1'])
        logic.raise_concerns
      end

      it 'rejects if any resolved IP is internal' do
        result = logic.process

        expect(result[:success]).to be false
        expect(result[:details][:error_code]).to eq('invalid_issuer')
      end
    end

    context 'when DNS resolution fails' do
      let(:issuer_url) { 'https://nonexistent.invalid/auth' }

      before do
        allow(Resolv).to receive(:getaddresses).with('nonexistent.invalid').and_raise(Resolv::ResolvError)
        logic.raise_concerns
      end

      it 'blocks request when DNS fails (fail-closed)' do
        result = logic.process

        expect(result[:success]).to be false
        expect(result[:details][:error_code]).to eq('invalid_issuer')
      end
    end

    context 'when hostname resolves to IPv6 loopback' do
      let(:issuer_url) { 'https://ipv6loop.attacker.com/auth' }

      before do
        allow(Resolv).to receive(:getaddresses).with('ipv6loop.attacker.com').and_return(['::1'])
        logic.raise_concerns
      end

      it 'rejects hostname that resolves to IPv6 loopback' do
        result = logic.process

        expect(result[:success]).to be false
        expect(result[:details][:error_code]).to eq('invalid_issuer')
      end
    end
  end

  describe 'error sanitization' do
    let(:params) do
      {
        'extid' => 'ext-org-123',
        'provider_type' => 'oidc',
        'client_id' => 'test-client',
        'issuer' => 'https://auth.example.com',
      }
    end

    subject(:logic) { described_class.new(strategy_result, params) }

    it 'sanitizes IP addresses from error messages' do
      sanitizer = logic.send(:sanitize_error_message, 'Connection refused to 192.168.1.100:443')
      expect(sanitizer).to include('[IP]')
      expect(sanitizer).to include('[PORT]')
      expect(sanitizer).not_to include('192.168.1.100')
    end

    it 'truncates long error messages' do
      long_message = 'x' * 300
      sanitized = logic.send(:sanitize_error_message, long_message)
      expect(sanitized.length).to be <= 200
    end
  end

  describe '#success_data' do
    let(:params) do
      {
        'extid' => 'ext-org-123',
        'provider_type' => 'github',
        'client_id' => '12345678901234567890',
      }
    end

    subject(:logic) { described_class.new(strategy_result, params) }

    before do
      logic.raise_concerns
    end

    it 'includes user_id in response' do
      result = logic.process
      expect(result[:user_id]).to eq('ext-cust-123')
    end
  end
end
