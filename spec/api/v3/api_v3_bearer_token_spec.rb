# spec/api/v3/api_v3_bearer_token_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (Rack-level, mounted v3 app, real Otto strategy chain)
# =============================================================================
#
# PASETO v4.public bearer tokens on the v3 API (#2427), end to end:
#
#   - the operator flag: everything below is inert while auth.paseto.enabled
#     is off, and POST /token answers 403 BEARER_TOKENS_DISABLED;
#   - the exchange: a session (with CSRF) or a Basic auth API key mints a
#     token; a bearer token does not;
#   - the credential: a token authenticates the v3 secret routes without a
#     cookie or CSRF token, is refused when expired, tampered, or signed by
#     a key this deployment never held, and dies with the account's
#     suspension or password change;
#   - the refusal: 401 with the credential code and the RFC 6750 Bearer
#     challenge; a valid session still outranks a stale header.
#
# RUN:
#   tests/lanes/run api --only spec/api/v3/api_v3_bearer_token_spec.rb
#
# Requires Valkey on port 2163 (pnpm run test:database:start).
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../integration/integration_spec_helper'
require 'json'
require 'base64'
require 'securerandom'

RSpec.describe 'API v3 PASETO bearer tokens', type: :integration do
  include Rack::Test::Methods

  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  before(:all) do
    require 'onetime'
    Onetime.boot! :test
    Onetime::Application::Registry.prepare_application_registry
  end

  let(:password) { 'Bearer-Token-Spec1234!' }
  let(:customer) do
    cust          = Onetime::Customer.new(email: "bearer-token-#{SecureRandom.hex(8)}@example.com")
    cust.update_passphrase(password)
    cust.verified = 'true'
    cust.apitoken = SecureRandom.hex(20)
    cust.save
    cust
  end
  let(:basic_header) { "Basic #{Base64.strict_encode64("#{customer.email}:#{customer.apitoken}")}" }
  let(:payload) { { secret: { secret: 'bearer token fixture', ttl: 3600 } } }

  before do
    clear_cookies
    %w[Authorization Content-Type Accept X-CSRF-Token].each { |name| header name, nil }
    allow(Onetime.auth_config).to receive(:paseto_enabled?).and_return(true)
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(true)
  end

  def json_response
    JSON.parse(last_response.body)
  end

  def request(method, path, body: nil, authorization: nil, csrf: nil)
    env                       = { 'HTTP_ACCEPT' => 'application/json' }
    env['HTTP_AUTHORIZATION'] = authorization if authorization
    env['HTTP_X_CSRF_TOKEN']  = csrf if csrf
    if body
      env['CONTENT_TYPE'] = 'application/json'
      public_send(method, path, body.to_json, env)
    else
      public_send(method, path, {}, env)
    end
    last_response
  end

  def fetch_csrf_token
    get '/auth', {}, { 'HTTP_ACCEPT' => 'application/json' }
    last_response.headers['X-CSRF-Token']
  end

  def sign_in!
    token = fetch_csrf_token
    post '/auth/login',
      { login: customer.email, password: password, shrimp: token }.to_json,
      { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json', 'HTTP_X_CSRF_TOKEN' => token }
    expect(last_response.status).to eq(200), last_response.body
    fetch_csrf_token
  end

  def mint_with_basic
    request(:post, '/api/v3/token', body: {}, authorization: basic_header)
    expect(last_response.status).to eq(200), last_response.body
    json_response.fetch('record')
  end

  def expect_bearer_refusal(code, challenge: 'Bearer realm="onetimesecret", error="invalid_token"')
    expect(last_response.status).to eq(401)
    expect(json_response).to include('code' => code, 'code_scope' => 'credential')
    expect(last_response.headers['www-authenticate']).to start_with(challenge)
  end

  def expect_session_refusal(code = 'not_authenticated')
    expect(last_response.status).to eq(401)
    expect(json_response).to include('code' => code, 'code_scope' => 'customer_session')
    expect(last_response.headers['www-authenticate']).to eq('Session realm="onetimesecret"')
  end

  def secret_storage
    [Onetime::Secret, Onetime::Receipt].to_h do |model|
      [model.name, model.dbclient.scan_each(match: "#{model.prefix}:*").to_a.sort]
    end
  end

  describe 'while auth.paseto.enabled is off' do
    before { allow(Onetime.auth_config).to receive(:paseto_enabled?).and_return(false) }

    it 'refuses the exchange with 403 BEARER_TOKENS_DISABLED for a session and for Basic auth' do
      request(:post, '/api/v3/token', body: {}, authorization: basic_header)
      expect(last_response.status).to eq(403)
      expect(json_response).to include('code' => 'BEARER_TOKENS_DISABLED', 'error_type' => 'BearerTokensDisabled')

      csrf = sign_in!
      request(:post, '/api/v3/token', body: {}, csrf: csrf)
      expect(last_response.status).to eq(403)
      expect(json_response).to include('code' => 'BEARER_TOKENS_DISABLED')
    end

    it 'ignores a bearer header on the secret routes exactly as before: a session refusal' do
      allow(Onetime.auth_config).to receive(:paseto_enabled?).and_return(true)
      token          = mint_with_basic.fetch('token')
      allow(Onetime.auth_config).to receive(:paseto_enabled?).and_return(false)
      before_storage = secret_storage

      request(:get, '/api/v3/receipt/recent', authorization: "Bearer #{token}")
      expect_session_refusal

      request(:post, '/api/v3/secret/conceal', body: payload, authorization: "Bearer #{token}")
      expect_session_refusal
      expect(secret_storage).to eq(before_storage)
    end

    it 'keeps the Basic challenge on /version for a stray bearer header' do
      request(:get, '/api/v3/version', authorization: 'Bearer not-a-token')
      expect(last_response.status).to eq(401)
      expect(json_response).to include('code' => 'api_key_invalid')
      expect(last_response.headers['www-authenticate']).to eq('Basic realm="onetimesecret"')
    end
  end

  describe 'POST /api/v3/token' do
    it 'exchanges a Basic auth API key for a one-hour token without a CSRF token' do
      record = mint_with_basic

      expect(record).to include('token_type' => 'Bearer', 'expires_in' => 3600, 'scope' => ['*'])
      expect(record.fetch('token')).to start_with('v4.public.')
      expect(record.fetch('expires_at') - record.fetch('issued_at')).to eq(3600)
      expect(record.fetch('kid')).to eq(Onetime::Paseto.keyring.signing_key.kid)
      expect(json_response.fetch('details')).to eq(
        'subject' => customer.extid, 'audience' => Onetime::Paseto::V3_AUDIENCE, 'issuer' => Onetime::Paseto.issuer,
      )
      expect(last_request.env.fetch('otto.strategy_result').auth_method).to eq('basic_auth')
    end

    it 'exchanges a browser session, requiring its CSRF token' do
      csrf = sign_in!
      request(:post, '/api/v3/token', body: {})
      expect(last_response.status).to eq(403)
      expect(last_request.env['onetime.csrf.rejected']).to be(true)

      request(:post, '/api/v3/token', body: {}, csrf: csrf)
      expect(last_response.status).to eq(200), last_response.body
      expect(json_response.dig('details', 'subject')).to eq(customer.extid)
      expect(last_request.env.fetch('otto.strategy_result').auth_method).to eq('sessionauth')
    end

    it 'honours the configured lifetime' do
      allow(Onetime.auth_config).to receive(:paseto_token_ttl).and_return(900)
      expect(mint_with_basic).to include('expires_in' => 900)
    end

    it 'refuses to mint from a bearer token: a leaked token cannot renew itself' do
      token = mint_with_basic.fetch('token')
      request(:post, '/api/v3/token', body: {}, authorization: "Bearer #{token}")

      # pasetoauth is not in the chain, so the Basic strategy answers the
      # unknown scheme with its own terminal refusal.
      expect(last_response.status).to eq(401)
      expect(json_response).to include('code' => 'api_key_invalid')
    end

    it 'refuses anonymous callers and wrong API keys' do
      request(:post, '/api/v3/token', body: {})
      expect_session_refusal

      request(
        :post,
        '/api/v3/token',
        body: {},
        authorization: "Basic #{Base64.strict_encode64("#{customer.email}:wrong")}",
      )
      expect(last_response.status).to eq(401)
      expect(json_response).to include('code' => 'api_key_invalid')
    end

    it 'refuses to mint while a colonel impersonates the customer' do
      csrf        = sign_in!
      session_key = Onetime.session_config.fetch('key')
      expect(rack_mock_session.cookie_jar[session_key]).to be_a(String)
      allow(Onetime::SessionImpersonation).to receive(:active).and_return({ 'target_extid' => customer.extid })

      request(:post, '/api/v3/token', body: {}, csrf: csrf)
      expect(last_response.status).to eq(403)
      expect(json_response.fetch('error')).to include('impersonating')
    end
  end

  describe 'a bearer token as the credential' do
    let(:token) { mint_with_basic.fetch('token') }

    it 'authenticates reads and creation on the v3 secret routes with no cookie and no CSRF token' do
      clear_cookies
      request(:get, '/api/v3/receipt/recent', authorization: "Bearer #{token}")
      expect(last_response.status).to eq(200), last_response.body
      result = last_request.env.fetch('otto.strategy_result')
      expect(result.auth_method).to eq('pasetoauth')
      expect(result.user.objid).to eq(customer.objid)
      expect(result.metadata).to include(auth_type: 'paseto', token_kid: Onetime::Paseto.keyring.signing_key.kid)

      request(:post, '/api/v3/secret/conceal', body: payload, authorization: "Bearer #{token}")
      expect(last_response.status).to eq(200), last_response.body
      record  = json_response.fetch('record')
      receipt = Onetime::Receipt.load(record.fetch('receipt').fetch('identifier'))
      expect(receipt.owner_id).to eq(customer.objid)

      request(:get, "/api/v3/receipt/#{receipt.identifier}", authorization: "Bearer #{token}")
      expect(last_response.status).to eq(200), last_response.body
    end

    it 'authenticates /version alongside session and Basic auth' do
      request(:get, '/api/v3/version', authorization: "Bearer #{token}")
      expect(last_response.status).to eq(200)
      expect(last_request.env.fetch('otto.strategy_result').auth_method).to eq('pasetoauth')
    end

    it 'is not accepted on the guest routes, which stay anonymous' do
      request(:post, '/api/v3/guest/secret/conceal', body: payload, authorization: "Bearer #{token}")
      expect(last_response.status).to eq(200), last_response.body
      result = last_request.env.fetch('otto.strategy_result')
      expect(result.auth_method).to eq('noauth')
      expect(result.user).to be_nil
    end

    it 'refuses a tampered token with api_token_invalid and a Bearer challenge' do
      body           = token.split('.')[2]
      flipped        = body.dup
      flipped[12]    = flipped[12] == 'A' ? 'B' : 'A'
      before_storage = secret_storage

      request(:post, '/api/v3/secret/conceal', body: payload, authorization: "Bearer #{token.sub(body, flipped)}")
      expect_bearer_refusal('api_token_invalid')
      expect(secret_storage).to eq(before_storage)
    end

    it 'refuses a token that is not PASETO, failing the chain closed' do
      request(:get, '/api/v3/receipt/recent', authorization: 'Bearer unimplemented-authentication-boundary-token')
      expect_bearer_refusal('api_token_invalid')
    end

    it 'refuses an expired token with api_token_expired and names the expiry in the challenge' do
      expired, = Onetime::Paseto::AccessToken.issue(
        subject: customer.extid,
        keyring: Onetime::Paseto.keyring,
        audience: Onetime::Paseto::V3_AUDIENCE,
        issuer: Onetime::Paseto.issuer,
        ttl: 60,
        now: Time.now - 120,
      )
      request(:get, '/api/v3/receipt/recent', authorization: "Bearer #{expired}")
      expect_bearer_refusal(
        'api_token_expired',
        challenge: 'Bearer realm="onetimesecret", error="invalid_token", error_description="The access token expired"',
      )
    end

    it 'refuses a token signed by a SECRET this deployment never held, and accepts one from SECRET_PREVIOUS' do
      stranger, = Onetime::Paseto::AccessToken.issue(
        subject: customer.extid,
        keyring: Onetime::Paseto::Keyring.derive('deadbeef' * 8),
        audience: Onetime::Paseto::V3_AUDIENCE,
        issuer: Onetime::Paseto.issuer,
      )
      request(:get, '/api/v3/receipt/recent', authorization: "Bearer #{stranger}")
      expect_bearer_refusal('api_token_invalid')

      # Rotation: the running keyring now lists the old SECRET as previous.
      live    = Onetime::Paseto.keyring
      retired = Onetime::Paseto::Keyring.derive('cafef00d' * 8)
      rotated = Onetime::Paseto::Keyring.new(live.signing_key, [retired.signing_key])
      Onetime::Runtime.update_security(paseto_keyring: rotated)
      begin
        old_token, = Onetime::Paseto::AccessToken.issue(
          subject: customer.extid,
          keyring: retired,
          audience: Onetime::Paseto::V3_AUDIENCE,
          issuer: Onetime::Paseto.issuer,
        )
        request(:get, '/api/v3/receipt/recent', authorization: "Bearer #{old_token}")
        expect(last_response.status).to eq(200), last_response.body
        expect(last_request.env.fetch('otto.strategy_result').metadata[:token_kid]).to eq(retired.signing_key.kid)
      ensure
        Onetime::Runtime.update_security(paseto_keyring: live)
      end
    end

    it 'dies with the account: suspension and a password change both refuse it' do
      request(:get, '/api/v3/receipt/recent', authorization: "Bearer #{token}")
      expect(last_response.status).to eq(200)

      customer.last_password_update!(Time.now.to_i + 1)
      request(:get, '/api/v3/receipt/recent', authorization: "Bearer #{token}")
      expect_bearer_refusal('api_token_invalid')
      customer.last_password_update!(0)

      customer.suspended!('true')
      request(:get, '/api/v3/receipt/recent', authorization: "Bearer #{token}")
      expect_bearer_refusal('suspended_credentials')
    end

    it 'yields to a valid browser session on the same request, with CSRF still enforced' do
      csrf           = sign_in!
      other          = Onetime::Customer.new(email: "bearer-other-#{SecureRandom.hex(8)}@example.com")
      other.verified = 'true'
      other.save
      other_token,   = Onetime::Paseto::AccessToken.issue(
        subject: other.extid,
        keyring: Onetime::Paseto.keyring,
        audience: Onetime::Paseto::V3_AUDIENCE,
        issuer: Onetime::Paseto.issuer,
      )

      request(:post, '/api/v3/secret/conceal', body: payload, authorization: "Bearer #{other_token}")
      expect(last_response.status).to eq(403)
      expect(last_request.env['onetime.csrf.rejected']).to be(true)

      request(:post, '/api/v3/secret/conceal', body: payload, authorization: "Bearer #{other_token}", csrf: csrf)
      expect(last_response.status).to eq(200), last_response.body
      expect(last_request.env.fetch('otto.strategy_result').auth_method).to eq('sessionauth')
      expect(last_request.env.fetch('otto.strategy_result').user.objid).to eq(customer.objid)
    end

    it 'lets a valid session outrank a stale bearer header instead of signing the browser out' do
      csrf = sign_in!
      request(:get, '/api/v3/receipt/recent', authorization: 'Bearer stale-cached-token')
      expect(last_response.status).to eq(200), last_response.body
      expect(last_request.env.fetch('otto.strategy_result').auth_method).to eq('sessionauth')
      expect(csrf).to be_a(String)
    end
  end
end
