# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/tenant_test_fixtures'

# Real login, session persistence and mounted routes; no injected rack.session.
# Cookie replay deliberately bypasses browser host-only delivery so a refusal
# proves the server-side surface gate, not Rack::Test's cookie jar behavior.
# Run: tests/lanes/run full-sqlite --only apps/web/auth/spec/integration/full/host_proxy_stateful_boundaries_spec.rb

RSpec.describe 'Host proxy stateful boundaries', :shared_db_state, type: :integration do
  include Rack::Test::Methods
  include_context 'tenant fixtures'
  include_context 'domains enabled'

  before(:all) { boot_onetime_app }

  let(:account_email) { unique_test_email('host-boundary') }
  let!(:account_id) { seed_account_with_password(account_email) }
  let!(:account_customer) do
    Onetime::Customer.find_by_extid(auth_db[:accounts].where(id: account_id).get(:external_id))
  end
  let(:other_host) { "other-#{test_run_id}.example.net" }
  let!(:other_domain) do
    domain = Onetime::CustomDomain.new(display_domain: other_host, org_id: test_organization.org_id)
    domain.verified = true
    domain.save
    Onetime::CustomDomain.display_domain_index.put(other_host, domain.domainid)
    domain
  end

  before do
    [test_custom_domain, other_domain].each do |domain|
      Onetime::CustomDomain::SigninConfig.create!(
        domain_id: domain.identifier, enabled: true, signin_enabled: true, sso_enabled: true,
      )
    end
    Onetime::Application::MiddlewareStack.ip_privacy_security_config
  end

  after do
    [test_custom_domain, other_domain].each do |domain|
      Onetime::CustomDomain::SigninConfig.delete_for_domain!(domain.identifier)
    end
    Onetime::CustomDomain.display_domain_index.remove(other_host)
    other_domain.destroy!
    account_customer.destroy!
    clear_auth_database
  end

  # AdminNetworkIsolation resolves allowlists at construction. The registry's
  # cached map may have been built by another file with domains disabled and
  # the lane's bare-IP site.host (an intentionally inactive host gate). Build
  # this group's full stack after its domains context has installed the host.
  def app
    @boundary_app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  def proxy_headers(host)
    clear_body_headers
    header 'Host', canonical_host
    header 'X-Forwarded-Host', host
    header 'X-Forwarded-Proto', 'https'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', nil
    header 'Origin', nil
  end

  def proxy_get(host, path, cookie: nil)
    proxy_headers(host)
    header 'Cookie', cookie if cookie
    get "https://#{host}#{path}"
  end

  def stored_session(sid)
    db = Familia.dbclient
    key = Onetime::Operations::Sessions::Store.find_key(db, sid)
    expect(key).not_to be_nil, 'HP-PRE-02: login did not persist a session in the lane datastore'
    Onetime::Operations::Sessions::Store.load_data(db, key, codec: Onetime::SessionCodec.from_config)
  end

  def login_on(host, colonel: false)
    if colonel
      customer = account_customer
      customer.role = 'colonel'
      customer.verified = true
      customer.save
    end
    proxy_get(host, '/auth')
    token = last_response.headers['X-CSRF-Token']
    expect(token).not_to be_nil, 'HP-PRE-03: GET /auth did not issue a CSRF token'
    proxy_headers(host)
    header 'Content-Type', 'application/json'
    header 'X-CSRF-Token', token
    header 'Origin', "https://#{host}"
    post "https://#{host}/auth/login", JSON.generate(
      login: account_email, password: AuthTestConstants::TEST_PASSWORD, shrimp: token,
    )
    expect(last_response.status).to eq(200), "HP-PRE-04: login failed: #{last_response.status} #{last_response.body}"
    cookies = Array(last_response.headers['Set-Cookie']).flat_map { |value| value.split("\n") }
    session_cookie = cookies.find { |value| value.start_with?('onetime.session=') }
    expect(session_cookie).not_to be_nil, 'HP-PRE-05: successful login did not emit the session cookie'
    @login_set_cookie = session_cookie
    @cookie = session_cookie.split(';').first
    @sid = @cookie.split('=', 2).last
    clear_cookies
    header 'Cookie', @cookie
    @cookie
  end

  def logout_on(host, token:, origin:)
    proxy_headers(host)
    header 'Cookie', @cookie
    header 'Content-Type', 'application/json'
    header 'X-CSRF-Token', token
    header 'Origin', origin
    post "https://#{host}/auth/logout", JSON.generate(shrimp: token)
  end

  def with_rewrite(value)
    network                        = (OT.conf['site']['network'] ||= {})
    saved                          = network['public_host_rewrite']
    network['public_host_rewrite'] = value
    yield
  ensure
    network['public_host_rewrite'] = saved
  end

  # Everything after the name=value pair, with the expiry time blanked.
  def cookie_attributes(set_cookie)
    set_cookie.split(/;\s*/).drop(1).map { |attribute| attribute.sub(/\Aexpires=.*/i, 'expires=<time>') }
  end

  # Onetime::Session takes these when the stack is built, which is the
  # example's first request.
  def with_session_cookie_config(secure:, same_site:)
    session = OT.conf['site']['session']
    saved   = session.slice('secure', 'same_site')
    session.merge!('secure' => secure, 'same_site' => same_site)
    yield
  ensure
    session.merge!(saved)
  end

  # Onetime::Session sits above the rewrite and commits the session after the
  # layers below have returned, so on the way out it sees the rewritten Host.
  # Its cookie carries no Domain and takes Secure and SameSite from
  # site.session; the lane's own secure:false is run next to secure:true.
  describe 'the session Set-Cookie, compared across the setting' do
    [
      { secure: false, same_site: 'lax', attributes: ['path=/', 'expires=<time>', 'httponly', 'samesite=lax'] },
      { secure: true, same_site: 'strict',
        attributes: ['path=/', 'expires=<time>', 'secure', 'httponly', 'samesite=strict'] },
    ].each do |config|
      it "HP-COOKIE-02: has the same attributes with the setting off and on (secure: #{config[:secure]}, " \
         "same_site: #{config[:same_site]})" do
        with_session_cookie_config(**config.slice(:secure, :same_site)) do
          off, on = [false, true].map do |rewrite|
            with_rewrite(rewrite) do
              header 'Cookie', nil
              login_on(tenant_domain)
              # The login request that set the cookie was rewritten in the
              # second run and not in the first.
              expect(last_request.env.key?(Onetime::Middleware::PublicHostRewrite::ORIGINAL_HTTP_HOST)).to eq(rewrite)
              cookie_attributes(@login_set_cookie)
            end
          end

          expect(on).to eq(off)
          expect(off).to eq(config[:attributes])
        end
      end
    end
  end

  [false, true].each do |rewrite|
    context "public_host_rewrite #{rewrite ? 'on' : 'off'}" do
      around do |example|
        network = (OT.conf['site']['network'] ||= {})
        saved = network['public_host_rewrite']
        network['public_host_rewrite'] = rewrite
        example.run
      ensure
        network['public_host_rewrite'] = saved
      end

      [[:tenant, :other], [:tenant, :canonical], [:canonical, :tenant], [:other, :tenant]].each do |from, to|
        it "HP-SESSION-#{from}-#{to}: refuses replay on a different surface after accepting the issuing surface" do
          hosts = { tenant: tenant_domain, other: other_host, canonical: canonical_host }
          login_on(hosts.fetch(from))
          marker = from == :canonical ? Onetime::SessionSurface::CANONICAL : {
            'kind' => 'custom', 'id' => (from == :tenant ? test_custom_domain : other_domain).identifier,
          }
          expect(stored_session(@sid)[Onetime::SessionSurface::KEY]).to eq(marker)
          proxy_get(hosts.fetch(from), '/auth/account', cookie: @cookie)
          expect(last_response.status).to eq(200)
          expect(last_request.env.key?(Onetime::Middleware::PublicHostRewrite::ORIGINAL_HTTP_HOST))
            .to eq(rewrite && from != :canonical)

          proxy_get(hosts.fetch(to), '/auth/account', cookie: @cookie)
          expect(last_response.status).to eq(401)
          expect(JSON.parse(last_response.body).to_s).to include('surface_mismatch')
          expect(Onetime::Operations::Sessions::Store.find_key(Familia.dbclient, @sid)).to be_nil
        end
      end

      it 'HP-COOKIE-01: emits a host-only session cookie, not an origin-target Domain cookie' do
        login_on(tenant_domain)
        expect(@login_set_cookie).not_to match(/;\s*domain=/i)
        expect(@login_set_cookie).to match(/;\s*path=\//i)
        expect(@login_set_cookie).to match(/;\s*httponly/i)
        expect(@login_set_cookie).to match(/;\s*samesite=lax/i)
        # The lane intentionally uses secure:false; this does not claim that
        # production's Secure attribute was tested.
        proxy_get(tenant_domain, '/auth/account', cookie: @cookie)
        expect(last_response.status).to eq(200)
      end

      [nil, 'invalid-token'].each do |token|
        it "HP-CSRF-#{token.nil? ? 'missing' : 'invalid'}: refuses logout without a valid session token" do
          login_on(tenant_domain)
          logout_on(tenant_domain, token: token, origin: "https://#{tenant_domain}")
          expect(last_response.status).to eq(403)
          proxy_get(tenant_domain, '/auth/account', cookie: @cookie)
          expect(last_response.status).to eq(200)
        end
      end

      it 'HP-ORIGIN-01: refuses a foreign Origin with a valid CSRF token but permits tenant Origin logout' do
        login_on(tenant_domain)
        proxy_get(tenant_domain, '/auth', cookie: @cookie)
        token = last_response.headers['X-CSRF-Token']
        expect(token).not_to be_nil
        logout_on(tenant_domain, token: token, origin: "https://#{other_host}")
        expect(last_response.status).to eq(403)
        proxy_get(tenant_domain, '/auth/account', cookie: @cookie)
        expect(last_response.status).to eq(200)
        logout_on(tenant_domain, token: token, origin: "https://#{tenant_domain}")
        expect(last_response.status).to eq(200)
        proxy_get(tenant_domain, '/auth/account', cookie: @cookie)
        expect(last_response.status).to eq(401)
      end

      it 'HP-ORIGIN-02: pins origin-target logout admission rather than claiming tenant-only Origin enforcement' do
        login_on(tenant_domain)
        proxy_get(tenant_domain, '/auth', cookie: @cookie)
        token = last_response.headers['X-CSRF-Token']
        expect(token).not_to be_nil
        # With rewrite off, HttpOrigin's own base_url comparison still admits
        # the canonical backend Origin. With rewrite on, that comparison uses
        # the tenant authority instead. This is a baseline, not a claim that
        # the off-mode stack enforces a tenant-only Origin boundary.
        logout_on(tenant_domain, token: token, origin: "https://#{canonical_host}")
        expect(last_response.status).to eq(rewrite ? 403 : 200)
        proxy_get(tenant_domain, '/auth/account', cookie: @cookie)
        expect(last_response.status).to eq(rewrite ? 200 : 401)
      end

      it 'HP-ADMIN-02: still enforces the role gate on the canonical host' do
        login_on(canonical_host)
        proxy_get(canonical_host, '/api/colonel/info', cookie: @cookie)
        expect(last_response.status).to eq(403)
        proxy_get(canonical_host, '/auth/account', cookie: @cookie)
        expect(last_response.status).to eq(200)
      end

      it 'HP-ADMIN-01: refuses tenant admin access even when replaying a real colonel session' do
        login_on(canonical_host, colonel: true)
        expect(stored_session(@sid)['role']).to eq('colonel')
        proxy_get(canonical_host, '/api/colonel/info', cookie: @cookie)
        expect(last_response.status).to eq(200),
          "HP-ADMIN-01 canonical control: #{last_response.status} #{last_response.body}"
        proxy_get(tenant_domain, '/api/colonel/info', cookie: @cookie)
        expect(last_response.status).to eq(404)
        proxy_get(tenant_domain, '/colonel', cookie: @cookie)
        expect(last_response.status).to eq(404)
        # The host gate refuses before the session surface evaluator; the
        # canonical session remains usable rather than being destroyed.
        proxy_get(canonical_host, '/api/colonel/info', cookie: @cookie)
        expect(last_response.status).to eq(200)
      end

      # The one Set-Cookie writer whose Domain is taken from the request host:
      # CookieTossing (inside Onetime::Middleware::Security, below the rewrite)
      # expires a duplicated session cookie on Rack's host and each parent
      # domain. The setting changes which host that is.
      it "HP-COOKIE-03: expires a duplicated session cookie on #{rewrite ? 'the public host' : 'the origin target'} and its parent domains" do
        proxy_get(tenant_domain, '/auth', cookie: 'onetime.session=a; onetime.session=b')
        expect(last_response.status).to eq(403)
        expect(last_response.body).to eq('Forbidden')

        cookies = Array(last_response.headers['Set-Cookie']).flat_map { |value| value.split("\n") }
        clears  = cookies.select { |value| value.start_with?('onetime.session=;') }
        domains = rewrite ? [tenant_domain, 'acme-corp.example.com', 'example.com'] : [canonical_host, 'example.org']
        expect(clears).to eq(
          domains.flat_map do |domain|
            %w[/ /auth].map do |path|
              "onetime.session=; domain=#{domain}; path=#{path}; expires=Thu, 01 Jan 1970 00:00:00 GMT"
            end
          end,
        )
        # The session cookie issued alongside stays host-only in both runs.
        issued = cookies - clears
        expect(issued.size).to eq(1)
        expect(cookie_attributes(issued.first)).to eq(['path=/', 'expires=<time>', 'httponly', 'samesite=lax'])
      end
    end
  end
end
