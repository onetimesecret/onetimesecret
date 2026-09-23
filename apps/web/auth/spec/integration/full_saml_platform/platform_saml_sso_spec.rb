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
#   2. Saml.platform_sp_entity_id is the AuthnRequest Issuer (and the SP
#      metadata's entityID), and callback_url is the canonical host's ACS;
#   3. a platform identity is keyed (route, BARE EntityID, NameID) — never ''
#      and never a tenant's domain-scoped key, so a tenant row that names the
#      same EntityID is not matched;
#   4. the InResponseTo binding, the replay cache, the issuer gate and the
#      signature-algorithm gate all refuse on this surface too.
#
# OWN LANE. Auth::Config configures once per process and reads SAML_* then.
# The lane (tests/lanes/full-saml-platform) provides the three public strings;
# the IdP KEYPAIR is minted here at load time and its certificate installed in
# ENV before the first boot, so no key material is checked in. If the app is
# already booted when this file loads, the environment cannot take effect —
# that is a loud failure, not a skip.
#
# REQUIREMENTS:
# - Valkey on 2163, AUTHENTICATION_MODE=full, ORGS_SSO_ENABLED=true,
#   SAML_IDP_SSO_SERVICE_URL, SAML_IDP_ENTITY_ID (lane-provided)
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

  include_context 'domains enabled'

  before(:all) { boot_onetime_app }

  let(:db) { Auth::Database.connection }
  let(:identities) { db[:account_identities] }
  let(:run_id) { SecureRandom.hex(6) }
  let(:idp) { PlatformSamlSsoSpec::IDP }
  let(:entity_id) { PlatformSamlSsoSpec::ENTITY_ID }
  let(:name_id) { "platform-nameid-#{run_id}" }
  let(:email) { "platform-user-#{run_id}@saml-platform.example.com" }
  let(:created_emails) { [] }

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

  def start_login
    header 'Host', canonical_host
    post '/auth/sso/saml'

    expect(last_response.status).to eq(302), "request phase: #{last_response.status} #{last_response.body[0, 200]}"
    location = last_response.headers['Location'].to_s
    expect(location).to start_with("#{PlatformSamlSsoSpec::SSO_URL}?"),
      "expected a redirect to the platform IdP, got #{location} (is the saml route the placeholder?)"

    query = CGI.parse(URI.parse(location).query)
    xml   = Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(Base64.decode64(query.fetch('SAMLRequest').first))

    PlatformSamlSsoSpec::AuthnRequest.new(
      id: xml[/<samlp:AuthnRequest[^>]*\sID=['"]([^'"]+)['"]/, 1],
      acs_url: xml[/AssertionConsumerServiceURL=['"]([^'"]+)['"]/, 1],
      sp_entity_id: xml[%r{<saml:Issuer[^>]*>([^<]+)</saml:Issuer>}, 1],
      destination: xml[/Destination=['"]([^'"]+)['"]/, 1],
    )
  end

  def post_callback(saml_response)
    header 'Host', canonical_host
    header 'Origin', 'https://login.platform-idp.test'
    post '/auth/sso/saml/callback', { 'SAMLResponse' => saml_response }
  ensure
    header 'Origin', nil
  end

  def answer(request, signer: idp, **overrides)
    signer.response(
      in_response_to: request.id, acs_url: request.acs_url, audience: request.sp_entity_id,
      name_id: name_id, attributes: { 'email' => [email] }, **overrides
    )
  end

  def sign_in(**overrides)
    created_emails << email
    post_callback(answer(start_login, **overrides))
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
      expect(Onetime::SsoProvider::Saml.platform_usable?).to be true

      request = start_login
      expect(request.id).not_to be_nil
      expect(request.destination).to eq(PlatformSamlSsoSpec::SSO_URL)
    end

    it 'names the canonical host in the ACS URL and the derived platform SP EntityID as Issuer' do
      request = start_login

      expect(request.acs_url).to eq("http://#{canonical_host}/auth/sso/saml/callback")
      expect(request.sp_entity_id).to eq(Onetime::SsoProvider::Saml.platform_sp_entity_id('saml'))
      expect(request.sp_entity_id).to end_with('/auth/sso/saml/metadata')
      expect(request.sp_entity_id).not_to be_empty
    end

    it 'serves SP metadata naming the platform SP EntityID and the ACS URL' do
      header 'Host', canonical_host
      get '/auth/sso/saml/metadata'

      expect(last_response.status).to eq(200), last_response.body[0, 200]
      expect(last_response.body).to include('EntityDescriptor')
      expect(last_response.body).to match(/entityID=['"]#{Regexp.escape(Onetime::SsoProvider::Saml.platform_sp_entity_id('saml'))}['"]/)
      expect(last_response.body).to include("http://#{canonical_host}/auth/sso/saml/callback")
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
        acs_url: "http://#{canonical_host}/auth/sso/saml/callback",
        audience: Onetime::SsoProvider::Saml.platform_sp_entity_id('saml'),
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

      header 'Host', canonical_host
      get '/auth/sso/saml/callback'
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location'].to_s).to include('auth_error=sso_failed')

      post_callback(answer(request))

      expect(last_response.headers['Location'].to_s).not_to include('auth_error')
      expect(identity_rows.size).to eq(1)
    end
  end
end
