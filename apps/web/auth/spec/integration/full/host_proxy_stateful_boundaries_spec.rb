# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/tenant_test_fixtures'
require_relative '../../support/external_https_browser'

# Real login, session persistence and mounted routes; no injected rack.session.
# Cookie replay deliberately bypasses browser host-only delivery so a refusal
# proves the server-side surface gate, not Rack::Test's cookie jar behavior.
# Run: tests/lanes/run full-sqlite --only apps/web/auth/spec/integration/full/host_proxy_stateful_boundaries_spec.rb

# Rack::Protection::HttpOrigin compares Origin with scheme://host[:port] as
# Rack reads them from the request, and falls back to the shared allow_if
# (Onetime::Middleware::HttpOriginOptions), which admits exactly
# https://{display domain}, and only for a host DomainStrategy classified
# :canonical, :subdomain or :custom (#4669; the H-03 examples cover an
# unregistered host). Both mounts sit below PublicHostRewrite, so with the
# setting on the first comparison is against the public authority.
#
# {public} is the tenant's custom domain, {target} the canonical host the
# proxy addresses the origin server by, {foreign} another verified custom
# domain. `off` and `on` are the verdict with site.network.public_host_rewrite
# off and on; `rewritten` says whether the setting changes the request at all.
#
# Three Origins are admitted only with the setting on: the public host with
# its non-default port (O05, O09) and the public host over http on a request
# the application sees as http (O12). Each is what a proxy that preserves
# Host already gets in either setting (O16, O19). The origin target stops
# being admitted with the setting on (O02, O07, O10, O14).
module HostProxyOrigin
  PROXIED = { host: '{target}', xfh: '{public}', proto: 'https', scheme: 'https', rewritten: true }.freeze

  SHAPES = {
    default_port: PROXIED,
    port_in_xfh: PROXIED.merge(xfh: '{public}:8443'),
    port_in_xfp: PROXIED.merge(xfp: '8443'),
    seen_as_http: PROXIED.merge(proto: nil, scheme: 'http'),
    host_preserved_port: { host: '{public}:8443', scheme: 'https', proto: 'https', rewritten: false },
    host_preserved_http: { host: '{public}', scheme: 'http', proto: nil, rewritten: false },
  }.freeze

  ROWS = [
    # --- Host rewritten to the origin target, default public port ------------
    { id: 'O01', shape: :default_port, origin: 'https://{public}', off: :admitted, on: :admitted },
    { id: 'O02', shape: :default_port, origin: 'https://{target}', off: :admitted, on: :refused },
    { id: 'O03', shape: :default_port, origin: 'https://{foreign}', off: :refused, on: :refused },
    { id: 'O04', shape: :default_port, origin: 'http://{public}', off: :refused, on: :refused },
    # --- public port 8443, carried in X-Forwarded-Host -----------------------
    { id: 'O05', shape: :port_in_xfh, origin: 'https://{public}:8443', off: :refused, on: :admitted },
    { id: 'O06', shape: :port_in_xfh, origin: 'https://{public}', off: :admitted, on: :admitted },
    { id: 'O07', shape: :port_in_xfh, origin: 'https://{target}', off: :admitted, on: :refused },
    { id: 'O08', shape: :port_in_xfh, origin: 'https://{foreign}:8443', off: :refused, on: :refused },
    # --- public port 8443, carried in X-Forwarded-Port -----------------------
    { id: 'O09', shape: :port_in_xfp, origin: 'https://{public}:8443', off: :refused, on: :admitted },
    { id: 'O10', shape: :port_in_xfp, origin: 'https://{target}:8443', off: :admitted, on: :refused },
    { id: 'O11', shape: :port_in_xfp, origin: 'https://{target}', off: :refused, on: :refused },
    # --- no forwarded scheme: the application sees http ----------------------
    { id: 'O12', shape: :seen_as_http, origin: 'http://{public}', off: :refused, on: :admitted },
    { id: 'O13', shape: :seen_as_http, origin: 'https://{public}', off: :admitted, on: :admitted },
    { id: 'O14', shape: :seen_as_http, origin: 'http://{target}', off: :admitted, on: :refused },
    { id: 'O15', shape: :seen_as_http, origin: 'http://{foreign}', off: :refused, on: :refused },
    # --- controls: the proxy preserves Host, nothing is rewritten ------------
    { id: 'O16', shape: :host_preserved_port, origin: 'https://{public}:8443', off: :admitted, on: :admitted },
    { id: 'O17', shape: :host_preserved_port, origin: 'https://{public}', off: :admitted, on: :admitted },
    { id: 'O18', shape: :host_preserved_port, origin: 'https://{foreign}:8443', off: :refused, on: :refused },
    { id: 'O19', shape: :host_preserved_http, origin: 'http://{public}', off: :admitted, on: :admitted },
  ].freeze
end

RSpec.describe 'Host proxy stateful boundaries', :shared_db_state, type: :integration do
  include Rack::Test::Methods
  include_context 'tenant fixtures'
  include_context 'domains enabled'
  # proxy_headers sends X-Forwarded-Proto: https from a browser on https. The
  # rows that carry a cookie by hand (header 'Cookie') are not affected.
  include_context 'external HTTPS browser'

  before(:all) { boot_onetime_app }

  let(:account_email) { unique_test_email('host-boundary') }
  let!(:account_id) { seed_account_with_password(account_email) }
  let!(:account_customer) do
    Onetime::Customer.find_by_extid(auth_db[:accounts].where(id: account_id).get(:external_id))
  end
  let(:other_host) { "other-#{test_run_id}.example.net" }
  let(:unregistered_host) { "unregistered-#{test_run_id}.tenant-example.com" }
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

  def unregistered_headers(forwarded:)
    proxy_headers(unregistered_host)
    unless forwarded
      header 'Host', unregistered_host
      header 'X-Forwarded-Host', nil
    end
  end

  # The lambda refuses the unregistered host in both shapes (#4669). With
  # Host preserved, the request's own authority is https://{unregistered},
  # so HttpOrigin's base-url comparison admits that Origin before the lambda
  # runs; with Host rewritten, the authority is the origin target and the
  # lambda decides.
  def expect_unregistered_request(forwarded:)
    env = last_request.env
    expect(env['onetime.display_domain']).to eq(unregistered_host)
    expect(env['onetime.domain_strategy']).to eq(:invalid)
    expect(env.key?(Onetime::Middleware::PublicHostRewrite::ORIGINAL_HTTP_HOST)).to be(false)
    expect(Rack::Request.new(env).host).to eq(forwarded ? canonical_host : unregistered_host)
    expect(Rack::Request.new(env).base_url).to eq("https://#{forwarded ? canonical_host : unregistered_host}")
    expect(Onetime::Middleware::HttpOriginOptions::ALLOW_IF.call(env)).to be(false)
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

  def fill(value)
    value&.gsub('{public}', tenant_domain)&.gsub('{target}', canonical_host)&.gsub('{foreign}', other_host)
  end

  # Send one unsafe request in the row's shape, then drop the headers the
  # other helpers do not reset.
  def shaped_post(row, path, body, token: nil, cookie: nil)
    shape = HostProxyOrigin::SHAPES.fetch(row[:shape])
    clear_cookies
    header 'Host', fill(shape[:host])
    header 'X-Forwarded-Host', fill(shape[:xfh])
    header 'X-Forwarded-Port', shape[:xfp]
    header 'X-Forwarded-Proto', shape[:proto]
    header 'Accept', 'application/json'
    header 'Content-Type', 'application/json'
    header 'X-CSRF-Token', token
    header 'Cookie', cookie
    header 'Origin', fill(row[:origin])
    post "#{shape[:scheme]}://#{tenant_domain}#{path}", JSON.generate(body)
  ensure
    header 'X-Forwarded-Port', nil
  end

  def expect_shape_rewritten(row, rewrite)
    expect(last_request.env.key?(Onetime::Middleware::PublicHostRewrite::ORIGINAL_HTTP_HOST))
      .to eq(rewrite && HostProxyOrigin::SHAPES.fetch(row[:shape])[:rewritten])
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
  # Its cookie carries no Domain and takes SameSite from site.session. Secure
  # it takes from site.session too, and adds on any request it sees as https
  # (Onetime::Session#set_cookie, upgrade-only): proxy_headers forwards
  # https, so the lane's own secure:false still yields a Secure cookie, and
  # is run next to secure:true.
  describe 'the session Set-Cookie, compared across the setting' do
    [
      { secure: false, same_site: 'lax',
        attributes: ['path=/', 'expires=<time>', 'secure', 'httponly', 'samesite=lax'] },
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

  describe 'HTTPS policy through the complete mounted stack' do
    [false, true].product([false, true], [false, true]).each do |assume, trusted, rewrite|
      it "HP-HTTPS-01: persists Secure sessions with assume_https=#{assume}, trusted=#{trusted}, rewrite=#{rewrite}" do
        network = OT.conf['site']['network']
        saved = network.slice('assume_https', 'trusted_proxy', 'public_host_rewrite')
        network.merge!(
          'assume_https' => assume,
          'public_host_rewrite' => rewrite,
          'trusted_proxy' => { 'enabled' => true, 'mode' => 'filter', 'cidrs' => ['203.0.113.7/32'] },
        )
        with_session_cookie_config(secure: true, same_site: 'lax') do
          clear_cookies
          proxy_headers(tenant_domain)
          peer = trusted ? '203.0.113.7' : '198.51.100.9'
          get "http://#{canonical_host}/auth", {}, 'REMOTE_ADDR' => peer

          expected_ssl = assume || trusted
          expected_host = trusted ? tenant_domain : canonical_host
          request_env = last_request.env
          expect(last_response.status).to eq(200)
          expect(Rack::Request.new(request_env).ssl?).to eq(expected_ssl)
          expect(request_env[Rack::DetectHost.result_field_name]).to eq(expected_host)
          expect(request_env['onetime.domain_strategy']).to eq(trusted ? :custom : :canonical)
          expect(request_env).not_to have_key('HTTP_X_FORWARDED_HOST')
          expect(request_env).not_to have_key('HTTP_X_FORWARDED_PROTO') unless trusted
          session_cookie = Array(last_response.headers['Set-Cookie']).find { |value| value.start_with?('onetime.session=') }
          if expected_ssl
            expect(session_cookie).not_to be_nil
            expect(cookie_attributes(session_cookie)).to include('secure', 'httponly', 'samesite=lax')
            expect(session_cookie).not_to match(/;\s*domain=/i)
            token = last_response.headers.fetch('X-CSRF-Token')
            clear_cookies
            proxy_headers(tenant_domain)
            header 'Cookie', session_cookie.split(';').first
            header 'Origin', "https://#{expected_host}"
            header 'Content-Type', 'application/json'
            header 'X-CSRF-Token', token
            post "http://#{canonical_host}/auth/login", JSON.generate(
              login: account_email, password: AuthTestConstants::TEST_PASSWORD, shrimp: token,
            ), 'REMOTE_ADDR' => peer
            expect(last_response.status).to eq(200), last_response.body
            expect(Rack::Request.new(last_request.env).ssl?).to be(true)
            cookie = Array(last_response.headers['Set-Cookie']).find { |value| value.start_with?('onetime.session=') }
            expect(cookie).not_to be_nil
            expect(cookie_attributes(cookie)).to include('secure')
            data = stored_session(cookie.split(';').first.split('=', 2).last)
            expect(data['account_id']).to eq(account_id)
            expect(data['authenticated']).to be(true)
          else
            expect(session_cookie).to be_nil
          end
        end
      ensure
        saved.each { |key, value| network[key] = value } if saved
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

      # Onetime::Session writes the session's metadata row after the layers
      # below have returned, and resolves the active organization then
      # (Sessions::TrackMetadata -> OrganizationLoader, which reads HTTP_HOST).
      # The account belongs to the organization that owns the tenant domain
      # and has another organization as its own default. Behind a proxy that
      # rewrites Host the loader sees the origin target with the setting off,
      # finds no custom domain for it and falls to the account's default;
      # with the setting on it sees the tenant domain and selects its owner.
      it "HP-ORG-01: records #{rewrite ? "the tenant domain's organization" : "the account's default organization"} " \
         'as the session\'s active organization for a tenant sign-in' do
        home = Onetime::Organization.create!("Home #{test_run_id}", account_customer, account_email)
        Onetime::OrganizationMembership.ensure_membership(test_organization, account_customer, role: 'member')
        account_customer.default_org_id = home.objid
        account_customer.save

        login_on(tenant_domain)
        proxy_get(tenant_domain, '/auth/account', cookie: @cookie)
        expect(last_response.status).to eq(200)
        expect(last_request.env.key?(Onetime::Middleware::PublicHostRewrite::ORIGINAL_HTTP_HOST)).to eq(rewrite)

        expected = rewrite ? test_organization.objid : home.objid
        expect(Onetime::SessionMetadata.load(@sid).org_id).to eq(expected)
      ensure
        home&.destroy!
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

      # A refusal is Rack::Protection's own 403, text/plain "Forbidden", sent
      # before the application runs.
      def expect_origin_refusal
        expect(last_response.status).to eq(403)
        expect(last_response.content_type).to eq('text/plain')
        expect(last_response.body).to eq('Forbidden')
      end

      describe 'H-03: unregistered display host on the auth mount' do
        # A CSRF token from the unregistered host, a foreign Origin refused,
        # then the host's own Origin left set for the example's POSTs.
        # Returns the token.
        def unregistered_recovery_token(forwarded:)
          expect(Onetime::CustomDomain.from_display_domain(unregistered_host)).to be_nil
          expect(Onetime::Jobs::Publisher).not_to receive(:enqueue_email_raw)
          unregistered_headers(forwarded: forwarded)
          get '/auth'
          token = last_response.headers['X-CSRF-Token']
          expect(token).not_to be_nil
          header 'Content-Type', 'application/json'
          header 'X-CSRF-Token', token
          header 'Origin', "https://#{other_host}"
          post '/auth/reset-password-request', JSON.generate(login: account_email, shrimp: token)
          expect_origin_refusal

          clear_body_headers
          header 'Content-Type', 'application/json'
          header 'Origin', "https://#{unregistered_host}"
          token
        end

        # A replayed canonical session with a valid CSRF token posting an
        # account mutation from the unregistered host. Logout deliberately
        # succeeds after clearing a mismatched session, so it is not the
        # mutation used. Returns the stored password hash before the POST.
        def replay_canonical_session_change_password(forwarded:)
          login_on(canonical_host)
          proxy_get(canonical_host, '/auth', cookie: @cookie)
          token = last_response.headers['X-CSRF-Token']
          expect(token).not_to be_nil
          password_hash = auth_db[:account_password_hashes].where(id: account_id).get(:password_hash)
          unregistered_headers(forwarded: forwarded)
          header 'Cookie', @cookie
          header 'Content-Type', 'application/json'
          header 'X-CSRF-Token', token
          header 'Origin', "https://#{unregistered_host}"
          post '/auth/change-password', JSON.generate(
            shrimp: token, password: 'MustNotBeApplied123!', 'password-confirm': 'MustNotBeApplied123!',
          )
          expect_unregistered_request(forwarded: forwarded)
          password_hash
        end

        # Host preserved: the request's own authority is the unregistered
        # host, so HttpOrigin's base-url comparison admits its Origin before
        # the lambda runs, and the application answers.
        it 'H03-A-preserved: the base-url comparison admits the matching Origin; recovery and SSO are refused' do
          token = unregistered_recovery_token(forwarded: false)
          post '/auth/reset-password-request', JSON.generate(login: account_email, shrimp: token)
          expect_unregistered_request(forwarded: false)
          expect(last_response.status).to eq(404)
          expect(JSON.parse(last_response.body)).to eq(Auth::ErrorTranslator::NOT_FOUND_BODY.transform_keys(&:to_s))
          expect(auth_db[:account_password_reset_keys].where(id: account_id).count).to eq(0)

          clear_body_headers
          post '/auth/sso/entra'
          expect_unregistered_request(forwarded: false)
          expect(last_response.status).to eq(302)
          expect(last_response.headers['Location']).to end_with('/signin?auth_error=sso_not_configured')
        end

        # Host rewritten to the origin target: the authority differs from the
        # Origin, so the lambda decides, and it refuses the unregistered host
        # (#4669) before recovery or SSO initiation runs.
        it 'H03-A-forwarded: refuses the matching Origin of an unregistered host before recovery or SSO runs' do
          token = unregistered_recovery_token(forwarded: true)
          post '/auth/reset-password-request', JSON.generate(login: account_email, shrimp: token)
          expect_unregistered_request(forwarded: true)
          expect_origin_refusal
          expect(auth_db[:account_password_reset_keys].where(id: account_id).count).to eq(0)

          clear_body_headers
          post '/auth/sso/entra'
          expect_unregistered_request(forwarded: true)
          expect_origin_refusal
        end

        it 'H03-SESSION-preserved: does not authorize a replayed canonical session' do
          password_hash = replay_canonical_session_change_password(forwarded: false)
          expect(last_response.status).to eq(401)
          expect(JSON.parse(last_response.body).to_s).to include('surface_mismatch')
          expect(Onetime::Operations::Sessions::Store.find_key(Familia.dbclient, @sid)).to be_nil
          expect(auth_db[:account_password_hashes].where(id: account_id).get(:password_hash)).to eq(password_hash)
        end

        # Refused by HttpOrigin before the application runs, so the surface
        # gate never evaluates the replayed session: it is kept, and the
        # password is unchanged.
        it 'H03-SESSION-forwarded: refuses the matching Origin before the replayed session is evaluated' do
          password_hash = replay_canonical_session_change_password(forwarded: true)
          expect_origin_refusal
          expect(Onetime::Operations::Sessions::Store.find_key(Familia.dbclient, @sid)).not_to be_nil
          expect(auth_db[:account_password_hashes].where(id: account_id).get(:password_hash)).to eq(password_hash)
        end
      end

      describe 'HttpOrigin on the auth app mount (authenticated_web profile)' do
        HostProxyOrigin::ROWS.each do |row|
          verdict = row.fetch(rewrite ? :on : :off)
          changed = row[:off] == row[:on] ? '' : " (#{row[:off]} with the setting off, #{row[:on]} with it on)"

          it "HP-ORIGIN-A#{row[:id]}: #{row[:shape]}, Origin #{row[:origin]} is #{verdict}#{changed}" do
            login_on(tenant_domain)
            proxy_get(tenant_domain, '/auth', cookie: @cookie)
            token = last_response.headers['X-CSRF-Token']
            expect(token).not_to be_nil

            # A valid session and CSRF token, so Origin alone decides.
            shaped_post(row, '/auth/logout', { shrimp: token }, token: token, cookie: @cookie)
            expect_shape_rewritten(row, rewrite)

            if verdict == :admitted
              expect(last_response.status).to eq(200)
              expect(JSON.parse(last_response.body)).to eq('success' => 'You have been logged out')
            else
              expect_origin_refusal
            end
            # The session is gone exactly when the logout was admitted.
            proxy_get(tenant_domain, '/auth/account', cookie: @cookie)
            expect(last_response.status).to eq(verdict == :admitted ? 401 : 200)
          end
        end
      end

      # site.middleware.http_origin is off by default and in the lane. The
      # route is outside the auth app, so its HttpOrigin is not involved, and
      # anonymous, so AuthenticityToken lets it through: this mount decides.
      describe 'HttpOrigin on the Onetime::Middleware::Security mount' do
        def security_http_origin(value)
          middleware                = (OT.conf['site']['middleware'] ||= {})
          @saved_http_origin        = middleware['http_origin']
          middleware['http_origin'] = value
        end

        after { OT.conf['site']['middleware']['http_origin'] = @saved_http_origin }

        it 'HP-ORIGIN-S00: leaves a foreign Origin alone while site.middleware.http_origin is off (control)' do
          security_http_origin(false)
          shaped_post(HostProxyOrigin::ROWS.find { |row| row[:id] == 'O03' }, '/api/v3/secret/status', {})

          expect(last_response.status).to eq(200)
        end

        # A foreign Origin, then the unregistered host's own Origin, on this
        # mount's HttpOrigin; the matching Origin's response is the last one.
        def unregistered_status_posts(forwarded:)
          security_http_origin(true)
          expect(Onetime::CustomDomain.from_display_domain(unregistered_host)).to be_nil
          unregistered_headers(forwarded: forwarded)
          header 'Content-Type', 'application/json'
          header 'Origin', "https://#{other_host}"
          post '/api/v3/secret/status', '{}'
          expect_origin_refusal

          clear_body_headers
          header 'Content-Type', 'application/json'
          header 'Origin', "https://#{unregistered_host}"
          post '/api/v3/secret/status', '{}'
          expect_unregistered_request(forwarded: forwarded)
        end

        # Host preserved: the base-url comparison admits the unregistered
        # host's own Origin before the lambda runs.
        it 'H03-S-preserved: the base-url comparison admits the matching Origin of an unregistered host' do
          unregistered_status_posts(forwarded: false)
          expect(last_response.status).to eq(200)
          expect(JSON.parse(last_response.body)).to eq('records' => [], 'count' => 0)
        end

        it 'H03-S-forwarded: refuses the matching Origin of an unregistered host like a foreign one' do
          unregistered_status_posts(forwarded: true)
          expect_origin_refusal
        end

        HostProxyOrigin::ROWS.each do |row|
          verdict = row.fetch(rewrite ? :on : :off)
          changed = row[:off] == row[:on] ? '' : " (#{row[:off]} with the setting off, #{row[:on]} with it on)"

          it "HP-ORIGIN-S#{row[:id]}: #{row[:shape]}, Origin #{row[:origin]} is #{verdict}#{changed}" do
            # Read when the stack is built, which is this example's first request.
            security_http_origin(true)
            shaped_post(row, '/api/v3/secret/status', {})
            expect_shape_rewritten(row, rewrite)

            if verdict == :admitted
              expect(last_response.status).to eq(200)
              expect(JSON.parse(last_response.body)).to eq('records' => [], 'count' => 0)
            else
              expect_origin_refusal
            end
          end
        end
      end

      # The one Set-Cookie writer whose Domain is taken from the request:
      # CookieTossing expires a duplicated session cookie on the host
      # DetectHost resolved and each parent domain. It runs above
      # Onetime::Session and the rewrite, so the setting does not change the
      # host, and the refusal sets no session cookie.
      it 'HP-COOKIE-03: expires a duplicated session cookie on the public host and its parent domains' do
        proxy_get(tenant_domain, '/auth', cookie: 'onetime.session=a; onetime.session=b')
        expect(last_response.status).to eq(403)
        expect(last_response.body).to eq('Forbidden')

        cookies = Array(last_response.headers['Set-Cookie']).flat_map { |value| value.split("\n") }
        expect(cookies).to eq(
          [tenant_domain, 'acme-corp.example.com', 'example.com'].flat_map do |domain|
            %w[/ /auth].map do |path|
              "onetime.session=; domain=#{domain}; path=#{path}; expires=Thu, 01 Jan 1970 00:00:00 GMT"
            end
          end,
        )
      end
    end
  end
end
