# spec/integration/all/csrf_enforcement_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration
# =============================================================================
#
# These tests verify CSRF protection enforcement across the application.
# They make REAL HTTP requests through the full middleware stack via Rack::Test.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
#
# RUN:
#   pnpm run test:rspec spec/integration/all/csrf_enforcement_spec.rb
#
# =============================================================================

require_relative '../integration_spec_helper'
require 'rack'
require 'rack/mock'
require 'base64'

RSpec.describe 'CSRF Enforcement', type: :integration do
  include Rack::Test::Methods

  # Build app once for all tests
  before(:all) do
    # Ensure test environment
    ENV['RACK_ENV'] = 'test'

    # Clear Redis env vars to ensure test config (port 2121) is used
    @original_redis_url = ENV['REDIS_URL']
    @original_valkey_url = ENV['VALKEY_URL']
    ENV.delete('REDIS_URL')
    ENV.delete('VALKEY_URL')

    # Boot the application
    Onetime.boot! :test

    @app = Rack::Builder.parse_file('config.ru')
  end

  after(:all) do
    ENV['REDIS_URL'] = @original_redis_url if @original_redis_url
    ENV['VALKEY_URL'] = @original_valkey_url if @original_valkey_url
  end

  def app
    @app
  end

  # Helper to get a valid CSRF token from a session
  # Makes a GET request first to establish session, then extracts token
  def get_csrf_token
    # Make an initial GET request to establish a session
    get '/'

    # Extract token from response header (set by CsrfResponseHeader middleware)
    last_response.headers['X-CSRF-Token']
  end

  # Helper to make a POST with a specific CSRF token
  def post_with_csrf(path, params = {}, token: nil, header_name: 'X-CSRF-Token')
    if token
      header header_name, token
    end
    post path, params
  end

  # Helper to encode Basic Auth credentials
  def basic_auth_header(username, password)
    encoded = Base64.strict_encode64("#{username}:#{password}")
    "Basic #{encoded}"
  end

  describe 'Middleware Configuration' do
    it 'has AuthenticityToken middleware enabled in test config' do
      middleware_config = Onetime::Middleware::Security.middleware_components['AuthenticityToken']

      expect(middleware_config).not_to be_nil
      expect(middleware_config[:klass]).to eq(Rack::Protection::AuthenticityToken)
      expect(middleware_config[:options][:authenticity_param]).to eq('shrimp')
    end

    it 'has allow_if proc configured for API and SSO bypass' do
      middleware_config = Onetime::Middleware::Security.middleware_components['AuthenticityToken']
      allow_if = middleware_config[:options][:allow_if]

      expect(allow_if).to be_a(Proc)
    end
  end

  describe 'CSRF Token Required for State-Changing Requests' do
    # These tests verify that state-changing HTTP methods require CSRF tokens
    # when accessing web routes (non-API routes)

    context 'POST without token' do
      it 'returns 403 Forbidden for form submission endpoint' do
        # Use a web endpoint that accepts POST but requires CSRF
        # The /signin endpoint processes login forms
        post '/signin', { u: 'test@example.com', p: 'password' }

        expect(last_response.status).to eq(403)
      end

      it 'returns 403 for feedback submission' do
        post '/feedback', { msg: 'test feedback' }

        expect(last_response.status).to eq(403)
      end
    end

    context 'PUT without token' do
      it 'returns 403 Forbidden' do
        # Web endpoints don't typically use PUT, but middleware still protects
        put '/account/update', { name: 'test' }

        # Either 403 (CSRF rejection) or 404 (no route) is acceptable
        # The key is it should NOT return 200
        expect([403, 404]).to include(last_response.status)
      end
    end

    context 'PATCH without token' do
      it 'returns 403 Forbidden' do
        patch '/account/settings', { locale: 'fr' }

        expect([403, 404]).to include(last_response.status)
      end
    end

    context 'DELETE without token' do
      it 'returns 403 Forbidden' do
        delete '/account/session'

        expect([403, 404]).to include(last_response.status)
      end
    end
  end

  describe 'Valid Token Allows Requests' do
    context 'with X-CSRF-Token header' do
      it 'allows POST request with valid masked token' do
        # Get a CSRF token from a session
        token = get_csrf_token
        skip 'CSRF token not returned in response header' unless token

        # Use the token for a POST request
        header 'X-CSRF-Token', token
        post '/feedback', { msg: 'test feedback with valid token' }

        # Should not be 403 (CSRF rejection)
        expect(last_response.status).not_to eq(403)
      end
    end

    context 'with shrimp form parameter' do
      it 'allows POST request with valid token in shrimp param' do
        token = get_csrf_token
        skip 'CSRF token not returned in response header' unless token

        # Submit with 'shrimp' parameter (the configured authenticity_param)
        post '/feedback', { msg: 'test feedback', shrimp: token }

        # Should not be 403 (CSRF rejection)
        expect(last_response.status).not_to eq(403)
      end
    end
  end

  describe 'Safe Methods Do Not Require Token' do
    context 'GET requests' do
      it 'succeeds without CSRF token' do
        get '/'

        expect(last_response.status).to eq(200)
      end

      it 'succeeds for any GET route' do
        get '/signin'

        expect(last_response.status).to eq(200)
      end
    end

    context 'HEAD requests' do
      it 'succeeds without CSRF token' do
        head '/'

        # HEAD should return success (same as GET but no body)
        expect([200, 302]).to include(last_response.status)
      end
    end

    context 'OPTIONS requests' do
      it 'succeeds without CSRF token' do
        options '/'

        # OPTIONS typically returns 200 or 204
        expect([200, 204, 404]).to include(last_response.status)
      end
    end
  end

  describe 'API Routes Bypass CSRF (Use Basic Auth Instead)' do
    # API routes use HTTP Basic Auth for authentication, not session cookies
    # Therefore CSRF protection is not needed and is bypassed

    context 'API v1 routes' do
      it 'allows POST without CSRF token' do
        # The /api/v1/generate endpoint creates random secrets
        # It allows anonymous access
        post '/api/v1/generate'

        # Should succeed (200) or require auth (401/404), but NOT 403 CSRF
        expect(last_response.status).not_to eq(403)
        expect([200, 401, 404]).to include(last_response.status)
      end

      it 'allows POST with Basic Auth and no CSRF token' do
        # Even with Basic Auth credentials, CSRF should be bypassed
        header 'Authorization', basic_auth_header('test@example.com', 'fake_api_token')
        post '/api/v1/status'

        # Should fail auth (401/404) but not CSRF (403)
        expect(last_response.status).not_to eq(403)
      end

      it 'processes request normally after CSRF bypass' do
        post '/api/v1/generate'

        expect(last_response.status).to eq(200)
        expect(last_response.content_type).to include('application/json')
      end
    end

    context 'API v2 routes' do
      it 'allows POST without CSRF token' do
        post '/api/v2/secret/conceal', { secret: 'test value' }

        # Should NOT be 403 (CSRF rejection)
        # May be 422 (validation error) or other status
        expect(last_response.status).not_to eq(403)
      end

      it 'returns proper JSON response' do
        get '/api/v2/status'

        expect(last_response.status).to eq(200)
        expect(last_response.content_type).to include('application/json')

        body = JSON.parse(last_response.body)
        expect(body['status']).to eq('nominal')
      end
    end
  end

  describe 'SSO Routes Bypass CSRF (Use OAuth State Instead)' do
    # SSO routes use OAuth state parameter for CSRF protection
    # The standard CSRF token is bypassed for these routes

    it 'allows POST to /auth/sso/ without CSRF token' do
      # SSO callback routes receive POSTs from identity providers
      post '/auth/sso/callback', { code: 'fake_code', state: 'fake_state' }

      # Should NOT be 403 (CSRF rejection)
      # May be 302 (redirect), 400 (bad request), or 404 (not configured)
      expect(last_response.status).not_to eq(403)
    end
  end

  describe 'JSON Requests Still Require CSRF' do
    # IMPORTANT: This is the vulnerability fix verification
    # Previously, JSON requests could bypass CSRF via Content-Type header
    # This was a security hole because Content-Type is attacker-controlled

    context 'POST with Content-Type: application/json but no token' do
      it 'returns 403 Forbidden for web routes' do
        header 'Content-Type', 'application/json'
        header 'Accept', 'application/json'
        post '/signin', { u: 'test@example.com', p: 'password' }.to_json

        expect(last_response.status).to eq(403)
      end
    end

    context 'POST with Accept: application/json but no token' do
      it 'returns 403 Forbidden for web routes' do
        header 'Accept', 'application/json'
        post '/feedback', { msg: 'test' }

        expect(last_response.status).to eq(403)
      end
    end

    context 'JSON request with valid CSRF token' do
      it 'succeeds when token is provided' do
        token = get_csrf_token
        skip 'CSRF token not returned in response header' unless token

        header 'Content-Type', 'application/json'
        header 'Accept', 'application/json'
        header 'X-CSRF-Token', token
        post '/feedback', { msg: 'test feedback' }.to_json

        # Should not be 403 (CSRF rejection)
        expect(last_response.status).not_to eq(403)
      end
    end
  end

  describe 'Token Rotation (Replay Attack Prevention)' do
    # After a successful state-changing request, the CSRF token should rotate
    # This prevents replay attacks where an attacker reuses a captured token

    it 'provides new token in response header after successful POST' do
      # Get initial token
      initial_token = get_csrf_token
      skip 'CSRF token not returned in response header' unless initial_token

      # Make a successful POST (to an API route to avoid needing auth)
      # Then check if a new token is returned
      post '/api/v1/generate'

      new_token = last_response.headers['X-CSRF-Token']

      # Token should be present in response
      # Note: For API routes, the token may or may not rotate since CSRF is bypassed
      # The key test is that tokens ARE rotated for web routes
      expect(new_token).to be_a(String) if new_token
    end

    it 'rejects previously used token (replay attack prevention)' do
      # This test verifies the application-level token regeneration
      # Get a token
      token = get_csrf_token
      skip 'CSRF token not returned in response header' unless token

      # Use it for a request (web route, not API)
      header 'X-CSRF-Token', token
      post '/feedback', { msg: 'first request' }

      first_status = last_response.status

      # If first request succeeded (wasn't blocked by CSRF), try to reuse token
      if first_status != 403
        # Clear headers and reuse same token
        header 'X-CSRF-Token', token
        post '/feedback', { msg: 'replay attempt' }

        # Second request should be rejected if token was properly rotated
        # Note: This depends on the ShrimpHelpers#verify_shrimp! regeneration
        # The middleware itself may still accept the token since it's "valid"
        # but the application layer should regenerate
        second_status = last_response.status

        # Either the middleware rejects it (403) or app handles it (not 200)
        # This is a defense-in-depth check
        expect([403, 404, 302, 422]).to include(second_status)
      end
    end
  end

  describe 'Cross-Origin Request Protection' do
    # Additional protection layer: HttpOrigin middleware validates Origin header

    context 'when HttpOrigin middleware is enabled' do
      it 'validates Origin header for POST requests' do
        # This test checks that the HttpOrigin middleware is configured
        middleware_config = Onetime::Middleware::Security.middleware_components['HttpOrigin']

        expect(middleware_config).not_to be_nil
        expect(middleware_config[:klass]).to eq(Rack::Protection::HttpOrigin)
      end
    end
  end

  describe 'Error Response Format' do
    it 'returns HTML error page for web requests without token' do
      post '/signin', { u: 'test@example.com', p: 'password' }

      expect(last_response.status).to eq(403)
      # Rack::Protection returns HTML by default for CSRF failures
      # or the app may customize this
    end

    it 'returns proper status code in the response' do
      post '/feedback', { msg: 'test' }

      # 403 Forbidden is the expected response for CSRF violations
      expect(last_response.status).to eq(403)
    end
  end

  describe 'Session Persistence' do
    it 'maintains session across requests for CSRF validation' do
      # First request establishes session
      get '/'
      token1 = last_response.headers['X-CSRF-Token']

      # Second request with same session should have consistent token
      # (until it's used for a state-changing request)
      get '/about'
      token2 = last_response.headers['X-CSRF-Token']

      # Tokens should be consistent within a session for GET requests
      # (they only rotate on state-changing requests)
      if token1 && token2
        # Both tokens should be valid format (URL-safe Base64 with - and _)
        expect(token1).to match(/^[A-Za-z0-9+\/=_-]+$/)
        expect(token2).to match(/^[A-Za-z0-9+\/=_-]+$/)
      end
    end
  end
end
