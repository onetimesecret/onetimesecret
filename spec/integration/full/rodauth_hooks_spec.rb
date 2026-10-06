# spec/integration/full/rodauth_hooks_spec.rb
#
# frozen_string_literal: true

require_relative '../integration_spec_helper'
require 'rack/test'

# Requires full authentication mode - Rodauth/Auth::Database only available in full mode
RSpec.describe 'Rodauth Security Hooks', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    # Set full mode before loading the application
    ENV['AUTHENTICATION_MODE'] = 'full'

    # Reset both registries to clear state from previous test runs
    Onetime::Application::Registry.reset!

    # Reload auth config to pick up AUTHENTICATION_MODE env var
    Onetime.auth_config.reload!

    # Boot application (Redis mocking is handled globally by integration_spec_helper.rb)
    Onetime.boot! :test

    # Prepare the application registry
    Onetime::Application::Registry.prepare_application_registry
  end

  after(:all) do
    ENV.delete('AUTHENTICATION_MODE')
  end

  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  # Establish session and get CSRF token
  def ensure_csrf_token
    return @csrf_token if defined?(@csrf_token) && @csrf_token

    # Rack::Test keeps the Content-Type a previous json_post set; a GET with a
    # JSON content type and no body trips the request parser.
    header 'Content-Type', nil
    header 'Accept', 'application/json'
    get '/auth'
    @csrf_token = last_response.headers['X-CSRF-Token']
    @csrf_token
  end

  # Forget the cached CSRF token so the next request fetches the session's
  # current one (auth requests can rotate it).
  def reset_csrf_token
    @csrf_token = nil
  end

  # Helper method to send JSON requests to Rodauth endpoints with CSRF token
  def json_post(path, params)
    csrf_token = ensure_csrf_token

    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', csrf_token if csrf_token
    post path, JSON.generate(params.merge(shrimp: csrf_token))
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

  # Messages the audit_logging feature wrote for an account
  # (apps/web/auth/config/features/audit_logging.rb registers the text per event)
  def audit_messages(account_id)
    auth_db[:account_authentication_audit_logs].where(account_id: account_id).map(:message)
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

        expect(last_response.status).to eq(200), last_response.body
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
    # Rodauth's lockout feature (apps/web/auth/config/features/lockout.rb,
    # max_invalid_logins 5) and the app's hooks of the same names compose:
    # Rodauth chains hook methods through `super`, so one failed attempt both
    # increments account_login_failures and runs the app's after_login_failure
    # block, and a locked account is refused in before_login_attempt before
    # the password is checked.
    #
    # The account is written straight into the auth database so the attempts
    # run in an anonymous session; creating it over HTTP would leave the
    # Rack::Test session signed in. Every attempt fetches a fresh CSRF token.
    let(:lockout_test_email) { "lockout-test-#{SecureRandom.hex(8)}@example.com" }
    let(:lockout_test_password) { 'SecureP@ss123!' }
    let(:max_invalid_logins) { 5 }
    let!(:account_id) do
      create_verified_account(db: auth_db, email: lockout_test_email, password: lockout_test_password)[:id]
    end

    def attempt_login(password)
      reset_csrf_token
      json_post '/auth/login', { login: lockout_test_email, password: password }
    end

    # Wrong-password attempts, each answered as a bad password rather than a
    # lockout refusal.
    def fail_login(times)
      times.times do
        attempt_login('wrong-password')
        expect(last_response.status).to eq(401), last_response.body
      end
    end

    context 'lockout tracking (Rodauth SQL-based)' do
      it 'allows initial login attempts for existing account' do
        fail_login(max_invalid_logins - 1)

        expect(login_failure_count(account_id)).to eq(max_invalid_logins - 1)
        expect(account_locked?(account_id)).to be(false)

        # One short of the limit, the right password still signs in.
        attempt_login(lockout_test_password)
        expect(last_response.status).to eq(200), last_response.body
      end

      it 'locks account after max_invalid_logins (5) failed attempts' do
        fail_login(max_invalid_logins)

        # The attempt that reaches the limit is still answered as a bad
        # password (asserted above). Rodauth writes the lockout row as its
        # side effect and the app's audit registration records it once.
        lockout = auth_db[:account_lockouts].where(id: account_id).first
        expect(lockout).not_to be_nil
        expect(lockout[:key]).not_to be_nil
        expect(lockout[:deadline]).not_to be_nil
        expect(audit_messages(account_id).count('Account locked due to failed login attempts')).to eq(1)

        # Locked: the correct password is refused before it is checked, the
        # refusal is not counted as another failure, and no session results.
        attempt_login(lockout_test_password)
        expect(last_response.status).to eq(403), last_response.body
        expect(JSON.parse(last_response.body)['error']).to match(/locked/i)
        expect(login_failure_count(account_id)).to eq(max_invalid_logins)

        header 'Content-Type', nil
        get '/auth/account'
        expect(last_response.status).to eq(401)
      end

      it 'tracks login failures in SQL database' do
        allow(Auth::Logging).to receive(:log_auth_event).and_call_original

        expect(auth_db[:account_login_failures].where(id: account_id).count).to eq(0)

        fail_login(1)
        expect(login_failure_count(account_id)).to eq(1)

        fail_login(2)
        expect(login_failure_count(account_id)).to eq(3)
        expect(account_locked?(account_id)).to be(false)

        # The same chained hook ran the app's after_login_failure block (its
        # :login_failure log event) and the audit_logging per-failure row.
        expect(Auth::Logging).to have_received(:log_auth_event).with(:login_failure, any_args).exactly(3).times
        expect(audit_messages(account_id).count('Login failed - invalid credentials')).to eq(3)
      end
    end

    context 'successful login clears lockout data' do
      it 'resets failure counter on successful login' do
        fail_login(3)
        expect(login_failure_count(account_id)).to eq(3)

        attempt_login(lockout_test_password)
        expect(last_response.status).to eq(200), last_response.body

        expect(auth_db[:account_login_failures].where(id: account_id).count).to eq(0)
        expect(account_locked?(account_id)).to be(false)

        # The count starts over: the earlier failures no longer bring the
        # account closer to lockout.
        clear_cookies
        fail_login(1)
        expect(login_failure_count(account_id)).to eq(1)
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
