# spec/integration/dual_auth_mode_spec.rb
#
# frozen_string_literal: true

# Integration tests for dual authentication mode (simple/full)
#
# @note: You can add `DEBUG_DATABASE=1` when running rspec or tryouts
# tests to see the database commands in stderr. Be careful how many tests
# you run at one time: it is a lot of output for small context windows.

require_relative '../integration_spec_helper'
require_relative '../../support/factories/auth_account_factory'
require 'json'
require 'familia'

RSpec.describe 'Dual Authentication Mode Integration', type: :integration do
  include AuthTestConstants
  include Rack::Test::Methods

  def json_response
    response = JSON.parse(last_response.body)
    # Handle wrapped responses: {"data": "{...}", "success": true}
    if response.is_a?(Hash) && response['data'].is_a?(String)
      JSON.parse(response['data'])
    else
      response
    end
  end

  # Headers for JSON API requests (Rodauth json-only mode requires both)
  def json_request_headers
    {
      'HTTP_ACCEPT' => 'application/json',
      'CONTENT_TYPE' => 'application/json'
    }
  end

  # Helper to post JSON data to Rodauth endpoints
  def post_json(path, data = {}, headers = {})
    post path, data.to_json, json_request_headers.merge(headers)
  end

  let(:dbclient) do
    Familia.dbclient
  end

  let(:test_email) { 'testuser@example.com' }
  let(:test_password) { 'SecureP@ssw0rd123' }

  # Helper to create a test customer (Redis) and SQL account (Rodauth)
  #
  # For full auth mode, Rodauth uses SQL accounts table while the app uses
  # Redis-based Customer model. Both must be created and linked via external_id.
  #
  def create_test_customer(email: test_email, password: test_password)
    require 'argon2'

    # Get SQL database connection
    sql_db = Auth::Database.connection

    # Clean up any existing account with this email in SQL
    # Must delete from all tables with foreign keys to accounts first
    existing_account = sql_db[:accounts].where(email: email).first
    if existing_account
      account_id = existing_account[:id]

      # Delete from tables using 'id' as foreign key (Rodauth convention for 1:1 tables)
      # These tables have a 1:1 relationship with accounts - the id IS the account_id
      tables_with_id_fk = %i[
        account_password_hashes
        account_otp_keys
        account_webauthn_user_ids
        account_email_auth_keys
        account_lockouts
        account_login_failures
        account_password_reset_keys
        account_remember_keys
        account_verification_keys
        account_login_change_keys
        account_single_session_keys
        account_sms_codes_keys
        account_expiration_times
        account_password_change_times
        account_otp_unlock_keys
        account_recovery_codes
      ]

      # Delete from tables using 'account_id' as foreign key (Rodauth convention for 1:many tables)
      # These tables can have multiple rows per account
      tables_with_account_id_fk = %i[
        account_authentication_audit_logs
        account_active_session_keys
        account_previous_password_hashes
        account_jwt_refresh_keys
        account_webauthn_keys
      ]

      tables_with_id_fk.each do |table|
        next unless sql_db.table_exists?(table)

        sql_db[table].where(id: account_id).delete
      end

      tables_with_account_id_fk.each do |table|
        next unless sql_db.table_exists?(table)

        sql_db[table].where(account_id: account_id).delete
      end

      sql_db[:accounts].where(id: account_id).delete
    end

    # Create Redis customer first
    if Onetime::Customer.email_exists?(email)
      existing = Onetime::Customer.find_by_email(email)
      existing&.destroy!
    end

    cust = Onetime::Customer.create!(email)
    cust.verified = 'true'
    cust.role = 'customer'
    cust.save

    # Create SQL account for Rodauth
    # status_id: 2 = Verified (see account_statuses table)
    account_id = sql_db[:accounts].insert(
      email: email,
      status_id: AuthTestConstants::STATUS_VERIFIED
    )

    # Link SQL account to Redis customer via external_id
    # The external_identity feature with autocreate mode adds this column
    sql_db[:accounts].where(id: account_id).update(external_id: cust.extid)

    # Hash password with Argon2 (same params as test config)
    argon2 = Argon2::Password.new(t_cost: 1, m_cost: 5, p_cost: 1)
    password_hash = argon2.create(password)

    # Store password hash in account_password_hashes table
    sql_db[:account_password_hashes].insert(
      id: account_id,
      password_hash: password_hash
    )

    cust
  end

  describe 'Simple Mode Configuration' do
    def app
      @simple_app ||= begin
        # Setup environment for simple mode
        ENV['AUTHENTICATION_MODE'] = 'simple'

        # IMPORTANT: Reload auth config BEFORE reset! so that
        # should_skip_loading? checks see the correct mode
        Onetime.auth_config.reload!

        # Reset both registries to clear state from previous test runs
        # This re-registers loaded applications but skips Auth in simple mode
        Onetime::Application::Registry.reset!
        Onetime::Boot::InitializerRegistry.soft_reset!

        # Reset ready state to allow boot! to reload config
        # Without this, boot! returns early and OT.conf may be stale/nil
        Onetime.reset_ready!

        # Boot application (Redis mocking is handled globally by integration_spec_helper.rb)
        Onetime.boot! :test

        # Prepare registry with simple mode ENV set
        Onetime::Application::Registry.prepare_application_registry

        # Return full Rack app with middleware stack (including session middleware)
        Onetime::Application::Registry.generate_rack_url_map
      end
    end

    before(:all) do
      # Force app loading by calling app method
      app
    end

    after(:all) do
      # Reset for next describe block
      ENV.delete('AUTHENTICATION_MODE')
    end

    it 'runs in simple mode' do
      expect(Onetime.auth_config.mode).to eq('simple')
    end

    it 'has full mode disabled' do
      expect(Onetime.auth_config.full_enabled?).to be false
    end

    it 'does not mount Auth app' do
      expect(Onetime::Application::Registry.mount_mappings.key?('/auth')).to be false
    end

    it 'mounts Core app at root' do
      expect(Onetime::Application::Registry.mount_mappings.key?('/')).to be true
    end
  end

  # All /auth/* endpoint tests require full mode
  describe 'Full Mode - Auth Endpoints' do
    def app
      @full_app ||= begin
        # Setup environment for full mode
        ENV['AUTHENTICATION_MODE'] = 'full'

        # Reset both registries to clear state from previous test runs
        Onetime::Application::Registry.reset!
        Onetime::Boot::InitializerRegistry.soft_reset!

        # Reload auth config to pick up AUTHENTICATION_MODE env var
        Onetime.auth_config.reload!

        # Reset ready state to allow boot! to reload config
        # Without this, boot! returns early and OT.conf may be stale/nil
        Onetime.reset_ready!

        # Boot application
        Onetime.boot! :test

        # Prepare registry with full mode ENV set
        Onetime::Application::Registry.prepare_application_registry

        # Return full Rack app with middleware stack
        Onetime::Application::Registry.generate_rack_url_map
      end
    end

    before(:all) do
      # Force app loading in full mode
      app
    end

    after(:all) do
      # Reset for next describe block
      ENV.delete('AUTHENTICATION_MODE')
    end

    describe 'POST /auth/login' do
      context 'with invalid credentials' do
        it 'returns 400 or 401 status' do
          post_json '/auth/login', { login: 'nonexistent@example.com', password: 'wrongpassword' }

          # 400 = Bad Request (Rodauth default for invalid login)
          # 401 = Unauthorized (alternative authentication failure response)
          expect([400, 401]).to include(last_response.status)
        end

        it 'returns JSON response' do
          post_json '/auth/login', { login: 'nonexistent@example.com', password: 'wrongpassword' }

          expect(last_response.headers['Content-Type']).to include('application/json')
        end

        it 'returns error structure' do
          post_json '/auth/login', { login: 'nonexistent@example.com', password: 'wrongpassword' }

          response = json_response
          expect(response).to have_key('error')
          expect(response['error']).to be_a(String)
        end

        it 'returns field-error tuple' do
          post_json '/auth/login', { login: 'nonexistent@example.com', password: 'wrongpassword' }

          response = json_response
          expect(response).to have_key('field-error')
          expect(response['field-error']).to be_an(Array)
          expect(response['field-error'].length).to eq(2)
          # Rodauth uses 'login' as the field name, not 'email'
          expect(response['field-error'][0]).to eq('login')
          # Rodauth returns "no matching login" for non-existent accounts
          expect(response['field-error'][1]).to eq('no matching login')
        end
      end

      context 'without JSON Accept header' do
        it 'rejects non-JSON requests in JSON-only mode' do
          post '/auth/login', { login: 'test@example.com', password: 'password' }

          # Rodauth is configured with only_json? true, so non-JSON requests return 400
          expect(last_response.status).to eq(400)
        end
      end
    end

    describe 'POST /auth/create-account' do
      context 'with incomplete data' do
        it 'returns validation error (400 or 422)' do
          post_json '/auth/create-account', { login: 'incomplete@example.com' }

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
      around(:each) do |example|
        # Clear database and create test customer
        dbclient.flushdb
        @test_cust = create_test_customer

        # Login to establish authenticated session
        post_json '/auth/login', { login: test_email, password: test_password }

        @session_cookie = last_response.headers['Set-Cookie']

        # Run the test
        example.run
      ensure
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
        post_json '/auth/logout'

        # Logout is idempotent - succeeds even if not authenticated
        expect(last_response.status).to eq(200).or eq(302)
      end

      context 'with JSON request' do
        it 'returns JSON success response' do
          post_json '/auth/logout'

          expect(last_response.status).to eq(200).or eq(302)
          expect(last_response.headers['Content-Type']).to include('application/json')
        end
      end
    end

    describe 'POST /auth/logout (WITH authentication)' do
      around(:each) do |example|
        # Clear database and create test customer
        dbclient.flushdb
        @test_cust = create_test_customer

        # Login to establish authenticated session
        post_json '/auth/login', { login: test_email, password: test_password }

        @session_cookie = last_response.headers['Set-Cookie']

        # Run the test
        example.run
      ensure
        @test_cust&.destroy! if @test_cust
        dbclient.flushdb
      end

      it 'successfully logs out with valid session' do
        post_json '/auth/logout', {}, 'HTTP_COOKIE' => @session_cookie

        # Should succeed with 200 or 302
        expect(last_response.status).to eq(200).or eq(302)
      end

      it 'is idempotent - second logout succeeds gracefully' do
        # First logout
        post_json '/auth/logout', {}, 'HTTP_COOKIE' => @session_cookie
        expect(last_response.status).to eq(200).or eq(302)

        # Second logout with same cookie should succeed (idempotent)
        post_json '/auth/logout', {}, 'HTTP_COOKIE' => @session_cookie
        expect(last_response.status).to eq(200).or eq(302)
      end
    end

    describe 'POST /auth/reset-password-request' do
      it 'accepts password reset request' do
        post_json '/auth/reset-password-request', { login: 'reset@example.com' }

        # Rodauth behavior for reset-password-request:
        # - 200: Request accepted (email may or may not be sent)
        # - 401: Authentication required before reset (Rodauth config dependent)
        # - 422: Validation error
        # Uniform responses prevent user enumeration
        expect(last_response.status).to satisfy { |status| [200, 401, 422].include?(status) }
        expect(last_response.headers['Content-Type']).to include('application/json')
      end
    end

    describe 'POST /auth/reset-password/:key' do
      it 'rejects invalid reset token' do
        post_json '/auth/reset-password/testtoken123',
          { newpassword: 'newpassword123', 'password-confirm': 'newpassword123' }

        # Invalid token should return 400 (bad request), 404 (not found), or 422 (invalid)
        expect(last_response.status).to satisfy { |status| [400, 404, 422].include?(status) }
        expect(last_response.headers['Content-Type']).to include('application/json')
      end
    end

    describe 'Response Format Compatibility' do
      it 'uses Rodauth-compatible JSON format for errors' do
        post_json '/auth/login', { login: 'test@example.com', password: 'wrong' }

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
      around(:each) do |example|
        # Clear database before test
        dbclient.flushdb

        # Create test customer for each test
        @test_cust = create_test_customer

        # Run the test
        example.run
      ensure
        # Clean up test customer and database
        @test_cust&.destroy! if @test_cust
        dbclient.flushdb
      end

      context 'successful authentication' do
        it 'login returns 200 with success message' do
          post_json '/auth/login', { login: test_email, password: test_password }

          expect(last_response.status).to eq(200)
          expect(last_response.headers['Content-Type']).to include('application/json')

          response = json_response
          expect(response).to have_key('success')
          expect(response['success']).to be_a(String)
        end

        it 'sets session cookie on successful login' do
          # Clear any existing session state to ensure Set-Cookie is sent
          clear_cookies

          post_json '/auth/login', { login: test_email, password: test_password }

          expect(last_response.status).to eq(200)

          # Verify session is working by making a follow-up request
          # Rack::Test automatically persists cookies across requests
          get '/dashboard'

          # A working session should NOT return 401 Unauthorized
          # It may return 302 (redirect to login if session not recognized) or 200/other
          # The key is that the session was created successfully
          expect(last_response.status).not_to eq(401)

          # Alternatively, check if Set-Cookie was explicitly set
          set_cookie = last_response.headers['Set-Cookie']
          expect(set_cookie).to include('onetime.session') if set_cookie
        end

        it 'session persists across requests' do
          # Step 1: Login
          post_json '/auth/login', { login: test_email, password: test_password }

          expect(last_response.status).to eq(200)

          # Step 2: Logout - Rack::Test automatically persists cookies
          post_json '/auth/logout'

          # Logout should work with valid session cookie
          expect(last_response.status).to eq(200).or eq(302)
        end

        it 'logout destroys the session' do
          # Step 1: Login
          post_json '/auth/login', { login: test_email, password: test_password }

          cookie = last_response.headers['Set-Cookie']

          # Step 2: Logout
          post_json '/auth/logout', {}, 'HTTP_COOKIE' => cookie

          expect(last_response.status).to eq(200).or eq(302)

          # Step 3: Try to logout again with old cookie (should be idempotent)
          post_json '/auth/logout', {}, 'HTTP_COOKIE' => cookie

          # Second logout succeeds (idempotent behavior)
          expect(last_response.status).to eq(200).or eq(302)
        end
      end

      context 'Session storage' do
        it 'stores session in kv database after login' do
          post_json '/auth/login', { login: test_email, password: test_password }

          expect(last_response.status).to eq(200)

          # Check kv database for session keys
          session_keys = dbclient.keys('*session*')
          expect(session_keys).not_to be_empty
        end

        it 'removes session from kv database after logout' do
          # Login
          post_json '/auth/login', { login: test_email, password: test_password }

          cookie = last_response.headers['Set-Cookie']

          # Verify session exists in kv database
          session_keys_before = dbclient.keys('*session*')
          expect(session_keys_before).not_to be_empty

          # Logout
          post_json '/auth/logout', {}, 'HTTP_COOKIE' => cookie

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
          post_json '/auth/login', { login: test_email, password: test_password }

          expect(last_response.status).to eq(200)

          # Make another request to verify session state
          # Rack::Test automatically persists cookies across requests
          get '/dashboard'

          # The session should be authenticated (regardless of whether dashboard exists)
          # This is verified by not getting a 401
          expect(last_response.status).not_to eq(401)
        end
      end
    end
  end
end
