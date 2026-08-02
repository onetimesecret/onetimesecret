# apps/web/auth/spec/integration/full/email_auth_rate_limit_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — magic-link request rate limiting in FULL mode
# (audit 2026-08-02 finding L-5)
# =============================================================================
#
# POST /auth/email-login-request (Rodauth's email_auth_request route) relied
# solely on the built-in email_auth_skip_resend_email_within throttle, which
# is PER ACCOUNT — it bounds resends for one mailbox but caps nothing across
# addresses. The before_email_auth_request_route hook
# (config/hooks/email_auth_request.rb) enforces
# Onetime::Security::EmailAuthRateLimiter at the top of the route: ahead of
# the POST body and the account_from_login lookup, after Rodauth's own
# check_already_logged_in.
#
# Full mode is the WHOLE surface for this route: the email_auth feature (and
# its request route) exists only in the Rodauth app; simple mode's GET
# /email-login renders the SPA page and the POST it would submit to does not
# exist there. So unlike the create-account limiter there is no simple-mode
# sibling call site or spec.
#
# These tests assert the properties that distinguish a correct implementation
# from one that merely returns 429 somewhere:
#
#   1. the cap bites across DISTINCT submitted logins (only an IP-keyed tier
#      can do that — cross-address volume per origin is the gap the built-in
#      per-account throttle leaves open);
#   2. the key written is exactly email_auth:locked:ip:<masked-ip> — the
#      privacy-masked address IPPrivacyMiddleware resolved, never a raw
#      REMOTE_ADDR and never a global bucket one caller could use to shut off
#      passwordless login deployment-wide;
#   3. no key is ever derived from the submitted login (enumeration safety);
#   4. requests for UNKNOWN logins cost budget too — a limiter that only
#      counted successful sends would leak registration state through its own
#      bookkeeping.
#
# Sibling coverage: try/unit/security/email_auth_rate_limiter_try.rb (unit,
# including the audit-write bound and the collapsed-IP operator hint).
#
# The suite-wide test config ships the limiter DISABLED (spec/config.test.yaml)
# so other full-mode specs are not throttled; each example here enables it
# in-process with small caps and restores the config after.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
# - AUTH_EMAIL_AUTH_ENABLED=true (the route only exists when the email_auth
#   feature is enabled; the examples self-skip otherwise)
#
# RUN:
#   RACK_ENV=test AUTHENTICATION_MODE=full AUTH_DATABASE_URL='sqlite::memory:' \
#     AUTH_EMAIL_AUTH_ENABLED=true bundle exec rspec \
#     apps/web/auth/spec/integration/full/email_auth_rate_limit_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require 'rack/test'

RSpec.describe 'Magic-link request rate limiting — full mode (audit 2026-08-02 L-5)', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    # Boot the full app so the REAL Auth::Config — with the rate-limit hook
    # wired in via config/hooks/email_auth_request.rb — is loaded and mounted
    # at /auth.
    boot_onetime_app
  end

  before do
    unless defined?(Auth::Database) && Auth::Database.connection
      skip 'Auth database not configured (run with AUTH_DATABASE_URL set)'
    end

    unless Onetime.auth_config.email_auth_enabled?
      skip 'email_auth feature not enabled (run with AUTH_EMAIL_AUTH_ENABLED=true)'
    end

    # Isolate from real delivery: a request for an EXISTING login dispatches a
    # magic-link email. Everything upstream still runs for real.
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(true)
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw).and_return(true)

    @saved_conf = YAML.load(YAML.dump(OT.conf))
    clear_limiter_keys
  end

  after do
    OT.send(:conf=, @saved_conf) if @saved_conf
    clear_limiter_keys
  end

  # The counters live on the Customer shard (see
  # EmailAuthRateLimiter#email_auth_redis), which is not necessarily the
  # logical DB the suite helpers flush.
  let(:rl_redis) { Onetime::Customer.dbclient }

  def clear_limiter_keys
    stale = rl_redis.keys('email_auth:attempts:*') +
            rl_redis.keys('email_auth:locked:*')
    rl_redis.del(*stale) unless stale.empty?
  end

  # Enable the limiter in-process with an example-specific cap
  # (spec/config.test.yaml ships it disabled). Restored from @saved_conf above.
  def enable_limiter(max_per_ip:)
    new_conf = YAML.load(YAML.dump(OT.conf))
    site     = (new_conf['site'] ||= {})
    auth     = (site['authentication'] ||= {})

    auth['email_auth_rate_limit'] = {
      'enabled' => true,
      'max_per_ip' => max_per_ip,
      'window' => 900,
      'lockout' => 900,
    }

    OT.send(:conf=, new_conf)
  end

  # Fresh session + CSRF token per request: an attacker is not obliged to
  # reuse a session, so the limiter must bite regardless of session identity.
  # REMOTE_ADDR drives the source; IPPrivacyMiddleware resolves and masks it
  # into env['otto.client_ip'], which is what the limiter keys on.
  def post_link_request(login, from:)
    clear_cookies
    rack_env = { 'REMOTE_ADDR' => from }

    header 'Content-Type', nil
    header 'Content-Length', nil
    header 'Accept', 'application/json'
    get '/auth', {}, rack_env
    token = last_response.headers['X-CSRF-Token']

    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', token if token
    post '/auth/email-login-request',
      JSON.generate(login: login, shrimp: token),
      rack_env
    last_response
  end

  def probe_email(prefix)
    "#{prefix}-#{SecureRandom.hex(8)}@example.com"
  end

  # The /24 (IPv4) mask IPPrivacyMiddleware applies before the app sees the
  # address — the bucket is that masked network, never the raw source.
  def masked(ip)
    "#{ip.split('.').first(3).join('.')}.0"
  end

  it 'runs the full-mode path with the hook wired in' do
    expect(Onetime.auth_config.full_enabled?).to be true
    expect(Onetime::Application::Registry.mount_mappings.key?('/auth')).to be true
    # The hook is what can possibly be enforcing here: the limiter module is
    # mixed into the Rodauth class, and OUR block is what
    # `_before_email_auth_request_route` compiles to.
    #
    # Assert the source_location, not merely that the method is defined:
    # Rodauth's `before` definer class_evals a nil stub for every class
    # carrying the :email_auth feature, so `private_method_defined?` is true
    # whether or not we registered anything. The file the method actually came
    # from is the part that discriminates.
    expect(Auth::Config.ancestors).to include(Onetime::Security::EmailAuthRateLimiter)
    hook_source = Auth::Config.instance_method(:_before_email_auth_request_route).source_location&.first
    expect(hook_source).to end_with('apps/web/auth/config/hooks/email_auth_request.rb')
  end

  describe 'per-IP cap' do
    let(:source_a) { '203.0.113.10' }
    let(:source_b) { '198.51.100.20' }

    it 'caps request volume from one source across DIFFERENT logins (the abuse pattern)' do
      enable_limiter(max_per_ip: 2)

      # Unknown logins on purpose: they MUST cost budget (they are free to
      # generate, and a limiter that only counted successful sends would leak
      # registration state through its own bookkeeping). The route answers
      # them with its no-matching-login error, never a 429, while under cap.
      2.times do |i|
        response = post_link_request(probe_email("burst-#{i}"), from: source_a)
        expect(response.status).not_to eq(429),
          "Under-cap request #{i + 1} must not be throttled, got #{response.status}: #{response.body}"
      end

      # Assert the EXACT key, not merely that something locked. A constant or
      # global bucket and a raw-REMOTE_ADDR key would both satisfy a glob
      # count; this pins the subject to the privacy-masked address the
      # middleware resolved. Every request above used a distinct login, so
      # only an IP-keyed tier can be what engaged.
      expect(rl_redis.keys('email_auth:locked:ip:*'))
        .to eq(["email_auth:locked:ip:#{masked(source_a)}"])

      response = post_link_request(probe_email('burst-over'), from: source_a)
      expect(response.status).to eq(429),
        "Over-cap request must be throttled, got #{response.status}: #{response.body}"
      body = JSON.parse(response.body)
      expect(body['error_type']).to eq('LimitExceeded')
      expect(body['retry_after']).to be_a(Integer)
      expect(body['max_attempts']).to eq(2)
    end

    it 'isolates sources: one locked-out network does not throttle another' do
      enable_limiter(max_per_ip: 1)

      post_link_request(probe_email('iso-a'), from: source_a)
      expect(post_link_request(probe_email('iso-a-over'), from: source_a).status).to eq(429)

      response = post_link_request(probe_email('iso-b'), from: source_b)
      expect(response.status).not_to eq(429),
        "A different source must be unaffected, got #{response.status}: #{response.body}"
    end
  end

  describe 'ordering: nothing runs for a throttled request' do
    let(:source) { '192.0.2.30' }

    it 'never reaches the account lookup for a throttled request' do
      enable_limiter(max_per_ip: 1)

      # Route-hook placement runs ahead of account_from_login. On a route
      # where a limiter keyed on anything account-derived would be an
      # enumeration oracle, not running the lookup at all is the strongest
      # form of that guarantee. Counted rather than asserted with
      # have_received: the meaningful assertion is that a throttled request
      # adds ZERO queries, not that the total is any one number.
      lookups = 0
      accounts_ds = Auth::Database.connection[:accounts]
      allow(Auth::Database.connection).to receive(:[]).and_wrap_original do |orig, *args, &blk|
        lookups += 1 if args.first == :accounts
        orig.call(*args, &blk)
      end

      expect(post_link_request(probe_email('lookup'), from: source).status).not_to eq(429)

      # The allowed sibling pins the spy to a call site that really is on this
      # path — without it, the assertion below would hold for a typo'd table
      # name just as well.
      baseline = lookups
      expect(baseline).to be_positive

      expect(post_link_request(probe_email('lookup-blocked'), from: source).status).to eq(429)
      expect(lookups).to eq(baseline)

      # Silence the unused-variable lint without changing behavior.
      _ = accounts_ds
    end

    it 'never writes a key derived from the submitted login' do
      enable_limiter(max_per_ip: 3)

      email = probe_email('nokey')
      post_link_request(email, from: source)

      # A login-keyed bucket would make throttling observable per address — a
      # registration-state oracle.
      local_part = email.split('@').first
      expect(rl_redis.keys('email_auth:*').grep(/#{Regexp.escape(local_part)}|@/)).to be_empty
    end
  end

  describe 'suite default (limiter disabled by test config)' do
    it 'does not throttle when site.authentication.email_auth_rate_limit is disabled' do
      # No enable_limiter call: this runs under spec/config.test.yaml, which
      # ships enabled:false — repeated requests write no limiter keys.
      3.times do |i|
        response = post_link_request(probe_email("off-#{i}"), from: '198.51.100.77')
        expect(response.status).not_to eq(429),
          "Request #{i + 1} must pass with the limiter off, got #{response.status}: #{response.body}"
      end

      expect(rl_redis.keys('email_auth:attempts:*')).to be_empty
      expect(rl_redis.keys('email_auth:locked:*')).to be_empty
    end
  end
end
