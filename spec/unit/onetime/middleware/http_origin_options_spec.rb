# spec/unit/onetime/middleware/http_origin_options_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'rack'
require 'rack/protection'
require 'onetime/middleware/http_origin_options'

# Regression coverage: the HttpOrigin protection resolves the
# request host via Rack::Request#host (Host / X-Forwarded-Host), while the
# application's authoritative answer lives in env['onetime.display_domain']
# (DetectHost + DomainStrategy). Behind a proxy that rewrites Host to the
# canonical origin, every custom-domain POST used to 403 because Origin
# (custom domain) never matched Host (canonical origin).
#
# These specs run the real Rack::Protection::HttpOrigin with the shared
# allow_if, as both consumers mount it — the main app's Security stack and
# the auth app's production stack.
RSpec.describe Onetime::Middleware::HttpOriginOptions do
  let(:downstream) { ->(_env) { [200, { 'content-type' => 'text/plain' }, ['ok']] } }
  let(:app) do
    Rack::Protection::HttpOrigin.new(downstream, **described_class.options)
  end

  def post(path, headers)
    env = Rack::MockRequest.env_for(path, method: 'POST', **headers)
    app.call(env).first
  end

  # A proxy may rewrite Host to the canonical origin while DetectHost and
  # DomainStrategy resolve the true public host upstream.
  let(:canonical_host) { 'app.example.com' }
  let(:custom_domain)  { 'tenant.example.net' }

  describe 'custom domain behind a Host-rewriting proxy' do
    it 'allows a POST whose Origin matches the resolved display domain' do
      status = post('/auth/sso/entra',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => "https://#{custom_domain}",
        'onetime.display_domain' => custom_domain,
      )
      expect(status).to eq(200)
    end

    it 'denies a POST whose Origin does not match the display domain' do
      status = post('/auth/sso/entra',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => 'https://evil.example.org',
        'onetime.display_domain' => custom_domain,
      )
      expect(status).to eq(403)
    end

    it 'denies an http (non-TLS) Origin even for the correct display domain' do
      status = post('/auth/sso/entra',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => "http://#{custom_domain}",
        'onetime.display_domain' => custom_domain,
      )
      expect(status).to eq(403)
    end

    it 'denies an Origin with an appended port (exact match only)' do
      status = post('/auth/sso/entra',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => "https://#{custom_domain}:8443",
        'onetime.display_domain' => custom_domain,
      )
      expect(status).to eq(403)
    end
  end

  describe 'canonical host' do
    it 'still allows a same-origin POST (default HttpOrigin check)' do
      status = post('/signin',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => "http://#{canonical_host}",
        'onetime.display_domain' => canonical_host,
      )
      expect(status).to eq(200)
    end

    it 'still denies a cross-origin POST' do
      status = post('/signin',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => 'https://evil.example.org',
        'onetime.display_domain' => canonical_host,
      )
      expect(status).to eq(403)
    end
  end

  describe 'fail-closed behavior without a display domain' do
    it 'denies a mismatched Origin when display_domain is absent' do
      status = post('/auth/sso/entra',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => "https://#{custom_domain}",
      )
      expect(status).to eq(403)
    end

    it 'denies a mismatched Origin when display_domain is empty' do
      status = post('/auth/sso/entra',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => "https://#{custom_domain}",
        'onetime.display_domain' => '',
      )
      expect(status).to eq(403)
    end

    it 'does not blanket-allow when Origin is also empty' do
      # ALLOW_IF must not return true for '' == 'https://' style accidents.
      expect(described_class::ALLOW_IF.call(
        'onetime.display_domain' => '', 'HTTP_ORIGIN' => ''
      )).to be(false)
    end
  end

  describe 'GET requests' do
    it 'are never blocked (safe method)' do
      env = Rack::MockRequest.env_for('/auth/sso/entra',
        method: 'GET',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => 'https://evil.example.org',
      )
      expect(app.call(env).first).to eq(200)
    end
  end

  # Sign in with Apple is the first provider whose callback is a POST
  # (response_mode=form_post). Every earlier provider used a GET callback,
  # which `safe?` short-circuits, so HttpOrigin never saw one — and an
  # unhandled Apple callback is a 403 raised before OmniAuth runs, with no
  # failure redirect and nothing in the auth log to explain it.
  describe 'form_post SSO callback from a configured IdP' do
    let(:apple_origin) { 'https://appleid.apple.com' }

    def stub_idp_origins(origins)
      allow(Onetime).to receive(:auth_config)
        .and_return(instance_double('AuthConfig', sso_idp_origins: origins))
    end

    it 'allows a POST callback whose Origin is a configured IdP' do
      stub_idp_origins([apple_origin])
      status = post('/auth/sso/apple/callback',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => apple_origin,
      )
      expect(status).to eq(200)
    end

    it 'denies a POST callback from an IdP this deployment has not configured' do
      # The allowance is an exact membership test, not "any https origin".
      stub_idp_origins([apple_origin])
      status = post('/auth/sso/apple/callback',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => 'https://appleid.apple.com.evil.example.org',
      )
      expect(status).to eq(403)
    end

    it 'denies a POST callback when no provider is configured' do
      stub_idp_origins([])
      status = post('/auth/sso/apple/callback',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => apple_origin,
      )
      expect(status).to eq(403)
    end

    # THE SCOPE THAT MATTERS. The REQUEST phase mints the account-bound
    # Connect intent nonce that authorizes attaching an identity to the
    # signed-in account. Granting it the callback's exemption would let an IdP
    # origin initiate that flow cross-site.
    it 'does NOT allow the request phase, only the callback' do
      stub_idp_origins([apple_origin])
      status = post('/auth/sso/apple',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => apple_origin,
      )
      expect(status).to eq(403)
    end

    it 'does not allow a nested path that merely ends in /callback' do
      stub_idp_origins([apple_origin])
      status = post('/auth/sso/apple/extra/callback',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => apple_origin,
      )
      expect(status).to eq(403)
    end

    it 'does not allow a non-SSO path from an IdP origin' do
      stub_idp_origins([apple_origin])
      status = post('/auth/login',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => apple_origin,
      )
      expect(status).to eq(403)
    end

    # SAML's HTTP-POST binding (#4450) is the same shape as Apple's
    # form_post: a cross-site POST to the callback, from the origin of the
    # IdP's SSO service URL. The route segment is operator-chosen
    # (SAML_ROUTE_NAME), which the path pattern must not care about.
    it 'allows a SAML HTTP-POST binding callback on an operator-named route' do
      stub_idp_origins(['https://login.idp.example.com'])
      status = post('/auth/sso/okta/callback',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => 'https://login.idp.example.com',
      )
      expect(status).to eq(200)
    end

    # /metadata, /slo and /spslo are omniauth-saml sub-paths under the same
    # prefix. None of them is a callback; none gets the exemption.
    %w[metadata slo spslo].each do |subpath|
      it "does not allow a cross-site POST to the SAML /#{subpath} sub-path" do
        stub_idp_origins(['https://login.idp.example.com'])
        status = post("/auth/sso/saml/#{subpath}",
          'HTTP_HOST' => canonical_host,
          'HTTP_ORIGIN' => 'https://login.idp.example.com',
        )
        expect(status).to eq(403)
      end
    end

    it 'fails closed when auth_config cannot answer' do
      allow(Onetime).to receive(:auth_config).and_raise(StandardError, 'boom')
      allow(OT).to receive(:lw)
      status = post('/auth/sso/apple/callback',
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => apple_origin,
      )
      expect(status).to eq(403)
    end
  end

  # #4450. A TENANT's SAML IdP posts the SAMLResponse to the tenant's own
  # custom domain. Its origin lives in a per-domain record, so it is not in
  # AuthConfig#sso_idp_origins; it is admitted per request, for the request's
  # own domain only, from the SAME resolution + origin derivation that
  # TenantCspExtras uses for form-action.
  describe 'form_post SSO callback from the request domain\'s own tenant IdP' do
    let(:tenant_idp_origin) { 'https://login.tenant-idp.example' }

    # The REAL origin derivation (tenant_origin_source -> origin_from_url),
    # with only the platform set stubbed empty: what is pinned here is that
    # HttpOrigin admits exactly what AuthConfig#tenant_idp_origin answers.
    let(:auth_config) do
      Onetime::AuthConfig.send(:allocate).tap { |config| allow(config).to receive(:sso_idp_origins).and_return([]) }
    end

    def concealed(plaintext)
      Class.new { define_method(:reveal) { |&block| block.call(plaintext) } }.new
    end

    def saml_config(url = 'https://login.tenant-idp.example/app/sso/saml')
      double('CustomDomain::SsoConfig', provider_type: 'saml', idp_sso_service_url: concealed(url))
    end

    # @param sso_config [Object, nil] what the availability ladder resolved
    def stub_resolution(sso_config, for_domain: custom_domain)
      allow(Onetime::TenantSsoResolution).to receive(:for) do |env|
        resolved = env['onetime.display_domain'] == for_domain ? sso_config : nil
        instance_double(Onetime::TenantSsoResolution, sso_config: resolved)
      end
    end

    before { allow(Onetime).to receive(:auth_config).and_return(auth_config) }

    def tenant_callback(origin:, path: '/auth/sso/saml/callback', display_domain: custom_domain)
      post(path,
        'HTTP_HOST' => canonical_host,
        'HTTP_ORIGIN' => origin,
        'onetime.display_domain' => display_domain,
      )
    end

    it 'allows the callback POST from the tenant IdP\'s SSO service origin' do
      stub_resolution(saml_config)

      expect(tenant_callback(origin: tenant_idp_origin)).to eq(200)
    end

    it 'admits the origin of the SSO service URL, not of the EntityID' do
      stub_resolution(saml_config)

      expect(tenant_callback(origin: 'https://entity.tenant-idp.example')).to eq(403)
    end

    it 'denies another tenant\'s IdP origin on this domain' do
      stub_resolution(saml_config, for_domain: 'other-tenant.example.net')

      expect(tenant_callback(origin: tenant_idp_origin)).to eq(403)
    end

    it 'denies when the domain has no AVAILABLE tenant SSO config' do
      stub_resolution(nil)

      expect(tenant_callback(origin: tenant_idp_origin)).to eq(403)
    end

    it 'denies without a display domain (never falls back to the Host header)' do
      stub_resolution(saml_config, for_domain: '')

      expect(tenant_callback(origin: tenant_idp_origin, display_domain: '')).to eq(403)
      expect(Onetime::TenantSsoResolution).not_to have_received(:for)
    end

    it 'does NOT allow the request phase or a SAML sub-path' do
      stub_resolution(saml_config)

      %w[/auth/sso/saml /auth/sso/saml/metadata /auth/sso/saml/slo].each do |path|
        expect(tenant_callback(origin: tenant_idp_origin, path: path)).to eq(403), path
      end
    end

    it 'does not resolve the tenant at all for a same-origin POST' do
      stub_resolution(saml_config)

      post('/api/v3/anything', 'HTTP_HOST' => canonical_host, 'HTTP_ORIGIN' => "https://#{canonical_host}")

      expect(Onetime::TenantSsoResolution).not_to have_received(:for)
    end

    it 'denies an unreadable (undecryptable) SSO service URL' do
      unreadable = Class.new { def reveal = raise(Familia::EncryptionError, 'tag') }.new
      stub_resolution(double('CustomDomain::SsoConfig', provider_type: 'saml', idp_sso_service_url: unreadable))

      expect(tenant_callback(origin: tenant_idp_origin)).to eq(403)
    end

    it 'fails closed when the tenant resolution raises' do
      allow(Onetime::TenantSsoResolution).to receive(:for).and_raise(Redis::CannotConnectError)
      allow(OT).to receive(:lw)

      expect(tenant_callback(origin: tenant_idp_origin)).to eq(403)
      expect(OT).to have_received(:lw).with(/tenant SSO callback origin check failed: Redis::CannotConnectError/)
    end

    # Parity: the two tenant consumers cannot disagree, because this one asks
    # the question TenantCspExtras asks. An OIDC tenant's issuer origin is
    # therefore admitted too — harmless (its callback is a GET) and the price
    # of having ONE answer.
    it 'admits exactly AuthConfig#tenant_idp_origin for any record-derived type' do
      oidc = double('CustomDomain::SsoConfig', provider_type: 'oidc', issuer: 'https://idp.tenant.example/realms/x')
      stub_resolution(oidc)

      expect(tenant_callback(origin: auth_config.tenant_idp_origin(oidc), path: '/auth/sso/oidc/callback')).to eq(200)
    end
  end

  describe 'consumers' do
    it 'is wired into the Security stack HttpOrigin component' do
      require 'onetime/middleware/security'
      options = Onetime::Middleware::Security.middleware_components['HttpOrigin'][:options]
      expect(options[:allow_if]).to eq(described_class::ALLOW_IF)
    end
  end
end
