# spec/unit/onetime/middleware/session_failure_code_spec.rb
#
# frozen_string_literal: true

# Otto renders the session 401 inside the gem from a failure string, so the
# evaluator's typed reason used to reach the client only as a bracket marker in
# `message`. The session strategy stashes the reason in env and this middleware
# adds `code` / `code_scope` to the body (#4462). A rejected credential is
# stashed by the code that refuses it, on every surface, and rendered the same
# way (#4469). The same annotate path gives the refusal its HTTP semantics:
# a `WWW-Authenticate` challenge on every annotated 401, and a 503 with
# `Retry-After` for a session that could not be verified (#4469, v0.26.14).

require 'spec_helper'
require 'json'
require 'onetime/middleware/session_failure_code'

RSpec.describe Onetime::Middleware::SessionFailureCode do
  let(:env_key) { described_class::ENV_KEY }

  let(:otto_body) do
    {
      error: 'Authentication Required',
      message: '[SESSION_SURFACE_MISMATCH] Session surface does not match request; sign in again',
      timestamp: 1_700_000_000,
    }.to_json
  end

  # What Otto's auth chain leaves behind when every strategy failed.
  let(:failed_chain) do
    Struct.new(:metadata).new({ auth_failure: 'All authentication strategies failed', failure_reasons: [] })
  end

  def otto_response(status: 401, body: otto_body, content_type: 'application/json')
    [status, { 'content-type' => content_type, 'content-length' => body.bytesize.to_s }, [body]]
  end

  def call(response, env)
    described_class.new(->(_env) { response }).call(env)
  end

  def refused_env(reason, extra = {})
    { env_key => reason, 'otto.strategy_result' => failed_chain }.merge(extra)
  end

  # What a Basic auth strategy leaves behind on its terminal failure
  # (Helpers#credentialed_failure): the reason and the scheme it examined.
  def basic_refused_env(reason, extra = {})
    env = refused_env(reason, extra)
    Onetime::SessionFailureCode.stash_scheme(env, Onetime::SessionFailureCode::SCHEME_BASIC)
    env
  end

  describe 'a session refusal rendered by Otto' do
    subject(:result) { call(otto_response, refused_env(:surface_mismatch)) }

    let(:parsed) { JSON.parse(result[2].join) }

    it 'adds the code and its scope' do
      expect(parsed).to include('code' => 'surface_mismatch', 'code_scope' => 'customer_session')
    end

    it 'keeps the status and every existing field' do
      expect(result[0]).to eq(401)
      expect(parsed).to include(JSON.parse(otto_body))
    end

    it 'recomputes content-length for the new body' do
      expect(result[1]['content-length']).to eq(result[2].join.bytesize.to_s)
    end

    it 'writes content-length under the key the app used' do
      response = [401, { 'Content-Type' => 'application/json', 'Content-Length' => '1' }, [otto_body]]
      _status, headers, body = call(response, refused_env(:surface_mismatch))

      expect(headers.keys).to contain_exactly('Content-Type', 'Content-Length', 'www-authenticate')
      expect(headers['Content-Length']).to eq(body.join.bytesize.to_s)
    end

    it 'challenges with the Session scheme (RFC 9110 §15.5.2), never Basic' do
      expect(result[1]['www-authenticate']).to eq('Session realm="onetimesecret"')
    end

    it 'sends no Retry-After: a verdict is not an outage' do
      expect(result[1].keys.map(&:downcase)).not_to include('retry-after')
    end
  end

  # A refusal in the verification_unavailable scope is an outage, not a
  # verdict: it answers 503 with Retry-After (RFC 9110 §15.6.4, §10.2.3) and
  # keeps every field the 401 had plus the pair, so a client tells it from
  # any other 503 by `code_scope`.
  describe 'a verification outage' do
    %i[customer_unavailable active_session_unavailable].each do |reason|
      it "answers #{reason} with 503, Retry-After and the pair" do
        status, headers, body = call(otto_response, refused_env(reason))

        expect(status).to eq(described_class::UNAVAILABLE_STATUS)
        expect(status).to eq(503)
        expect(headers['retry-after']).to eq(described_class::UNAVAILABLE_RETRY_AFTER.to_s)
        expect(JSON.parse(body.join)).to include(
          JSON.parse(otto_body).merge('code' => reason.to_s, 'code_scope' => 'verification_unavailable'),
        )
        expect(headers['content-length']).to eq(body.join.bytesize.to_s)
      end
    end

    it 'sends no WWW-Authenticate: a 503 is not a request for credentials' do
      _s, headers, _b = call(otto_response, refused_env(:customer_unavailable))

      expect(headers.keys.map(&:downcase)).not_to include('www-authenticate')
    end

    it 'keeps a Retry-After the app already set' do
      response = [401, { 'content-type' => 'application/json', 'Retry-After' => '1' }, [otto_body]]
      status, headers, _b = call(response, refused_env(:active_session_unavailable))

      expect(status).to eq(503)
      expect(headers['Retry-After']).to eq('1')
      expect(headers.keys.map(&:downcase).count('retry-after')).to eq(1)
    end

    it 'answers the /auth surface the same way' do
      body = { error: 'Session could not be verified; try again', error_type: 'SessionUnverified' }.to_json
      status, headers, annotated = call(otto_response(body: body), { env_key => :active_session_unavailable })

      expect(status).to eq(503)
      expect(headers['retry-after']).to eq('5')
      expect(JSON.parse(annotated.join)).to include(
        'error_type' => 'SessionUnverified',
        'code' => 'active_session_unavailable',
        'code_scope' => 'verification_unavailable',
      )
    end

    it 'stays a 401 when the body cannot carry the pair' do
      response = otto_response(body: '[1,2]')

      expect(call(response, refused_env(:customer_unavailable))).to eq(response)
    end
  end

  describe 'the WWW-Authenticate challenge' do
    def challenge_for(reason, env_extra = {}, body: otto_body)
      _s, headers, _b = call(otto_response(body: body), refused_env(reason, env_extra))
      headers['www-authenticate']
    end

    it 'is Session for every session-scope and admin-scope refusal' do
      Onetime::SessionFailureCode::SESSION_REASON_SCOPES.each do |reason, scope|
        next if scope == Onetime::SessionFailureCode::SCOPE_VERIFICATION_UNAVAILABLE

        expect(challenge_for(reason)).to eq('Session realm="onetimesecret"'), reason.to_s
      end
    end

    it 'is Session on a sessionauth,basicauth route refused for its session, even with a header present' do
      # The header was never examined; a Basic challenge here would open the
      # browser dialog on the client that uses cookies.
      expect(challenge_for(:session_missing, 'HTTP_AUTHORIZATION' => 'Basic Zm9vOmJhcg==')).to eq(
        'Session realm="onetimesecret"',
      )
    end

    def basic_challenge_for(reason, env_extra = {})
      _s, headers, _b = call(otto_response, basic_refused_env(reason, env_extra))
      headers['www-authenticate']
    end

    it 'is Basic for a rejected API key: the scheme the Basic strategy examined' do
      expect(basic_challenge_for(:api_key_invalid, 'HTTP_AUTHORIZATION' => 'Basic Zm9vOmJhcg==')).to eq(
        'Basic realm="onetimesecret"',
      )
      # Wrong scheme is still api_key_invalid from a Basic strategy.
      expect(basic_challenge_for(:api_key_invalid, 'HTTP_AUTHORIZATION' => 'Bearer abc')).to eq(
        'Basic realm="onetimesecret"',
      )
    end

    it 'is Basic for a valid but suspended API key, Session for the simple-mode password' do
      expect(basic_challenge_for(:suspended_credentials, 'HTTP_AUTHORIZATION' => 'Basic Zm9vOmJhcg==')).to eq(
        'Basic realm="onetimesecret"',
      )
      expect(challenge_for(:suspended_credentials)).to eq('Session realm="onetimesecret"')
    end

    it 'is Session for a rejected login, second factor or password confirmation' do
      body = { error: 'There was an error logging in', 'field-error' => ['password', 'invalid password'] }.to_json
      _s, headers, _b = call(otto_response(body: body), { env_key => :invalid_credentials })

      expect(headers['www-authenticate']).to eq('Session realm="onetimesecret"')
    end

    # The scheme follows the provenance of the stash, never the headers the
    # request carried: a form login (noauth, no Basic strategy in its chain)
    # that rejected its password may still arrive with an Authorization
    # header, and a Basic challenge on that response would open the browser
    # dialog.
    it 'is Session for a form-credential refusal even when the request carried an Authorization header' do
      header = { 'HTTP_AUTHORIZATION' => 'Basic Zm9vOmJhcg==' }
      passed = Struct.new(:metadata).new({ ip: '127.0.0.0' })
      body   = { error: 'Invalid email or password', 'field-error' => %w[email invalid] }.to_json

      %i[suspended_credentials invalid_credentials].each do |reason|
        env = { env_key => reason, 'otto.strategy_result' => passed }.merge(header)
        _s, headers, _b = call(otto_response(body: body), env)

        expect(headers['www-authenticate']).to eq('Session realm="onetimesecret"'), reason.to_s
      end

      # And the /auth Roda app, which has no Otto chain at all.
      _s, headers, _b = call(otto_response(body: body), { env_key => :invalid_credentials }.merge(header))
      expect(headers['www-authenticate']).to eq('Session realm="onetimesecret"')
    end

    it 'is Session once a later stash replaced the Basic strategy\'s reason' do
      env = basic_refused_env(:api_key_invalid)
      Onetime::SessionFailureCode.stash(env, :session_missing)

      _s, headers, _b = call(otto_response, env)

      expect(headers['www-authenticate']).to eq('Session realm="onetimesecret"')
    end

    it 'keeps a challenge the app already set' do
      response = [401, { 'content-type' => 'application/json', 'WWW-Authenticate' => 'Bearer realm="x"' }, [otto_body]]
      _s, headers, _b = call(response, refused_env(:session_missing))

      expect(headers['WWW-Authenticate']).to eq('Bearer realm="x"')
      expect(headers.keys.map(&:downcase).count('www-authenticate')).to eq(1)
    end

    it 'is not added to a 401 the middleware leaves uncoded' do
      response = otto_response(body: { error: 'x', code: 'handler_owned' }.to_json)
      _s, headers, _b = call(response, refused_env(:surface_mismatch))

      expect(headers.keys.map(&:downcase)).not_to include('www-authenticate')
    end
  end

  it 'scopes the admin timeout as admin_session' do
    _s, _h, body = call(otto_response, refused_env(:admin_session_expired))

    expect(JSON.parse(body.join)).to include(
      'code' => 'admin_session_expired', 'code_scope' => 'admin_session',
    )
  end

  describe 'responses it leaves exactly as it found them' do
    def untouched(response, env)
      expect(call(response, env)).to eq(response)
    end

    it 'a 401 with no session refusal recorded (login or handler rejection)' do
      untouched(otto_response, { 'otto.strategy_result' => failed_chain })
    end

    it 'a session 401 that did not come from the Otto auth chain' do
      # A session strategy failed, the chain fell through to noauth, and a
      # handler answered 401 for its own reasons.
      passed = Struct.new(:metadata).new({ ip: '127.0.0.0' })
      untouched(otto_response, { env_key => :not_authenticated, 'otto.strategy_result' => passed })
    end

    it 'any other status' do
      [200, 302, 403, 500, 503].each do |status|
        untouched(otto_response(status: status), refused_env(:surface_mismatch))
      end
    end

    it 'a non-JSON 401' do
      untouched(otto_response(content_type: 'text/plain', body: 'Unauthorized'), refused_env(:surface_mismatch))
    end

    it 'a 401 whose body is not a JSON object' do
      untouched(otto_response(body: '[1,2]'), refused_env(:surface_mismatch))
      untouched(otto_response(body: '{not json'), refused_env(:surface_mismatch))
    end

    it 'a 401 that already carries a code' do
      untouched(otto_response(body: { error: 'x', code: 'handler_owned' }.to_json), refused_env(:surface_mismatch))
    end

    it 'a streaming (non-Array) body' do
      streaming = Enumerator.new { |y| y << otto_body }
      response  = [401, { 'content-type' => 'application/json' }, streaming]

      expect(call(response, refused_env(:surface_mismatch))[2]).to equal(streaming)
    end

    it 'an unknown reason in env' do
      untouched(otto_response, refused_env(:no_such_reason))
    end
  end

  # #4469: a rejected credential is coded, on every surface.
  describe 'a credential refusal' do
    let(:basic_body) do
      { error: 'Authentication Required', message: '[CREDENTIALS_INVALID] Invalid credentials', timestamp: 1 }.to_json
    end

    it 'codes a rejected API key, stashed by the terminal Basic auth failure that failed the chain' do
      env = refused_env(:api_key_invalid, 'HTTP_AUTHORIZATION' => 'Basic Zm9vOmJhcg==')
      _s, _h, body = call(otto_response(body: basic_body), env)

      expect(JSON.parse(body.join)).to include('code' => 'api_key_invalid', 'code_scope' => 'credential')
    end

    it 'codes a rejected sign-in stashed by a handler after the chain passed (simple-mode login)' do
      passed = Struct.new(:metadata).new({ ip: '127.0.0.0' })
      env    = { env_key => :invalid_credentials, 'otto.strategy_result' => passed }
      body   = { error: 'Invalid email or password', 'field-error' => %w[email invalid] }.to_json
      _s, _h, annotated = call(otto_response(body: body), env)

      expect(JSON.parse(annotated.join)).to include(
        'error' => 'Invalid email or password',
        'field-error' => %w[email invalid],
        'code' => 'invalid_credentials',
        'code_scope' => 'credential',
      )
    end

    # Rodauth answers a locked-out or unverified account with 403. The pair is
    # rendered there too, and only there: a credential-scope stash.
    it 'codes a 403 credential refusal, status and fields unchanged' do
      body = { error: 'This account is currently locked out and cannot be logged in to' }.to_json
      status, headers, annotated = call(otto_response(status: 403, body: body), { env_key => :account_locked })

      expect(status).to eq(403)
      expect(JSON.parse(annotated.join)).to eq(
        'error' => 'This account is currently locked out and cannot be logged in to',
        'code' => 'account_locked',
        'code_scope' => 'credential',
      )
      expect(headers['content-length']).to eq(annotated.join.bytesize.to_s)
      # Not a request for credentials: no challenge, no Retry-After.
      expect(headers.keys.map(&:downcase)).not_to include('www-authenticate', 'retry-after')
    end

    it 'codes an unverified-account 403 the same way' do
      _s, _h, body = call(otto_response(status: 403), { env_key => :account_unverified })

      expect(JSON.parse(body.join)).to include('code' => 'account_unverified', 'code_scope' => 'credential')
    end

    it 'leaves a bare 403, and a 403 with a session reason stashed, untouched' do
      bare = otto_response(status: 403)
      expect(call(bare, {})).to eq(bare)
      expect(call(bare, refused_env(:not_authenticated))).to eq(bare)
      expect(call(bare, { env_key => :active_session_revoked })).to eq(bare)
    end

    it 'codes a valid API key on a suspended account' do
      _s, _h, body = call(otto_response, refused_env(:suspended_credentials))

      expect(JSON.parse(body.join)).to include('code' => 'suspended_credentials', 'code_scope' => 'credential')
    end
  end

  # The /auth Roda app has no Otto chain: its router and routes stash only as
  # they refuse, and the Rodauth seam stashes as Rodauth throws.
  describe 'the /auth surface (no otto.strategy_result)' do
    it 'codes a login-required refusal with the reason the router stashed' do
      body = { error: 'Please login to continue' }.to_json
      _s, _h, annotated = call(otto_response(body: body), { env_key => :session_missing })

      expect(JSON.parse(annotated.join)).to include('code' => 'session_missing', 'code_scope' => 'customer_session')
    end

    it 'codes a rejected login with what the Rodauth seam stashed' do
      body = { error: 'There was an error logging in', 'field-error' => ['password', 'invalid password'] }.to_json
      _s, _h, annotated = call(otto_response(body: body), { env_key => :invalid_credentials })

      expect(JSON.parse(annotated.join)).to include(
        'field-error' => ['password', 'invalid password'],
        'code' => 'invalid_credentials',
        'code_scope' => 'credential',
      )
    end

    it 'leaves a 401 uncoded once the stash has been withdrawn' do
      env = { env_key => :session_missing }
      Onetime::SessionFailureCode.forget(env)

      response = otto_response(body: { error: 'This linking request has expired.', error_code: 'link_expired' }.to_json)
      expect(call(response, env)).to eq(response)
    end
  end

  # A session reason on a sessionauth-only route reached with an Authorization
  # header: the header was never examined (no Basic strategy in the chain), so
  # the refusal is the session's and is coded as such. On a chain with a
  # Basic strategy the terminal credential stash replaces it.
  it 'codes a session refusal even when the request carried an Authorization header' do
    _s, _h, body = call(otto_response, refused_env(:session_missing, 'HTTP_AUTHORIZATION' => 'Basic Zm9vOmJhcg=='))

    expect(JSON.parse(body.join)).to include('code' => 'session_missing', 'code_scope' => 'customer_session')
  end

  it 'accepts a vendor +json content type with parameters' do
    response         = otto_response(content_type: 'application/problem+json; charset=utf-8')
    _s, _h, body     = call(response, refused_env(:stale_credentials))

    expect(JSON.parse(body.join)['code']).to eq('stale_credentials')
  end
end
