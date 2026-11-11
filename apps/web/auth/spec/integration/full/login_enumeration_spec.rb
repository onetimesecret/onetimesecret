# apps/web/auth/spec/integration/full/login_enumeration_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — login-route enumeration safety (audit 2026-08-02 M-1)
# =============================================================================
#
# Stock Rodauth answers POST /auth/login with distinct error tuples for
# "no matching login" (unknown email) and "invalid password" (known email,
# wrong password) — a single-request account-existence oracle (CWE-204). The
# override in config/overrides/account_enumeration.rb collapses both branches
# to one generic message on one field, and equalizes timing by verifying the
# submitted password against a precomputed dummy Argon2 hash when no account
# exists.
#
# These tests pin the response contract (identical status + body for both
# failure modes) and the timing-pad mechanism (the dummy verification runs on
# the miss path). Wall-clock timing itself is NOT asserted — it is jitter-prone
# and the mechanism assertion is the reliable guard.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec \
#     apps/web/auth/spec/integration/full/login_enumeration_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require 'rack/test'
require 'argon2'

RSpec.describe 'Login enumeration safety (audit 2026-08-02 M-1)', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    # Boot the full app so the REAL Auth::Config (with the enumeration override
    # wired in via config/overrides/account_enumeration.rb) is loaded and
    # mounted at /auth.
    boot_onetime_app
  end

  before do
    unless defined?(Auth::Database) && Auth::Database.connection
      skip 'Auth database not configured (run with AUTH_DATABASE_URL set)'
    end

    # Isolate from real email delivery: the happy-path login enqueues a
    # new-login security alert (after_login hook). The enumeration property
    # under test never depends on delivery.
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(true)
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw).and_return(true)
  end

  # No per-example DB cleanup here on purpose — FullModeSuiteDatabase wipes the
  # Rodauth tables between examples for full-mode specs (see the note in
  # reset_password_request_enumeration_spec.rb).
  #
  # Accounts are seeded via AccountSeedHelper#seed_account_with_password
  # (accounts row + paired Customer + Argon2 hash at test cost params).
  def create_account(email:, password: 'TestPassword123!')
    seed_account_with_password(email, password: password)
  end

  # Fresh session + CSRF token, then POST a JSON login (mirrors the probe
  # helper in reset_password_request_enumeration_spec.rb).
  def attempt_login(login, password)
    clear_cookies

    header 'Content-Type', nil
    header 'Content-Length', nil
    header 'Accept', 'application/json'
    get '/auth'
    token = last_response.headers['X-CSRF-Token']

    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', token if token
    post '/auth/login', JSON.generate(login: login, password: password, shrimp: token)
    last_response
  end

  def probe(login, password)
    response = attempt_login(login, password)
    [response.status, JSON.parse(response.body)]
  end

  describe 'unknown email vs wrong password' do
    it 'returns an identical status and body for both failure modes' do
      existing = unique_test_email('m1-exists')
      create_account(email: existing, password: 'CorrectHorse1!')

      wrong_pw_status, wrong_pw_body = probe(existing, 'WrongPassword1!')
      missing_status,  missing_body  = probe(unique_test_email('m1-missing'), 'WrongPassword1!')

      expect(missing_status).to eq(wrong_pw_status)
      expect(missing_body).to eq(wrong_pw_body)
    end

    it 'uses the generic message on the password field (no "no matching login")' do
      status, body = probe(unique_test_email('m1-generic'), 'AnyPassword1!')

      # Pre-fix, Rodauth answered ["login", "no matching login"], which named
      # both a different field and a different message than the wrong-password
      # branch — either alone confirms the email is unregistered.
      expect(status).to eq(401)
      expect(body['field-error']).to eq(['password', 'Invalid email or password'])
      expect(body['error']).to be_a(String)
      expect(body['error']).not_to match(/no matching/i)
    end

    it 'keeps the wrong-password branch on the same generic contract' do
      existing = unique_test_email('m1-wrongpw')
      create_account(email: existing, password: 'CorrectHorse1!')

      status, body = probe(existing, 'WrongPassword1!')

      expect(status).to eq(401)
      expect(body['field-error']).to eq(['password', 'Invalid email or password'])
    end
  end

  describe 'generic-message scoping (non-login routes)' do
    # invalid_password_message is shared by authenticated password-confirmation
    # routes (close_account, change_password, 2FA setup). The M-1 generic
    # "Invalid email or password" applies ONLY to /auth/login: the SPA's
    # CloseAccount.vue renders the field error verbatim on a dialog with no
    # email field, so the stock Rodauth "invalid password" must survive there.
    it 'keeps the stock invalid-password message on the close-account route' do
      existing = unique_test_email('m1-close')
      create_account(email: existing, password: 'CorrectHorse1!')

      status, = probe(existing, 'CorrectHorse1!')
      expect(status).to eq(200)

      # Fresh CSRF token on the now-authenticated session, then a wrong-password
      # close-account attempt.
      header 'Content-Type', nil
      header 'Content-Length', nil
      header 'Accept', 'application/json'
      get '/auth'
      token = last_response.headers['X-CSRF-Token']

      header 'Content-Type', 'application/json'
      header 'X-CSRF-Token', token if token
      post '/auth/close-account', JSON.generate(password: 'WrongPassword1!', shrimp: token)

      expect(last_response.status).to eq(401)
      body = JSON.parse(last_response.body)
      expect(body['field-error']).to eq(['password', 'invalid password'])
      expect(last_response.body).not_to include('Invalid email or password')
    end
  end

  describe 'timing equalization (dummy Argon2 verification)' do
    it 'verifies the submitted password against the precomputed dummy hash when no account exists' do
      allow(::Argon2::Password).to receive(:verify_password).and_call_original

      probe(unique_test_email('m1-timing'), 'ProbePassword1!')

      # The miss path must do comparable Argon2 work to the wrong-password
      # path. The override calls password_hash_match? with the frozen dummy
      # hash built once at configure time — never Argon2::Password.create per
      # request (which would double the cost).
      expect(::Argon2::Password).to have_received(:verify_password)
        .with(anything, Auth::Config::Overrides::AccountEnumeration.dummy_password_hash, anything)
        .at_least(:once)
    end

    it 'does not run the dummy verification for an existing account' do
      existing = unique_test_email('m1-real')
      create_account(email: existing, password: 'CorrectHorse1!')

      allow(::Argon2::Password).to receive(:verify_password).and_call_original

      probe(existing, 'WrongPassword1!')

      expect(::Argon2::Password).not_to have_received(:verify_password)
        .with(anything, Auth::Config::Overrides::AccountEnumeration.dummy_password_hash, anything)
    end
  end

  describe 'happy path' do
    it 'still logs in with correct credentials' do
      existing = unique_test_email('m1-happy')
      create_account(email: existing, password: 'CorrectHorse1!')

      status, body = probe(existing, 'CorrectHorse1!')

      expect(status).to eq(200)
      expect(body['success']).to be_a(String)
      expect(body).not_to have_key('field-error')
    end
  end
end
