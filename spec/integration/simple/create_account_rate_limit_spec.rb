# spec/integration/simple/create_account_rate_limit_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — account-creation rate limiting in SIMPLE mode
# =============================================================================
#
# Covers the SIMPLE-mode half of finding #4 of the 2026-07-30 audit. In simple
# mode POST /auth/create-account (apps/web/core/routes.txt:32, auth=noauth)
# reaches AccountAPI::Logic::Account::CreateAccount, which had NO limiter of
# any kind — a grep for rate_limit/enforce_ across that logic class and
# Core::Controllers::Registration returned nothing. The reachable primitive was
# unauthenticated, unthrottled account creation: one Customer record (the hash
# carries no TTL) plus one welcome email per DISTINCT address, with
# subaddressing folding arbitrarily many addresses onto one mailbox.
#
# The FULL-mode half of the same finding is covered by
# apps/web/auth/spec/integration/full/create_account_rate_limit_spec.rb: there
# the Auth app owns /auth/* and Rodauth serves this route, so the identical
# limiter is enforced from the before_create_account_route hook instead
# (apps/web/auth/config/hooks/create_account.rb). Neither spec's assertions
# transfer to the other mode — hence the skip guard below — but the two together
# are what close the finding for every deployment shape.
#
# The limiter is single-tier and keyed on the client IP alone. That is a
# necessity, not a preference: every request in the abuse pattern carries a
# fresh address, so a per-email tier would mint one bucket per request and cap
# nothing. It also must not key on anything account-derived — this route's whole
# response contract is that new and existing accounts are byte-identical.
#
# These tests drive the REAL middleware stack, so the subject under test is the
# privacy-masked client IP that IPPrivacyMiddleware resolves, not a raw
# REMOTE_ADDR the app never sees.
#
# Sibling coverage: try/unit/security/create_account_rate_limiter_try.rb (unit,
# including the audit-write bound and the collapsed-IP operator hint).
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTHENTICATION_MODE=simple
#
# RUN:
#   RACK_ENV=test AUTHENTICATION_MODE=simple bundle exec rspec \
#     spec/integration/simple/create_account_rate_limit_spec.rb
#
# =============================================================================

require_relative '../integration_spec_helper'

RSpec.describe 'Account-creation rate limiting — simple mode (#3948 finding #4)', type: :integration do
  include Rack::Test::Methods

  # Full Rack::URLMap so requests traverse the complete middleware stack.
  # Memoized: repeated generate_rack_url_map calls corrupt middleware state.
  def app
    @rack_app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

  before(:all) do
    Onetime.boot! :test
    app
  end

  before do
    # Full mode routes /auth/create-account to Rodauth, so these assertions
    # would be exercising the wrong code path entirely.
    skip 'requires simple auth mode' if Onetime.auth_config.full_enabled?

    # Intercept delivery at the Mailer seam: send_verification_email delivers
    # synchronously (lib/onetime/logic/base.rb), so without this every allowed
    # signup would attempt real SMTP. Everything upstream still runs for real.
    allow(Onetime::Mail::Mailer).to receive(:deliver).and_return(true)

    @saved_conf     = YAML.load(YAML.dump(OT.conf))
    @created_emails = []
    clear_limiter_keys
  end

  after do
    OT.send(:conf=, @saved_conf) if @saved_conf
    clear_limiter_keys

    Array(@created_emails).each do |email|
      cust = Onetime::Customer.find_by_email(email)
      next unless cust

      Onetime::Customer.dbclient.del("verification_resend:cooldown:#{cust.objid}")
      cust.destroy!
    rescue StandardError => e
      warn "[create-account limiter spec] customer cleanup failed: #{e.message}"
    end
  end

  # The counters live on the Customer shard (see
  # CreateAccountRateLimiter#create_account_redis), which is not necessarily the
  # logical DB the integration helper flushes.
  let(:rl_redis) { Onetime::Customer.dbclient }

  def clear_limiter_keys
    stale = rl_redis.keys('create_account:attempts:*') +
            rl_redis.keys('create_account:locked:*')
    rl_redis.del(*stale) unless stale.empty?
  end

  # Enable the limiter in-process with an example-specific cap
  # (spec/config.test.yaml ships it disabled so the rest of the suite's signups
  # are not throttled). Restored from @saved_conf in the after hook.
  def enable_limiter(max_per_ip:)
    new_conf = YAML.load(YAML.dump(OT.conf))
    site     = (new_conf['site'] ||= {})
    auth     = (site['authentication'] ||= {})

    auth['create_account_rate_limit'] = {
      'enabled' => true,
      'max_per_ip' => max_per_ip,
      'window' => 900,
      'lockout' => 900,
    }

    OT.send(:conf=, new_conf)
  end

  def disable_limiter
    new_conf                          = YAML.load(YAML.dump(OT.conf))
    site                              = (new_conf['site'] ||= {})
    auth                              = (site['authentication'] ||= {})
    auth['create_account_rate_limit'] = { 'enabled' => false }
    OT.send(:conf=, new_conf)
  end

  def unique_email(prefix = 'signup')
    "#{prefix}-#{SecureRandom.hex(8)}@integration-test.example.com"
  end

  # Fresh session + CSRF token per request: an attacker is not obliged to reuse
  # a session, so the limiter must bite regardless of session identity. `from:`
  # drives REMOTE_ADDR; IPPrivacyMiddleware resolves and masks it into
  # env['otto.client_ip'], which is what the limiter keys on.
  #
  # Setup failure must be LOUD: a silently-nil shrimp draws a 403 from the CSRF
  # middleware and surfaces as a misleading status assertion further down.
  def post_signup(login, from: nil, password: 'integration-test-pw')
    clear_cookies
    rack_env = from ? { 'REMOTE_ADDR' => from } : {}

    header 'Content-Type', nil
    header 'Content-Length', nil
    header 'Accept', 'application/json'
    get '/', {}, rack_env
    token = last_response.headers['X-CSRF-Token']

    if token.to_s.empty?
      raise "CSRF setup failed: GET / returned #{last_response.status} with no X-CSRF-Token header " \
            "(headers: #{last_response.headers.keys.sort.join(', ')})."
    end

    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', token
    post '/auth/create-account',
      JSON.generate(login: login, password: password, skill: '', shrimp: token),
      rack_env

    if last_response.status == 403
      raise "CSRF rejected by the stack (403): #{last_response.body}. " \
            'This is a session/middleware problem, not a signup result.'
    end

    last_response
  end

  # The /24 (IPv4) mask IPPrivacyMiddleware applies before the app sees the
  # address — the bucket is that masked network, never the raw source.
  def masked(ip)
    "#{ip.split('.').first(3).join('.')}.0"
  end

  it 'runs the simple-mode path (the Auth app is not mounted)' do
    expect(Onetime.auth_config.full_enabled?).to be false
    expect(Onetime::Application::Registry.mount_mappings.key?('/auth')).to be false
  end

  describe 'per-IP cap' do
    let(:source_a) { '203.0.113.10' }
    let(:source_b) { '198.51.100.20' }

    it 'caps signup volume from one source across DIFFERENT addresses (the abuse pattern)' do
      enable_limiter(max_per_ip: 2)

      2.times do |i|
        email    = unique_email("burst-#{i}")
        @created_emails << email
        response = post_signup(email, from: source_a)
        expect(response.status).to eq(200),
          "Under-cap signup #{i + 1} should pass, got #{response.status}: #{response.body}"
      end

      # Assert the EXACT key, not merely that something locked. A constant or
      # global bucket (one caller shutting off signup deployment-wide) and a
      # raw-REMOTE_ADDR key would both satisfy a glob count; this pins the
      # subject to the privacy-masked address the middleware resolved. Every
      # signup above used a distinct email, so only an IP-keyed tier can be
      # what engaged.
      expect(rl_redis.keys('create_account:locked:ip:*'))
        .to eq(["create_account:locked:ip:#{masked(source_a)}"])

      response = post_signup(unique_email('burst-over'), from: source_a)
      expect(response.status).to eq(429),
        "Over-cap signup must be throttled, got #{response.status}: #{response.body}"
      body     = JSON.parse(response.body)
      expect(body['error_type']).to eq('LimitExceeded')
      expect(body['retry_after']).to be_a(Integer)
      expect(body['max_attempts']).to eq(2)
    end

    it 'carries a Retry-After header on the 429, not only a body field' do
      enable_limiter(max_per_ip: 1)

      first = unique_email('hdr')
      @created_emails << first
      post_signup(first, from: source_a)

      response = post_signup(unique_email('hdr-over'), from: source_a)
      expect(response.status).to eq(429)
      # RetryAfterHeader middleware (#3956) turns the body's retry_after into
      # the RFC 9110 header for every LimitExceeded, this limiter included.
      expect(response.headers['Retry-After']).to match(/\A\d+\z/)
      expect(response.headers['Retry-After'].to_i).to be_positive
    end

    it 'isolates sources: one locked-out network does not throttle another' do
      enable_limiter(max_per_ip: 1)

      first = unique_email('iso-a')
      @created_emails << first
      post_signup(first, from: source_a)

      expect(post_signup(unique_email('iso-a-over'), from: source_a).status).to eq(429)

      second   = unique_email('iso-b')
      @created_emails << second
      response = post_signup(second, from: source_b)
      expect(response.status).to eq(200),
        "A different source must be unaffected, got #{response.status}: #{response.body}"
    end
  end

  describe 'ordering and enumeration safety' do
    let(:source) { '192.0.2.30' }

    it 'creates NO customer for a throttled signup' do
      enable_limiter(max_per_ip: 1)

      first = unique_email('order')
      @created_emails << first
      post_signup(first, from: source)

      blocked  = unique_email('order-blocked')
      response = post_signup(blocked, from: source)
      expect(response.status).to eq(429)

      # The limiter runs in #raise_concerns, ahead of the find_by_email lookup
      # and the Customer.create! in #process. If it were enforced anywhere later
      # the record would exist despite the 429 — which is the entire point of
      # the finding (datastore growth), so assert the absence directly.
      expect(Onetime::Customer.find_by_email(blocked)).to be_nil
    end

    it 'never writes a key derived from the submitted address' do
      enable_limiter(max_per_ip: 3)

      email = unique_email('nokey')
      @created_emails << email
      post_signup(email, from: source)

      # An address-keyed bucket would be an enumeration oracle on a route whose
      # contract is that existing and new accounts respond identically.
      local_part = email.split('@').first
      expect(rl_redis.keys('create_account:*').grep(/#{Regexp.escape(local_part)}|@/)).to be_empty
    end

    it 'charges budget for submissions rejected as malformed' do
      enable_limiter(max_per_ip: 2)

      # Malformed addresses are free to generate and equally good for flooding,
      # so they must cost budget even though they never reach #process. The
      # limiter sits ahead of the format check for exactly this reason.
      expect(post_signup('not-an-email', from: source).status).to eq(422).or eq(400)

      valid = unique_email('after-malformed')
      @created_emails << valid
      post_signup(valid, from: source)

      response = post_signup(unique_email('after-malformed-over'), from: source)
      expect(response.status).to eq(429),
        "The malformed submission should have consumed budget, got #{response.status}: #{response.body}"
    end
  end

  describe 'when disabled' do
    let(:source) { '198.51.100.77' }

    it 'writes no keys and never throttles' do
      disable_limiter

      3.times do |i|
        email    = unique_email("off-#{i}")
        @created_emails << email
        response = post_signup(email, from: source)
        expect(response.status).to eq(200),
          "Signup #{i + 1} should pass with the limiter off, got #{response.status}: #{response.body}"
      end

      expect(rl_redis.keys('create_account:attempts:*')).to be_empty
      expect(rl_redis.keys('create_account:locked:*')).to be_empty
    end
  end
end
