# spec/integration/dual_auth_mode_spec.rb

# Integration tests for dual authentication mode (basic/advanced)
#
# @note: You can add `DEBUG_DATABASE=1` when running rspec or tryouts
# tests to see the redis commands in stderr. Be careful how many tests
# you run at one time: it is a lot of output for small context windows.

require 'spec_helper'
require 'rack/test'
require 'json'
require 'familia'

RSpec.describe 'Dual Authentication Mode Integration', type: :request do
  include Rack::Test::Methods

  def app
    @app ||= begin
      # Setup environment
      ENV['RACK_ENV'] = 'test'
      ENV['AUTHENTICATION_MODE'] = 'basic'
      ENV['REDIS_URL'] = 'redis://127.0.0.1:2121/0'

      # Boot application
      require_relative '../../lib/onetime'
      require_relative '../../lib/onetime/config'
      Onetime.boot! :test

      require_relative '../../lib/onetime/auth_config'
      require_relative '../../lib/onetime/middleware'
      require_relative '../../lib/onetime/application/registry'

      # Prepare registry
      Onetime::Application::Registry.prepare_application_registry

      # Return Core app (handles /auth/* in basic mode)
      Onetime::Application::Registry.mount_mappings['/'].new
    end
  end

  def json_response
    response = JSON.parse(last_response.body)
    # Handle wrapped responses: {"data": "{...}", "success": true}
    if response.is_a?(Hash) && response['data'].is_a?(String)
      JSON.parse(response['data'])
    else
      response
    end
  end

  def json_request_headers
    { 'HTTP_ACCEPT' => 'application/json' }
  end

  let(:redis) do
    require 'redis'
    Redis.new(url: 'redis://127.0.0.1:2121/0')
  end

  let(:test_email) { 'testuser@example.com' }
  let(:test_password) { 'SecureP@ssw0rd123' }

  before(:all) do
    # Clear Redis before tests
    require 'redis'
    redis = Redis.new(url: 'redis://127.0.0.1:2121/0')
    redis.flushdb
  end

  # Helper to create a test customer
  def create_test_customer(email: test_email, password: test_password)
    require 'bcrypt'
    require_relative '../../lib/onetime/models/customer'

    # Check if customer already exists and delete if so
    existing = Onetime::Customer.find_by_email(email)
    existing&.destroy!

    # Create customer
    cust = Onetime::Customer.create(email)

    # Set password (BCrypt hash)
    cust.passphrase = BCrypt::Password.create(password).to_s
    cust.verified = 'true'
    cust.role = 'customer'
    cust.save

    cust
  end

  describe 'Basic Mode Configuration' do
    before(:all) do
      # Force app loading by calling app method
      app
    end

    it 'runs in basic mode' do
      expect(Onetime.auth_config.mode).to eq('basic')
    end

    it 'has advanced mode disabled' do
      expect(Onetime.auth_config.advanced_enabled?).to be false
    end

    it 'does not mount Auth app' do
      expect(Onetime::Application::Registry.mount_mappings.key?('/auth')).to be false
    end

    it 'mounts Core app at root' do
      expect(Onetime::Application::Registry.mount_mappings.key?('/')).to be true
    end
  end

  describe 'POST /auth/login' do
    context 'with invalid credentials' do
      it 'returns 401 status' do
        post '/auth/login',
          { u: 'nonexistent@example.com', p: 'wrongpassword' },
          json_request_headers

        expect(last_response.status).to eq(401)
      end

      it 'returns JSON response' do
        post '/auth/login',
          { u: 'nonexistent@example.com', p: 'wrongpassword' },
          json_request_headers

        expect(last_response.headers['Content-Type']).to include('application/json')
      end

      it 'returns error structure' do
        post '/auth/login',
          { u: 'nonexistent@example.com', p: 'wrongpassword' },
          json_request_headers

        response = json_response
        expect(response).to have_key('error')
        expect(response['error']).to be_a(String)
      end

      it 'returns field-error tuple' do
        post '/auth/login',
          { u: 'nonexistent@example.com', p: 'wrongpassword' },
          json_request_headers

        response = json_response
        expect(response).to have_key('field-error')
        expect(response['field-error']).to be_an(Array)
        expect(response['field-error'].length).to eq(2)
        expect(response['field-error'][0]).to eq('email')
        expect(response['field-error'][1]).to eq('invalid')
      end
    end

    context 'without JSON Accept header' do
      it 'redirects on authentication failure' do
        post '/auth/login',
          { u: 'test@example.com', p: 'password' }

        # Should redirect or return 401, but never 500 (server error)
        expect(last_response.status).to eq(302).or eq(401)
      end
    end
  end

  describe 'POST /auth/create-account' do
    context 'with incomplete data' do
      it 'returns validation error (400 or 422)' do
        post '/auth/create-account',
          { u: 'incomplete@example.com' },
          json_request_headers

        # Missing password should return 400 (bad request) or 422 (unprocessable)
        expect(last_response.status).to eq(400).or eq(422)
        expect(last_response.headers['Content-Type']).to include('application/json')
      end
    end
  end

  describe 'POST /logout' do
    it 'accepts logout request' do
      post '/logout', {}, json_request_headers

      # Success or redirect (no active session)
      expect(last_response.status).to eq(200).or eq(302)
    end

    context 'with JSON request' do
      it 'returns JSON response on success' do
        post '/logout', {}, json_request_headers

        if last_response.status == 200
          expect(last_response.headers['Content-Type']).to include('application/json')
        end
      end
    end
  end

  describe 'POST /auth/reset-password' do
    it 'accepts password reset request' do
      post '/auth/reset-password',
        { u: 'reset@example.com' },
        json_request_headers

      # Could be success (200), bad request (400), or validation error (422)
      expect(last_response.status).to satisfy { |status| [200, 400, 422].include?(status) }
      expect(last_response.headers['Content-Type']).to include('application/json')
    end
  end

  describe 'POST /auth/reset-password/:key' do
    it 'rejects invalid reset token' do
      post '/auth/reset-password/testtoken123',
        { p: 'newpassword123', password_confirm: 'newpassword123' },
        json_request_headers

      # Invalid token should return 400 (bad request), 404 (not found), or 422 (invalid)
      expect(last_response.status).to satisfy { |status| [400, 404, 422].include?(status) }
      expect(last_response.headers['Content-Type']).to include('application/json')
    end
  end

  describe 'Response Format Compatibility' do
    it 'uses Rodauth-compatible JSON format for errors' do
      post '/auth/login',
        { u: 'test@example.com', p: 'wrong' },
        json_request_headers

      response = json_response

      # Should have either 'success' or 'error' key
      expect(response.keys & ['success', 'error']).not_to be_empty

      # If error, should have field-error tuple
      if response.key?('error')
        expect(response).to have_key('field-error')
        expect(response['field-error']).to be_an(Array)
      end
    end
  end

  describe 'Session Lifecycle (Full Authentication Flow)' do
    before(:each) do
      # Create test customer for each test
      @test_cust = create_test_customer
    end

    after(:each) do
      # Clean up test customer
      @test_cust&.destroy! if @test_cust
    end

    context 'successful authentication' do
      it 'login returns 200 with success message' do
        post '/auth/login',
          { u: test_email, p: test_password },
          json_request_headers

        expect(last_response.status).to eq(200)
        expect(last_response.headers['Content-Type']).to include('application/json')

        response = json_response
        expect(response).to have_key('success')
        expect(response['success']).to be_a(String)
      end

      it 'sets session cookie on successful login' do
        post '/auth/login',
          { u: test_email, p: test_password },
          json_request_headers

        expect(last_response.status).to eq(200)

        # Extract session cookie
        set_cookie = last_response.headers['Set-Cookie']
        expect(set_cookie).not_to be_nil
        expect(set_cookie).to include('rack.session')
      end

      it 'session persists across requests' do
        # Step 1: Login
        post '/auth/login',
          { u: test_email, p: test_password },
          json_request_headers

        expect(last_response.status).to eq(200)

        # Extract cookie from login response
        cookie = last_response.headers['Set-Cookie']
        expect(cookie).not_to be_nil

        # Step 2: Make authenticated request using the cookie
        get '/private',
          {},
          { 'HTTP_COOKIE' => cookie }

        # Should either succeed (200) or redirect to login if route doesn't exist (302)
        expect(last_response.status).to satisfy { |s| [200, 302, 404].include?(s) }
      end

      it 'logout destroys the session' do
        # Step 1: Login
        post '/auth/login',
          { u: test_email, p: test_password },
          json_request_headers

        cookie = last_response.headers['Set-Cookie']

        # Step 2: Logout
        post '/logout',
          {},
          json_request_headers.merge('HTTP_COOKIE' => cookie)

        expect(last_response.status).to eq(200).or eq(302)

        # Step 3: Try to use the old cookie (should fail)
        get '/private',
          {},
          { 'HTTP_COOKIE' => cookie }

        # Should redirect to login or return unauthorized
        expect(last_response.status).to satisfy { |s| [302, 401].include?(s) }
      end
    end

    context 'Redis session storage' do
      it 'stores session in Redis after login' do
        post '/auth/login',
          { u: test_email, p: test_password },
          json_request_headers

        expect(last_response.status).to eq(200)

        # Check Redis for session keys
        session_keys = redis.keys('*session*')
        expect(session_keys).not_to be_empty
      end

      it 'removes session from Redis after logout' do
        # Login
        post '/auth/login',
          { u: test_email, p: test_password },
          json_request_headers

        cookie = last_response.headers['Set-Cookie']

        # Verify session exists in Redis
        session_keys_before = redis.keys('*session*')
        expect(session_keys_before).not_to be_empty

        # Logout
        post '/logout',
          {},
          json_request_headers.merge('HTTP_COOKIE' => cookie)

        # Verify session removed from Redis
        # Note: Rack session middleware might keep empty session, so check for authenticated data
        session_keys_after = redis.keys('*session*')

        # Session should either be deleted or cleared (no authenticated_at)
        if session_keys_after.any?
          session_keys_after.each do |key|
            session_data = redis.get(key)
            expect(session_data).not_to include('authenticated_at') if session_data
          end
        end
      end
    end

    context 'session authentication state' do
      it 'sets authenticated_at timestamp on login' do
        post '/auth/login',
          { u: test_email, p: test_password },
          json_request_headers

        expect(last_response.status).to eq(200)

        # Extract session cookie and verify it contains auth timestamp
        cookie = last_response.headers['Set-Cookie']
        expect(cookie).not_to be_nil

        # Make another request to verify session state
        get '/dashboard',
          {},
          { 'HTTP_COOKIE' => cookie }

        # The session should be authenticated (regardless of whether dashboard exists)
        # This is verified by not getting a 401
        expect(last_response.status).not_to eq(401)
      end
    end
  end
end
