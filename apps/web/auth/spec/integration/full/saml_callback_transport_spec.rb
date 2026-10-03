# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/oauth_flow_helper'
require_relative '../../../../../../spec/support/saml/test_idp'
require 'zlib'

RSpec.describe 'Staged tenant SAML Connect', :shared_db_state, type: :integration do
  include Rack::Test::Methods
  include OAuthFlowHelper
  include_context 'domains enabled'

  before(:all) { boot_onetime_app }

  let(:host) { "staged-connect-#{SecureRandom.hex(6)}.tenant.example.com" }
  let(:actor_email) { unique_test_email('staged-saml-connect') }
  let(:actor_id) { seed_account_with_password(actor_email) }
  let(:idp) { SamlSpec::TestIdp.new }
  let(:uid) { "staged-#{SecureRandom.hex(8)}" }
  let(:identities) { auth_db[:account_identities] }

  before do
    raise 'This test requires the full-sqlite lane with ORGS_SSO_ENABLED' unless Onetime.auth_config.orgs_sso_enabled?

    @tenant = setup_oauth_test_domain(host)
    @tenant[:domain].verified = true
    @tenant[:domain].save
    Onetime::CustomDomain::SsoConfig.delete_for_domain!(@tenant[:domain].identifier)
    Onetime::CustomDomain::SsoConfig.create!(
      domain_id: @tenant[:domain].identifier, provider_type: 'saml', enabled: true,
      idp_sso_service_url: 'https://idp.example.com/sso', idp_entity_id: idp.entity_id, idp_cert: idp.cert_pem,
    )
    Onetime::CustomDomain::SigninConfig.create!(
      domain_id: @tenant[:domain].identifier, enabled: true, signin_enabled: true, sso_enabled: true,
    )
    customer = Onetime::Customer.find_by_extid(auth_db[:accounts].where(id: actor_id).get(:external_id))
    Onetime::OrganizationMembership.ensure_membership(
      @tenant[:org], customer, role: 'member', domain_scope_id: @tenant[:domain].objid, provisioning_source: 'sso',
    )
    header 'Host', host
    csrf_login(actor_email)
    expect(last_request.env['rack.session']['account_id']).to eq(actor_id)
    clear_body_headers
    post '/auth/sso/saml', connect: '1'
    expect(last_response.status).to eq(302)
    expect(last_response.location).to start_with('https://idp.example.com/sso?')
    @sid = last_request.env['rack.session'].id.public_id
    expect(Onetime::SessionSidecar.exists?(@sid, 'sso_connect_intent')).to be(true)
    query = Rack::Utils.parse_query(URI.parse(last_response.location).query)
    xml = Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(Base64.decode64(query.fetch('SAMLRequest')))
    @request_id = xml[/\sID=['"]([^'"]+)['"]/, 1]
    @acs = xml[/AssertionConsumerServiceURL=['"]([^'"]+)['"]/, 1]
    @audience = xml[%r{<saml:Issuer[^>]*>([^<]+)</saml:Issuer>}, 1]
  end

  after do
    identities.where(uid: uid).delete
    cleanup_oauth_test_fixtures
  end

  def stage_connect
    response = idp.response(
      in_response_to: @request_id, acs_url: @acs, audience: @audience,
      name_id: uid, attributes: { 'email' => ['different-person@example.com'] }, conditions_expiry: nil,
    )
    cookie = rack_mock_session.cookie_jar['onetime.session']
    expect(cookie).to eq(@sid)
    clear_cookies # Model a cross-site Lax POST; Rack::Test does not enforce SameSite.
    clear_body_headers
    header 'Origin', 'https://idp.example.com'
    post @acs, 'SAMLResponse' => response
    expect(last_response.status).to eq(303), last_response.body
    expect(last_response.headers['Set-Cookie']).to be_nil
    expect(identities.where(uid: uid).count).to eq(0)
    expect(Onetime::SessionSidecar.exists?(@sid, 'sso_connect_intent')).to be(true)
    location = URI.join(@acs, last_response.location).to_s
    header 'Origin', nil
    rack_mock_session.cookie_jar.merge("onetime.session=#{cookie}; path=/", URI.parse(location))
    expect(rack_mock_session.cookie_jar.for(URI.parse(location))).to include(cookie)
    location
  end

  it 'preserves account-bound intent through the cookieless POST and binds only on the original-session GET' do
    accounts_before = auth_db[:accounts].count
    location = stage_connect
    get location
    expect(last_response.status).to eq(302)
    expect(last_request.env['HTTP_COOKIE'].to_s).to include(@sid), 'The test browser must send the initiating session cookie'
    expect(last_response.location).not_to include('auth_error')
    row = identities.where(uid: uid).first
    expect(row).not_to be_nil
    expect(row[:account_id]).to eq(actor_id)
    expect(row[:issuer]).to eq(Onetime::SsoProvider::Saml.tenant_issuer(@tenant[:domain].identifier, idp.entity_id))
    expect(auth_db[:accounts].count).to eq(accounts_before)
    expect(Onetime::SessionSidecar.exists?(@sid, 'sso_connect_intent')).to be(false)
  end

  it 'does not consume the original Connect intent when a cookieless GET visits the handle first' do
    location = stage_connect
    cookie = @sid
    clear_cookies
    get location
    expect(last_response.location).to include('auth_error=sso_failed')
    expect(identities.where(uid: uid).count).to eq(0)
    expect(Onetime::SessionSidecar.exists?(@sid, 'sso_connect_intent')).to be(true)
    clear_cookies
    rack_mock_session.cookie_jar.merge("onetime.session=#{cookie}; path=/", URI.parse(location))
    get location
    expect(identities.where(uid: uid).get(:account_id)).to eq(actor_id)
  end
end
