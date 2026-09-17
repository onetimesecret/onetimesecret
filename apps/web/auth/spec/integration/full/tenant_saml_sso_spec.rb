# apps/web/auth/spec/integration/full/tenant_saml_sso_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full Rack stack, real Rodauth, real Onetime::Session)
# =============================================================================
#
# Tenant SAML SSO end to end (#4450).
#
# Drives the REAL OmniAuth::Strategies::RequestBoundSAML — not OmniAuth
# test_mode — through rodauth-omniauth on a tenant custom domain:
#
#   POST /auth/sso/saml            tenant hook injects the domain's IdP trio
#                                  and per-request SP identifiers; the strategy
#                                  redirects to the IdP with an AuthnRequest
#   POST /auth/sso/saml/callback   a REAL signed response (SamlSpec::TestIdp)
#                                  answering that AuthnRequest
#
# and asserts what the whole feature exists to guarantee:
#
#   1. the identity row is keyed (route, idp_entity_id, uid) — the issuer
#      column holds the TENANT's IdP EntityID, never '' and never our own SP
#      EntityID;
#   2. two tenants whose IdPs assert the SAME NameID get two identities and
#      two accounts (no cross-tenant collapse);
#   3. a response signed by tenant A's IdP is refused on tenant B, whether it
#      names A's EntityID honestly or forges B's;
#   4. the SP metadata served on a tenant host names that tenant's identifiers,
#      and a host with no resolvable tenant config emits none.
#
# The route exists because ORGS_SSO_ENABLED=true registers the saml
# PLACEHOLDER (blank trust anchors) at boot; no platform SAML_* var is set in
# any lane, so every usable value below came from the tenant record.
#
# REQUIREMENTS:
# - Valkey on 2163, AUTHENTICATION_MODE=full, ORGS_SSO_ENABLED=true
#
# RUN:
#   tests/lanes/run full-sqlite --only apps/web/auth/spec/integration/full/tenant_saml_sso_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../../../../../spec/support/saml/test_idp'

require 'base64'
require 'cgi'
require 'zlib'

# Namespaced: a constant assigned inside an RSpec.describe block lands on
# Object, and other specs in this lane already define a top-level `Tenant`.
module TenantSamlSsoSpec
  Tenant       = Struct.new(:host, :org, :owner, :domain, :idp, :sso_url, keyword_init: true)
  AuthnRequest = Struct.new(:id, :acs_url, :sp_entity_id, :destination, keyword_init: true)
end

# :shared_db_state — fixtures are built per example under unique ids and torn
# down in `after`; see tenant_sso_proxy_host_spec.rb for why the per-example
# Valkey flush cannot be relied on to run before `let!`.
RSpec.describe 'Tenant SAML SSO', :shared_db_state, type: :integration do
  include Rack::Test::Methods

  include_context 'domains enabled'

  before(:all) { boot_onetime_app }

  let(:db) { Auth::Database.connection }
  let(:identities) { db[:account_identities] }
  let(:run_id) { SecureRandom.hex(6) }

  # A tenant: organization + TXT-verified custom domain + saml SsoConfig
  # pointing at its OWN IdP (own keypair, own EntityID, own origin).
  def build_tenant(label)
    host  = "secrets-#{label}-#{run_id}.saml-tenant.example.com"
    owner = Onetime::Customer.new(email: "owner-#{label}-#{run_id}@saml-tenant.example.com")
    owner.save
    org = Onetime::Organization.create!("SAML Org #{label} #{run_id}", owner, "contact-#{label}-#{run_id}@saml-tenant.example.com")

    domain          = Onetime::CustomDomain.new(display_domain: host, org_id: org.org_id)
    # TXT-verified: Auth::PublicHost only roots auth URLs (and so the SAML
    # ACS / SP EntityID) on a domain whose ownership is proven.
    domain.verified = true
    domain.save
    Onetime::CustomDomain.display_domain_index.put(host, domain.domainid)

    idp     = SamlSpec::TestIdp.new(
      entity_id: "https://idp-#{label}.example.net/saml/metadata/#{run_id}",
      key: OpenSSL::PKey::RSA.new(2048),
    )
    sso_url = "https://login.idp-#{label}.example.net/saml/sso"

    Onetime::CustomDomain::SsoConfig.create!(
      domain_id: domain.identifier,
      provider_type: 'saml',
      display_name: "SAML #{label}",
      idp_sso_service_url: sso_url,
      idp_entity_id: idp.entity_id,
      idp_cert: idp.cert_pem,
      enabled: true,
    )

    TenantSamlSsoSpec::Tenant.new(host: host, org: org, owner: owner, domain: domain, idp: idp, sso_url: sso_url)
  end

  let!(:tenant_a) { build_tenant('a') }
  let!(:tenant_b) { build_tenant('b') }

  let(:created_emails) { [] }

  before do
    unless Onetime.auth_config.orgs_sso_enabled?
      skip 'ORGS_SSO_ENABLED not set at boot — /auth/sso/* routes are not registered'
    end
  end

  after do
    created_emails.each do |email|
      account_ids = db[:accounts].where(email: email).select_map(:id)
      identities.where(account_id: account_ids).delete
      db[:accounts].where(id: account_ids).delete
      Onetime::Customer.find_by_email(email)&.destroy!
    rescue StandardError => ex
      OT.le "[tenant_saml_sso_spec] cleanup error for #{OT::Utils.obscure_email(email)}: #{ex.class}"
    end

    [tenant_a, tenant_b].each do |tenant|
      Onetime::CustomDomain::SsoConfig.delete_for_domain!(tenant.domain.identifier) rescue nil
      Onetime::CustomDomain.display_domain_index.remove(tenant.host) rescue nil
      tenant.domain&.destroy! rescue nil
      tenant.org&.destroy! rescue nil
      tenant.owner&.destroy! rescue nil
    end
  end

  # ── flow helpers ──────────────────────────────────────────────────────────

  # Request phase on the tenant's host. Returns what the SP actually asked the
  # IdP for — the response below answers THAT, the way a real IdP would.
  def start_login(tenant)
    header 'Host', tenant.host
    post '/auth/sso/saml'

    expect(last_response.status).to eq(302), "request phase: #{last_response.status} #{last_response.body[0, 200]}"
    location = last_response.headers['Location'].to_s
    expect(location).to start_with("#{tenant.sso_url}?"), "expected a redirect to the tenant IdP, got #{location}"

    query = CGI.parse(URI.parse(location).query)
    xml   = Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(Base64.decode64(query.fetch('SAMLRequest').first))

    TenantSamlSsoSpec::AuthnRequest.new(
      id: xml[/<samlp:AuthnRequest[^>]*\sID=['"]([^'"]+)['"]/, 1],
      acs_url: xml[/AssertionConsumerServiceURL=['"]([^'"]+)['"]/, 1],
      sp_entity_id: xml[%r{<saml:Issuer[^>]*>([^<]+)</saml:Issuer>}, 1],
      destination: xml[/Destination=['"]([^'"]+)['"]/, 1],
    )
  end

  # Callback phase: the HTTP-POST binding, as the IdP's auto-submitting form
  # delivers it — a cross-site POST carrying the IdP's Origin.
  def post_callback(tenant, saml_response, origin: URI.join(tenant.sso_url, '/').to_s.chomp('/'))
    header 'Host', tenant.host
    header 'Origin', origin
    post '/auth/sso/saml/callback', { 'SAMLResponse' => saml_response }
  ensure
    header 'Origin', nil
  end

  def sign_in(tenant, name_id:, email:, idp: tenant.idp, **overrides)
    created_emails << email
    request = start_login(tenant)
    post_callback(tenant, idp.response(
      in_response_to: request.id, acs_url: request.acs_url, audience: request.sp_entity_id,
      name_id: name_id, attributes: { 'email' => [email] }, **overrides
    ))
  end

  def identity_rows(uid)
    identities.where(uid: uid).all
  end

  # ── request phase ─────────────────────────────────────────────────────────

  describe 'request phase on a tenant domain' do
    it 'sends the tenant IdP an AuthnRequest naming per-request SP identifiers on the PUBLIC host' do
      request = start_login(tenant_a)

      expect(request.id).not_to be_nil
      expect(request.destination).to eq(tenant_a.sso_url)
      expect(request.acs_url).to eq("http://#{tenant_a.host}/auth/sso/saml/callback")
      expect(request.sp_entity_id).to eq("http://#{tenant_a.host}/auth/sso/saml/metadata")
    end

    it 'follows a Host-rewriting proxy: identifiers name the tenant domain, not the origin target' do
      header 'Host', canonical_host
      header 'Apx-Incoming-Host', tenant_a.host
      post '/auth/sso/saml'
      header 'Apx-Incoming-Host', nil

      xml = Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(
        Base64.decode64(CGI.parse(URI.parse(last_response.headers['Location']).query).fetch('SAMLRequest').first),
      )

      expect(xml).to include("#{tenant_a.host}/auth/sso/saml/callback")
      expect(xml).not_to include(canonical_host)
    end

    it 'refuses (never redirects to an IdP) when the stored certificate has expired' do
      config          = Onetime::CustomDomain::SsoConfig.find_by_domain_id(tenant_a.domain.identifier)
      config.idp_cert = SamlSpec::TestIdp.new(cert_not_after: Time.now - 60).cert_pem
      config.commit_fields

      header 'Host', tenant_a.host
      post '/auth/sso/saml'

      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('auth_error=sso_not_configured')
      expect(last_response.headers['Location']).not_to include('SAMLRequest')
    end
  end

  # ── callback: identity keying ─────────────────────────────────────────────

  describe 'callback with a signed response from the tenant IdP' do
    let(:name_id) { "nameid-#{run_id}" }
    let(:email_a) { "user-a-#{run_id}@saml-tenant.example.com" }
    let(:email_b) { "user-b-#{run_id}@saml-tenant.example.com" }

    it 'keys the identity on (route, IdP EntityID, NameID)' do
      sign_in(tenant_a, name_id: name_id, email: email_a)

      expect(last_response.status).to eq(302), last_response.body[0, 300]
      expect(last_response.headers['Location'].to_s).not_to include('auth_error')

      rows = identity_rows(name_id)
      expect(rows.size).to eq(1)
      expect(rows.first).to include(provider: 'saml', issuer: tenant_a.idp.entity_id, uid: name_id)

      account = db[:accounts].where(id: rows.first[:account_id]).first
      expect(account[:email]).to eq(email_a)
    end

    it 'never keys on the sentinel or on our own SP EntityID' do
      sign_in(tenant_a, name_id: name_id, email: email_a)

      issuer = identity_rows(name_id).first[:issuer]
      expect(issuer).not_to eq('')
      expect(issuer).not_to include(tenant_a.host)
    end

    it 'joins the JIT account to the tenant organization' do
      sign_in(tenant_a, name_id: name_id, email: email_a)

      customer = Onetime::Customer.find_by_email(email_a)
      expect(customer).not_to be_nil
      expect(tenant_a.org.member?(customer)).to be true
      expect(tenant_b.org.member?(customer)).to be false
    end

    it 'signs the same user in again through the same identity (no second row)' do
      sign_in(tenant_a, name_id: name_id, email: email_a)
      clear_cookies
      sign_in(tenant_a, name_id: name_id, email: email_a)

      expect(last_response.headers['Location'].to_s).not_to include('auth_error')
      expect(identity_rows(name_id).size).to eq(1)
    end

    # The takeover the issuer column exists to prevent: tenant B's IdP can
    # assert ANY NameID it likes, including one tenant A's IdP already issued.
    it 'gives a colliding NameID from another tenant IdP its own identity and account' do
      sign_in(tenant_a, name_id: name_id, email: email_a)
      clear_cookies
      sign_in(tenant_b, name_id: name_id, email: email_b)

      expect(last_response.headers['Location'].to_s).not_to include('auth_error')

      rows = identity_rows(name_id)
      expect(rows.map { |row| row[:issuer] }).to contain_exactly(tenant_a.idp.entity_id, tenant_b.idp.entity_id)
      expect(rows.map { |row| row[:account_id] }.uniq.size).to eq(2)
    end

    it 'consumes the pending request id: a second callback has nothing to answer' do
      sign_in(tenant_a, name_id: name_id, email: email_a)

      header 'Host', tenant_a.host
      post '/auth/sso/saml/callback', { 'SAMLResponse' => 'irrelevant' }

      expect(last_response.headers['Location'].to_s).to include('auth_error=sso_failed')
    end
  end

  # ── callback: cross-tenant refusal ────────────────────────────────────────

  describe 'a response signed by tenant A IdP, presented on tenant B' do
    let(:name_id) { "victim-#{run_id}" }
    let(:email)   { "victim-#{run_id}@saml-tenant.example.com" }

    def expect_refused
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location'].to_s).to include('auth_error=sso_failed')
      expect(identity_rows(name_id)).to be_empty
      expect(db[:accounts].where(email: email).count).to eq(0)
    end

    it 'is refused when it honestly names tenant A IdP as the issuer' do
      sign_in(tenant_b, name_id: name_id, email: email, idp: tenant_a.idp)

      expect_refused
    end

    it 'is refused when it forges tenant B IdP EntityID (signature does not verify against B certificate)' do
      sign_in(tenant_b, name_id: name_id, email: email, idp: tenant_a.idp,
        response_issuer: tenant_b.idp.entity_id, assertion_issuer: tenant_b.idp.entity_id)

      expect_refused
    end

    # The mirror image: a response that is entirely valid FOR TENANT A (A's
    # IdP, A's audience, A's ACS) delivered to tenant B's callback, answering
    # B's pending request id.
    it 'is refused when it is a valid tenant A response replayed at tenant B' do
      created_emails << email
      request_b = start_login(tenant_b)

      post_callback(tenant_b, tenant_a.idp.response(
        in_response_to: request_b.id,
        acs_url: "http://#{tenant_a.host}/auth/sso/saml/callback",
        audience: "http://#{tenant_a.host}/auth/sso/saml/metadata",
        name_id: name_id, attributes: { 'email' => [email] }
      ))

      expect_refused
    end

    it 'is refused without a pending AuthnRequest (IdP-initiated SSO is unsupported)' do
      created_emails << email

      post_callback(tenant_a, tenant_a.idp.response(
        in_response_to: nil,
        acs_url: "http://#{tenant_a.host}/auth/sso/saml/callback",
        audience: "http://#{tenant_a.host}/auth/sso/saml/metadata",
        name_id: name_id, attributes: { 'email' => [email] }
      ))

      expect_refused
    end

    it 'refuses a second presentation of the same assertion' do
      created_emails << email
      assertion_id = "_#{SecureRandom.uuid}"
      answer       = lambda do |request|
        tenant_a.idp.response(
          in_response_to: request.id, acs_url: request.acs_url, audience: request.sp_entity_id,
          name_id: name_id, attributes: { 'email' => [email] }, assertion_id: assertion_id
        )
      end

      post_callback(tenant_a, answer.call(start_login(tenant_a)))
      expect(last_response.headers['Location'].to_s).not_to include('auth_error')

      clear_cookies
      post_callback(tenant_a, answer.call(start_login(tenant_a)))
      expect(last_response.headers['Location'].to_s).to include('auth_error=sso_failed')
      expect(identity_rows(name_id).size).to eq(1)
    end
  end

  # ── HttpOrigin admission of the tenant IdP ────────────────────────────────
  #
  # Rack::Protection::HttpOrigin is not mounted in the test stack
  # (http_origin=false), so the callbacks above never met it. This drives the
  # allowance itself against the REAL records — TenantSsoResolution, the
  # AAD-bound encrypted SSO URL, and whichever auth_config the lane boots
  # (MockAuthConfig delegates to the production derivation). The middleware
  # wiring is pinned in spec/unit/onetime/middleware/http_origin_options_spec.rb.
  describe 'HttpOriginOptions tenant IdP admission' do
    def callback_env(host:, origin:, path: '/auth/sso/saml/callback')
      Rack::MockRequest.env_for("http://#{host}#{path}",
        :method => 'POST', 'HTTP_ORIGIN' => origin, 'onetime.display_domain' => host)
    end

    let(:origin_a) { 'https://login.idp-a.example.net' }
    let(:origin_b) { 'https://login.idp-b.example.net' }
    let(:options)  { Onetime::Middleware::HttpOriginOptions }

    it "admits the tenant's own IdP origin on the tenant's own host" do
      expect(options.sso_callback_from_tenant_idp?(callback_env(host: tenant_a.host, origin: origin_a))).to be true
      expect(options::ALLOW_IF.call(callback_env(host: tenant_a.host, origin: origin_a))).to be true
    end

    it "denies another tenant's IdP origin, in both directions" do
      expect(options.sso_callback_from_tenant_idp?(callback_env(host: tenant_a.host, origin: origin_b))).to be false
      expect(options.sso_callback_from_tenant_idp?(callback_env(host: tenant_b.host, origin: origin_a))).to be false
    end

    it 'denies the EntityID origin, the request phase and the canonical host' do
      entity_origin = 'https://idp-a.example.net'

      expect(options.sso_callback_from_tenant_idp?(callback_env(host: tenant_a.host, origin: entity_origin))).to be false
      expect(options.sso_callback_from_tenant_idp?(
        callback_env(host: tenant_a.host, origin: origin_a, path: '/auth/sso/saml'),
      )).to be false
      expect(options.sso_callback_from_tenant_idp?(callback_env(host: canonical_host, origin: origin_a))).to be false
    end

    it 'agrees with the CSP form-action origin for the same record' do
      config = Onetime::CustomDomain::SsoConfig.find_by_domain_id(tenant_a.domain.identifier)

      expect(Onetime.auth_config.tenant_idp_origin(config)).to eq(origin_a)
    end

    it 'stops admitting the origin once the tenant config is disabled' do
      Onetime::CustomDomain::SsoConfig.find_by_domain_id(tenant_a.domain.identifier).disable!

      expect(options.sso_callback_from_tenant_idp?(callback_env(host: tenant_a.host, origin: origin_a))).to be false
    end
  end

  # ── SP metadata sub-path ──────────────────────────────────────────────────

  describe 'GET /auth/sso/saml/metadata' do
    it 'serves the resolved tenant SP metadata' do
      header 'Host', tenant_a.host
      get '/auth/sso/saml/metadata'

      expect(last_response.status).to eq(200), last_response.body[0, 200]
      expect(last_response.body).to include('EntityDescriptor')
      expect(last_response.body).to include("http://#{tenant_a.host}/auth/sso/saml/metadata")
      expect(last_response.body).to include("http://#{tenant_a.host}/auth/sso/saml/callback")
    end

    # omniauth-saml's other_phase runs the tenant setup hook too. A bare GET
    # must not plant a pending tenant flow in the visitor's session — only the
    # request phase does (positive control below).
    it 'does not start a tenant flow' do
      header 'Host', tenant_a.host
      get '/auth/sso/saml/metadata'
      after_metadata = last_request.env['rack.session'].to_h.keys.map(&:to_s)

      post '/auth/sso/saml'
      after_request = last_request.env['rack.session'].to_h.keys.map(&:to_s)

      expect(after_metadata).not_to include('omniauth_tenant_domain_id', 'saml_authn_request_id')
      expect(after_request).to include('omniauth_tenant_domain_id', 'saml_authn_request_id')
    end

    it 'emits no metadata on the canonical host (placeholder registration, blank trust anchors)' do
      header 'Host', canonical_host
      get '/auth/sso/saml/metadata'

      expect(last_response.body).not_to include('EntityDescriptor')
      expect(last_response.status).to eq(404)
    end

    it 'emits no metadata for a tenant whose SSO config is disabled' do
      config = Onetime::CustomDomain::SsoConfig.find_by_domain_id(tenant_a.domain.identifier)
      config.disable!

      header 'Host', tenant_a.host
      get '/auth/sso/saml/metadata'

      expect(last_response.body).not_to include('EntityDescriptor')
      expect([302, 404]).to include(last_response.status)
    end

    it 'emits no metadata for a tenant whose trust anchor is unusable' do
      config          = Onetime::CustomDomain::SsoConfig.find_by_domain_id(tenant_a.domain.identifier)
      config.idp_cert = SamlSpec::TestIdp.new(cert_not_after: Time.now - 60).cert_pem
      config.commit_fields

      header 'Host', tenant_a.host
      get '/auth/sso/saml/metadata'

      expect(last_response.body).not_to include('EntityDescriptor')
      expect(last_response.headers['Location'].to_s).to include('auth_error=sso_not_configured')
    end
  end
end
