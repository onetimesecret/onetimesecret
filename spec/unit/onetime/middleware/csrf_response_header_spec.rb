# spec/unit/onetime/middleware/csrf_response_header_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/middleware/csrf_response_header'

# Unit tests for the CSRF response-header middleware.
#
# Two behaviors live here and they are entangled by design:
#
#   1. Token exposure. `AuthenticityToken.token(session)` does
#      `session[:csrf] ||= random` — it does not merely READ the session, it
#      WRITES to it. That write is what made every anonymous probe request
#      dirty its session and commit a `session:<hex>` key to Valkey (#3997).
#      The `!session_skipped?` gate added for #3997 is therefore the decisive
#      guard, not a cosmetic one: without it, SessionSkip's `:skip` flag would
#      still suppress the commit, but the middleware would hand the client a
#      masked token backed by a session that will never exist.
#
#   2. 403 classification (#3837). A CSRF 403 is either a token mismatch
#      (forgery) or a session-continuity break (the session was lost). The two
#      are only distinguishable BEFORE `@app.call`, because AuthenticityToken
#      mints the token during validation. The `had_csrf` snapshot is that
#      "before" reading.
RSpec.describe Onetime::Middleware::CsrfResponseHeader do
  let(:downstream_status) { 200 }
  let(:downstream_headers) { { 'content-type' => 'application/json' } }

  # Lets an example stamp env keys (e.g. the CSRF rejection marker) from where
  # the real InstrumentedAuthenticityToken would stamp them: below this
  # middleware, during @app.call.
  let(:downstream_side_effect) { ->(_env) {} }

  let(:downstream) do
    lambda do |env|
      downstream_side_effect.call(env)
      [downstream_status, downstream_headers.dup, ['{}']]
    end
  end

  let(:middleware) { described_class.new(downstream) }

  # A plain Hash stands in for Onetime::Session's SessionHash: both respond to
  # []/[]= with symbol keys, which is all AuthenticityToken.token touches.
  let(:session) { {} }

  def env_for(method: 'GET', session: nil, session_options: nil, script_name: '', path_info: '/')
    env = {
      'REQUEST_METHOD' => method,
      'SCRIPT_NAME' => script_name,
      'PATH_INFO' => path_info,
    }
    env['rack.session']         = session unless session.nil?
    env['rack.session.options'] = session_options unless session_options.nil?
    env
  end

  describe 'token exposure with a normal (non-skipped) session' do
    it 'adds a masked X-CSRF-Token header' do
      _status, headers, = middleware.call(env_for(session: session))

      expect(headers['X-CSRF-Token']).to be_a(String)
      expect(headers['X-CSRF-Token']).not_to be_empty
    end

    it 'seeds the raw token into the session' do
      middleware.call(env_for(session: session))

      expect(session[:csrf]).to be_a(String)
    end

    it 'masks the token rather than exposing the raw session value' do
      # BREACH mitigation: the header must never be the raw session token.
      _status, headers, = middleware.call(env_for(session: session))

      expect(headers['X-CSRF-Token']).not_to eq(session[:csrf])
    end

    it 'issues a different masked value on each response for the same raw token' do
      _s1, first_headers,  = middleware.call(env_for(session: session))
      _s2, second_headers, = middleware.call(env_for(session: session))

      expect(second_headers['X-CSRF-Token']).not_to eq(first_headers['X-CSRF-Token'])
    end

    it 'preserves an already-present raw token' do
      # Must be a real base64 token: global_token decodes the stored value to
      # build the HMAC, so an arbitrary string raises inside rack-protection.
      existing       = Rack::Protection::AuthenticityToken.random_token
      session[:csrf] = existing

      middleware.call(env_for(session: session))

      expect(session[:csrf]).to eq(existing)
    end

    it 'passes the downstream status and body through unchanged' do
      status, _headers, body = middleware.call(env_for(session: session))

      expect(status).to eq(200)
      expect(body).to eq(['{}'])
    end

    it 'preserves the downstream headers' do
      _status, headers, = middleware.call(env_for(session: session))

      expect(headers['content-type']).to eq('application/json')
    end

    it 'adds the header when the options hash exists but carries no :skip' do
      _status, headers, = middleware.call(
        env_for(session: session, session_options: { expire_after: 86_400 })
      )

      expect(headers['X-CSRF-Token']).to be_a(String)
    end

    it 'adds the header when :skip is explicitly false' do
      _status, headers, = middleware.call(
        env_for(session: session, session_options: { skip: false })
      )

      expect(headers['X-CSRF-Token']).to be_a(String)
    end
  end

  describe 'suppression when SessionSkip marked the request (#3997)' do
    let(:skipped_env) do
      env_for(
        session: session,
        session_options: { skip: true },
        path_info: '/health',
      )
    end

    it 'does not call AuthenticityToken.token' do
      expect(Rack::Protection::AuthenticityToken).not_to receive(:token)

      middleware.call(skipped_env)
    end

    it 'does not add an X-CSRF-Token header' do
      _status, headers, = middleware.call(skipped_env)

      expect(headers).not_to have_key('X-CSRF-Token')
    end

    it 'leaves the session undirtied — this is what stops the Valkey write' do
      # The whole point: AuthenticityToken.token would do
      # `session[:csrf] ||= random`, marking the session loaded-and-changed.
      middleware.call(skipped_env)

      expect(session).to be_empty
    end

    it 'still passes the response through unchanged' do
      status, headers, body = middleware.call(skipped_env)

      expect(status).to eq(200)
      expect(headers['content-type']).to eq('application/json')
      expect(body).to eq(['{}'])
    end

    it 'reads the :skip flag without setting it' do
      # SessionSkip owns the flag; this middleware must be a pure reader, or a
      # false positive here would silently disable session persistence.
      options = { skip: false }

      middleware.call(env_for(session: session, session_options: options))

      expect(options).to eq(skip: false)
    end

    it 'treats a non-true :skip value as not skipped' do
      # Guards against a truthy-but-not-true value (e.g. a config string)
      # accidentally suppressing tokens on real routes.
      _status, headers, = middleware.call(
        env_for(session: session, session_options: { skip: 'true' })
      )

      expect(headers['X-CSRF-Token']).to be_a(String)
    end

    it 'tolerates a nil rack.session.options (no session middleware above)' do
      # `respond_to?(:[])` in session_skipped? exists for exactly this: nil has
      # no #[], so the guard short-circuits rather than raising.
      env                         = env_for(session: session)
      env['rack.session.options'] = nil

      _status, headers, = middleware.call(env)

      expect(headers['X-CSRF-Token']).to be_a(String)
    end
  end

  describe 'sessionless requests' do
    it 'adds no header and does not raise when rack.session is absent' do
      status, headers, = middleware.call(env_for)

      expect(status).to eq(200)
      expect(headers).not_to have_key('X-CSRF-Token')
    end

    it 'adds no header when rack.session is nil' do
      env                 = env_for
      env['rack.session'] = nil

      _status, headers, = middleware.call(env)

      expect(headers).not_to have_key('X-CSRF-Token')
    end

    it 'does not raise on an unsafe sessionless request' do
      # csrf_token_present? runs before @app.call for unsafe methods and must
      # tolerate a nil session.
      expect { middleware.call(env_for(method: 'POST')) }.not_to raise_error
    end
  end

  describe 'CSRF 403 classification (#3837)' do
    let(:rejection_key) { Onetime::Middleware::InstrumentedAuthenticityToken::REJECTION_ENV_KEY }
    let(:downstream_status) { 403 }

    # The marker is stamped by InstrumentedAuthenticityToken#deny, i.e. below
    # this middleware while @app.call is on the stack.
    let(:downstream_side_effect) { ->(env) { env[rejection_key] = true } }

    it 'logs a token-mismatch when the session already held a CSRF token' do
      session[:csrf] = Rack::Protection::AuthenticityToken.random_token

      expect(OT).to receive(:lw).with(/token-mismatch/, hash_including(method: 'POST', path: '/api/v2/x'))

      middleware.call(
        env_for(method: 'POST', session: session, script_name: '/api/v2', path_info: '/x')
      )
    end

    it 'logs a session-continuity break when the session had no token' do
      expect(OT).to receive(:lw).with(/session-continuity break/, hash_including(method: 'POST'))

      middleware.call(env_for(method: 'POST', session: session))
    end

    it 'logs the full external path, not the mount-relative remainder' do
      expect(OT).to receive(:lw).with(anything, hash_including(path: '/api/v2/secret/conceal'))

      middleware.call(
        env_for(method: 'POST', session: session, script_name: '/api/v2', path_info: '/secret/conceal')
      )
    end

    it 'does not log for a safe method' do
      expect(OT).not_to receive(:lw)

      middleware.call(env_for(method: 'GET', session: session))
    end

    it 'treats an empty-string token as absent when classifying' do
      session[:csrf] = ''

      expect(OT).to receive(:lw).with(/session-continuity break/, anything)

      middleware.call(env_for(method: 'POST', session: session))
    end

    context 'when the 403 came from the app rather than the CSRF layer' do
      let(:downstream_side_effect) { ->(_env) {} }

      it 'does not log (no rejection marker)' do
        expect(OT).not_to receive(:lw)

        middleware.call(env_for(method: 'POST', session: session))
      end
    end

    context 'when the marker is set but the status is not 403' do
      let(:downstream_status) { 200 }

      it 'does not log' do
        expect(OT).not_to receive(:lw)

        middleware.call(env_for(method: 'POST', session: session))
      end
    end

    it 'still exposes a token on the 403 response' do
      # The client needs a usable token to retry; the 403 path must not strip it.
      _status, headers, = middleware.call(env_for(method: 'POST', session: session))

      expect(headers['X-CSRF-Token']).to be_a(String)
    end
  end

  describe 'unsafe-method session probing' do
    it 'does not read the session on safe methods' do
      # Reading the session lazy-loads it; safe requests must not pay that cost.
      probed = double('session')
      expect(probed).not_to receive(:[])

      middleware.call(env_for(method: 'GET', session_options: { skip: true }).merge('rack.session' => probed))
    end

    %w[POST PUT PATCH DELETE].each do |method|
      it "probes the session for a #{method} request" do
        probed = {}
        expect(probed).to receive(:[]).with(:csrf).and_return(nil).at_least(:once)

        middleware.call(
          env_for(method: method, session: probed, session_options: { skip: true })
        )
      end
    end
  end
end
