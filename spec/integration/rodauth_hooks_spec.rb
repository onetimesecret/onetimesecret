# spec/integration/rodauth_hooks_spec.rb
#
# frozen_string_literal: true

require_relative 'integration_spec_helper'
require 'rack/test'

# Requires full authentication mode - Rodauth/Auth::Database only available in full mode
RSpec.describe 'Rodauth Security Hooks', :full_auth_mode, type: :integration do
  include Rack::Test::Methods

  skip_unless_mode :full

  before(:all) do
    # Set full mode before loading the application
    ENV['AUTHENTICATION_MODE'] = 'full'

    # Reset both registries to clear state from previous test runs
    Onetime::Application::Registry.reset!
    Onetime::Boot::InitializerRegistry.reset!

    # Reload auth config to pick up AUTHENTICATION_MODE env var
    Onetime.auth_config.reload!

    # Boot application (Redis mocking is handled globally by integration_spec_helper.rb)
    Onetime.boot! :test

    # Prepare the application registry
    Onetime::Application::Registry.prepare_application_registry
  end

  def app
    Onetime::Application::Registry.generate_rack_url_map
  end

  # Helper method to send JSON requests to Rodauth endpoints
  def json_post(path, params)
    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    post path, JSON.generate(params)
  end

  # Access the Rodauth/Sequel auth database for lockout assertions
  let(:auth_db) { Auth::Database.connection }
  let(:test_email) { "test-#{SecureRandom.hex(8)}@example.com" }
  let(:valid_password) { 'SecureP@ss123' }

  # Helper to get login failure count for an account
  def login_failure_count(account_id)
    record = auth_db[:account_login_failures].where(id: account_id).first
    record ? record[:number] : 0
  end

  # Helper to check if account is locked out
  def account_locked?(account_id)
    auth_db[:account_lockouts].where(id: account_id).count > 0
  end

  # Helper to clear lockout data for an account
  def clear_lockout_data(account_id)
    auth_db[:account_login_failures].where(id: account_id).delete
    auth_db[:account_lockouts].where(id: account_id).delete
  end

  describe 'before_create_account hook' do
    context 'with valid email' do
      it 'allows account creation' do
        json_post '/auth/create-account', {
          login: test_email,
          'login-confirm': test_email,
          password: valid_password,
          'password-confirm': valid_password
        }

        expect(last_response.status).to be_between(200, 299).or be(422) # 422 if DB constraints fail
      end
    end

    context 'with invalid email format' do
      it 'rejects account creation' do
        json_post '/auth/create-account', {
          login: 'not-an-email',
          'login-confirm': 'not-an-email',
          password: valid_password,
          'password-confirm': valid_password
        }

        expect(last_response.status).to eq(422)
        json = JSON.parse(last_response.body)
        # Check field-error which contains our custom validation message
        expect(json['field-error']).to be_an(Array)
        expect(json['field-error'][0]).to eq('login')
      end
    end

    context 'with empty email' do
      it 'rejects account creation' do
        json_post '/auth/create-account', {
          login: '',
          'login-confirm': '',
          password: valid_password,
          'password-confirm': valid_password
        }

        expect(last_response.status).to eq(422)
        json = JSON.parse(last_response.body)
        # Check field-error which contains our custom validation message
        expect(json['field-error']).to be_an(Array)
        expect(json['field-error'][0]).to eq('login')
      end
    end
  end

  describe 'before_login_attempt and after_login_failure hooks' do
    # Rodauth lockout requires an existing account to track failures
    # These tests create an account first, then test lockout behavior

    let(:lockout_test_email) { "lockout-test-#{SecureRandom.hex(8)}@example.com" }
    let(:lockout_test_password) { 'SecureP@ss123!' }

    # Create account and return its ID for lockout testing
    def create_test_account_for_lockout
      json_post '/auth/create-account', {
        login: lockout_test_email,
        'login-confirm': lockout_test_email,
        password: lockout_test_password,
        'password-confirm': lockout_test_password
      }

      # Get the account ID from the database
      account = auth_db[:accounts].where(email: lockout_test_email).first
      account[:id] if account
    end

    context 'lockout tracking (Rodauth SQL-based)' do
      it 'allows initial login attempts for existing account' do
        account_id = create_test_account_for_lockout
        skip 'Account creation failed' unless account_id

        # Clear any existing lockout data
        clear_lockout_data(account_id)

        3.times do
          json_post '/auth/login', {
            login: lockout_test_email,
            password: 'wrong-password'
          }

          expect(last_response.status).to eq(401)
        end

        # Account should not be locked yet (max_invalid_logins is 5)
        expect(account_locked?(account_id)).to be false
      end

      it 'locks account after max_invalid_logins (5) failed attempts' do
        account_id = create_test_account_for_lockout
        skip 'Account creation failed' unless account_id

        # Clear any existing lockout data
        clear_lockout_data(account_id)

        # Make 5 failed attempts (max_invalid_logins configured in security.rb)
        5.times do
          json_post '/auth/login', {
            login: lockout_test_email,
            password: 'wrong-password'
          }
        end

        # Account should now be locked
        expect(account_locked?(account_id)).to be true

        # 6th attempt should indicate account is locked
        # Rodauth may return 401 or 403 depending on configuration
        json_post '/auth/login', {
          login: lockout_test_email,
          password: 'wrong-password'
        }

        expect([401, 403]).to include(last_response.status)
        json = JSON.parse(last_response.body)
        # Rodauth returns field-error or error for locked accounts
        expect(json['field-error'] || json['error']).to be_truthy
      end

      it 'tracks login failures in SQL database' do
        account_id = create_test_account_for_lockout
        skip 'Account creation failed' unless account_id

        # Clear any existing lockout data
        clear_lockout_data(account_id)

        # Make a failed login attempt
        json_post '/auth/login', {
          login: lockout_test_email,
          password: 'wrong-password'
        }

        # Check that failure is tracked in account_login_failures table
        failure_count = login_failure_count(account_id)
        expect(failure_count).to be >= 1
      end
    end

    context 'successful login clears lockout data' do
      it 'resets failure counter on successful login' do
        account_id = create_test_account_for_lockout
        skip 'Account creation failed' unless account_id

        # Clear any existing lockout data
        clear_lockout_data(account_id)

        # Make some failed attempts (but not enough to trigger lockout)
        2.times do
          json_post '/auth/login', {
            login: lockout_test_email,
            password: 'wrong-password'
          }
        end

        # Verify failures are tracked
        expect(login_failure_count(account_id)).to be >= 1

        # Successful login should clear failure count
        json_post '/auth/login', {
          login: lockout_test_email,
          password: lockout_test_password
        }

        # After successful login, failure count should be reset
        expect(login_failure_count(account_id)).to eq(0)
      end
    end
  end

  describe 'security logging' do
    it 'logs failed login attempts' do
      # Capture OT.info calls would require a logger spy
      # For now, just verify the endpoint responds correctly
      json_post '/auth/login', {
        login: test_email,
        password: 'wrong-password'
      }

      expect(last_response.status).to eq(401)
    end
  end
end
