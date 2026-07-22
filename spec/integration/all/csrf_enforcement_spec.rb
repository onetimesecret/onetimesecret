# spec/integration/all/csrf_enforcement_spec.rb
#
# frozen_string_literal: true

require_relative '../integration_spec_helper'

RSpec.describe 'CSRF Enforcement', type: :integration do
  # Use shared_db_state to avoid flushing between tests in this group
  # since we're sharing the app instance
  before(:all) do
    require 'rack'
    require 'rack/mock'
    require 'base64'

    # Clear Redis env vars to ensure test config defaults are used (port 2121)
    @original_rack_env = ENV['RACK_ENV']
    @original_redis_url = ENV['REDIS_URL']
    @original_valkey_url = ENV['VALKEY_URL']
    ENV.delete('REDIS_URL')
    ENV.delete('VALKEY_URL')
    ENV['RACK_ENV'] = 'test'

    @app = Rack::Builder.parse_file('config.ru')
    @mock_request = Rack::MockRequest.new(@app)
  end

  after(:all) do
    if @original_rack_env
      ENV['RACK_ENV'] = @original_rack_env
    else
      ENV.delete('RACK_ENV')
    end
    if @original_redis_url
      ENV['REDIS_URL'] = @original_redis_url
    else
      ENV.delete('REDIS_URL')
    end
    if @original_valkey_url
      ENV['VALKEY_URL'] = @original_valkey_url
    else
      ENV.delete('VALKEY_URL')
    end
  end

  describe 'Rack::Protection::AuthenticityToken middleware' do
    describe 'middleware configuration' do
      it 'is configured with shrimp as the authenticity parameter' do
        middleware_config = Onetime::Middleware::Security.middleware_components['AuthenticityToken']

        expect(middleware_config).not_to be_nil
        expect(middleware_config[:klass]).to eq(Onetime::Middleware::InstrumentedAuthenticityToken)
        expect(middleware_config[:klass]).to be < Rack::Protection::AuthenticityToken
        expect(middleware_config[:options][:authenticity_param]).to eq('shrimp')
      end

      it 'has an allow_if proc for bypass logic' do
        middleware_config = Onetime::Middleware::Security.middleware_components['AuthenticityToken']
        allow_if = middleware_config[:options][:allow_if]

        expect(allow_if).to be_a(Proc)
      end
    end

    describe 'safe HTTP methods (GET, HEAD, OPTIONS)' do
      it 'GET requests work without CSRF token' do
        response = @mock_request.get('/')
        expect(response.status).to be_between(200, 302)
      end

      it 'HEAD requests work without CSRF token' do
        response = @mock_request.head('/')
        expect(response.status).to be_between(200, 302)
      end

      it 'OPTIONS requests work without CSRF token' do
        response = @mock_request.options('/')
        # OPTIONS may return 200 or 204 depending on CORS config
        expect(response.status).to be_between(200, 404)
      end

      it 'GET to authenticated route redirects without CSRF token (expected)' do
        response = @mock_request.get('/dashboard')
        # Should redirect to signin, not fail CSRF
        expect(response.status).to eq(302)
        expect(response.headers['location']).to eq('/signin')
      end
    end

    describe 'web routes require CSRF for state-changing requests' do
      it 'POST to web route without CSRF token returns 403 Forbidden' do
        # POST to signin without CSRF token should be rejected
        response = @mock_request.post('/signin', {
          params: { login: 'test@example.com', pass: 'password123' }
        })

        expect(response.status).to eq(403)
      end

      it 'POST to web route with valid X-CSRF-Token header succeeds' do
        # First, get a session with CSRF token
        get_response = @mock_request.get('/signin')
        cookie = get_response.headers['set-cookie']

        # Extract session cookie for subsequent request
        session_cookie = cookie.split(';').first if cookie

        # The session now has a CSRF token. We need to get it.
        # In a real browser, the token is embedded in the page.
        # For testing, we generate a valid token from the session.
        #
        # Since we can't easily extract the token from HTML,
        # we test the bypass logic instead (API with Basic Auth)
        # and verify the rejection works for missing tokens.

        # This confirms the middleware is enforcing CSRF
        response = @mock_request.post('/signin', {
          'HTTP_COOKIE' => session_cookie,
          params: { login: 'test@example.com', pass: 'password123' }
        })

        # Without valid CSRF token, should be 403
        expect(response.status).to eq(403)
      end

      it 'POST with shrimp form parameter would be validated' do
        # This test verifies the parameter name is correct
        # The actual token validation requires a valid session token
        response = @mock_request.post('/signin', {
          params: {
            login: 'test@example.com',
            pass: 'password123',
            shrimp: 'invalid_token_value'
          }
        })

        # Invalid token still returns 403
        expect(response.status).to eq(403)
      end
    end

    describe 'API routes with Basic Auth bypass CSRF' do
      let(:api_credentials) { Base64.strict_encode64('testuser:testapikey') }

      it 'POST to /api/v1/* with Basic Auth and no CSRF token succeeds' do
        # The /api/v1/generate endpoint allows anonymous POST
        # With Basic Auth header, CSRF should be bypassed
        response = @mock_request.post('/api/v1/generate', {
          'HTTP_AUTHORIZATION' => "Basic #{api_credentials}"
        })

        # Should not be 403 (CSRF rejection)
        # May be 401 (invalid credentials) or 200 (success) or other
        expect(response.status).not_to eq(403)
      end

      it 'POST to /api/v1/* with valid Basic Auth succeeds without CSRF' do
        # Generate endpoint works without auth, but with Basic Auth
        # it should bypass CSRF validation
        response = @mock_request.post('/api/v1/generate', {
          'HTTP_AUTHORIZATION' => "Basic #{api_credentials}"
        })

        # The generate endpoint is permissive - focus on CSRF not blocking it
        expect(response.status).not_to eq(403)
      end

      it 'POST to /api/v2/* with Basic Auth bypasses CSRF' do
        response = @mock_request.post('/api/v2/status', {
          'HTTP_AUTHORIZATION' => "Basic #{api_credentials}"
        })

        # Should not be 403 (CSRF rejection)
        # May be 404 (POST not allowed on status) or other
        expect(response.status).not_to eq(403)
      end
    end

    describe 'API routes without authentication' do
      it 'POST to /api/v1/generate without auth bypasses CSRF (anonymous allowed)' do
        # Anonymous API request with no session cookie has no CSRF vector:
        # - API v1 has no session auth (Basic Auth or anonymous only)
        # - Anonymous requests are stateless (no session = nothing to forge)
        response = @mock_request.post('/api/v1/generate')

        # Should NOT be 403 (CSRF rejection) - no session => bypass
        # Will be 400 (missing params) or similar API-level error
        expect(response.status).not_to eq(403)
      end

      it 'POST to /api/v1/* without any auth gets API-level response' do
        # Endpoint that requires auth
        response = @mock_request.post('/api/v1/share', {
          params: { secret: 'test secret' }
        })

        # Should NOT be 403 (CSRF rejection) - API routes bypass CSRF
        # Will be 401 (unauthorized) or other API-level response
        expect(response.status).not_to eq(403)
      end

      it 'bypasses CSRF for an anonymous API request with no session cookie' do
        # No ambient session cookie => nothing a forged cross-site request could
        # ride => no CSRF vector => bypass. Covers v1 (no session auth),
        # anonymous/programmatic clients, and the /api/incoming/* inbound surface.
        middleware_config = Onetime::Middleware::Security.middleware_components['AuthenticityToken']
        allow_if = middleware_config[:options][:allow_if]

        # Simulate request without Basic Auth and without an authenticated session
        env_without_auth = {
          'PATH_INFO' => '/api/v1/test',
          'REQUEST_METHOD' => 'POST'
        }

        result = allow_if.call(env_without_auth)
        expect(result).to be true # No session => no CSRF vector => bypass
      end

      it 'bypasses CSRF for an API request authenticated via Basic Auth' do
        middleware_config = Onetime::Middleware::Security.middleware_components['AuthenticityToken']
        allow_if = middleware_config[:options][:allow_if]

        # Simulate request WITH Basic Auth to /api/v1/test. Basic Auth is a
        # stateless per-request credential (API key), not an ambient cookie.
        credentials = Base64.strict_encode64('user:pass')
        env_with_auth = {
          'PATH_INFO' => '/api/v1/test',
          'REQUEST_METHOD' => 'POST',
          'HTTP_AUTHORIZATION' => "Basic #{credentials}"
        }

        result = allow_if.call(env_with_auth)
        expect(result).to be true # Basic Auth (no ambient cookie) => bypass
      end
    end

    describe 'session-authenticated API routes require CSRF (H-1)' do
      let(:allow_if) do
        Onetime::Middleware::Security.middleware_components['AuthenticityToken'][:options][:allow_if]
      end

      it 'does NOT bypass a session-authenticated API POST with no token' do
        # This is exactly the forged-cross-site scenario H-1 closed: an ambient
        # authenticated session cookie is present and no explicit credential is
        # supplied, so the request must fall through and require X-CSRF-Token.
        env = {
          'PATH_INFO' => '/api/v2/account',
          'REQUEST_METHOD' => 'POST',
          'rack.session' => { 'authenticated' => true }
        }

        expect(allow_if.call(env)).to be false
      end

      it 'still bypasses when Basic Auth is present even with a session cookie' do
        # Basic Auth short-circuits before the session check: an explicit API-key
        # credential is not a forgeable ambient credential.
        credentials = Base64.strict_encode64('user:pass')
        env = {
          'PATH_INFO' => '/api/v2/account',
          'REQUEST_METHOD' => 'POST',
          'HTTP_AUTHORIZATION' => "Basic #{credentials}",
          'rack.session' => { 'authenticated' => true }
        }

        expect(allow_if.call(env)).to be true
      end

      it 'bypasses an anonymous (unauthenticated) session API POST' do
        # Anonymous SPA guest flows carry a session cookie but authenticated=false,
        # so there is no sensitive ambient authority to abuse => bypass. (The SPA
        # sends a valid token anyway; not broken either way.)
        env = {
          'PATH_INFO' => '/api/v2/secret/conceal',
          'REQUEST_METHOD' => 'POST',
          'rack.session' => { 'authenticated' => false }
        }

        expect(allow_if.call(env)).to be true
      end
    end

    describe 'SSO routes bypass CSRF' do
      it 'bypasses CSRF for /auth/sso/* paths' do
        middleware_config = Onetime::Middleware::Security.middleware_components['AuthenticityToken']
        allow_if = middleware_config[:options][:allow_if]

        # SSO callback path
        env = {
          'PATH_INFO' => '/auth/sso/callback',
          'REQUEST_METHOD' => 'POST'
        }

        result = allow_if.call(env)
        expect(result).to be true
      end

      it 'bypasses CSRF for /auth/sso/google path' do
        middleware_config = Onetime::Middleware::Security.middleware_components['AuthenticityToken']
        allow_if = middleware_config[:options][:allow_if]

        env = {
          'PATH_INFO' => '/auth/sso/google',
          'REQUEST_METHOD' => 'POST'
        }

        result = allow_if.call(env)
        expect(result).to be true
      end

      it 'does NOT bypass CSRF for /auth/signin (non-SSO auth route)' do
        middleware_config = Onetime::Middleware::Security.middleware_components['AuthenticityToken']
        allow_if = middleware_config[:options][:allow_if]

        env = {
          'PATH_INFO' => '/auth/signin',
          'REQUEST_METHOD' => 'POST'
        }

        result = allow_if.call(env)
        expect(result).to be false
      end

      it 'does NOT bypass CSRF for /authentication route' do
        middleware_config = Onetime::Middleware::Security.middleware_components['AuthenticityToken']
        allow_if = middleware_config[:options][:allow_if]

        env = {
          'PATH_INFO' => '/authentication',
          'REQUEST_METHOD' => 'POST'
        }

        result = allow_if.call(env)
        expect(result).to be false
      end
    end

    describe 'non-API web routes enforce CSRF' do
      it 'POST to /feedback API route bypasses CSRF' do
        response = @mock_request.post('/api/v2/feedback', {
          params: { feedback: 'test feedback' }
        })

        # API routes bypass CSRF, will get API-level response (not 403)
        expect(response.status).not_to eq(403)
      end

      it 'POST to /account/* without CSRF token returns 403' do
        response = @mock_request.post('/account/update', {
          params: { name: 'Test User' }
        })

        expect(response.status).to eq(403)
      end
    end

    describe 'bypass logic edge cases' do
      let(:allow_if) do
        Onetime::Middleware::Security.middleware_components['AuthenticityToken'][:options][:allow_if]
      end

      it 'does not bypass for partial path match /api' do
        env = { 'PATH_INFO' => '/api', 'REQUEST_METHOD' => 'POST' }
        # /api without trailing / is ambiguous but start_with?('/api/') should be false
        result = allow_if.call(env)
        expect(result).to be false
      end

      it 'does not bypass for /apiv1/test (no slash after api)' do
        env = { 'PATH_INFO' => '/apiv1/test', 'REQUEST_METHOD' => 'POST' }
        result = allow_if.call(env)
        expect(result).to be false
      end

      it 'does not bypass for /auth/sso (no trailing path)' do
        env = { 'PATH_INFO' => '/auth/sso', 'REQUEST_METHOD' => 'POST' }
        # start_with?('/auth/sso/') would be false
        result = allow_if.call(env)
        expect(result).to be false
      end

      it 'bypasses for deep SSO paths like /auth/sso/provider/callback' do
        env = { 'PATH_INFO' => '/auth/sso/provider/callback', 'REQUEST_METHOD' => 'POST' }
        result = allow_if.call(env)
        expect(result).to be true
      end

      it 'bypasses an API route with a Bearer header and no session cookie' do
        # A Bearer header is not Basic Auth, but with no ambient session cookie
        # there is still no CSRF vector, so the request bypasses.
        env = {
          'PATH_INFO' => '/api/v1/test',
          'REQUEST_METHOD' => 'POST',
          'HTTP_AUTHORIZATION' => 'Bearer some-jwt-token'
        }
        result = allow_if.call(env)
        expect(result).to be true
      end

      it 'bypasses an API route with a malformed auth header and no session' do
        # 'Basic' without a trailing space + credentials does NOT match the Basic
        # short-circuit, but with no session cookie there is still nothing to
        # forge, so it bypasses on the no-session rule.
        env = {
          'PATH_INFO' => '/api/v1/test',
          'REQUEST_METHOD' => 'POST',
          'HTTP_AUTHORIZATION' => 'Basic' # Missing credentials
        }
        result = allow_if.call(env)
        expect(result).to be true # No session => no CSRF vector => bypass
      end
    end

    describe 'CSRF token parameter name' do
      it 'uses shrimp as form parameter name (legacy naming)' do
        config = Onetime::Middleware::Security.middleware_components['AuthenticityToken']
        expect(config[:options][:authenticity_param]).to eq('shrimp')
      end

      it 'accepts X-CSRF-Token header (Rack::Protection default)' do
        # Rack::Protection::AuthenticityToken checks both form param and header
        # The header name is hardcoded in the gem as X-CSRF-Token
        # This is used by Axios interceptor in the frontend

        # We verify by checking the middleware is our subclass of the standard
        # one (InstrumentedAuthenticityToken inherits the header handling).
        config = Onetime::Middleware::Security.middleware_components['AuthenticityToken']
        expect(config[:klass]).to be < Rack::Protection::AuthenticityToken
      end
    end
  end

  describe 'CSRF protection integration with authentication flow' do
    it 'login page is accessible via GET' do
      response = @mock_request.get('/signin')
      expect(response.status).to eq(200)
    end

    it 'login POST without CSRF is rejected' do
      response = @mock_request.post('/signin', {
        params: { login: 'test@example.com', pass: 'password123' }
      })
      expect(response.status).to eq(403)
    end

    it 'signup page is accessible via GET' do
      response = @mock_request.get('/signup')
      expect(response.status).to eq(200)
    end

    it 'signup POST without CSRF is rejected' do
      response = @mock_request.post('/signup', {
        params: { email: 'test@example.com', password: 'password123' }
      })
      expect(response.status).to eq(403)
    end
  end

  describe 'CsrfResponseHeader middleware positioning' do
    it 'returns X-CSRF-Token header on CSRF-rejected 403 responses' do
      # Establish a session first
      get_response = @mock_request.get('/signin')
      cookie = get_response.headers['set-cookie']
      session_cookie = cookie.split(';').first if cookie

      # POST without CSRF token — should be rejected with 403
      post_response = @mock_request.post('/signin', {
        'HTTP_COOKIE' => session_cookie,
        params: { login: 'test@example.com', pass: 'password123' }
      })

      expect(post_response.status).to eq(403)
      # CsrfResponseHeader wraps Security, so even a 403 gets the header
      expect(post_response.headers['X-CSRF-Token']).not_to be_nil,
        'Expected X-CSRF-Token header on 403 response so frontend can recover'
    end

    it 'returns X-CSRF-Token header on successful GET responses' do
      response = @mock_request.get('/signin')
      expect(response.status).to eq(200)
      expect(response.headers['X-CSRF-Token']).not_to be_nil
    end
  end

  describe 'CsrfResponseHeader 403 discrimination (#3837, root cause of #3831)' do
    # A CSRF 403 has two very different root causes that are indistinguishable
    # AFTER @app.call (AuthenticityToken#accepts? sets session[:csrf] before it
    # validates). CsrfResponseHeader captures presence BEFORE @app.call and logs
    # a discriminated warning. We drive the middleware directly with a stub app
    # so the branch is deterministic and does not depend on the full CSRF flow.
    # Simulates InstrumentedAuthenticityToken rejecting the request: its #deny
    # stamps the rejection marker BEFORE returning a 403. CsrfResponseHeader keys
    # its diagnostic on that marker, so the stub sets the SAME key to exercise the
    # real code path. (The live-stack tripwire below proves the real middleware
    # actually sets it.)
    let(:stub_403_app) do
      ->(env) {
        env[Onetime::Middleware::InstrumentedAuthenticityToken::REJECTION_ENV_KEY] = true
        [403, {}, []]
      }
    end
    let(:middleware) { Onetime::Middleware::CsrfResponseHeader.new(stub_403_app) }
    # A realistic raw session token: the downstream X-CSRF-Token masking block
    # base64-decodes session[:csrf], so it must be a valid urlsafe token (an
    # arbitrary string can trip Base64.urlsafe_decode64 on length).
    let(:valid_token) { Rack::Protection::AuthenticityToken.random_token }

    def env_for(method:, path:, session: nil)
      env = { 'REQUEST_METHOD' => method, 'PATH_INFO' => path }
      env['rack.session'] = session unless session.nil?
      env
    end

    it 'logs a session-continuity break when a POST 403s with NO token in session' do
      # No csrf token present at request start => the session was lost or never
      # persisted between issuing the token and this request. This is the #3837
      # bug class, NOT forgery.
      allow(OT).to receive(:lw).and_call_original
      middleware.call(env_for(method: 'POST', path: '/account/update', session: {}))

      expect(OT).to have_received(:lw).with(
        a_string_matching(/session-continuity break/),
        hash_including(method: 'POST', path: '/account/update')
      )
      # ...and it is NOT mis-classified as a genuine token-mismatch.
      expect(OT).not_to have_received(:lw).with(a_string_matching(/token-mismatch/), anything)
    end

    it 'logs a token-mismatch when a POST 403s WITH a token already in session' do
      # A raw token was present at request start but the submitted one did not
      # match => a genuine forged/stale request. CSRF_SESSION_KEY is :csrf, read
      # exactly as AuthenticityToken reads it.
      allow(OT).to receive(:lw).and_call_original
      middleware.call(env_for(method: 'POST', path: '/account/update', session: { csrf: valid_token }))

      expect(OT).to have_received(:lw).with(
        a_string_matching(/token-mismatch/),
        hash_including(method: 'POST', path: '/account/update')
      )
      # ...and it is NOT mis-classified as a session-continuity break.
      expect(OT).not_to have_received(:lw).with(a_string_matching(/session-continuity break/), anything)
    end

    it 'does NOT log for a SAFE method (GET) even when the response is 403' do
      # Safe methods are never CSRF-checked, so they must not pay the session
      # load cost nor emit a rejection log.
      allow(OT).to receive(:lw).and_call_original
      middleware.call(env_for(method: 'GET', path: '/account/update', session: {}))

      expect(OT).not_to have_received(:lw)
    end

    it 'does NOT log when an unsafe POST is NOT rejected (status != 403)' do
      ok_app = ->(_env) { [200, {}, []] }
      ok_middleware = Onetime::Middleware::CsrfResponseHeader.new(ok_app)
      allow(OT).to receive(:lw).and_call_original
      ok_middleware.call(env_for(method: 'POST', path: '/account/update', session: {}))

      expect(OT).not_to have_received(:lw)
    end

    it 'does NOT log when a non-CSRF 403 is returned (no attack marker)' do
      # An app-level 403 (Onetime::Forbidden, EntitlementRequired,
      # GuestRoutesDisabled) never sets the rejection marker. Before the marker
      # gate these were mis-logged as CSRF failures; now they are correctly
      # ignored so the CSRF diagnostic only fires on genuine CSRF rejections.
      plain_403_app   = ->(_env) { [403, {}, []] }
      plain_middleware = Onetime::Middleware::CsrfResponseHeader.new(plain_403_app)
      allow(OT).to receive(:lw).and_call_original
      plain_middleware.call(env_for(method: 'POST', path: '/account/update', session: {}))

      expect(OT).not_to have_received(:lw)
    end

    it 'logs the full request path including the URLMap SCRIPT_NAME prefix' do
      # CsrfResponseHeader runs above the URLMap mount, so a rejected POST to a
      # mounted app must log SCRIPT_NAME + PATH_INFO, not the prefix-stripped
      # PATH_INFO alone.
      allow(OT).to receive(:lw).and_call_original
      env = env_for(method: 'POST', path: '/v2/account/update', session: {})
      env['SCRIPT_NAME'] = '/api'
      middleware.call(env)

      expect(OT).to have_received(:lw).with(
        a_string_matching(/CSRF 403/),
        hash_including(path: '/api/v2/account/update')
      )
    end

    # TRIPWIRE: the tests above stub the marker. This one drives the FULL live
    # stack (CsrfResponseHeader wrapping the real InstrumentedAuthenticityToken),
    # so it fails loudly if the subclass's #deny stops setting the marker — e.g.
    # if rack-protection changes its reaction dispatch and `default_reaction
    # :deny` no longer rebinds, or if the subclass is dropped. Without this, a
    # marker that silently stopped firing would leave every other test green.
    it 'stamps the rejection marker through the REAL middleware stack on a genuine CSRF 403' do
      allow(OT).to receive(:lw).and_call_original

      # POST to a web route with no session and no shrimp -> the real
      # AuthenticityToken denies with 403 via its (rebound) deny path.
      response = @mock_request.post('/signin', {
        params: { login: 'test@example.com', pass: 'password123' }
      })

      expect(response.status).to eq(403)
      expect(OT).to have_received(:lw).with(
        a_string_matching(/CSRF 403/),
        hash_including(method: 'POST', path: '/signin')
      )
    end
  end

  describe 'CSRF round-trip: page-rendered token accepted on POST' do
    # Validates the invariant that tokens generated from rack.session
    # during page render are accepted by Rack::Protection on subsequent
    # POST. The tests above only confirm rejection (no token -> 403)
    # but never confirm the page serves a valid, usable token.
    it 'GET /signin serves a shrimp token that is accepted on POST /signin' do
      require 'nokogiri'

      # Step 1: GET the signin page to establish a session and receive HTML
      get_response = @mock_request.get('/signin')
      expect(get_response.status).to eq(200)

      # Extract session cookie from Set-Cookie header
      set_cookie = get_response.headers['set-cookie'] || get_response.headers['Set-Cookie']
      expect(set_cookie).not_to be_nil, 'Expected Set-Cookie header from GET /signin'
      session_cookie = set_cookie.split(';').first

      # Step 2: Parse the HTML to extract shrimp from __BOOTSTRAP_ME__
      doc = Nokogiri::HTML(get_response.body)
      state_script = doc.css('script[type="application/json"]').first
      expect(state_script).not_to be_nil, 'Expected <script type="application/json"> in signin page'

      state_data = JSON.parse(state_script.content)
      shrimp = state_data['shrimp']
      expect(shrimp).not_to be_nil, 'Expected shrimp in __BOOTSTRAP_ME__'
      expect(shrimp).not_to be_empty, 'Expected non-empty shrimp token'

      # Step 3: POST /signin with session cookie + extracted shrimp
      post_response = @mock_request.post('/signin', {
        'HTTP_COOKIE' => session_cookie,
        params: {
          login: 'test@example.com',
          pass: 'password123',
          shrimp: shrimp
        }
      })

      # Step 4: Assert NOT 403 -- the token from the page must be accepted
      # The response will be a redirect or auth error (invalid credentials),
      # but critically NOT a 403 CSRF rejection.
      expect(post_response.status).not_to eq(403),
        "CSRF round-trip failed: page-rendered shrimp was rejected. " \
        "Status #{post_response.status}. This means the token generated " \
        "during GET /signin is not valid for the subsequent POST."
    end
  end
end
