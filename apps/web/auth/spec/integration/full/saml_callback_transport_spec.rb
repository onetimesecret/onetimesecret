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
  let(:public_origin) { "http://#{host}" }
  let(:store) { Onetime::Security::SamlCallbackStore }

  # Declared ahead of the `before` below, which already sends requests: the
  # AuthnRequest and staging POST use the initial setting. Transition examples
  # change it before the redeeming GET. `rewrite_on` and `request_headers`
  # come from the contexts at the end of the file.
  include_context 'public host rewrite setting'

  before do
    raise 'This test requires the full-sqlite lane with ORGS_SSO_ENABLED' unless Onetime.auth_config.orgs_sso_enabled?
    expect(OmniAuth.config.test_mode).to be(false)

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
    request_headers.each { |name, value| header name, value }
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
    expect(@acs).to eq("#{public_origin}/auth/sso/saml/callback")
    expect(@audience).to eq("#{public_origin}/auth/sso/saml/metadata")
    expect_topology
  end

  # What the layers below the rewrite received for the last request.
  def expect_topology(rewrite: rewritten, received_host: request_headers.fetch('Host'))
    expect_host_rewrite(received_host, rewritten: rewrite)
    received_hostname = URI.parse("http://#{received_host}").host
    expect(Rack::Request.new(last_request.env).host).to eq(rewrite ? host : received_hostname)
    expect(last_request.env['onetime.display_domain']).to eq(host)
    expect(last_request.env['onetime.domain_strategy']).to eq(:custom)
    expect(last_request.env['onetime.custom_domain'].identifier).to eq(@tenant[:domain].identifier)
  end

  after do
    identities.where(uid: uid).delete
    Familia.dbclient.del(store.key(@handle)) if @handle
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
    expect_topology
    expect(last_response.headers['Set-Cookie']).to be_nil
    expect(identities.where(uid: uid).count).to eq(0)
    expect(Onetime::SessionSidecar.exists?(@sid, 'sso_connect_intent')).to be(true)
    location = URI.join(@acs, last_response.location).to_s
    @handle = Rack::Utils.parse_query(URI.parse(location).query).fetch('saml_handle')
    @staged_raw = Familia.dbclient.get(store.key(@handle))
    expect(@staged_raw).not_to be_nil
    expect(JSON.parse(@staged_raw).fetch('response')).to eq(response)
    expect(Familia.dbclient.ttl(store.key(@handle))).to be_between(1, store::TTL)
    header 'Origin', nil
    rack_mock_session.cookie_jar.merge("onetime.session=#{cookie}; path=/", URI.parse(location))
    expect(rack_mock_session.cookie_jar.for(URI.parse(location))).to include(cookie)
    location
  end

  shared_examples 'a staged Connect callback' do
    it 'preserves account-bound intent through the cookieless POST and binds only on the original-session GET' do
      accounts_before = auth_db[:accounts].count
      location = stage_connect
      get location
      expect(last_response.status).to eq(302)
      expect_topology
      expect(last_request.env['HTTP_COOKIE'].to_s).to include(@sid), 'The test browser must send the initiating session cookie'
      expect(last_response.location).not_to include('auth_error')
      row = identities.where(uid: uid).first
      expect(row).not_to be_nil
      expect(row[:account_id]).to eq(actor_id)
      expect(row[:issuer]).to eq(Onetime::SsoProvider::Saml.tenant_issuer(@tenant[:domain].identifier, idp.entity_id))
      expect(auth_db[:accounts].count).to eq(accounts_before)
      expect(Onetime::SessionSidecar.exists?(@sid, 'sso_connect_intent')).to be(false)
      expect(Familia.dbclient.get(store.key(@handle))).to be_nil
    end

    it 'does not consume the original Connect intent when a cookieless GET visits the handle first' do
      location = stage_connect
      cookie = @sid
      clear_cookies
      get location
      expect(last_response.location).to include('auth_error=sso_failed')
      expect(identities.where(uid: uid).count).to eq(0)
      expect(Onetime::SessionSidecar.exists?(@sid, 'sso_connect_intent')).to be(true)
      expect(Familia.dbclient.get(store.key(@handle))).to eq(@staged_raw)
      clear_cookies
      rack_mock_session.cookie_jar.merge("onetime.session=#{cookie}; path=/", URI.parse(location))
      get location
      expect(identities.where(uid: uid).get(:account_id)).to eq(actor_id)
      expect(Familia.dbclient.get(store.key(@handle))).to be_nil
    end

    it 'refuses a second GET of the consumed handle without relinking or creating accounts' do
      location = stage_connect
      get location
      expect(last_response.location).not_to include('auth_error')
      row = identities.where(uid: uid).first
      expect(row).not_to be_nil
      expect(Familia.dbclient.get(store.key(@handle))).to be_nil
      accounts_before = auth_db[:accounts].count

      get location
      expect_topology
      expect(last_response.status).to eq(302)
      expect(last_response.location).to include('auth_error=sso_failed')
      expect(last_request.env['omniauth.error.type']).to eq(:saml_callback_missing)
      expect(identities.where(uid: uid).all).to eq([row])
      expect(auth_db[:accounts].count).to eq(accounts_before)
      expect(Onetime::SessionSidecar.exists?(@sid, 'sso_connect_intent')).to be(false)
    end
  end

  shared_examples 'a proxy-bound staged Connect callback' do
    it 'completes on the same mount after public_host_rewrite changes to the opposite setting' do
      mounted_app = app
      accounts_before = auth_db[:accounts].count
      location = stage_connect
      OT.conf['site']['network']['public_host_rewrite'] = !rewrite_on
      expect(app).to equal(mounted_app)

      get location
      expect_topology(rewrite: !rewrite_on)
      expect(last_request.env['HTTP_COOKIE'].to_s).to include(@sid)
      expect(last_response.status).to eq(302)
      expect(last_response.location).not_to include('auth_error')
      expect(identities.where(uid: uid).first).to include(
        account_id: actor_id, issuer: Onetime::SsoProvider::Saml.tenant_issuer(@tenant[:domain].identifier, idp.entity_id),
      )
      expect(auth_db[:accounts].count).to eq(accounts_before)
      expect(Onetime::SessionSidecar.exists?(@sid, 'sso_connect_intent')).to be(false)
      expect(Familia.dbclient.get(store.key(@handle))).to be_nil
    end

    [:origin_host, :origin_port, :scheme].each do |mismatch|
      it "refuses a GET with a different #{mismatch} without consuming Connect intent or the staged value" do
        accounts_before = auth_db[:accounts].count
        location = stage_connect
        changed_host = case mismatch
                       when :origin_host then "other-origin.example.net:#{URI.parse(public_origin).port}"
                       when :origin_port then "#{canonical_host}:9443"
                       else request_headers.fetch('Host')
                       end
        header 'Host', changed_host
        changed_location = location
        if mismatch == :scheme
          scheme = URI.parse(public_origin).scheme == 'https' ? 'http' : 'https'
          header 'X-Forwarded-Proto', scheme
          changed_location = location.sub(/\Ahttps?:/, "#{scheme}:")
        end
        get changed_location

        expect_topology(received_host: changed_host)
        expect(last_request.env['HTTP_COOKIE'].to_s).to include(@sid)
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('auth_error=sso_failed')
        expect(last_request.env['omniauth.error.type']).to eq(:saml_callback_missing)
        expect(identities.where(uid: uid).count).to eq(0)
        expect(auth_db[:accounts].count).to eq(accounts_before)
        expect(Onetime::SessionSidecar.exists?(@sid, 'sso_connect_intent')).to be(true)
        expect(Familia.dbclient.get(store.key(@handle))).to eq(@staged_raw)
        expect(last_request.env['rack.session'].to_h['saml_authn_request_id']).to eq(@request_id)

        request_headers.each { |name, value| header name, value }
        header 'X-Forwarded-Proto', nil unless request_headers.key?('X-Forwarded-Proto')
        get location
        expect_topology
        expect(last_response.location).not_to include('auth_error')
        expect(identities.where(uid: uid).get(:account_id)).to eq(actor_id)
        expect(Familia.dbclient.get(store.key(@handle))).to be_nil
      end
    end
  end

  # The staging scope is computed from the Host as received
  # (SamlCallbackStore.scope), so every outcome is the same in all four runs.
  [false, true].each do |rewrite|
    context "with public_host_rewrite #{rewrite ? 'on' : 'off'}" do
      let(:rewrite_on) { rewrite }

      # A request whose Host already names the tenant is never rewritten.
      context 'with the tenant host in Host' do
        let(:request_headers) { { 'Host' => host } }
        let(:rewritten) { false }

        it_behaves_like 'a staged Connect callback'
      end

      # The proxy puts its origin target in Host; the rewrite, when on, puts
      # the tenant host back for the layers below it.
      context 'with the origin target in Host and the tenant host in X-Forwarded-Host' do
        let(:request_headers) { { 'Host' => canonical_host, 'X-Forwarded-Host' => host } }
        let(:rewritten) { rewrite }

        it_behaves_like 'a staged Connect callback'
        it_behaves_like 'a proxy-bound staged Connect callback'

        context 'with HTTPS and a non-default authority port' do
          let(:public_origin) { "https://#{host}:8443" }
          let(:request_headers) do
            { 'Host' => "#{canonical_host}:8443", 'X-Forwarded-Host' => "#{host}:8443", 'X-Forwarded-Proto' => 'https' }
          end

          it_behaves_like 'a staged Connect callback'
          it_behaves_like 'a proxy-bound staged Connect callback'
        end
      end
    end
  end
end
