# apps/web/auth/spec/integration/full_mfa/email_login_request_rate_limit_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — email-login-request rate limiting
#            (RISK-2026-08-14-M04; full mode + AUTH_EMAIL_AUTH_ENABLED=true)
# =============================================================================
#
# POST /auth/email-login-request had no limit per source: Rodauth's resend
# window caps emails per account, so one origin could mail links to address
# after address and sample the enumeration-safe route without bound. The
# before_email_auth_request_route hook (config/hooks/email_login_request.rb)
# enforces Onetime::Security::ResetRequestRateLimiter under its
# :email_login_request scope BEFORE the route body runs: a per-client-IP tier
# plus a per-submitted-login backstop, keyed only on request-observable inputs.
#
# These tests assert: under-cap requests still get the generic success, an
# over-cap source gets the ADR-013 429 whichever login it probes, the
# per-login backstop holds case-insensitively, the 429 is identical for an
# existing and a non-existent login, and the reset-request buckets are not
# charged. Sibling: integration/full/reset_password_request_rate_limit_spec.rb.
#
# The suite config ships the limiter DISABLED (spec/config.test.yaml); each
# example enables it in-process with small caps and restores the config after.
#
# WHY THIS LANE: see email_login_request_enumeration_spec.rb.
#
# RUN:
#   tests/lanes/run full-mfa \
#     --only apps/web/auth/spec/integration/full_mfa/email_login_request_rate_limit_spec.rb
# =============================================================================

# Load-time, before the suite's first boot (see magic_link_session_rotation_spec.rb).
ENV['AUTH_EMAIL_AUTH_ENABLED'] = 'true'

require_relative '../../spec_helper'

RSpec.describe 'Email-login-request rate limiting (RISK-2026-08-14-M04)',
  :aggregate_failures,
  :full_auth_mode,
  type: :integration do
  before(:all) do
    next if Auth::Config.method_defined?(:email_auth_route)

    raise 'Rodauth email_auth feature not loaded — this suite must boot with ' \
          'AUTH_EMAIL_AUTH_ENABLED=true in a fresh process (run via ' \
          '`tests/lanes/run full-mfa`; Auth::Config is one-shot)'
  end

  before do
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw).and_return(true)

    @saved_conf = YAML.load(YAML.dump(OT.conf))
    clear_limiter_keys
  end

  after do
    OT.send(:conf=, @saved_conf) if @saved_conf
    clear_limiter_keys
  end

  let(:rl_redis) { Onetime::Customer.dbclient }

  # The per-IP subject is the privacy-MASKED address Otto's IPPrivacyMiddleware
  # resolves, so keys are matched by prefix rather than assumed. Both scopes'
  # prefixes are cleared so the cross-scope example starts clean.
  def clear_limiter_keys
    stale = %w[email_login_request reset_request].flat_map do |prefix|
      rl_redis.keys("#{prefix}:attempts:*") + rl_redis.keys("#{prefix}:locked:*")
    end
    rl_redis.del(*stale) unless stale.empty?
  end

  # Enable the limiter in-process with example-specific caps.
  def enable_limiter(max_per_ip:, max_per_email:)
    new_conf = YAML.load(YAML.dump(OT.conf))

    new_conf.dig('site', 'authentication')['email_login_request_rate_limit'] = {
      'enabled' => true,
      'max_per_ip' => max_per_ip,
      'max_per_email' => max_per_email,
      'window' => 900,
      'lockout' => 900,
    }
    OT.send(:conf=, new_conf)
  end

  def request_login_link(login)
    clear_cookies
    csrf_json_post('/auth/email-login-request', login: login)
  end

  describe 'per-IP tier' do
    it 'caps request volume from one source across DIFFERENT logins' do
      enable_limiter(max_per_ip: 2, max_per_email: 100)

      2.times do |i|
        response = request_login_link(unique_test_email("sample-#{i}"))
        expect(response.status).to eq(200),
          "Under-cap request #{i + 1} should pass, got #{response.status}: #{response.body}"
        expect(JSON.parse(response.body)['success']).to be_a(String)
      end

      # The IP tier, not the per-login backstop, locked (every probe used a
      # distinct login).
      expect(rl_redis.keys('email_login_request:locked:ip:*').size).to eq(1)

      response = request_login_link(unique_test_email('sample-2'))
      expect(response.status).to eq(429),
        "Over-cap request must be throttled, got #{response.status}: #{response.body}"
      body     = JSON.parse(response.body)
      expect(body['error_type']).to eq('LimitExceeded')
      expect(body['error']).to eq('Too many login link requests. Please try again later.')
      expect(body['retry_after']).to be_a(Integer)
      expect(body['max_attempts']).to eq(2)
      expect(response.headers['retry-after']).to eq(body['retry_after'].to_s)
    end
  end

  describe 'per-login backstop' do
    it 'caps repeated probes of ONE target case-insensitively, independent of the IP tier' do
      enable_limiter(max_per_ip: 100, max_per_email: 2)
      target = unique_test_email('backstop')

      2.times do |i|
        response = request_login_link(target)
        expect(response.status).to eq(200),
          "Under-cap request #{i + 1} should pass, got #{response.status}: #{response.body}"
      end

      expect(rl_redis.keys('email_login_request:locked:email:*').size).to eq(1)

      response = request_login_link(target.upcase)
      expect(response.status).to eq(429),
        "Over-cap request must be throttled, got #{response.status}: #{response.body}"
      expect(JSON.parse(response.body)['error_type']).to eq('LimitExceeded')
    end
  end

  describe 'enumeration safety of the 429' do
    it 'throttles an existing and a non-existent login identically, before any lookup' do
      enable_limiter(max_per_ip: 100, max_per_email: 1)

      existing = unique_test_email('exists')
      missing  = unique_test_email('missing')
      seed_existing_account(existing)

      expect(request_login_link(existing).status).to eq(200)
      expect(request_login_link(missing).status).to eq(200)

      throttled_existing = request_login_link(existing)
      throttled_missing  = request_login_link(missing)

      expect(throttled_existing.status).to eq(429)
      expect(throttled_missing.status).to eq(429)

      # request_id varies per request, so compare the discriminating fields.
      existing_body = JSON.parse(throttled_existing.body)
      missing_body  = JSON.parse(throttled_missing.body)
      %w[error error_type max_attempts].each do |field|
        expect(existing_body[field]).to eq(missing_body[field])
      end

      # Only the first (allowed) request for the existing account mailed.
      expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email_raw)
        .with(hash_including(to: contain_exactly(existing)), any_args).once
    end
  end

  describe 'scope separation' do
    it 'charges only the email_login_request buckets' do
      enable_limiter(max_per_ip: 100, max_per_email: 100)

      request_login_link(unique_test_email('scoped'))

      expect(rl_redis.keys('email_login_request:attempts:*').size).to eq(2)
      expect(rl_redis.keys('reset_request:attempts:*')).to be_empty
    end
  end

  describe 'suite default (limiter disabled by test config)' do
    it 'does not throttle when site.authentication.email_login_request_rate_limit is disabled' do
      3.times do
        expect(request_login_link(unique_test_email('off')).status).to eq(200)
      end
      expect(rl_redis.keys('email_login_request:attempts:*')).to be_empty
      expect(rl_redis.keys('email_login_request:locked:*')).to be_empty
    end
  end
end
