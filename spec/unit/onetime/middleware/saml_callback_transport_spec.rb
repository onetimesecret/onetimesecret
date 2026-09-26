# frozen_string_literal: true

require 'spec_helper'
require 'rack/mock'
require 'rack/session/cookie'
require 'rack/protection'
require 'climate_control'
require 'onetime/middleware/http_origin_options'
require 'zlib'
require 'sentry-ruby'
require 'onetime/application/request_logger'
require 'onetime/middleware/saml_callback_transport'
require 'onetime/sso_provider/request_bound_saml'
require 'onetime/sso_provider/saml'
require_relative '../../../support/saml/test_idp'

# Real signed assertions, Rack cookie round trips, and real lane-only Valkey
# Lua/expiry semantics. Cookie omission on cross-site POST is modeled explicitly;
# this is not a claim of browser-level SameSite validation.
RSpec.describe Onetime::Middleware::SamlCallbackTransport do
  let(:store) { Onetime::Security::SamlCallbackStore }
  let(:idp) { SamlSpec::TestIdp.new }
  let(:host) { 'https://ots.example.com' }
  let(:path) { '/auth/sso/saml/callback' }
  let(:reached) { [] }
  let(:failures) { [] }
  let(:options) do
    Onetime::SsoProvider::Saml.strategy_options_for(
      idp_sso_service_url: 'https://idp.example.com/sso', idp_entity_id: idp.entity_id, idp_cert: idp.cert_pem,
    ).merge(path_prefix: '/auth/sso', sp_entity_id: "#{host}/metadata", assertion_consumer_service_url: "#{host}#{path}")
  end
  let(:http_origin_options) do
    { allow_if: ->(env) { env['HTTP_ORIGIN'] == 'https://idp.example.com' && env['PATH_INFO'] == '/auth/sso/saml/callback' } }
  end
  # The resolved public host (DetectHost + DomainStrategy in production).
  # Stage stages only for a host with an active SAML route; the top-level
  # stubs below make ots.example.com the usable platform ACS host.
  let(:display_domain) { 'ots.example.com' }
  let(:app) do
    opts = options
    origin_options = http_origin_options
    authenticated = reached
    stack = Rack::Builder.new do
      use Onetime::Middleware::SamlCallbackTransport::Boundary
      use Rack::Session::Cookie, secret: 'x' * 64, same_site: :lax, secure: true
      use Rack::Protection::HttpOrigin, **origin_options
      use Onetime::Middleware::SamlCallbackTransport::Stage
      use OmniAuth::Strategies::RequestBoundSAML, **opts
      run lambda { |env|
        authenticated << env['omniauth.auth'] if env['omniauth.auth']
        [200, { 'content-type' => 'text/plain' }, ['app']]
      }
    end.to_app
    resolved = display_domain
    ->(env) { env['onetime.display_domain'] = resolved; stack.call(env) }
  end

  around do |example|
    config = OmniAuth.config
    saved = %i[on_failure request_validation_phase logger test_mode full_host].to_h { |key| [key, config.public_send(key)] }
    recorded = failures
    config.test_mode = false
    config.full_host = nil
    config.request_validation_phase = nil
    config.logger = Logger.new(File::NULL)
    config.on_failure = ->(env) { recorded << env['omniauth.error.type']; [401, {}, ['refused']] }
    example.run
  ensure
    saved.each { |key, value| config.public_send(:"#{key}=", value) }
  end

  around do |example|
    ClimateControl.modify(
      SAML_ROUTE_NAME: 'saml', SAML_ALLOW_NULL_ORIGIN: nil,
      SAML_IDP_SSO_SERVICE_URL: 'https://idp.example.com/sso',
      SAML_IDP_ENTITY_ID: idp.entity_id, SAML_IDP_CERT: idp.cert_pem,
      SAML_NAME_ID_FORMAT: nil, SAML_SP_ENTITY_ID: nil,
      SAML_CALLBACK_GLOBAL_LIMIT: nil, SAML_CALLBACK_SOURCE_LIMIT: nil,
    ) { example.run }
  end

  before do
    stub_const('Onetime::Security::SamlCallbackStore::PREFIX', "spec:saml:callback:#{SecureRandom.hex(8)}")
    allow(Onetime).to receive(:get_logger).and_return(double(warn: nil, debug: nil))
    # Platform SAML is configured (env above), usable, and pinned to `host`,
    # so HttpOriginOptions.saml_callback_route_active? admits staging.
    allow(Onetime).to receive(:session_config).and_return('same_site' => 'lax', 'secure' => true)
    allow(Onetime).to receive(:auth_config).and_return(instance_double(Onetime::AuthConfig, sso_enabled?: true))
    allow(Onetime::SsoProvider::Saml).to receive(:platform_base_url).and_return(host)
    store.reset_limits!
  end

  after { store.reset_limits! }

  def start
    response = Rack::MockRequest.new(app).post("#{host}/auth/sso/saml")
    expect(response.status).to eq(302)
    expect(response['set-cookie'].to_s).to include('samesite=lax')
    cookie = Array(response['set-cookie']).first.split(';').first
    query = Rack::Utils.parse_query(URI.parse(response['location']).query)
    xml = Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(Base64.decode64(query.fetch('SAMLRequest')))
    [cookie, xml[/\sID=['"]([^'"]+)['"]/, 1]]
  end

  def assertion(request_id)
    idp.response(in_response_to: request_id, acs_url: "#{host}#{path}", audience: "#{host}/metadata", conditions_expiry: nil)
  end

  def stage(response, **env)
    Rack::MockRequest.new(app).post("#{host}#{path}", params: { 'SAMLResponse' => response }, 'HTTP_ORIGIN' => 'https://idp.example.com', **env)
  end

  def complete(location, cookie)
    Rack::MockRequest.new(app).get("#{host}#{location}", 'HTTP_COOKIE' => cookie)
  end

  context 'with the operator null-origin policy and real HttpOrigin options' do
    let(:http_origin_options) { Onetime::Middleware::HttpOriginOptions.options }

    around do |example|
      ClimateControl.modify(SAML_ALLOW_NULL_ORIGIN: 'true') { example.run }
    end

    it 'stages literal null but authenticates only after signed, session-bound completion' do
      cookie, request_id = start
      response = stage(assertion(request_id), 'HTTP_ORIGIN' => 'null')
      expect(response.status).to eq(303)
      expect(response['set-cookie']).to be_nil
      expect(reached).to be_empty
      expect(complete(response['location'], cookie).status).to eq(200)
      expect(reached.size).to eq(1)
      expect(complete(response['location'], cookie).status).to eq(401)
    end

    it 'denies literal null before staging when the operator has not opted in' do
      cookie, request_id = start
      ClimateControl.modify(SAML_ALLOW_NULL_ORIGIN: nil) do
        expect(store).not_to receive(:stage)
        response = stage(assertion(request_id), 'HTTP_ORIGIN' => 'null', 'HTTP_COOKIE' => cookie)
        expect(response.status).to eq(403)
        expect(response['set-cookie']).to be_nil
        expect(reached).to be_empty
      end
    end

    it 'does not authenticate null-origin assertions without the initiating session' do
      cookie, request_id = start
      other_cookie, = start
      response = stage(assertion(request_id), 'HTTP_ORIGIN' => 'null')
      expect(response.status).to eq(303)
      expect(complete(response['location'], '').status).to eq(401)
      expect(complete(response['location'], other_cookie).status).to eq(401)
      expect(reached).to be_empty
      expect(complete(response['location'], cookie).status).to eq(200)
    end

    it 'refuses unsigned assertions even after the null-origin POST was admitted' do
      cookie, request_id = start
      unsigned = idp.response(in_response_to: request_id, acs_url: "#{host}#{path}", audience: "#{host}/metadata", sign: false)
      response = stage(unsigned, 'HTTP_ORIGIN' => 'null')
      expect(response.status).to eq(303)
      expect(complete(response['location'], cookie).status).to eq(401)
      expect(reached).to be_empty
    end
  end

  it 'preserves a Lax cookie on a cookieless POST and authenticates only on the recovered-session GET' do
    cookie, request_id = start
    response = stage(assertion(request_id))
    expect(response.status).to eq(303)
    expect(response['set-cookie']).to be_nil
    expect(response['cache-control']).to eq('no-store')
    expect(response['referrer-policy']).to eq('no-referrer')
    expect(response['location']).to match(%r{\A/auth/sso/saml/callback\?saml_handle=[0-9a-f]{64}\z})
    expect(reached).to be_empty
    expect(complete(response['location'], cookie).status).to eq(200)
    expect(reached.size).to eq(1)
    expect(complete(response['location'], cookie).status).to eq(401)
    expect(reached.size).to eq(1)
  end

  it 'does not let a different pending session consume the rightful handle' do
    original, request_id = start
    other, = start
    response = stage(assertion(request_id))
    expect(complete(response['location'], other).status).to eq(401)
    expect(complete(response['location'], '').status).to eq(401)
    expect(reached).to be_empty
    expect(complete(response['location'], original).status).to eq(200)
    expect(reached.size).to eq(1)
  end

  it 'ignores cookies on POST even when the browser sends them (SameSite=None compatibility)' do
    cookie, request_id = start
    response = stage(assertion(request_id), 'HTTP_COOKIE' => cookie)
    expect(response.status).to eq(303)
    expect(response['set-cookie']).to be_nil
    expect(reached).to be_empty
    expect(complete(response['location'], cookie).status).to eq(200)
  end

  it 'refuses unlisted POST origins without replacing the original cookie' do
    cookie, request_id = start
    response = stage(assertion(request_id), 'HTTP_ORIGIN' => 'https://evil.example', 'HTTP_COOKIE' => cookie)
    expect(response.status).to eq(403)
    expect(response['set-cookie']).to be_nil
    expect(reached).to be_empty
  end

  it 'leaves ordinary routes subject to Origin checks' do
    response = Rack::MockRequest.new(app).post("#{host}/ordinary", 'HTTP_ORIGIN' => 'https://idp.example.com')
    expect(response.status).to eq(403)
  end

  it 'bounds bodies before any downstream parser, including absent Content-Length' do
    inner = double('parser')
    expect(inner).not_to receive(:call)
    boundary = described_class::Boundary.new(inner)
    env = Rack::MockRequest.env_for("#{host}#{path}", method: 'POST', input: 'x' * (described_class::MAX_BODY_BYTES + 1), 'CONTENT_TYPE' => 'application/x-www-form-urlencoded')
    env.delete('CONTENT_LENGTH')
    expect(boundary.call(env).first).to eq(413)
  end

  it 'fails closed on storage write and read failures without exposing details' do
    cookie, request_id = start
    allow(store).to receive(:stage).and_raise(StandardError, 'secret assertion')
    response = stage(assertion(request_id))
    expect(response.status).to eq(503)
    expect(response.body).not_to include('secret assertion')
    expect(response['set-cookie']).to be_nil
    allow(store).to receive(:read).and_raise(StandardError, 'secret assertion')
    expect(complete("#{path}?saml_handle=#{'a' * 64}", cookie).status).to eq(401)
    expect(reached).to be_empty
  end

  it 'rejects unsigned staged responses without consuming the handle' do
    cookie, request_id = start
    unsigned = idp.response(in_response_to: request_id, acs_url: "#{host}#{path}", audience: "#{host}/metadata", sign: false)
    response = stage(unsigned)
    expect(store).not_to receive(:consume)
    expect(complete(response['location'], cookie).status).to eq(401)
    expect(reached).to be_empty
  end

  it 'enforces real datastore single-use, scope, expiry, and per-source bounds' do
    scope = ['scope']
    handle = store.stage(response: 'assertion', scope: scope, source: 'one')
    expect(store.read(handle, scope: ['other'])).to be_nil
    response, raw = store.read(handle, scope: scope)
    expect(response).to eq('assertion')
    expect(Familia.dbclient.ttl(store.key(handle))).to be_between(1, store::TTL)
    expect(store.consume(handle, 'wrong')).to be(false)
    expect(store.consume(handle, raw)).to be(true)
    expect(store.consume(handle, raw)).to be(false)
    expect(store.read(handle, scope: scope)).to be_nil
    expired = store.stage(response: 'assertion', scope: scope, source: 'two')
    Familia.dbclient.pexpire(store.key(expired), 1)
    sleep 0.01
    expect(store.read(expired, scope: scope)).to be_nil
    (store.source_limit - 1).times { store.stage(response: 'a', scope: scope, source: 'one') }
    expect { store.stage(response: 'a', scope: scope, source: 'one') }.to raise_error(store::CapacityExceeded)
  end

  it 'reads the admission limits from the environment once, validated and clamped, warning on bad values' do
    expect([store.global_limit, store.source_limit]).to eq([store::DEFAULT_GLOBAL_LIMIT, store::DEFAULT_SOURCE_LIMIT])
    expect(store::DEFAULT_GLOBAL_LIMIT).to eq(256)
    expect(store::DEFAULT_SOURCE_LIMIT).to eq(64)
    allow(OT).to receive(:lw)

    ClimateControl.modify(SAML_CALLBACK_GLOBAL_LIMIT: '10', SAML_CALLBACK_SOURCE_LIMIT: '3') do
      store.reset_limits!
      expect([store.global_limit, store.source_limit]).to eq([10, 3])
    end
    # Memoized: a later environment change is not observed until reset.
    expect([store.global_limit, store.source_limit]).to eq([10, 3])
    expect(OT).not_to have_received(:lw)

    ClimateControl.modify(SAML_CALLBACK_GLOBAL_LIMIT: '10', SAML_CALLBACK_SOURCE_LIMIT: '500') do
      store.reset_limits!
      expect([store.global_limit, store.source_limit]).to eq([10, 10])
      expect(OT).to have_received(:lw).with(/SAML_CALLBACK_SOURCE_LIMIT=500 exceeds SAML_CALLBACK_GLOBAL_LIMIT=10/)
    end

    ['0', '-5', 'abc', '1.5', ' ', '0x10'].each do |bad|
      ClimateControl.modify(SAML_CALLBACK_GLOBAL_LIMIT: bad, SAML_CALLBACK_SOURCE_LIMIT: bad) do
        store.reset_limits!
        expect([store.global_limit, store.source_limit]).to eq([256, 64]), bad.inspect
      end
    end
    expect(OT).to have_received(:lw).with(/SAML_CALLBACK_GLOBAL_LIMIT=.* is not a positive integer; using 256/).at_least(:once)
    expect(OT).to have_received(:lw).with(/SAML_CALLBACK_SOURCE_LIMIT=.* is not a positive integer; using 64/).at_least(:once)

    ClimateControl.modify(SAML_CALLBACK_GLOBAL_LIMIT: '2', SAML_CALLBACK_SOURCE_LIMIT: '1') do
      store.reset_limits!
      # The Lua reads the configured values, not the defaults.
      store.stage(response: 'a', scope: [], source: 'one')
      expect { store.stage(response: 'a', scope: [], source: 'one') }.to raise_error(store::CapacityExceeded)
      store.stage(response: 'a', scope: [], source: 'two')
      expect { store.stage(response: 'a', scope: [], source: 'three') }.to raise_error(store::CapacityExceeded)
    end
  end

  it 'fails closed when atomic consumption fails after validation' do
    cookie, request_id = start
    response = stage(assertion(request_id))
    allow(store).to receive(:consume).and_raise(StandardError, 'private datastore details')
    expect(complete(response['location'], cookie).status).to eq(401)
    expect(failures).to include(:saml_callback_unavailable)
    expect(reached).to be_empty
  end

  it 'does not redeem a handle on another host or consume the rightful value' do
    cookie, request_id = start
    response = stage(assertion(request_id))
    wrong = Rack::MockRequest.new(app).get("https://other.example.com#{response['location']}", 'HTTP_COOKIE' => cookie)
    expect(wrong.status).to eq(401)
    expect(reached).to be_empty
    expect(complete(response['location'], cookie).status).to eq(200)
  end

  it 'refuses expired handles before authentication' do
    cookie, request_id = start
    response = stage(assertion(request_id))
    handle = Rack::Utils.parse_query(URI.parse(response['location']).query).fetch('saml_handle')
    Familia.dbclient.pexpire(store.key(handle), 1)
    sleep 0.01
    expect(complete(response['location'], cookie).status).to eq(401)
    expect(reached).to be_empty
  end

  it 'returns a bounded 429 without a cookie when staging is full' do
    allow(store).to receive(:global_limit).and_return(1)
    expect(stage('untrusted').status).to eq(303)
    response = stage('untrusted')
    expect(response.status).to eq(429)
    expect(response['set-cookie']).to be_nil
    expect(response['retry-after']).to eq(store::TTL.to_s)
  end

  it 'refuses invalid form types and oversized values without authenticating' do
    expect(store::MAX_RESPONSE_BYTES).to eq(128_000)
    expect(described_class::MAX_BODY_BYTES).to eq(200_000)
    expect(stage('a' * (store::MAX_RESPONSE_BYTES + 1)).status).to eq(400)
    expect(stage(['array']).status).to eq(400)
    response = Rack::MockRequest.new(app).post("#{host}#{path}", input: '{}', 'CONTENT_TYPE' => 'application/json')
    expect(response.status).to eq(415)
    expect(reached).to be_empty
  end

  it 'stages only base64 text (whitespace tolerated) and never stores anything else' do
    expect(store).not_to receive(:stage)
    ['<samlp:Response/>', 'PHNhbWw+#', "YWJj\u0000", 'YWJj-ZGVm_', '%PDF', 'a b*c'].each do |junk|
      response = stage(junk)
      expect(response.status).to eq(400), junk.inspect
      expect(response['set-cookie']).to be_nil
    end
    expect(reached).to be_empty
  end

  it 'tolerates line-wrapped and space-decoded base64 the way IdPs and form decoders produce it' do
    wrapped = "PHNhbWxwOlJlc3BvbnNlPg==\r\nPHNhbWxwOlJlc3BvbnNlPg==\n YWJj ZGVm\t"
    expect(stage(wrapped).status).to eq(303)
    expect(stage("#{'QUJD' * 20}=\n").status).to eq(303)
  end

  it 'matches only the configured callback route, including mounted and renamed routes' do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('SAML_ROUTE_NAME', 'saml').and_return('corp-saml')
    env = Rack::MockRequest.env_for('https://ots.example.com/sso/corp-saml/callback', method: 'POST')
    env['SCRIPT_NAME'] = '/auth'
    expect(described_class.callback_post?(env)).to be(true)
    env['PATH_INFO'] = '/sso/corp-saml/callback/'
    expect(described_class.callback_post?(env)).to be(true)
    env['PATH_INFO'] = '/sso/CORP-SAML/callback/'
    expect(described_class.callback_post?(env)).to be(true)
    env['PATH_INFO'] = '/sso/corp-saml/callback//'
    expect(described_class.callback_post?(env)).to be(false)
    env['PATH_INFO'] = '/sso/saml/callback'
    expect(described_class.callback_post?(env)).to be(false)
    env['PATH_INFO'] = '/sso/corp-saml'
    expect(described_class.callback_post?(env)).to be(false)
  end

  # The registered ACS has no trailing slash. HttpOrigin's callback allowance
  # is anchored to it, so through the full stack the spelling is refused
  # there; the Boundary still covers it (no cookie in, no Set-Cookie out,
  # body bounded), and Stage on its own refuses it rather than forwarding a
  # raw POST to the strategy. It is never staged.
  it 'covers the trailing-slash spelling without staging it' do
    cookie, request_id = start
    expect(store).not_to receive(:stage)
    response = Rack::MockRequest.new(app).post("#{host}#{path}/", params: { 'SAMLResponse' => assertion(request_id) },
      'HTTP_ORIGIN' => 'https://idp.example.com', 'HTTP_COOKIE' => cookie)
    expect(response.status).to eq(403)
    expect(response['set-cookie']).to be_nil
    expect(response['cache-control']).to eq('no-store')
    expect(reached).to be_empty

    inner = double('strategy')
    expect(inner).not_to receive(:call)
    bare = described_class::Boundary.new(described_class::Stage.new(inner))
    env = Rack::MockRequest.env_for("#{host}#{path}/", method: 'POST', params: { 'SAMLResponse' => assertion(request_id) },
      'HTTP_COOKIE' => cookie, 'onetime.display_domain' => 'ots.example.com')
    status, headers, = bare.call(env)
    expect(status).to eq(404)
    expect(headers['cache-control']).to eq('no-store')
    expect(env['HTTP_COOKIE']).to eq('')
    expect(complete("#{path}/?saml_handle=#{'a' * 64}", cookie).status).to eq(401)
  end

  describe 'staging admission by active SAML route' do
    let(:saml) { Onetime::SsoProvider::Saml }
    let(:tenant_config) do
      double('native SAML', provider_type: 'saml', platform_route_name: 'saml', enabled?: true, to_omniauth_options: {})
    end
    let(:resolution) { instance_double(Onetime::TenantSsoResolution, verified_custom_domain?: false, sso_config: nil) }

    before { allow(Onetime::TenantSsoResolution).to receive(:for).and_return(resolution) }

    it 'refuses with 404 and stores nothing when platform SAML is off, unusable or on another host' do
      expect(store).not_to receive(:stage)
      allow(saml).to receive(:platform_usable?).and_return(false)
      response = stage('untrusted')
      expect(response.status).to eq(404)
      expect(response['set-cookie']).to be_nil
      expect(response['cache-control']).to eq('no-store')

      allow(saml).to receive(:platform_usable?).and_call_original
      allow(Onetime).to receive(:auth_config).and_return(instance_double(Onetime::AuthConfig, sso_enabled?: false))
      expect(stage('untrusted').status).to eq(404)

      allow(Onetime).to receive(:auth_config).and_return(instance_double(Onetime::AuthConfig, sso_enabled?: true))
      allow(saml).to receive(:platform_base_url).and_return('https://elsewhere.example.com')
      expect(stage('untrusted').status).to eq(404)
      expect(reached).to be_empty
    end

    context 'on a custom domain' do
      let(:display_domain) { 'tenant.example.net' }

      it 'stages only for a verified domain whose own enabled SAML record names this route' do
        expect(stage('untrusted').status).to eq(404)

        allow(resolution).to receive(:verified_custom_domain?).and_return(true)
        expect(stage('untrusted').status).to eq(404)

        allow(resolution).to receive(:sso_config).and_return(tenant_config)
        expect(stage('untrusted').status).to eq(303)

        allow(tenant_config).to receive(:enabled?).and_return(false)
        expect(stage('untrusted').status).to eq(404)

        allow(tenant_config).to receive(:enabled?).and_return(true)
        allow(tenant_config).to receive(:to_omniauth_options).and_raise(Onetime::Problem, 'unusable')
        expect(stage('untrusted').status).to eq(404)

        allow(tenant_config).to receive(:to_omniauth_options).and_return({})
        allow(tenant_config).to receive(:platform_route_name).and_return('corporate')
        expect(stage('untrusted').status).to eq(404)
      end

      it 'does not stage without a resolved display domain' do
        allow(Onetime::TenantSsoResolution).to receive(:for).and_call_original
        stack = described_class::Stage.new(->(_env) { [200, {}, ['app']] })
        env = Rack::MockRequest.env_for("#{host}#{path}", method: 'POST', params: { 'SAMLResponse' => 'untrusted' })
        boundary = described_class::Boundary.new(stack)
        expect(store).not_to receive(:stage)
        expect(boundary.call(env).first).to eq(404)
      end
    end

    it 'fails closed when the route check raises' do
      allow(Onetime::Middleware::HttpOriginOptions).to receive(:saml_callback_route_active?).and_raise(RuntimeError, 'boom')
      expect(store).not_to receive(:stage)
      expect(stage('untrusted').status).to eq(404)
    end

    it 'does not gate the GET side: an unknown handle is still refused by the strategy, not the transport' do
      cookie, = start
      allow(saml).to receive(:platform_usable?).and_return(false)
      expect(complete("#{path}?saml_handle=#{'b' * 64}", cookie).status).to eq(401)
      expect(failures).to include(:saml_callback_missing)
    end
  end

  it 'does not let source-rejected requests exhaust the global quota' do
    now = Time.at(1_800_000_000)
    store.source_limit.times { store.stage(response: 'a', scope: [], source: 'attacker', now: now) }
    (store.global_limit * 2).times do
      expect { store.stage(response: 'a', scope: [], source: 'attacker', now: now) }.to raise_error(store::CapacityExceeded)
    end
    bucket = "#{store::PREFIX}:rate:#{now.to_i / store::TTL}"
    expect(Familia.dbclient.hget(bucket, 'total').to_i).to eq(store.source_limit)
    expect(Familia.dbclient.hlen(bucket)).to eq(2)
    expect(store.stage(response: 'legitimate', scope: [], source: 'other-source', now: now)).to match(store::HANDLE_PATTERN)
    expect(Familia.dbclient.hget(bucket, 'total').to_i).to eq(store.source_limit + 1)
  end

  it 'keeps callback credentials out of real HTTP debug logging and Sentry request capture even with PII enabled' do
    captured = []
    messages = []
    logger = double('HTTP logger')
    allow(logger).to receive(:info) { |message| messages << message }
    allow(logger).to receive(:warn) { |message| messages << message }
    allow(Onetime).to receive(:get_logger).with('HTTP').and_return(logger)
    allow(Onetime::ErrorHandler).to receive(:allowed_error_fields).and_return(%w[saml_handle SAMLResponse Referer])
    handle = 'd' * 64
    assertion = 'privateAssertionMarker0' # base64 alphabet: it has to be stageable
    capture = lambda do |env|
      request = Sentry::RequestInterface.new(env: env, send_default_pii: true, rack_env_whitelist: ['REQUEST_URI'])
      captured << JSON.generate(url: request.url, query: request.query_string, body: request.data, headers: request.headers, env: request.env)
    end
    endpoint = lambda do |env|
      expect(Rack::Request.new(env).GET['saml_handle']).to eq(handle)
      capture.call(env) # Also check capture during completion, not only after.
      [200, {}, ['ok']]
    end
    staged = described_class::Stage.new(endpoint)
    logged = Onetime::Application::RequestLogger.new(staged, 'capture' => 'debug')
    observed = lambda do |env|
      capture.call(env)
      response = logged.call(env)
      capture.call(env)
      response
    end
    boundary = described_class::Boundary.new(observed)
    get_env = Rack::MockRequest.env_for("#{host}#{path}?saml_handle=#{handle}&SAMLResponse=#{assertion}",
      'HTTP_REFERER' => "#{host}#{path}?saml_handle=#{handle}", 'REQUEST_URI' => "#{path}?saml_handle=#{handle}")
    response = boundary.call(get_env)
    expect(response.first).to eq(200)
    expect(response[1]['referrer-policy']).to eq('no-referrer')
    expect(response[1]['cache-control']).to eq('no-store')
    expect(get_env).not_to have_key(described_class::PREPARED)
    post_env = Rack::MockRequest.env_for("#{host}#{path}", method: 'POST', params: { 'SAMLResponse' => assertion },
      'onetime.display_domain' => 'ots.example.com')
    expect(boundary.call(post_env).first).to eq(303)
    expect(captured.join + messages.join).not_to include(handle, assertion)
    expect(messages.size).to eq(2)
  end

  it 'removes callback data on exceptions but does not swallow unrelated application errors' do
    handle = 'f' * 64
    inner = ->(_env) { raise 'application failure' }
    boundary = described_class::Boundary.new(described_class::Stage.new(inner))
    env = Rack::MockRequest.env_for("#{host}#{path}?saml_handle=#{handle}")
    expect { boundary.call(env) }.to raise_error('application failure')
    expect(Rack::Request.new(env).params).to eq({})
    expect(env['QUERY_STRING']).to eq('')
    expect(env).not_to have_key(described_class::PREPARED)
    ordinary = Rack::MockRequest.env_for("#{host}/ordinary?keep=value")
    expect { boundary.call(ordinary) }.to raise_error('application failure')
    expect(Rack::Request.new(ordinary).params).to eq('keep' => 'value')
  end

  it 'bounds GET query parsing and rejects malformed POST forms without logging their values' do
    expect(complete("#{path}?saml_handle=#{'x' * 4097}", '').status).to eq(414)
    malformed = Rack::MockRequest.new(app).post("#{host}#{path}", input: 'SAMLResponse=%ZZ', 'CONTENT_TYPE' => 'application/x-www-form-urlencoded')
    expect(malformed.status).to eq(400)
    expect(malformed.body).not_to include('%ZZ')
  end

  it 'does not expose store handles or assertions through Sentry Redis spans or breadcrumbs' do
    require 'sentry/redis'
    Sentry.init do |config|
      config.dsn = 'https://public@example.com/1'
      config.transport.transport_class = Sentry::DummyTransport
      config.background_worker_threads = 0
      config.traces_sample_rate = 1.0
      config.send_default_pii = true
      config.breadcrumbs_logger = [:redis_logger]
    end
    marker = 'private-assertion-redis-marker'
    Sentry::Redis.new([['EVAL', 'script', marker]], '127.0.0.1', 2163, 0).instrument { true }
    expect(Sentry.get_current_scope.breadcrumbs.peek.data[:commands].to_s).to include(marker)
    Sentry.get_current_scope.clear_breadcrumbs
    transaction = Sentry.start_transaction(name: 'callback', op: 'http.server', sampled: true)
    Sentry.get_current_scope.set_span(transaction)
    # Exercise the installed SDK's real command serialization even
    # when its global Redis patch was not installed by the unit boot sequence.
    instrumented = Object.new
    %i[eval get].each do |method|
      instrumented.define_singleton_method(method) do |*args, **kwargs|
        command = [method.to_s, *args, *kwargs.values.flatten.map(&:to_s)]
        Sentry::Redis.new([command], '127.0.0.1', 2163, 0).instrument do
          Familia.dbclient.public_send(method, *args, **kwargs)
        end
      end
    end
    handle = store.stage(response: marker, scope: [], source: 'one', dbclient: instrumented)
    _, raw = store.read(handle, scope: [], dbclient: instrumented)
    expect(store.consume(handle, raw, dbclient: instrumented)).to be(true)
    expect(Sentry.get_current_scope.get_span).to equal(transaction)
    expect(Sentry.get_current_scope.breadcrumbs.peek).to be_nil
    transaction.finish
    events = Sentry.get_current_client.transport.events
    expect(events).not_to be_empty
    serialized = JSON.generate(events.map(&:to_json_compatible))
    expect(serialized).not_to include(marker, handle, 'db.redis')
  ensure
    Sentry.close
  end

  it 'keeps the aggregate cap across host scopes and recovers admission in the next bucket' do
    now = Time.at(1_800_000_000)
    store.global_limit.times do |index|
      store.stage(response: 'untrusted', scope: ["host-#{index}.example"],
        source: "source-#{index / store.source_limit}", now: now)
    end
    expect do
      store.stage(response: 'legitimate', scope: ['unrelated.example'], source: 'unrelated', now: now)
    end.to raise_error(store::CapacityExceeded)
    bucket = "#{store::PREFIX}:rate:#{now.to_i / store::TTL}"
    expect(Familia.dbclient.hget(bucket, 'total').to_i).to eq(store.global_limit)
    expect(Familia.dbclient.hlen(bucket)).to eq(1 + (store.global_limit.to_f / store.source_limit).ceil)
    expect(Familia.dbclient.ttl(bucket)).to be_between(1, store::TTL)
    expect(store.stage(response: 'legitimate', scope: ['unrelated.example'], source: 'unrelated',
      now: now + store::TTL)).to match(store::HANDLE_PATTERN)
  end

  it 'bounds total staging even with distinct source addresses' do
    allow(store).to receive(:global_limit).and_return(3)
    3.times { |i| store.stage(response: 'a', scope: [], source: i.to_s) }
    expect { store.stage(response: 'a', scope: [], source: 'new') }.to raise_error(store::CapacityExceeded)
  end
end
