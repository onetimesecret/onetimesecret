# apps/web/auth/spec/integration/full/unlock_account_request_enumeration_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — unlock-account-request enumeration safety
#            (audit 2026-08-02 L-6)
# =============================================================================
#
# The lockout feature is enabled (config/features/lockout.rb, default on), so
# in full mode POST /auth/unlock-account-request is reachable. Stock Rodauth
# answers 200 "email sent" for a LOCKED account and 401 "No matching login"
# for a non-existent OR not-locked account — disclosing account existence and
# lock state. The override in config/overrides/account_enumeration.rb
# collapses every branch (missing account, not locked, recently-sent
# throttle) to the same generic success, while only the genuinely-locked
# path sends an unlock email.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec \
#     apps/web/auth/spec/integration/full/unlock_account_request_enumeration_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require 'rack/test'

RSpec.describe 'Unlock-account-request enumeration safety (audit 2026-08-02 L-6)', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    boot_onetime_app
  end

  before do
    unless defined?(Auth::Database) && Auth::Database.connection
      skip 'Auth database not configured (run with AUTH_DATABASE_URL set)'
    end

    # Spy on delivery: the locked-account happy path must still send exactly
    # one unlock email; every enumeration-safe branch must send none.
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw).and_return(true)
  end

  # Seed a verified account (+ Customer + password hash) via AccountSeedHelper.
  def create_account(email:)
    seed_account_with_password(email)
  end

  # Mark an account locked out, as Rodauth's invalid_login_attempted does after
  # max_invalid_logins failures (account_lockouts row with key + deadline).
  def lock_account(account_id, email_last_sent: nil)
    row = {
      id: account_id,
      key: SecureRandom.hex(16),
      deadline: Time.now + (24 * 60 * 60),
    }
    row[:email_last_sent] = email_last_sent if email_last_sent
    Auth::Database.connection[:account_lockouts].insert(row)
  end

  # Fresh session + CSRF token, then POST a JSON unlock-account-request.
  def request_unlock(login)
    clear_cookies

    header 'Content-Type', nil
    header 'Content-Length', nil
    header 'Accept', 'application/json'
    get '/auth'
    token = last_response.headers['X-CSRF-Token']

    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', token if token
    post '/auth/unlock-account-request', JSON.generate(login: login, shrimp: token)
    last_response
  end

  def probe(login)
    response = request_unlock(login)
    [response.status, JSON.parse(response.body)]
  end

  describe 'non-existent login' do
    it 'returns the generic success rather than "No matching login"' do
      status, body = probe(unique_test_email('l6-nobody'))

      expect(status).to eq(200)
      expect(body).not_to have_key('field-error')
      expect(body['error']).to be_nil
      expect(body['success']).to match(/email has been sent/i)
      expect(Onetime::Jobs::Publisher).not_to have_received(:enqueue_email_raw)
    end
  end

  describe 'locked vs not-locked vs non-existent' do
    it 'returns an identical response for all three' do
      locked   = unique_test_email('l6-locked')
      unlocked = unique_test_email('l6-unlocked')
      lock_account(create_account(email: locked))
      create_account(email: unlocked)

      locked_status,   locked_body   = probe(locked)
      unlocked_status, unlocked_body = probe(unlocked)
      missing_status,  missing_body  = probe(unique_test_email('l6-missing'))

      expect(locked_status).to eq(200)
      expect(unlocked_status).to eq(locked_status)
      expect(missing_status).to eq(locked_status)
      expect(unlocked_body).to eq(locked_body)
      expect(missing_body).to eq(locked_body)
    end

    it 'still sends the unlock email only for the genuinely locked account' do
      locked   = unique_test_email('l6-mail')
      unlocked = unique_test_email('l6-nomail')
      lock_account(create_account(email: locked))
      create_account(email: unlocked)

      probe(unlocked)
      probe(unique_test_email('l6-mail-missing'))
      expect(Onetime::Jobs::Publisher).not_to have_received(:enqueue_email_raw)

      probe(locked)
      expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email_raw)
        .with(hash_including(to: contain_exactly(locked)), any_args).once
    end
  end

  describe 'recently-sent throttle' do
    it 'stays enumeration-safe without resending (throttle preserved)' do
      throttled = unique_test_email('l6-throttled')
      lock_account(create_account(email: throttled), email_last_sent: Time.now)

      throttled_status, throttled_body = probe(throttled)
      missing_status,   missing_body   = probe(unique_test_email('l6-throttle-missing'))

      # Same generic success as a non-existent login...
      expect(throttled_status).to eq(missing_status)
      expect(throttled_body).to eq(missing_body)
      expect(throttled_body['success']).to match(/email has been sent/i)
      # ...and no additional unlock email was dispatched.
      expect(Onetime::Jobs::Publisher).not_to have_received(:enqueue_email_raw)
    end
  end
end
