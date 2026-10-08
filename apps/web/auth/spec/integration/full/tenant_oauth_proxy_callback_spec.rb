# frozen_string_literal: true

require_relative '../../spec_helper'
require 'jwt'

# These stateful integration examples span several layers, not one class.
# Boot is shared; records and mutable configuration are isolated per example.
# rubocop:disable RSpec/DescribeClass, RSpec/BeforeAfterAll, RSpec/MultipleMemoizedHelpers
# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations

# Mounted OIDC code flow, with only IdP HTTP and DNS responses mocked. State,
# nonce, PKCE, signature/issuer validation, tenant hooks, SQL identities and
# Valkey sessions all run normally; no injected rack.session or mock auth hash.
# Run: tests/lanes/run full-pg-agnostic --only apps/web/auth/spec/integration/full/tenant_oauth_proxy_callback_spec.rb
RSpec.describe 'Tenant OAuth callbacks behind a Host-rewriting proxy', :shared_db_state, type: :integration do
  subject { "shared-subject-#{run_id}" }

  include_context 'domains enabled'

  before(:all) { boot_onetime_app }

  let(:run_id) { SecureRandom.hex(8) }
  let(:signing_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:tenants) { [] }
  let!(:tenant_a) { build_tenant('a') }
  let!(:tenant_b) { build_tenant('b') }
  let(:token_requests) { [] }

  def build_tenant(label)
    host            = "oauth-#{label}-#{run_id}.tenant-example.com"
    owner           = Onetime::Customer.new(email: "owner-#{label}-#{run_id}@test.local")
    owner.save
    org             = Onetime::Organization.create!("OAuth #{label} #{run_id}", owner, owner.email)
    domain          = Onetime::CustomDomain.new(display_domain: host, org_id: org.org_id)
    domain.verified = true
    domain.save
    Onetime::CustomDomain.display_domain_index.put(host, domain.domainid)

    tenant = {
      host: host,
      domain: domain,
      org: org,
      owner: owner,
      issuer: "https://idp-#{label}-#{run_id}.example.com",
      client_id: "client-#{label}-#{run_id}",
      client_secret: "secret-#{label}-#{run_id}",
      email: "user-#{label}-#{run_id}@tenant-example.com",
    }
    tenants << tenant
    Onetime::CustomDomain::SsoConfig.create!(
      domain_id: domain.identifier,
      provider_type: 'oidc',
      issuer: tenant[:issuer],
      client_id: tenant[:client_id],
      client_secret: tenant[:client_secret],
      enabled: true,
      allowed_domains: ['tenant-example.com'],
    )
    tenant
  end

  # Build after the domains context has installed the canonical host, rather
  # than inheriting another file's memoized stack and construction-time gates.
  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  around do |example|
    saved_mode                = OmniAuth.config.test_mode
    network_config            = WebMock::Config.instance
    saved_network             = [:allow_net_connect, :allow_localhost, :allow, :net_http_connect_on_start]
      .to_h { |key| [key, network_config.public_send(key)] }
    OmniAuth.config.test_mode = false
    WebMock.disable_net_connect!(allow_localhost: true)
    example.run
  ensure
    OmniAuth.config.test_mode = saved_mode
    saved_network.each { |key, value| network_config.public_send("#{key}=", value) }
  end

  before do
    raise 'This spec requires the full SSO lane' unless Onetime.auth_config.orgs_sso_enabled?

    # WebMock does not intercept DNS. Keep Guard validation/pinning real and
    # replace only its DNS seam for these fictional providers.
    tenants.each do |tenant|
      allow(Onetime::Http::Guard).to receive(:resolve_addresses)
        .with(URI.parse(tenant[:issuer]).host).and_return(['203.0.113.10'])
      stub_discovery(tenant)
    end
  end

  after do
    tenants.each do |tenant|
      customer = Onetime::Customer.find_by_email(tenant[:email])
      Onetime::OrganizationMembership.find_by_org_customer(tenant[:org].objid, customer.objid)&.destroy! if customer
      customer&.destroy!
      Onetime::CustomDomain::SsoConfig.delete_for_domain!(tenant[:domain].identifier)
      Onetime::CustomDomain.display_domain_index.remove(tenant[:host])
      tenant[:domain].destroy!
      tenant[:org].destroy!
      tenant[:owner].destroy!
    end
    clear_auth_database
  end

  def stub_discovery(tenant)
    issuer    = tenant[:issuer]
    stub_request(:get, "#{issuer}/.well-known/openid-configuration").to_return(
      headers: { 'Content-Type' => 'application/json' },
      body: {
        issuer: issuer,
        authorization_endpoint: "#{issuer}/authorize",
        token_endpoint: "#{issuer}/token",
        userinfo_endpoint: "#{issuer}/userinfo",
        jwks_uri: "#{issuer}/jwks",
        response_types_supported: ['code'],
        subject_types_supported: ['public'],
        id_token_signing_alg_values_supported: ['RS256'],
        token_endpoint_auth_methods_supported: ['client_secret_basic'],
        code_challenge_methods_supported: ['S256'],
      }.to_json,
    )
    jwk       = JSON::JWK.new(signing_key.public_key)
    jwk[:kid] = 'proxy-test-key'
    stub_request(:get, "#{issuer}/jwks").to_return(
      headers: { 'Content-Type' => 'application/json' }, body: { keys: [jwk] }.to_json,
    )
  end

  def public_authority(tenant)
    public_port == 443 ? tenant[:host] : "#{tenant[:host]}:#{public_port}"
  end

  def origin_authority
    origin_port == 443 ? canonical_host : "#{canonical_host}:#{origin_port}"
  end

  def proxy_headers(tenant)
    clear_body_headers
    header 'Host', origin_authority
    header 'X-Forwarded-Host', port_carrier == :host ? public_authority(tenant) : tenant[:host]
    header 'X-Forwarded-Port', port_carrier == :port ? public_port.to_s : nil
    header 'X-Forwarded-Proto', 'https'
    header 'Origin', nil
    header 'Accept', 'text/html'
  end

  def expect_proxy_classification(tenant)
    env     = last_request.env
    expect(env['onetime.domain_strategy']).to eq(:custom)
    expect(env['onetime.display_domain']).to eq(tenant[:host])
    expect(env[Rack::DetectHost.result_field_name]).to eq(tenant[:host])
    expect_host_rewrite(origin_authority, rewritten: rewrite_on)
    request = Rack::Request.new(env)
    expect(request.host).to eq(rewrite_on ? tenant[:host] : canonical_host)
    expect(request.scheme).to eq('https')
    expect(request.port).to eq(rewrite_on ? public_port : origin_port)
    expect(env['onetime.tenant_sso_config'].domain_id).to eq(tenant[:domain].identifier)
  end

  def start_login(tenant)
    proxy_headers(tenant)
    post "https://#{public_authority(tenant)}/auth/sso/oidc", {}, 'REMOTE_ADDR' => '127.0.0.1'
    expect(last_response.status).to eq(302), last_response.body
    expect_proxy_classification(tenant)
    location = URI.parse(last_response.location)
    expect("#{location.scheme}://#{location.host}#{location.path}").to eq("#{tenant[:issuer]}/authorize")
    query    = CGI.parse(location.query).transform_values(&:first)
    expect(query.fetch('client_id')).to eq(tenant[:client_id])
    expect(query.fetch('redirect_uri')).to eq("https://#{public_authority(tenant)}/auth/sso/oidc/callback")
    expect(query.fetch('code_challenge_method')).to eq('S256')
    expect(query.fetch('state')).not_to be_empty
    expect(query.fetch('nonce')).not_to be_empty
    session  = last_request.env['rack.session'].to_h
    expect(session['omniauth_tenant_domain_id']).to eq(tenant[:domain].identifier)
    expect(session['omniauth_tenant_host']).to eq(tenant[:host])
    expect(session['omniauth.state']).to eq(query.fetch('state'))
    expect(session['omniauth.nonce']).to eq(query.fetch('nonce'))
    query
  end

  def stub_tokens(tenant, flow, issuer: tenant[:issuer])
    claims   = {
      iss: issuer,
      sub: subject,
      aud: tenant[:client_id],
      iat: Time.now.to_i,
      exp: Time.now.to_i + 300,
      nonce: flow.fetch('nonce'),
    }
    id_token = JWT.encode(claims, signing_key, 'RS256', kid: 'proxy-test-key')
    stub_request(:post, "#{tenant[:issuer]}/token").with do |request|
      token_requests << request
      true
    end.to_return(
      headers: { 'Content-Type' => 'application/json' },
      body: { access_token: "access-#{run_id}", token_type: 'Bearer', expires_in: 300, id_token: id_token }.to_json,
    )
    stub_request(:get, "#{tenant[:issuer]}/userinfo")
      .with(headers: { 'Authorization' => "Bearer access-#{run_id}" })
      .to_return(
        headers: { 'Content-Type' => 'application/json' },
        body: { sub: subject, email: tenant[:email], email_verified: true, name: 'Proxy OAuth User' }.to_json,
      )
  end

  def callback(tenant, flow, state: flow.fetch('state'), cookie: nil)
    proxy_headers(tenant)
    header 'Cookie', cookie if cookie
    get "https://#{public_authority(tenant)}/auth/sso/oidc/callback",
      { code: "code-#{run_id}", state: state },
      'REMOTE_ADDR' => '127.0.0.1'
    expect_proxy_classification(tenant)
  end

  def session_cookie
    values = Array(last_response.headers['Set-Cookie']).flat_map { |value| value.split("\n") }
    cookie = values.find { |value| value.start_with?('onetime.session=') }
    expect(cookie).not_to be_nil
    cookie.split(';').first
  end

  def expect_exchange(tenant, flow)
    request  = token_requests.last
    expect(request).not_to be_nil
    expect([request.uri.scheme, request.uri.host, request.uri.port, request.uri.path])
      .to eq(['https', URI.parse(tenant[:issuer]).host, 443, '/token'])
    params   = URI.decode_www_form(request.body).to_h
    expect(params).to include(
      'grant_type' => 'authorization_code',
      'code' => "code-#{run_id}",
      'redirect_uri' => flow.fetch('redirect_uri'),
    )
    verifier = params.fetch('code_verifier')
    expect(Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)).to eq(flow.fetch('code_challenge'))
    expect(request.headers['Authorization']).to eq(
      "Basic #{Base64.strict_encode64("#{tenant[:client_id]}:#{tenant[:client_secret]}")}",
    )
    expect(a_request(:get, "#{tenant[:issuer]}/jwks")).to have_been_made.at_least_once
    expect(a_request(:get, "#{tenant[:issuer]}/userinfo")).to have_been_made.at_least_once
  end

  def expect_tenant_login(tenant)
    expect(last_response.status).to eq(302), last_response.body
    expect(last_response.location).not_to include('auth_error=')
    account    = auth_db[:accounts].where(email: tenant[:email]).first
    expect(account).not_to be_nil
    session    = last_request.env['rack.session'].to_h
    expect(session).to include('authenticated' => true, 'account_id' => account[:id], 'email' => tenant[:email])
    expect(session.keys).not_to include(
      'omniauth_tenant_domain_id',
      'omniauth_tenant_host',
      'validated_omniauth_domain_id',
      'omniauth.state',
      'omniauth.nonce',
      'omniauth.pkce.verifier',
    )
    identity   = auth_db[:account_identities].where(provider: 'oidc', issuer: tenant[:issuer], uid: subject).first
    expect(identity).to include(account_id: account[:id])
    customer   = Onetime::Customer.find_by_extid(account[:external_id])
    expect(customer).not_to be_nil
    membership = Onetime::OrganizationMembership.find_by_org_customer(tenant[:org].objid, customer.objid)
    expect(membership).not_to be_nil
    expect(membership.domain_scope_id).to eq(tenant[:domain].identifier)
    expect(membership.provisioning_source).to eq('sso')

    cookie     = session_cookie
    proxy_headers(tenant)
    header 'Cookie', cookie
    get "https://#{public_authority(tenant)}/auth/account", {}, 'REMOTE_ADDR' => '127.0.0.1'
    expect(last_response.status).to eq(200), last_response.body
    expect(JSON.parse(last_response.body)).to include('id' => account[:id], 'email' => tenant[:email])
    expect(last_request.env['onetime.domain_strategy']).to eq(:custom)

    session_id = cookie.split('=', 2).last
    key        = Onetime::Operations::Sessions::Store.find_key(Familia.dbclient, session_id)
    expect(key).not_to be_nil
    stored     = Onetime::Operations::Sessions::Store.load_data(
      Familia.dbclient, key, codec: Onetime::SessionCodec.from_config
    )
    expect(stored).to include('authenticated' => true, 'account_id' => account[:id])
    expect(stored['external_id']).to eq(customer.extid)
    # TrackMetadata resolves the active org after the blob is written; its
    # read-through org cache need not be in the blob. Assert the persisted index.
    expect(Onetime::SessionMetadata.load(session_id)).to have_attributes(
      org_id: tenant[:org].objid,
      user_id: customer.extid,
    )
    account
  end

  def expect_no_login
    session = last_request.env['rack.session'].to_h
    expect(session['authenticated']).not_to be(true)
    expect(session['account_id']).to be_nil
    expect(auth_db[:accounts].where(email: tenants.map { |tenant| tenant[:email] }).count).to eq(0)
    expect(auth_db[:account_identities].where(uid: subject).count).to eq(0)
  end

  shared_examples 'mounted tenant OAuth callback' do
    it 'completes the code exchange and persists a tenant-bound identity, membership and active org' do
      flow = start_login(tenant_a)
      stub_tokens(tenant_a, flow)
      callback(tenant_a, flow)
      expect_exchange(tenant_a, flow)
      expect_tenant_login(tenant_a)
    end

    it 'rejects the wrong state before exchanging a token or creating an account' do
      flow = start_login(tenant_a)
      stub_tokens(tenant_a, flow)
      callback(tenant_a, flow, state: "wrong-#{flow.fetch('state')}")
      expect(last_response.status).to eq(302)
      expect(last_response.location).to include('auth_error=sso_failed')
      expect(last_request.env['omniauth.error.type']).to eq(:csrf_detected)
      expect(a_request(:post, "#{tenant_a[:issuer]}/token")).not_to have_been_made
      expect(a_request(:get, "#{tenant_a[:issuer]}/userinfo")).not_to have_been_made
      expect(last_request.env['rack.session'].to_h['omniauth.state']).to be_nil
      expect_no_login
    end

    it 'rejects a correctly signed ID token naming a different issuer' do
      flow = start_login(tenant_a)
      stub_tokens(tenant_a, flow, issuer: tenant_b[:issuer])
      callback(tenant_a, flow)
      expect(last_response.status).to eq(302)
      expect(last_response.location).to include('auth_error=sso_failed')
      expect(last_request.env['omniauth.error']).to be_a(OpenIDConnect::ResponseObject::IdToken::InvalidIssuer)
      expect(a_request(:post, "#{tenant_a[:issuer]}/token")).to have_been_made.once
      expect(a_request(:get, "#{tenant_a[:issuer]}/userinfo")).not_to have_been_made
      expect_no_login
    end

    it 'rejects tenant A state and cookie replayed on tenant B after a valid provider exchange' do
      flow   = start_login(tenant_a)
      cookie = session_cookie
      # B answers with B's issuer/audience but the captured nonce/state, so the
      # strategy succeeds. Only the real tenant-context gate can refuse this.
      stub_tokens(tenant_b, flow)
      callback(tenant_b, flow, cookie: cookie)
      expect(last_response.status).to eq(403)
      expect(JSON.parse(last_response.body)).to include('error' => 'tenant_mismatch')
      expect(a_request(:post, "#{tenant_b[:issuer]}/token")).to have_been_made.once
      expect(a_request(:get, "#{tenant_b[:issuer]}/userinfo")).to have_been_made.once
      expect(last_request.env['rack.session'].to_h.keys).not_to include(
        'omniauth_tenant_domain_id', 'omniauth_tenant_host', 'validated_omniauth_domain_id'
      )
      expect_no_login
    end

    it 'keeps colliding subjects under distinct issuers and signs a returning user into their own tenant' do
      accounts = [tenant_a, tenant_b].map do |tenant|
        clear_cookies
        header 'Cookie', nil
        flow = start_login(tenant)
        stub_tokens(tenant, flow)
        callback(tenant, flow)
        expect_exchange(tenant, flow)
        expect_tenant_login(tenant)
      end
      expect(accounts.map { |account| account[:id] }.uniq.size).to eq(2)
      expect(auth_db[:account_identities].where(uid: subject).select_map(:issuer))
        .to contain_exactly(tenant_a[:issuer], tenant_b[:issuer])
      expect(tenant_b[:org].member?(Onetime::Customer.find_by_extid(accounts.first[:external_id]))).to be(false)

      clear_cookies
      header 'Cookie', nil
      flow = start_login(tenant_b)
      stub_tokens(tenant_b, flow)
      callback(tenant_b, flow)
      expect_tenant_login(tenant_b).then { |account| expect(account[:id]).to eq(accounts.last[:id]) }
      expect(auth_db[:account_identities].where(uid: subject).count).to eq(2)
    end
  end

  [false, true].each do |rewrite|
    context "with public_host_rewrite #{rewrite ? 'on' : 'off'}" do
      let(:rewrite_on) { rewrite }

      include_context 'public host rewrite setting'

      # With rewriting off, Rack retains the origin-hop port. Use an aligned
      # origin/public port to test the supported nondefault-port topology in
      # both modes; differing ports are tested separately with rewriting on.
      [443, 8443].each do |port|
        context "with HTTPS on public port #{port}" do
          let(:public_port) { port }
          let(:origin_port) { port }
          let(:port_carrier) { :host }

          it_behaves_like 'mounted tenant OAuth callback'
        end
      end
    end
  end

  context 'with rewriting on and a different origin-hop port' do
    let(:rewrite_on) { true }
    let(:origin_port) { 3000 }
    let(:public_port) { 8443 }

    include_context 'public host rewrite setting'

    [:host, :port].each do |carrier|
      context "with the public port in X-Forwarded-#{carrier == :host ? 'Host' : 'Port'}" do
        let(:port_carrier) { carrier }

        it 'uses the public HTTPS port in both authorize and token-exchange redirect URIs' do
          flow = start_login(tenant_a)
          stub_tokens(tenant_a, flow)
          callback(tenant_a, flow)
          expect_exchange(tenant_a, flow)
          expect_tenant_login(tenant_a)
        end
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/BeforeAfterAll, RSpec/MultipleMemoizedHelpers
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
