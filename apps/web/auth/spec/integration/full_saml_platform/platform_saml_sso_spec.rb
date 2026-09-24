# apps/web/auth/spec/integration/full_saml_platform/platform_saml_sso_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full Rack stack, real Rodauth, real Onetime::Session)
# =============================================================================
#
# PLATFORM SAML SSO end to end (#4450): the env-configured IdP on the
# canonical host, through the REAL OmniAuth::Strategies::RequestBoundSAML and
# rodauth-omniauth. The tenant twin (integration/full/tenant_saml_sso_spec.rb)
# cannot cover this surface: every shared lane boots the saml route as the
# tenant PLACEHOLDER and asserts the canonical host refuses. What only this
# file pins:
#
#   1. configure_provider's real-credential branch registers the route from
#      SAML_IDP_SSO_SERVICE_URL / SAML_IDP_ENTITY_ID / SAML_IDP_CERT;
#   2. Saml.platform_sp_entity_id remains the fixed AuthnRequest Issuer (and SP
#      metadata entityID), while the ACS URL follows the verified public host;
#   3. platform fallback on a verified custom domain completes a real signed
#      round trip without tenant config, tenant context, or an organization join;
#   4. a platform identity is keyed (route, BARE EntityID, NameID) — never ''
#      and never a tenant's domain-scoped key, so a tenant row that names the
#      same EntityID is not matched;
#   5. the InResponseTo binding, replay cache, issuer gate, signature-algorithm
#      gate, and unknown/unverified host checks still refuse;
#   6. an active tenant SAML configuration overrides the live platform config.
#
# OWN LANE. Auth::Config configures once per process and reads SAML_* then.
# The lane (tests/lanes/full-saml-platform) provides the three public strings
# AND the SAML-compatible session cookie (SESSION_COOKIE_SAME_SITE=none,
# SESSION_COOKIE_SECURE=true — under any other cookie Saml.platform_options
# raises and the provider is SKIPPED at boot); the IdP KEYPAIR is minted here
# at load time and its certificate installed in ENV before the first boot, so
# no key material is checked in. If the app is already booted when this file
# loads, the environment cannot take effect — that is a loud failure, not a
# skip.
#
# EVERY REQUEST IS https://. The Secure cookie is withheld by Rack::Test on
# http and dropped by Onetime::Session on a non-SSL request.
#
# The 'domains enabled' context is included ONLY by the off-host describe.
# With the domains feature on, DomainStrategy.canonical_host? consults the
# PARSED canonical set, which skips the test config's IP site.host
# (127.0.0.1:3000) — the tenant hook then treats the platform host itself as
# an unknown non-canonical host and redirects sso_not_configured before the
# strategy runs. With the feature off (this lane's default) site.host is
# canonical through the raw fallback, which is what the platform examples
# need; the off-host cases need the feature on for a canonical-SET peer
# (`canonical_host`, features.domains.default) and a custom domain.
#
# REQUIREMENTS:
# - Valkey on 2163, AUTHENTICATION_MODE=full, ORGS_SSO_ENABLED=true,
#   SAML_IDP_SSO_SERVICE_URL, SAML_IDP_ENTITY_ID, SESSION_COOKIE_SAME_SITE=none,
#   SESSION_COOKIE_SECURE=true (lane-provided)
#
# RUN:
#   tests/lanes/run full-saml-platform
#   tests/lanes/run full-saml-platform --only apps/web/auth/spec/integration/full_saml_platform/platform_saml_sso_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../../../../../spec/support/saml/test_idp'

require 'base64'
require 'cgi'
require 'zlib'

module PlatformSamlSsoSpec
  AuthnRequest = Struct.new(:id, :acs_url, :sp_entity_id, :destination, keyword_init: true)

  ENTITY_ID = ENV.fetch('SAML_IDP_ENTITY_ID', '').freeze
  SSO_URL   = ENV.fetch('SAML_IDP_SSO_SERVICE_URL', '').freeze

  # The platform IdP for this process. Built at load time so its certificate
  # is in ENV before any before(:all) boots the app.
  IDP = SamlSpec::TestIdp.new(entity_id: ENTITY_ID, key: OpenSSL::PKey::RSA.new(2048))

  if defined?(Onetime) && Onetime.respond_to?(:ready?) && Onetime.ready?
    raise 'platform_saml_sso_spec loaded after the app booted: SAML_IDP_CERT cannot take effect. ' \
          'Run it through tests/lanes/run full-saml-platform (own process).'
  end

  ENV['SAML_IDP_CERT'] = IDP.cert_pem
end

# :full_auth_mode is explicit, as in integration/full_mfa: the directory-derived
# tag (spec/spec_helper.rb) matches only /integration/full/, and that tag is
# what installs the full-mode suite database and MockAuthConfig before boot.
RSpec.describe 'Platform SAML SSO', :full_auth_mode, :shared_db_state, type: :integration,
  lane_env: { 'ORGS_SSO_ENABLED' => 'true', 'SAML_IDP_ENTITY_ID' => PlatformSamlSsoSpec::ENTITY_ID } do
  include Rack::Test::Methods

  before(:all) { boot_onetime_app }

  let(:db) { Auth::Database.connection }
  let(:identities) { db[:account_identities] }
  let(:run_id) { SecureRandom.hex(6) }
  let(:idp) { PlatformSamlSsoSpec::IDP }
  let(:entity_id) { PlatformSamlSsoSpec::ENTITY_ID }
  let(:name_id) { "platform-nameid-#{run_id}" }
  let(:email) { "platform-user-#{run_id}@saml-platform.example.com" }
  let(:created_emails) { [] }
  let(:platform_base) { Onetime::SsoProvider::Saml.platform_base_url }
  let(:platform_acs) { "#{platform_base}/auth/sso/saml/callback" }
  let(:platform_entity_id) { Onetime::SsoProvider::Saml.platform_sp_entity_id('saml') }

  after do
    created_emails.each do |address|
      account_ids = db[:accounts].where(email: address).select_map(:id)
      identities.where(account_id: account_ids).delete
      db[:accounts].where(id: account_ids).delete
      Onetime::Customer.find_by_email(address)&.destroy!
    rescue StandardError => ex
      OT.le "[platform_saml_sso_spec] cleanup error for #{OT::Utils.obscure_email(address)}: #{ex.class}"
    end
    identities.where(uid: name_id).delete
  end

  # ── flow helpers ──────────────────────────────────────────────────────────

  def start_login(base_url = platform_base, expected_sso_url: PlatformSamlSsoSpec::SSO_URL)
    post "#{base_url}/auth/sso/saml"

    expect(last_response.status).to eq(302), "request phase: #{last_response.status} #{last_response.body[0, 200]}"
    location = last_response.headers['Location'].to_s
    expect(location).to start_with("#{expected_sso_url}?"),
      "expected a redirect to #{expected_sso_url}, got #{location}"

    query = CGI.parse(URI.parse(location).query)
    xml   = Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(Base64.decode64(query.fetch('SAMLRequest').first))

    PlatformSamlSsoSpec::AuthnRequest.new(
      id: xml[/<samlp:AuthnRequest[^>]*\sID=['"]([^'"]+)['"]/, 1],
      acs_url: xml[/AssertionConsumerServiceURL=['"]([^'"]+)['"]/, 1],
      sp_entity_id: xml[%r{<saml:Issuer[^>]*>([^<]+)</saml:Issuer>}, 1],
      destination: xml[/Destination=['"]([^'"]+)['"]/, 1],
    )
  end

  def post_callback(saml_response, acs_url = platform_acs)
    header 'Origin', 'https://login.platform-idp.test'
    post acs_url, { 'SAMLResponse' => saml_response }
  ensure
    header 'Origin', nil
  end

  def pending_request_id
    last_request.env['rack.session'].to_h[OmniAuth::Strategies::RequestBoundSAML::REQUEST_ID_KEY]
  end

  def answer(request, signer: idp, **overrides)
    signer.response(
      in_response_to: request.id, acs_url: request.acs_url, audience: request.sp_entity_id,
      name_id: name_id, attributes: { 'email' => [email] }, **overrides
    )
  end

  def sign_in(base_url: platform_base, **overrides)
    created_emails << email
    request = start_login(base_url)
    post_callback(answer(request, **overrides), request.acs_url)
  end

  def identity_rows
    identities.where(uid: name_id).all
  end

  def expect_refused
    expect(last_response.status).to eq(302)
    expect(last_response.headers['Location'].to_s).to include('auth_error=sso_failed')
    expect(identity_rows).to be_empty
    expect(db[:accounts].where(email: email).count).to eq(0)
  end

  # ── registration and request phase ────────────────────────────────────────

  describe 'registration from the environment' do
    it 'registered the saml route with the real trust anchors (not the placeholder)' do
      # The lane's cookie env is load-bearing: any other cookie skips the provider.
      expect(Onetime::SsoProvider::Saml.session_cookie_problem).to be_nil
      expect(Onetime::SsoProvider::Saml.platform_usable?).to be true

      request = start_login
      expect(request.id).not_to be_nil
      expect(request.destination).to eq(PlatformSamlSsoSpec::SSO_URL)
      expect(pending_request_id).to eq(request.id)
    end

    it 'names the pinned platform ACS URL and the derived platform SP EntityID as Issuer' do
      request = start_login

      expect(request.acs_url).to eq(platform_acs)
      expect(request.acs_url).to eq(Onetime::SsoProvider::Saml.platform_acs_url('saml'))
      expect(request.sp_entity_id).to eq(platform_entity_id)
      expect(request.sp_entity_id).to end_with('/auth/sso/saml/metadata')
      expect(request.sp_entity_id).not_to be_empty
      expect(URI.parse(request.acs_url).host).to eq(URI.parse(request.sp_entity_id).host)
    end

    it 'serves SP metadata naming the platform SP EntityID and the pinned ACS URL' do
      get "#{platform_base}/auth/sso/saml/metadata"

      expect(last_response.status).to eq(200), last_response.body[0, 200]
      expect(last_response.body).to include('EntityDescriptor')
      expect(last_response.body).to match(/entityID=['"]#{Regexp.escape(platform_entity_id)}['"]/)
      expect(last_response.body).to include(platform_acs)
      expect(last_response.body).not_to include(DomainsEnabledContext::CANONICAL_HOST)
    end
  end

  # ── custom-domain platform fallback ───────────────────────────────────────

  describe 'off the platform host' do
    include_context 'domains enabled'

    def expect_refused_before_the_idp(error: 'sso_failed')
      expect(last_response.status).to eq(302), "#{last_response.status} #{last_response.body[0, 200]}"
      expect(last_response.headers['Location'].to_s).to include("auth_error=#{error}")
      expect(last_response.headers['Location'].to_s).not_to include('SAMLRequest')
      expect(pending_request_id).to be_nil
    end

    it 'refuses a start on a secondary canonical-set host (not site.host)' do
      expect(Onetime::Middleware::DomainStrategy.canonical_host?(canonical_host)).to be true
      expect(Onetime::SsoProvider::Saml.platform_host?(canonical_host)).to be false

      post "https://#{canonical_host}/auth/sso/saml"

      expect_refused_before_the_idp
    end

    it 'completes platform fallback on a verified custom domain without tenant context or organization join' do
      tenant_host = "fallback-#{run_id}.saml-platform.example.com"
      tenant_base = "https://#{tenant_host}"
      owner        = Onetime::Customer.new(email: "fallback-owner-#{run_id}@saml-platform.example.com")
      owner.save
      org          = Onetime::Organization.create!("Fallback Org #{run_id}", owner, "fallback-contact-#{run_id}@saml-platform.example.com")
      domain       = Onetime::CustomDomain.new(display_domain: tenant_host, org_id: org.org_id)
      domain.verified = true
      domain.save
      Onetime::CustomDomain.display_domain_index.put(tenant_host, domain.domainid)
      allow(Onetime.auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
      allow(Auth::Operations::JoinDomainOrganization).to receive(:new).and_call_original

      begin
        expect(Onetime::CustomDomain::SsoConfig.find_by_domain_id(domain.identifier)).to be_nil

        request = start_login(tenant_base)
        session = last_request.env['rack.session'].to_h
        expect(request.acs_url).to eq("#{tenant_base}/auth/sso/saml/callback")
        expect(request.sp_entity_id).to eq(platform_entity_id)
        expect(session['omniauth_tenant_domain_id'] || session[:omniauth_tenant_domain_id]).to be_nil

        created_emails << email
        post_callback(answer(request), request.acs_url)

        expect(last_response.status).to eq(302), last_response.body[0, 300]
        expect(last_response.headers['Location'].to_s).not_to include('auth_error')
        expect(identity_rows).to contain_exactly(include(provider: 'saml', issuer: entity_id, uid: name_id))
        expect(last_request.env['rack.session'].to_h['validated_omniauth_domain_id']).to be_nil
        expect(Auth::Operations::JoinDomainOrganization).not_to have_received(:new)
        customer = Onetime::Customer.find_by_email(email)
        expect(customer).not_to be_nil
        expect(Onetime::OrganizationMembership.find_by_org_customer(org.objid, customer.objid)).to be_nil
      ensure
        Onetime::CustomDomain.display_domain_index.remove(tenant_host) rescue nil
        domain.destroy! rescue nil
        org.destroy! rescue nil
        owner.destroy! rescue nil
      end
    end

    it 'refuses an unknown host even when platform fallback is enabled' do
      allow(Onetime.auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)

      post "https://unknown-#{run_id}.saml-platform.example.com/auth/sso/saml"

      expect_refused_before_the_idp(error: 'sso_not_configured')
    end

    it 'refuses an unverified custom domain even when platform fallback is enabled' do
      tenant_host = "unverified-#{run_id}.saml-platform.example.com"
      owner        = Onetime::Customer.new(email: "unverified-owner-#{run_id}@saml-platform.example.com")
      owner.save
      org          = Onetime::Organization.create!("Unverified Org #{run_id}", owner, "unverified-contact-#{run_id}@saml-platform.example.com")
      domain       = Onetime::CustomDomain.new(display_domain: tenant_host, org_id: org.org_id)
      domain.save
      Onetime::CustomDomain.display_domain_index.put(tenant_host, domain.domainid)
      allow(Onetime.auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)

      begin
        post "https://#{tenant_host}/auth/sso/saml"

        expect_refused_before_the_idp(error: 'sso_not_configured')
      ensure
        Onetime::CustomDomain.display_domain_index.remove(tenant_host) rescue nil
        domain.destroy! rescue nil
        org.destroy! rescue nil
        owner.destroy! rescue nil
      end
    end

    it 'lets an active tenant SAML config override the live platform config' do
      tenant_host = "override-#{run_id}.saml-platform.example.com"
      owner        = Onetime::Customer.new(email: "override-owner-#{run_id}@saml-platform.example.com")
      owner.save
      org          = Onetime::Organization.create!("Override Org #{run_id}", owner, "override-contact-#{run_id}@saml-platform.example.com")
      domain       = Onetime::CustomDomain.new(display_domain: tenant_host, org_id: org.org_id)
      domain.verified = true
      domain.save
      Onetime::CustomDomain.display_domain_index.put(tenant_host, domain.domainid)
      tenant_idp = SamlSpec::TestIdp.new(entity_id: "https://override-idp.test/#{run_id}", key: OpenSSL::PKey::RSA.new(2048))
      tenant_sso_url = "https://login.override-idp.test/#{run_id}"
      Onetime::CustomDomain::SsoConfig.create!(
        domain_id: domain.identifier, provider_type: 'saml', display_name: 'Override SAML',
        idp_sso_service_url: tenant_sso_url, idp_entity_id: tenant_idp.entity_id,
        idp_cert: tenant_idp.cert_pem, enabled: true
      )

      begin
        request = start_login("https://#{tenant_host}", expected_sso_url: tenant_sso_url)

        expect(request.destination).to eq(tenant_sso_url)
        expect(request.destination).not_to eq(PlatformSamlSsoSpec::SSO_URL)
        expect(request.acs_url).to eq("https://#{tenant_host}/auth/sso/saml/callback")
      ensure
        Onetime::CustomDomain::SsoConfig.delete_for_domain!(domain.identifier) rescue nil
        Onetime::CustomDomain.display_domain_index.remove(tenant_host) rescue nil
        domain.destroy! rescue nil
        org.destroy! rescue nil
        owner.destroy! rescue nil
      end
    end
  end

  # ── callback: identity keying ─────────────────────────────────────────────

  describe 'callback with a signed response from the platform IdP' do
    it 'keys the identity on (route, BARE IdP EntityID, NameID)' do
      sign_in

      expect(last_response.status).to eq(302), last_response.body[0, 300]
      expect(last_response.headers['Location'].to_s).not_to include('auth_error')

      rows = identity_rows
      expect(rows.size).to eq(1)
      expect(rows.first).to include(provider: 'saml', issuer: entity_id, uid: name_id)
      expect(rows.first[:issuer]).not_to eq('')
      expect(rows.first[:issuer]).not_to include(Onetime::SsoProvider::Saml::TENANT_ISSUER_SEPARATOR)
      expect(db[:accounts].where(id: rows.first[:account_id]).first[:email]).to eq(email)
    end

    it 'signs the same user in again through the same identity' do
      sign_in
      clear_cookies
      sign_in

      expect(last_response.headers['Location'].to_s).not_to include('auth_error')
      expect(identity_rows.size).to eq(1)
    end

    # The reverse direction of the tenant scoping: a tenant that configured
    # the platform's EntityID has rows keyed "<domain>|<EntityID>". A platform
    # login must neither match nor rewrite such a row.
    it 'does not match a tenant row that names the same EntityID and NameID' do
      tenant_email = "tenant-victim-#{run_id}@saml-platform.example.com"
      created_emails << tenant_email
      tenant_account = db[:accounts].insert(email: tenant_email, status_id: 2)
      tenant_key     = Onetime::SsoProvider::Saml.tenant_issuer("cd_tenant_#{run_id}", entity_id)
      identities.insert(account_id: tenant_account, provider: 'saml', issuer: tenant_key, uid: name_id)

      sign_in

      expect(last_response.headers['Location'].to_s).not_to include('auth_error')
      rows = identity_rows
      expect(rows.map { |row| row[:issuer] }).to contain_exactly(tenant_key, entity_id)
      expect(rows.find { |row| row[:issuer] == tenant_key }[:account_id]).to eq(tenant_account)
      expect(rows.find { |row| row[:issuer] == entity_id }[:account_id]).not_to eq(tenant_account)
      expect(last_request.env['rack.session'].to_h['account_id']).not_to eq(tenant_account)
    end

    it 'never writes a sentinel-issuer row' do
      sign_in

      expect(identities.where(uid: name_id, issuer: '').count).to eq(0)
    end
  end

  # ── callback: refusals ────────────────────────────────────────────────────

  describe 'refusals on the platform surface' do
    it 'refuses a response with no pending AuthnRequest (IdP-initiated SSO)' do
      created_emails << email
      post_callback(idp.response(
        in_response_to: nil,
        acs_url: platform_acs,
        audience: platform_entity_id,
        name_id: name_id, attributes: { 'email' => [email] }
      ))

      expect_refused
    end

    it 'refuses a response from an IdP with another EntityID, even one signed by the platform key' do
      other = SamlSpec::TestIdp.new(entity_id: 'https://other-idp.test/saml/metadata', key: idp.key, cert: idp.cert)
      sign_in(signer: other)

      expect_refused
    end

    it 'refuses a response signed by another key' do
      impostor = SamlSpec::TestIdp.new(entity_id: entity_id, key: OpenSSL::PKey::RSA.new(2048))
      sign_in(signer: impostor)

      expect_refused
    end

    it 'refuses an RSA-SHA1 signed response' do
      sign_in(signature_method: XMLSecurity::Document::RSA_SHA1)

      expect_refused
    end

    it 'refuses a second presentation of the same assertion' do
      created_emails << email
      assertion_id = "_#{SecureRandom.uuid}"

      post_callback(answer(start_login, assertion_id: assertion_id))
      expect(last_response.headers['Location'].to_s).not_to include('auth_error')

      clear_cookies
      post_callback(answer(start_login, assertion_id: assertion_id))

      expect(last_response.headers['Location'].to_s).to include('auth_error=sso_failed')
      expect(identity_rows.size).to eq(1)
    end

    it 'refuses a second answer to an already-consumed AuthnRequest' do
      created_emails << email
      request = start_login

      post_callback(answer(request))
      expect(last_response.headers['Location'].to_s).not_to include('auth_error')

      post_callback(answer(request))

      expect(last_response.headers['Location'].to_s).to include('auth_error=sso_failed')
      expect(identity_rows.size).to eq(1)
    end

    # The binding must be in the SIGNED assertion: a valid signed assertion
    # whose SubjectConfirmationData carries no InResponseTo, rewrapped in a
    # Response naming this session's pending request id, passes ruby-saml.
    it 'refuses an unclaimed signed assertion rewrapped to name the pending request' do
      sign_in(subject_confirmations: [nil])

      expect_refused
    end

    # omniauth runs the callback phase for any method. A cross-site GET (an
    # <img> on any page the user visits mid-login) must not consume the
    # pending id, or the IdP's real POST is refused.
    it 'does not let a GET to the callback path burn the pending request' do
      created_emails << email
      request = start_login

      get platform_acs
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location'].to_s).to include('auth_error=sso_failed')

      post_callback(answer(request))

      expect(last_response.headers['Location'].to_s).not_to include('auth_error')
      expect(identity_rows.size).to eq(1)
    end
  end
end
