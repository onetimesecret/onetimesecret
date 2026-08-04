# apps/web/auth/spec/integration/full/create_account_enumeration_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — create-account enumeration safety (audit 2026-08-02 M-2)
# =============================================================================
#
# Stock Rodauth answers a duplicate-email signup with "already an account with
# this login" (or, unverified, a 403 "awaiting verification") — an explicit
# registration-state oracle. The fix (config/overrides/account_enumeration.rb
# + the before_create_account duplicate branches in config/hooks/account.rb)
# answers a duplicate with EXACTLY the response a fresh signup gets, writing
# no account row.
#
# NOTE on coverage limits in this lane: verify_account is disabled when
# RACK_ENV=test (Onetime.auth_config.verify_account_enabled?), so two
# production behaviors are dormant here and guarded by respond_to? in the
# override: (a) the unverified-duplicate verification-email RESEND, and
# (b) verify_account's stock new_account short-circuit that the override
# bypasses. The response-parity property asserted below is identical in both
# configs because both paths converge on create_account_response.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec \
#     apps/web/auth/spec/integration/full/create_account_enumeration_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require 'rack/test'

RSpec.describe 'Create-account enumeration safety (audit 2026-08-02 M-2)', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    boot_onetime_app
  end

  before do
    unless defined?(Auth::Database) && Auth::Database.connection
      skip 'Auth database not configured (run with AUTH_DATABASE_URL set)'
    end

    # Isolate from real email delivery (welcome/verification mails).
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(true)
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw).and_return(true)
  end

  # Signup emails must pass Truemail + SignupValidation, so use the
  # @example.com convention proven by rodauth_hooks_spec (NOT
  # unique_test_email's non-signup domain).
  def signup_email(prefix)
    "#{prefix}-#{SecureRandom.hex(8)}@example.com"
  end

  # Fresh session + CSRF token, then POST a JSON create-account.
  def attempt_signup(login, password)
    clear_cookies

    header 'Content-Type', nil
    header 'Content-Length', nil
    header 'Accept', 'application/json'
    get '/auth'
    token = last_response.headers['X-CSRF-Token']

    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', token if token
    post '/auth/create-account', JSON.generate(
      login: login,
      'login-confirm': login,
      password: password,
      'password-confirm': password,
      shrimp: token
    )
    last_response
  end

  def probe(login, password: 'SecureP@ss123')
    response = attempt_signup(login, password)
    [response.status, JSON.parse(response.body)]
  end

  def accounts_count(email)
    Auth::Database.connection[:accounts].where(email: email).count
  end

  describe 'duplicate email vs fresh signup' do
    it 'returns an identical success response and writes no second account' do
      email = signup_email('m2-dup')

      fresh_status, fresh_body = probe(email)
      expect(fresh_status).to eq(200)
      expect(fresh_body['success']).to be_a(String)
      expect(accounts_count(email)).to eq(1)

      dup_status, dup_body = probe(email)

      # The duplicate answer is byte-identical to the fresh-signup answer:
      # same 200, same success message, no error/field-error keys.
      expect(dup_status).to eq(fresh_status)
      expect(dup_body).to eq(fresh_body)
      expect(dup_body).not_to have_key('error')
      expect(dup_body).not_to have_key('field-error')

      # ...and the duplicate attempt did not create or clobber anything.
      expect(accounts_count(email)).to eq(1)
    end

    it 'matches the response of a fresh signup for a DIFFERENT email too' do
      taken = signup_email('m2-taken')
      probe(taken) # register it

      dup_status,   dup_body   = probe(taken)
      other_status, other_body = probe(signup_email('m2-other'))

      expect(dup_status).to eq(other_status)
      expect(dup_body).to eq(other_body)
    end
  end

  describe 'validation parity (no early duplicate short-circuit)' do
    it 'rejects a weak password identically for duplicate and fresh emails' do
      taken = signup_email('m2-weakpw')
      probe(taken) # register it

      dup_status,   dup_body   = probe(taken, password: 'short')
      fresh_status, fresh_body = probe(signup_email('m2-weakpw-fresh'), password: 'short')

      # Password validation runs BEFORE the duplicate check for both, so a
      # probe with an invalid password learns nothing about registration
      # state either.
      expect(dup_status).to eq(fresh_status)
      expect(dup_body).to eq(fresh_body)
      expect(dup_body['field-error']&.first).to eq('password')
    end
  end

  describe 'Redis-only duplicate (customer record without auth account)' do
    it 'returns the same generic success and writes no account row' do
      redis_only = signup_email('m2-redis')
      fresh      = signup_email('m2-redis-fresh')

      allow(Onetime::Customer).to receive(:email_exists?).and_call_original
      allow(Onetime::Customer).to receive(:email_exists?).with(redis_only).and_return(true)

      fresh_status, fresh_body = probe(fresh)
      dup_status,   dup_body   = probe(redis_only)

      expect(dup_status).to eq(fresh_status)
      expect(dup_body).to eq(fresh_body)
      expect(accounts_count(redis_only)).to eq(0)
    end
  end
end
