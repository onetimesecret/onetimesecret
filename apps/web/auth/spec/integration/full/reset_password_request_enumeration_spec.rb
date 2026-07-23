# apps/web/auth/spec/integration/full/reset_password_request_enumeration_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — reset-password-request enumeration safety (issue #3857)
# =============================================================================
#
# In `full` auth mode the Rodauth app is mounted at /auth and handles
# POST /auth/reset-password-request. Stock Rodauth distinguishes "account
# exists" from "no account" on that path (no_matching_login / unverified /
# recently-sent), which is an account-existence oracle (CWE-204). The override
# in config/overrides/reset_password_enumeration.rb collapses all three branches
# to the same generic "email sent" response.
#
# These tests assert the exposed request path is enumeration-safe: an existing
# login and a non-existent login yield an identical HTTP response.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec \
#     apps/web/auth/spec/integration/full/reset_password_request_enumeration_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require 'rack/test'
require 'argon2'

RSpec.describe 'Reset-password-request enumeration safety (issue #3857)', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    # Boot the full app so the REAL Auth::Config (with the enumeration override
    # wired in via config/overrides/reset_password_enumeration.rb) is loaded and
    # mounted at /auth. See pending_plan_intent_flow_spec.rb for why we must not
    # reopen Auth::Config as a plain module here.
    boot_onetime_app
  end

  before do
    unless defined?(Auth::Database) && Auth::Database.connection
      skip 'Auth database not configured (run with AUTH_DATABASE_URL set)'
    end

    # Isolate from real email delivery. The enumeration property holds with or
    # without a real send; stubbing keeps the happy path deterministic (the
    # publisher would otherwise attempt a synchronous delivery). Kept as a spy so
    # the throttle example can assert a resend did NOT happen.
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw).and_return(true)
  end

  let(:created_account_ids) { [] }

  after do
    db = Auth::Database.connection
    created_account_ids.each do |account_id|
      # Delete child rows before the parent. On PostgreSQL the FK from
      # account_password_reset_keys / account_password_hashes -> accounts makes a
      # bare accounts delete raise; the rescue below would then swallow it and the
      # rows would leak. (On SQLite FKs are off by default so order is moot, but we
      # keep the correct order so cleanup is real on either backend.)
      db[:account_password_reset_keys].where(id: account_id).delete
      db[:account_password_hashes].where(id: account_id).delete
      db[:accounts].where(id: account_id).delete
    rescue StandardError
      # Non-fatal cleanup error
    end
  end

  def unique_test_email(prefix = 'reset-enum')
    "#{prefix}-#{SecureRandom.hex(8)}@integration-test.example.com"
  end

  # Creates an account with a password hash. status_id defaults to verified.
  def create_account(email:, status_id: AuthTestConstants::STATUS_VERIFIED, password: 'TestPassword123!')
    db    = Auth::Database.connection
    extid = SecureRandom.uuid
    account_id = db[:accounts].insert(
      email: email,
      status_id: status_id,
      external_id: extid,
      created_at: Time.now,
      updated_at: Time.now
    )
    created_account_ids << account_id

    # Cost params match test config in config/features/argon2.rb (argon2 is
    # required at the top of the file).
    hasher = Argon2::Password.new(t_cost: 1, m_cost: 5, p_cost: 1)
    db[:account_password_hashes].insert(id: account_id, password_hash: hasher.create(password))

    { id: account_id, email: email, external_id: extid }
  end

  # Establish a fresh session, fetch the CSRF token from GET /auth, then POST a
  # JSON reset-password-request to the Rodauth endpoint (mounted at /auth). The
  # full Rack app enforces CSRF, so the shrimp token is included (mirrors the
  # csrf_login helper in pending_plan_intent_flow_spec.rb). "shrimp" is this
  # app's name for the CSRF authenticity token (the Rack authenticity_param is
  # literally 'shrimp'; see lib/onetime/middleware/security.rb).
  #
  # @return [Rack::MockResponse] the last response
  def request_password_reset(login)
    clear_cookies

    header 'Content-Type', nil
    header 'Content-Length', nil
    header 'Accept', 'application/json'
    get '/auth'
    token = last_response.headers['X-CSRF-Token']

    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', token if token
    post '/auth/reset-password-request', JSON.generate(login: login, shrimp: token)
    last_response
  end

  # Capture (status, parsed-body) for a probe so two probes can be compared.
  def probe(login)
    response = request_password_reset(login)
    [response.status, JSON.parse(response.body)]
  end

  describe 'non-existent login' do
    it 'returns a generic success rather than a no_matching_login field error' do
      status, body = probe(unique_test_email('nobody'))

      # Pre-fix, Rodauth answered a non-existent login with an error tuple:
      #   { "field-error": ["login", "no matching login"], "error": "..." }
      # The override must instead answer with the same success a real request
      # gets, disclosing nothing about account existence.
      expect(body).not_to have_key('field-error')
      expect(body['error']).to be_nil
      expect(body['success']).to be_a(String)
      expect(body['success']).to match(/email has been sent/i)
      expect(status).to eq(200)
    end
  end

  describe 'existing (verified) vs non-existent login' do
    it 'returns an identical response for both' do
      existing = unique_test_email('exists')
      create_account(email: existing)

      existing_status, existing_body = probe(existing)
      missing_status,  missing_body  = probe(unique_test_email('missing'))

      expect(existing_status).to eq(missing_status)
      expect(existing_body).to eq(missing_body)
      # And it is the success shape, not a shared error shape.
      expect(existing_body).not_to have_key('field-error')
      expect(existing_body['success']).to match(/email has been sent/i)
    end
  end

  describe 'happy path (existing verified account)' do
    it 'still enqueues exactly one reset email for a valid, verified account' do
      verified = unique_test_email('happy')
      create_account(email: verified)

      status, body = probe(verified)

      # Closing the oracle must not suppress real functionality: a valid, open,
      # non-throttled account still gets its reset email. probe() touches only
      # this one account, so exactly one enqueue to this address is expected.
      expect(status).to eq(200)
      expect(body['success']).to match(/email has been sent/i)
      # enqueue_email_raw is called with a message hash (to:/subject:/body:/from:)
      # then delivery options; assert exactly one reset email addressed to the
      # verified account.
      expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email_raw)
        .with(hash_including(to: include(verified)), any_args).once
    end
  end

  describe 'existing but unverified vs non-existent login' do
    it 'does not distinguish the unverified account (no unverified_account oracle)' do
      unverified = unique_test_email('unverified')
      create_account(email: unverified, status_id: AuthTestConstants::STATUS_UNVERIFIED)

      unverified_status, unverified_body = probe(unverified)
      missing_status,    missing_body    = probe(unique_test_email('missing-unverified'))

      expect(unverified_status).to eq(missing_status)
      expect(unverified_body).to eq(missing_body)
      expect(unverified_body).not_to have_key('field-error')
    end
  end

  describe 'recently-sent throttle' do
    it 'stays enumeration-safe without resending (throttle preserved)' do
      verified = unique_test_email('recent')
      account  = create_account(email: verified)

      # Simulate a reset email that was just sent: a live key row whose
      # email_last_sent is within reset_password_skip_resend_email_within.
      Auth::Database.connection[:account_password_reset_keys].insert(
        id: account[:id],
        key: SecureRandom.hex(16),
        deadline: Time.now + (24 * 60 * 60),
        email_last_sent: Time.now
      )

      throttled_status, throttled_body = probe(verified)
      missing_status,   missing_body   = probe(unique_test_email('missing-recent'))

      # Same generic success as a non-existent login...
      expect(throttled_status).to eq(missing_status)
      expect(throttled_body).to eq(missing_body)
      expect(throttled_body).not_to have_key('field-error')
      # ...and the throttle held: no additional reset email was dispatched.
      expect(Onetime::Jobs::Publisher).not_to have_received(:enqueue_email_raw)
    end
  end
end
