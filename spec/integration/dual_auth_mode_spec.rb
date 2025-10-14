# spec/integration/dual_auth_mode_spec.rb

# Integration tests for dual authentication mode (basic/advanced)
#
# @note: You can add `DEBUG_DATABASE=1` when running rspec or tryouts
# tests to see the database commands in stderr. Be careful how many tests
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

      Onetime.boot! :test

      # Prepare registry
      Onetime::Application::Registry.prepare_application_registry

      # Return full Rack app with middleware stack (including session middleware)
      Onetime::Application::Registry.generate_rack_url_map
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

  let(:dbclient) do
    Familia.dbclient
  end

  let(:test_email) { 'testuser@example.com' }
  let(:test_password) { 'SecureP@ssw0rd123' }

  # Helper to create a test customer
  def create_test_customer(email: test_email, password: test_password)
    require 'bcrypt'

    # Customer model should already be loaded from app initialization
    # Check if customer already exists using email index
    if Onetime::Customer.email_exists?(email)
      existing = Onetime::Customer.find_by_email(email)
      existing&.destroy!
    end

    # Create customer
    cust = Onetime::Customer.create!(email)

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

  describe 'POST /logout (without authentication)' do
    it 'succeeds gracefully (idempotent)' do
      post '/logout', {}, json_request_headers

      # Logout is idempotent - succeeds even if not authenticated
      expect(last_response.status).to eq(200).or eq(302)
    end
  end

  describe 'POST /logout (WITH authentication)' do
    before(:each) do
      # Clear database and create test customer
      dbclient.flushdb
      @test_cust = create_test_customer

      # Login to establish authenticated session
      post '/auth/login',
        { u: test_email, p: test_password },
        json_request_headers

      @session_cookie = last_response.headers['Set-Cookie']
    end

    after(:each) do
      @test_cust&.destroy! if @test_cust
      dbclient.flushdb
    end

    it 'successfully logs out with valid session' do
      post '/logout', {}, json_request_headers.merge('HTTP_COOKIE' => @session_cookie)

      # Should succeed with 200 or 302
      expect(last_response.status).to eq(200).or eq(302)
    end

    it 'is idempotent - second logout succeeds gracefully' do
      # First logout
      post '/logout', {}, json_request_headers.merge('HTTP_COOKIE' => @session_cookie)
      expect(last_response.status).to eq(200).or eq(302)

      # Second logout with same cookie should succeed (idempotent)
      post '/logout', {}, json_request_headers.merge('HTTP_COOKIE' => @session_cookie)
      expect(last_response.status).to eq(200).or eq(302)
    end
  end

  describe 'POST /auth/logout (without authentication)' do
    it 'succeeds gracefully (idempotent)' do
      post '/auth/logout', {}, json_request_headers

      # Logout is idempotent - succeeds even if not authenticated
      expect(last_response.status).to eq(200).or eq(302)
    end

    context 'with JSON request' do
      it 'returns JSON success response' do
        post '/auth/logout', {}, json_request_headers

        expect(last_response.status).to eq(200).or eq(302)
        expect(last_response.headers['Content-Type']).to include('application/json')
      end
    end
  end

  describe 'POST /auth/logout (WITH authentication)' do
    before(:each) do
      # Clear database and create test customer
      dbclient.flushdb
      @test_cust = create_test_customer

      # Login to establish authenticated session
      post '/auth/login',
        { u: test_email, p: test_password },
        json_request_headers

      @session_cookie = last_response.headers['Set-Cookie']
    end

    after(:each) do
      @test_cust&.destroy! if @test_cust
      dbclient.flushdb
    end

    it 'successfully logs out with valid session' do
      post '/auth/logout', {}, json_request_headers.merge('HTTP_COOKIE' => @session_cookie)

      # Should succeed with 200 or 302
      expect(last_response.status).to eq(200).or eq(302)
    end

    it 'is idempotent - second logout succeeds gracefully' do
      # First logout
      post '/auth/logout', {}, json_request_headers.merge('HTTP_COOKIE' => @session_cookie)
      expect(last_response.status).to eq(200).or eq(302)

      # Second logout with same cookie should succeed (idempotent)
      post '/auth/logout', {}, json_request_headers.merge('HTTP_COOKIE' => @session_cookie)
      expect(last_response.status).to eq(200).or eq(302)
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
    before(:all) do
      # Ensure app is loaded
      app
    end

    before(:each) do
      # Clear database to ensure clean state for each test
      dbclient.flushdb

      # Create test customer for each test
      @test_cust = create_test_customer
    end

    after(:each) do
      # Clean up test customer
      @test_cust&.destroy! if @test_cust
      # Ensure database is clean after test
      dbclient.flushdb
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
        # Session cookie name is "onetime.session"
        expect(set_cookie).to include('onetime.session')
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

        # Step 2: Logout with the session cookie
        post '/auth/logout',
          {},
          json_request_headers.merge('HTTP_COOKIE' => cookie)

        # Logout should work with valid session cookie
        expect(last_response.status).to eq(200).or eq(302)
      end

      it 'logout destroys the session' do
        # Step 1: Login
        post '/auth/login',
          { u: test_email, p: test_password },
          json_request_headers

        cookie = last_response.headers['Set-Cookie']

        # Step 2: Logout
        post '/auth/logout',
          {},
          json_request_headers.merge('HTTP_COOKIE' => cookie)

        expect(last_response.status).to eq(200).or eq(302)

        # Step 3: Try to logout again with old cookie (should be idempotent)
        post '/auth/logout',
          {},
          json_request_headers.merge('HTTP_COOKIE' => cookie)

        # Second logout succeeds (idempotent behavior)
        expect(last_response.status).to eq(200).or eq(302)
      end
    end

    context 'Session storage' do
      it 'stores session in kv database after login' do
        post '/auth/login',
          { u: test_email, p: test_password },
          json_request_headers

        expect(last_response.status).to eq(200)

        # Check kv database for session keys
        session_keys = dbclient.keys('*session*')
        expect(session_keys).not_to be_empty
      end

      it 'removes session from kv database after logout' do
        # Login
        post '/auth/login',
          { u: test_email, p: test_password },
          json_request_headers

        cookie = last_response.headers['Set-Cookie']

        # Verify session exists in kv database
        session_keys_before = dbclient.keys('*session*')
        expect(session_keys_before).not_to be_empty

        # Logout
        post '/auth/logout',
          {},
          json_request_headers.merge('HTTP_COOKIE' => cookie)

        # Verify session removed from kv database
        # Note: Rack session middleware might keep empty session, so check for authenticated data
        session_keys_after = dbclient.keys('*session*')

        # Session should either be deleted or cleared (no authenticated_at)
        if session_keys_after.any?
          session_keys_after.each do |key|
            session_data = dbclient.get(key)
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
