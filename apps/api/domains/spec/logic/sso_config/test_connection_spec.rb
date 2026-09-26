# apps/api/domains/spec/logic/sso_config/test_connection_spec.rb
#
# frozen_string_literal: true

# Unit tests for TestConnection's SSRF-pinned discovery fetch.
#
# The shared Onetime::SsoProvider::DiscoveryFetcher resolves + validates the
# issuer host ONCE through the egress guard (Onetime::Http::Guard) and pins
# the dial to that exact IP via Net::HTTP#ipaddr=, closing the
# validate-then-reresolve DNS-rebinding window. valid_issuer_host? remains
# upstream as a cheap early rejection, but the fetcher is the enforcement
# point — it also covers test_entra_id_connection, which never passes
# through valid_issuer_host?.
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

    # Upstream valid_issuer_host? resolves the host via Resolv.getaddresses and
    # now fails closed on empty resolution. Stub it to a public IP so the
    # save-time check passes and these tests exercise the fetcher's pinned guard
    # (the enforcement point). Guard.resolve_addresses is the separately-stubbed
    # fetch-time seam, so a test can model DNS rebinding: public at check time,
    # something else at fetch time.
    allow(Resolv).to receive(:getaddresses).and_return(['203.0.113.10'])

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

  # A real Net::HTTPOK whose streamed body (read_body with a block, as the
  # fetcher reads it under its size cap) yields +body+.
  def success_response(body)
    Net::HTTPOK.new('1.1', '200', 'OK').tap do |response|
      allow(response).to receive(:read_body) { |&blk| blk.call(body) }
    end
  end

  # Net::HTTP#request yields the response to the block before the body is
  # read. Each outcome is either a response (yielded and returned) or an
  # exception class (raised). The last outcome repeats.
  def respond_with(*outcomes)
    queue = outcomes.dup
    allow(http_instance).to receive(:request) do |_request, &blk|
      outcome = queue.size > 1 ? queue.shift : queue.first
      raise outcome if outcome.is_a?(Class) && outcome <= Exception

      blk&.call(outcome)
      outcome
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
        respond_with(success_response(discovery_body))
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

    context 'when the first validated address is unreachable' do
      let(:discovery_body) do
        {
          issuer: issuer,
          authorization_endpoint: "#{issuer}/authorize",
          token_endpoint: "#{issuer}/token",
          jwks_uri: "#{issuer}/jwks",
        }.to_json
      end

      before do
        stub_issuer_resolution(['203.0.113.10', '203.0.113.11'])
        respond_with(Errno::ECONNREFUSED, success_response(discovery_body))
      end

      it 'falls back to the next validated address, each dial still pinned' do
        result = logic.send(:test_oidc_connection)

        expect(result[:success]).to be true
        expect(http_instance).to have_received(:ipaddr=).with('203.0.113.10').ordered
        expect(http_instance).to have_received(:ipaddr=).with('203.0.113.11').ordered
      end
    end
  end

  describe 'OIDC discovery issuer comparison' do
    before { stub_issuer_resolution(['203.0.113.10']) }

    def discovery_body_for(discovered_issuer)
      {
        issuer: discovered_issuer,
        authorization_endpoint: 'https://idp.example.com/authorize',
        token_endpoint: 'https://idp.example.com/token',
        jwks_uri: 'https://idp.example.com/jwks',
      }.to_json
    end

    def run_with_discovered(discovered_issuer)
      respond_with(success_response(discovery_body_for(discovered_issuer)))
      logic.send(:test_oidc_connection)
    end

    context 'when the configured issuer matches exactly' do
      it 'succeeds and reports the discovered issuer' do
        result = run_with_discovered('https://idp.example.com')

        expect(result[:success]).to be true
        expect(result[:details][:issuer]).to eq('https://idp.example.com')
      end
    end

    context 'when the configured issuer has a trailing slash and matches exactly' do
      let(:issuer) { 'https://tenant.auth0.com/' }

      it 'succeeds' do
        result = run_with_discovered('https://tenant.auth0.com/')

        expect(result[:success]).to be true
        # The well-known path is built without doubling the slash.
        expect(Net::HTTP).to have_received(:new).with('tenant.auth0.com', 443, nil)
      end
    end

    context 'when discovery adds a trailing slash the configured issuer lacks' do
      let(:issuer) { 'https://tenant.auth0.com' }

      it 'fails with issuer_mismatch and both values' do
        result = run_with_discovered('https://tenant.auth0.com/')

        expect(result[:success]).to be false
        expect(result[:provider_type]).to eq('oidc')
        expect(result[:details]).to eq(
          error_code: 'issuer_mismatch',
          configured_issuer: 'https://tenant.auth0.com',
          discovery_issuer: 'https://tenant.auth0.com/',
        )
        expect(result[:message]).to include('compared exactly')
        expect(result[:message]).to include('trailing slash')
      end
    end

    context 'when the configured issuer has a trailing slash discovery lacks' do
      let(:issuer) { 'https://idp.example.com/' }

      it 'fails with issuer_mismatch' do
        result = run_with_discovered('https://idp.example.com')

        expect(result[:success]).to be false
        expect(result[:details][:error_code]).to eq('issuer_mismatch')
        expect(result[:details][:configured_issuer]).to eq('https://idp.example.com/')
        expect(result[:details][:discovery_issuer]).to eq('https://idp.example.com')
      end
    end

    it 'fails with issuer_mismatch on any other textual difference' do
      result = run_with_discovered('https://login.example.com')

      expect(result[:details][:error_code]).to eq('issuer_mismatch')
      expect(result[:details][:discovery_issuer]).to eq('https://login.example.com')
    end

    it 'fails with issuer_mismatch on a case-only difference' do
      expect(run_with_discovered('https://IDP.example.com')[:details][:error_code]).to eq('issuer_mismatch')
    end

    it 'fails with issuer_mismatch and a nil discovery_issuer for a non-string issuer' do
      result = run_with_discovered(['https://idp.example.com'])

      expect(result[:details][:error_code]).to eq('issuer_mismatch')
      expect(result[:details][:discovery_issuer]).to be_nil
    end

    it 'still reports a missing issuer as invalid_discovery' do
      result = run_with_discovered('')

      expect(result[:details][:error_code]).to eq('invalid_discovery')
      expect(result[:details][:missing_fields]).to eq(['issuer'])
    end
  end

  describe 'fetch outcome to error_code mapping' do
    before { stub_issuer_resolution(['203.0.113.10']) }

    def error_response(klass, code, message)
      klass.new('1.1', code, message).tap do |response|
        allow(response).to receive(:read_body)
      end
    end

    it 'maps 404 to discovery_not_found with the URL' do
      respond_with(error_response(Net::HTTPNotFound, '404', 'Not Found'))

      result = logic.send(:test_oidc_connection)

      expect(result[:message]).to eq('OIDC discovery document not found')
      expect(result[:details]).to eq(
        error_code: 'discovery_not_found',
        http_status: 404,
        url: 'https://idp.example.com/.well-known/openid-configuration',
      )
    end

    it 'maps a redirect to http_error without following it' do
      respond_with(error_response(Net::HTTPMovedPermanently, '301', 'Moved Permanently'))

      result = logic.send(:test_oidc_connection)

      expect(result[:details]).to eq(error_code: 'http_error', http_status: 301, description: 'Moved Permanently')
      expect(http_instance).to have_received(:request).once
    end

    it 'maps an oversize document to discovery_too_large' do
      response = success_response('x' * ((256 * 1024) + 1))
      respond_with(response)

      result = logic.send(:test_oidc_connection)

      expect(result[:success]).to be false
      expect(result[:details][:error_code]).to eq('discovery_too_large')
      expect(result[:details][:max_bytes]).to eq(256 * 1024)
    end

    it 'maps timeouts to timeout with the configured budget' do
      respond_with(Net::ReadTimeout)

      result = logic.send(:test_oidc_connection)

      expect(result[:details][:error_code]).to eq('timeout')
      expect(result[:details][:timeout_seconds]).to eq(10)
    end

    it 'maps TLS failures to ssl_error with a sanitized description' do
      allow(http_instance).to receive(:request).and_raise(OpenSSL::SSL::SSLError, 'SSL_connect 203.0.113.10:443 failed')

      result = logic.send(:test_oidc_connection)

      expect(result[:details][:error_code]).to eq('ssl_error')
      expect(result[:details][:description]).not_to include('203.0.113.10')
    end

    it 'maps exhausted connection attempts to unexpected_error' do
      respond_with(Errno::ECONNREFUSED)

      result = logic.send(:test_oidc_connection)

      expect(result[:details][:error_code]).to eq('unexpected_error')
      expect(OT).to have_received(:le).with(/Errno::ECONNREFUSED/)
    end

    it 'maps invalid JSON to invalid_json' do
      respond_with(success_response('<html>'))

      expect(logic.send(:test_oidc_connection)[:details][:error_code]).to eq('invalid_json')
    end

    it 'sends the Test Connection user agent' do
      sent = nil
      response = error_response(Net::HTTPNotFound, '404', 'Not Found')
      allow(http_instance).to receive(:request) do |request, &blk|
        sent = request
        blk&.call(response)
        response
      end

      logic.send(:test_oidc_connection)

      expect(sent.path).to eq('/.well-known/openid-configuration')
      expect(sent['User-Agent']).to eq('OneTimeSecret-SSO-Test/1.0')
      expect(sent['Accept']).to eq('application/json')
    end
  end

  describe '#test_entra_id_connection' do
    # Entra's discovery URL is built from the tenant, not the issuer, and
    # never passes through valid_issuer_host? — the fetcher's guard is the
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
      respond_with(success_response(body))

      result = logic.send(:test_entra_id_connection)

      # Entra has no configured issuer; the discovered one (here unrelated
      # to any input) is never compared.
      expect(result[:success]).to be true
      expect(result[:details][:issuer]).to eq('https://login.microsoftonline.com/x/v2.0')
      expect(Net::HTTP).to have_received(:new).with('login.microsoftonline.com', 443, nil)
      expect(http_instance).to have_received(:ipaddr=).with('203.0.113.20')
    end
  end

  # #4450. SAML's "connection test" is LOCAL validation: there is no discovery
  # document to fetch and the SSO service URL is only ever visited by the
  # user's browser. It must never open a connection.
  describe '#test_saml_configuration' do
    require_relative '../../../../../web/auth/spec/support/domain_sso_test_fixtures'
    include DomainSsoTestFixtures

    let(:provider_type) { 'saml' }
    let(:sso_url)   { 'https://idp.example.com/saml/sso' }
    let(:entity_id) { 'https://idp.example.com/saml/metadata' }
    let(:cert_pem)  { DomainSsoTestFixtures.saml_cert_pem }

    let(:logic) do
      described_class.allocate.tap do |instance|
        instance.instance_variable_set(:@provider_type, provider_type)
        instance.instance_variable_set(:@idp_sso_service_url, sso_url)
        instance.instance_variable_set(:@idp_entity_id, entity_id)
        instance.instance_variable_set(:@idp_cert, cert_pem)
        instance.instance_variable_set(:@name_id_format, Onetime::SsoProvider::Saml::PERSISTENT_NAME_ID_FORMAT)
        instance.instance_variable_set(:@callback_origins, [])
      end
    end

    let(:result) { logic.send(:test_saml_configuration) }

    # The shipped test config carries same_site: lax; the cookie rule is
    # exercised in its own context below.
    def stub_session_cookie(same_site:, secure:)
      allow(Onetime).to receive(:session_config).and_wrap_original do |original|
        original.call.merge('same_site' => same_site, 'secure' => secure)
      end
    end

    before { stub_session_cookie(same_site: 'none', secure: true) }

    # Test and save must agree (SamlFields#reject_incompatible_session_cookie!
    # refuses the PUT): a green Test followed by a 422 on save is the
    # disagreement the class comment promises not to produce.
    context 'under a session cookie SAML cannot use' do
      before { stub_session_cookie(same_site: 'lax', secure: false) }

      it 'fails on provider_type, naming the settings, before looking at the trio' do
        expect(result[:success]).to be false
        expect(result[:details]).to include(error_code: 'session_cookie_incompatible', field: 'provider_type')
        expect(result[:message]).to include("same_site is 'lax'").and include('secure is false')
      end

      it 'never opens a network connection' do
        result

        expect(Net::HTTP).not_to have_received(:new)
      end
    end

    it 'succeeds for a valid trio and reports the certificate expiry' do
      expect(result[:success]).to be true
      expect(result[:provider_type]).to eq('saml')
      expect(result[:details]).to include(
        idp_entity_id: entity_id,
        idp_sso_service_url: sso_url,
        certificate_subject: 'CN=fixture-idp.example.com',
        certificate_expires_in_days: 0,
      )
      expect(Time.iso8601(result[:details][:certificate_not_after])).to be > Time.now
    end

    it 'never opens a network connection' do
      result

      expect(Net::HTTP).not_to have_received(:new)
    end

    it 'says so: the IdP was not contacted' do
      expect(result[:message]).to include('not contacted')
    end

    context 'with an http SSO URL' do
      let(:sso_url) { 'http://idp.example.com/saml/sso' }

      it 'fails with invalid_sso_url, naming the field' do
        expect(result[:success]).to be false
        expect(result[:details]).to include(error_code: 'invalid_sso_url', field: 'idp_sso_service_url')
        expect(result[:message]).to eq('IdP SSO service URL must be an https:// URL')
      end
    end

    # The server never fetches the SSO URL (the browser is redirected to
    # it), so it gets no SSRF host check: an IdP on a private network is a
    # legitimate configuration. What is checked is that its ORIGIN is one
    # the CSP form-action / HttpOrigin allowances can carry.
    context 'with an SSO URL whose host resolves to a private address' do
      before { allow(Resolv).to receive(:getaddresses).and_return(['10.0.0.5']) }

      it 'succeeds without resolving the host' do
        expect(result[:success]).to be true
        expect(Resolv).not_to have_received(:getaddresses)
      end
    end

    context 'with an SSO URL whose host would break the CSP form-action directive' do
      let(:sso_url) { 'https://idp.example.com;/saml/sso' }

      it 'fails with invalid_sso_url, naming the field, without echoing the host' do
        expect(result[:success]).to be false
        expect(result[:details]).to include(error_code: 'invalid_sso_url', field: 'idp_sso_service_url')
        expect(result[:message]).to include('plain hostname')
        expect(result.inspect).not_to include('idp.example.com;')
      end
    end

    # otto's normalize_origin strips one trailing dot, so the admitted origin
    # would be 'https://idp.example.com' while the IdP's HTTP-POST callback
    # carries Origin 'https://idp.example.com.' — every callback would 403.
    context 'with an SSO URL whose host ends with a dot' do
      let(:sso_url) { 'https://idp.example.com./saml/sso' }

      it 'fails with invalid_sso_url, naming the field' do
        expect(result[:success]).to be false
        expect(result[:details]).to include(error_code: 'invalid_sso_url', field: 'idp_sso_service_url')
        expect(result[:message]).to eq('IdP SSO service URL host must not end with a dot')
      end
    end

    context 'with an EntityID containing a control character' do
      let(:entity_id) { "https://idp.example.com/\u0000metadata" }

      it 'fails with invalid_entity_id' do
        expect(result[:details]).to include(error_code: 'invalid_entity_id', field: 'idp_entity_id')
      end
    end

    context 'with a fingerprint where the certificate belongs' do
      let(:cert_pem) { 'AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01' }

      it 'fails with invalid_certificate' do
        expect(result[:success]).to be false
        expect(result[:details]).to include(error_code: 'invalid_certificate', field: 'idp_cert')
        expect(result[:details]).not_to have_key(:certificate_not_after)
      end
    end

    context 'with an expired certificate' do
      let(:cert_pem) { expired_saml_cert_pem }

      it 'fails with certificate_expired and reports when it expired' do
        expect(result[:success]).to be false
        expect(result[:details][:error_code]).to eq('certificate_expired')
        expect(Time.iso8601(result[:details][:certificate_not_after])).to be < Time.now
        expect(result[:message]).to match(/IdP certificate expired on \d{4}-\d{2}-\d{2}/)
      end
    end

    # ruby-saml drops a not-yet-valid certificate from the trust set exactly
    # as it drops an expired one (Utils.is_cert_active), so a green test here
    # followed by a saved record that refuses every sign-in is the
    # disagreement the class comment promises not to produce.
    context 'with a certificate that is not yet valid' do
      let(:cert_pem) { not_yet_valid_saml_cert_pem }

      it 'fails with certificate_not_yet_valid and reports when it becomes valid' do
        expect(result[:success]).to be false
        expect(result[:details]).to include(error_code: 'certificate_not_yet_valid', field: 'idp_cert')
        expect(Time.iso8601(result[:details][:certificate_not_before])).to be > Time.now
        expect(Time.iso8601(result[:details][:certificate_not_after])).to be > Time.now
        expect(result[:message]).to match(/IdP certificate is not valid until \d{4}-\d{2}-\d{2}T/)
      end

      it 'never opens a network connection' do
        result

        expect(Net::HTTP).not_to have_received(:new)
      end
    end
  end
end
