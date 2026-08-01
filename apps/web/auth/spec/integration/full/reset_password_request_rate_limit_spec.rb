# apps/web/auth/spec/integration/full/reset_password_request_rate_limit_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — reset-password-request rate limiting (issue #3872)
# =============================================================================
#
# In `full` auth mode the Rodauth app handles POST /auth/reset-password-request.
# The enumeration override (#3857) made every response identical, accepting a
# statistical timing residual; exploiting that residual needs many samples per
# target. The before_reset_password_request_route hook (config/hooks/
# reset_password_request.rb) enforces Onetime::Security::ResetRequestRateLimiter
# BEFORE the route body runs: a tight per-client-IP tier plus a higher
# per-submitted-login backstop, both keyed only on request-observable inputs.
#
# These tests assert: under-cap requests still get the generic success, an
# over-cap source gets the ADR-013 429 regardless of which login it probes, an
# IP-rotation-resistant per-login backstop exists (case-insensitively), and the
# 429 itself is enumeration-safe (identical for existing vs non-existent
# targets).
#
# The suite-wide test config ships the limiter DISABLED
# (spec/config.test.yaml) so other full-mode specs are not throttled; each
# example here enables it in-process with small caps and restores the config
# after.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec \
#     apps/web/auth/spec/integration/full/reset_password_request_rate_limit_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require 'rack/test'
require 'argon2'

RSpec.describe 'Reset-password-request rate limiting (issue #3872)', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    # Boot the full app so the REAL Auth::Config (with the rate-limit hook wired
    # in via config/hooks/reset_password_request.rb) is loaded and mounted at
    # /auth.
    boot_onetime_app
  end

  before do
    unless defined?(Auth::Database) && Auth::Database.connection
      skip 'Auth database not configured (run with AUTH_DATABASE_URL set)'
    end

    # Isolate from real email delivery (see the enumeration spec for rationale).
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw).and_return(true)

    @saved_conf = YAML.load(YAML.dump(OT.conf))
    clear_reset_request_keys
  end

  after do
    OT.send(:conf=, @saved_conf) if @saved_conf
    clear_reset_request_keys
  end

  let(:rl_redis) { Onetime::Customer.dbclient }

  # Clear every limiter key so each example starts from a clean slate. The
  # per-IP subject is the privacy-MASKED address Otto's IPPrivacyMiddleware
  # resolves (NOT the Rack::Test REMOTE_ADDR), so keys are matched by prefix
  # rather than assumed.
  def clear_reset_request_keys
    stale = rl_redis.keys('reset_request:attempts:*') +
            rl_redis.keys('reset_request:locked:*')
    rl_redis.del(*stale) unless stale.empty?
  end

  # Enable the limiter in-process with example-specific caps (the suite config
  # ships it disabled). Restored from @saved_conf in the after hook.
  def enable_limiter(max_per_ip:, max_per_email:)
    new_conf = YAML.load(YAML.dump(OT.conf))
    new_conf['site'] ||= {}
    new_conf['site']['authentication'] ||= {}
    new_conf['site']['authentication']['reset_request_rate_limit'] = {
      'enabled' => true,
      'max_per_ip' => max_per_ip,
      'max_per_email' => max_per_email,
      'window' => 900,
      'lockout' => 900,
    }
    OT.send(:conf=, new_conf)
  end

  # CSRF-correct JSON POST to the Rodauth endpoint; mirrors the helper in
  # reset_password_request_enumeration_spec.rb.
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

    hasher = Argon2::Password.new(t_cost: 1, m_cost: 5, p_cost: 1)
    db[:account_password_hashes].insert(id: account_id, password_hash: hasher.create(password))

    { id: account_id, email: email, external_id: extid }
  end

  describe 'per-IP tier' do
    it 'caps request volume from one source across DIFFERENT logins (the enumeration sampling pattern)' do
      enable_limiter(max_per_ip: 2, max_per_email: 100)

      # Under the cap: each probe of a fresh target still gets the generic
      # enumeration-safe success.
      2.times do |i|
        response = request_password_reset(unique_test_email("sample-#{i}"))
        expect(response.status).to eq(200),
          "Under-cap request #{i + 1} should pass, got #{response.status}: #{response.body}"
        expect(JSON.parse(response.body)['success']).to match(/email has been sent/i)
      end

      # The cap-hitting request locked the per-IP tier (attempts key cleared,
      # lockout flag set) — proving the IP tier, not the per-login backstop,
      # is what engaged (every probe used a distinct login).
      expect(rl_redis.keys('reset_request:locked:ip:*').size).to eq(1)

      # Over the cap: a THIRD distinct login from the same source is refused
      # with the ADR-013 429 before the route (and its account lookup) runs.
      response = request_password_reset(unique_test_email('sample-2'))
      expect(response.status).to eq(429),
        "Over-cap request must be throttled, got #{response.status}: #{response.body}"
      body = JSON.parse(response.body)
      expect(body['error_type']).to eq('LimitExceeded')
      expect(body['retry_after']).to be_a(Integer)
      expect(body['max_attempts']).to eq(2)

      # Security audit 2026-07-30, finding #2, residual 2: the delay must also
      # reach the HTTP header proxies and clients actually read (RFC 9110
      # §10.2.3). Set by Onetime::Middleware::RetryAfterHeader from the value
      # the Roda error handler stashes via ErrorCorrelation — the same
      # mechanism the simple-mode Otto stack uses, so the two modes cannot
      # drift (spec/integration/simple/reset_password_request_rate_limit_spec.rb).
      expect(response.headers['retry-after']).to eq(body['retry_after'].to_s)
    end
  end

  describe 'per-login backstop' do
    it 'caps repeated probes of ONE target case-insensitively, independent of the IP tier' do
      enable_limiter(max_per_ip: 100, max_per_email: 2)
      target = unique_test_email('backstop')

      2.times do |i|
        response = request_password_reset(target)
        expect(response.status).to eq(200),
          "Under-cap request #{i + 1} should pass, got #{response.status}: #{response.body}"
      end

      expect(rl_redis.keys('reset_request:locked:email:*').size).to eq(1)

      # A case-variant of the same target shares the bucket (normalization),
      # so the third probe is refused even though the per-IP cap is far away.
      response = request_password_reset(target.upcase)
      expect(response.status).to eq(429),
        "Over-cap request must be throttled, got #{response.status}: #{response.body}"
      expect(JSON.parse(response.body)['error_type']).to eq('LimitExceeded')
    end
  end

  describe 'enumeration safety of the 429' do
    it 'throttles an existing and a non-existent login identically' do
      enable_limiter(max_per_ip: 100, max_per_email: 1)

      existing = unique_test_email('exists')
      missing  = unique_test_email('missing')
      create_account(email: existing)

      # First request per target is allowed (and locks each per-login bucket).
      expect(request_password_reset(existing).status).to eq(200)
      expect(request_password_reset(missing).status).to eq(200)

      throttled_existing = request_password_reset(existing)
      throttled_missing  = request_password_reset(missing)

      expect(throttled_existing.status).to eq(429)
      expect(throttled_missing.status).to eq(429)

      # The throttle discloses nothing about account existence: same error
      # content either way. (request_id varies per request, so compare the
      # discriminating fields, not the whole body.)
      existing_body = JSON.parse(throttled_existing.body)
      missing_body  = JSON.parse(throttled_missing.body)
      %w[error error_type max_attempts].each do |field|
        expect(existing_body[field]).to eq(missing_body[field])
      end
    end
  end

  describe 'suite default (limiter disabled by test config)' do
    it 'does not throttle when site.authentication.reset_request_rate_limit is disabled' do
      # No enable_limiter call: this runs under spec/config.test.yaml, which
      # ships enabled:false — repeated probes stay on the generic success and
      # write no limiter keys.
      3.times do
        expect(request_password_reset(unique_test_email('off')).status).to eq(200)
      end
      expect(rl_redis.keys('reset_request:attempts:*')).to be_empty
      expect(rl_redis.keys('reset_request:locked:*')).to be_empty
    end
  end
end
