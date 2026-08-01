# spec/integration/simple/reset_password_request_rate_limit_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — reset-password-request rate limiting in SIMPLE mode
# =============================================================================
#
# Issue #3872 added Onetime::Security::ResetRequestRateLimiter but wired it only
# into the Rodauth before_reset_password_request_route hook
# (apps/web/auth/config/hooks/reset_password_request.rb). That file lives under
# apps/web/auth/, which the registry skips unless auth_config.full_enabled?
# (lib/onetime/application/registry.rb#find_application_files) — so in SIMPLE
# mode, the application default, POST /auth/reset-password-request was served by
# the Core app with no throughput cap at all: an unauthenticated caller could
# mail-bomb arbitrary addresses and accumulate unbounded samples against the
# timing residual documented in
# apps/api/account/logic/authentication/reset_password_request.rb.
#
# The simple-mode route runs
#   apps/web/core/routes.txt
#     -> Core::Controllers::Registration#request_reset_email
#       -> AccountAPI::Logic::Authentication::ResetPasswordRequest
# which now enforces the same limiter from #raise_concerns, with the same
# subjects and the same before-any-account-lookup ordering as the full-mode
# hook. These tests assert that end to end, through the real middleware stack.
#
# The sibling full-mode coverage is
# apps/web/auth/spec/integration/full/reset_password_request_rate_limit_spec.rb;
# keep the two in lockstep.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTHENTICATION_MODE=simple
#
# RUN:
#   RACK_ENV=test AUTHENTICATION_MODE=simple bundle exec rspec \
#     spec/integration/simple/reset_password_request_rate_limit_spec.rb
#
# =============================================================================

require_relative '../integration_spec_helper'

RSpec.describe 'Reset-password-request rate limiting — simple mode (#3872)', type: :integration do
  include Rack::Test::Methods

  # Full Rack::URLMap so requests traverse the complete middleware stack
  # (IPPrivacyMiddleware included — the per-IP tier keys on the masked client IP
  # it resolves, not on a raw REMOTE_ADDR).
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
    # Isolate from real delivery: every login probed below is unregistered, so
    # #process returns its generic response without dispatching — this is a
    # belt-and-braces guard, not load-bearing.
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(true)

    @saved_conf = YAML.load(YAML.dump(OT.conf))
    clear_reset_request_keys
  end

  after do
    OT.send(:conf=, @saved_conf) if @saved_conf
    clear_reset_request_keys
  end

  # The limiter's counters live on the Customer shard (see
  # ResetRequestRateLimiter#reset_request_redis), which is not necessarily the
  # logical DB the integration helper flushes.
  let(:rl_redis) { Onetime::Customer.dbclient }

  def clear_reset_request_keys
    stale = rl_redis.keys('reset_request:attempts:*') +
            rl_redis.keys('reset_request:locked:*')
    rl_redis.del(*stale) unless stale.empty?
  end

  # Enable the limiter in-process with example-specific caps (spec/config.test.yaml
  # ships it disabled so the rest of the suite is not throttled). Restored from
  # @saved_conf in the after hook.
  def enable_limiter(max_per_ip:, max_per_email:)
    new_conf = YAML.load(YAML.dump(OT.conf))
    site     = (new_conf['site'] ||= {})
    auth     = (site['authentication'] ||= {})

    auth['reset_request_rate_limit'] = {
      'enabled' => true,
      'max_per_ip' => max_per_ip,
      'max_per_email' => max_per_email,
      'window' => 900,
      'lockout' => 900,
    }

    OT.send(:conf=, new_conf)
  end

  def unique_login(prefix = 'probe')
    "#{prefix}-#{SecureRandom.hex(8)}@example.com"
  end

  # Fresh session + CSRF token per request, mirroring the full-mode helper: an
  # attacker is not obliged to reuse a session, so the limiter must bite
  # regardless of session identity. `from:` drives REMOTE_ADDR so examples can
  # present distinct sources; IPPrivacyMiddleware resolves and masks it into
  # env['otto.client_ip'], which is what the per-IP tier keys on.
  def request_password_reset(login, from: nil)
    clear_cookies
    rack_env = from ? { 'REMOTE_ADDR' => from } : {}

    header 'Content-Type', nil
    header 'Content-Length', nil
    header 'Accept', 'application/json'
    get '/', {}, rack_env
    token = last_response.headers['X-CSRF-Token']

    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', token if token
    post '/auth/reset-password-request', JSON.generate(login: login, shrimp: token), rack_env
    last_response
  end

  # The /24 (IPv4) mask IPPrivacyMiddleware applies before the app sees the
  # address — the per-IP bucket is that masked network, never the raw source.
  def masked(ip)
    "#{ip.split('.').first(3).join('.')}.0"
  end

  it 'runs the simple-mode path (the Auth app is not mounted)' do
    expect(Onetime.auth_config.full_enabled?).to be false
    expect(Onetime::Application::Registry.mount_mappings.key?('/auth')).to be false
  end

  describe 'per-IP tier' do
    let(:source_a) { '203.0.113.10' }
    let(:source_b) { '198.51.100.20' }

    it 'caps request volume from one source across DIFFERENT logins (the enumeration sampling pattern)' do
      enable_limiter(max_per_ip: 2, max_per_email: 100)

      2.times do |i|
        response = request_password_reset(unique_login("sample-#{i}"), from: source_a)
        expect(response.status).to eq(200),
          "Under-cap request #{i + 1} should pass, got #{response.status}: #{response.body}"
        expect(JSON.parse(response.body)['success']).to match(/email has been sent/i)
      end

      # Assert the EXACT key, not just that some ip-tier key locked: a
      # constant/global bucket (one caller 429s the whole deployment) or a
      # raw-REMOTE_ADDR key would both satisfy a glob count. This pins the
      # subject to the privacy-masked client IP the middleware resolved, and
      # proves the IP tier — not the per-login backstop — is what engaged, since
      # every probe used a distinct login.
      expect(rl_redis.keys('reset_request:locked:ip:*'))
        .to eq(["reset_request:locked:ip:#{masked(source_a)}"])

      response = request_password_reset(unique_login('sample-2'), from: source_a)
      expect(response.status).to eq(429),
        "Over-cap request must be throttled, got #{response.status}: #{response.body}"
      body     = JSON.parse(response.body)
      expect(body['error_type']).to eq('LimitExceeded')
      expect(body['retry_after']).to be_a(Integer)
      expect(body['max_attempts']).to eq(2)
    end

    it 'isolates sources: one locked-out network does not throttle another' do
      enable_limiter(max_per_ip: 2, max_per_email: 100)

      # Source A burns its budget. The cap-hitting request is itself allowed —
      # the Lua script locks AFTER incrementing — so the third request is the
      # first refusal.
      2.times { |i| expect(request_password_reset(unique_login("a-#{i}"), from: source_a).status).to eq(200) }
      expect(request_password_reset(unique_login('a-over'), from: source_a).status).to eq(429)

      # Source B is untouched: a per-IP tier keyed on a constant, on a global
      # counter, or on anything else shared would 429 here too, turning one
      # caller's burst into a full-endpoint denial of service.
      expect(request_password_reset(unique_login('b-first'), from: source_b).status).to eq(200)

      # ...and B's budget is its own, tracked under B's masked network while
      # only A is locked out.
      expect(rl_redis.keys('reset_request:locked:ip:*'))
        .to eq(["reset_request:locked:ip:#{masked(source_a)}"])
      expect(rl_redis.get("reset_request:attempts:ip:#{masked(source_b)}")).to eq('1')
    end
  end

  describe 'per-login backstop' do
    it 'caps repeated probes of ONE target case-insensitively, independent of the IP tier' do
      enable_limiter(max_per_ip: 100, max_per_email: 2)
      target = unique_login('backstop')

      2.times do |i|
        response = request_password_reset(target)
        expect(response.status).to eq(200),
          "Under-cap request #{i + 1} should pass, got #{response.status}: #{response.body}"
      end

      expect(rl_redis.keys('reset_request:locked:email:*').size).to eq(1)

      # A case-variant of the same target shares the bucket (the limiter
      # normalizes the login the same way the account lookup does), so the third
      # probe is refused even though the per-IP cap is far away.
      response = request_password_reset(target.upcase)
      expect(response.status).to eq(429),
        "Over-cap request must be throttled, got #{response.status}: #{response.body}"
      expect(JSON.parse(response.body)['error_type']).to eq('LimitExceeded')
    end
  end

  describe 'enumeration safety of the 429' do
    it 'throttles an existing and a non-existent login identically' do
      enable_limiter(max_per_ip: 100, max_per_email: 1)

      existing = unique_login('exists')
      missing  = unique_login('missing')

      customer          = Onetime::Customer.new(email: existing)
      customer.update_passphrase('Test123!@#')
      customer.verified = 'true'
      customer.save

      expect(request_password_reset(existing).status).to eq(200)
      expect(request_password_reset(missing).status).to eq(200)

      throttled_existing = request_password_reset(existing)
      throttled_missing  = request_password_reset(missing)

      expect(throttled_existing.status).to eq(429)
      expect(throttled_missing.status).to eq(429)

      # The throttle discloses nothing about account existence: same error
      # content either way (request-correlation fields vary per request, so
      # compare the discriminating fields rather than the whole body).
      existing_body = JSON.parse(throttled_existing.body)
      missing_body  = JSON.parse(throttled_missing.body)
      %w[error error_type max_attempts].each do |field|
        expect(existing_body[field]).to eq(missing_body[field])
      end
    end
  end

  describe 'throttled probes never reach the timing-sensitive path' do
    it 'performs no account lookup and dispatches no email once locked out' do
      enable_limiter(max_per_ip: 1, max_per_email: 100)

      expect(request_password_reset(unique_login('first')).status).to eq(200)

      # The limiter runs in raise_concerns, ahead of the format check and ahead
      # of #process — so a throttled probe never executes the lookup + reset-key
      # write + mail dispatch whose duration is the residual timing channel.
      expect(Onetime::Customer).not_to receive(:find_by_email)
      expect(Onetime::Jobs::Publisher).not_to receive(:enqueue_email)

      expect(request_password_reset(unique_login('second')).status).to eq(429)
    end
  end

  describe 'malformed submissions still cost budget' do
    it 'does not 500 on an invalid-UTF-8 login, and counts the probe' do
      # Rack::Parser parses the urlencoded body eagerly and caches it, so the
      # UTF8Sanitizer never touches these params: `login` arrives UTF-8-tagged
      # with an invalid byte sequence. process_params runs in the logic
      # constructor, which the controller builds OUTSIDE its error handling and
      # therefore before the limiter — so a raise there would be an
      # unauthenticated 500 that consumes no budget, i.e. an uncapped hole in
      # the cap this file exists to verify.
      enable_limiter(max_per_ip: 10, max_per_email: 10)

      clear_cookies
      header 'Content-Type', nil
      header 'Content-Length', nil
      header 'Accept', 'application/json'
      get '/', {}, 'REMOTE_ADDR' => '203.0.113.30'
      token = last_response.headers['X-CSRF-Token']

      header 'Content-Type', 'application/x-www-form-urlencoded'
      header 'Accept', 'application/json'
      header 'X-CSRF-Token', token if token
      post '/auth/reset-password-request',
        "login=user%C3%28%40example.com&shrimp=#{token}",
        'REMOTE_ADDR' => '203.0.113.30'

      expect(last_response.status).not_to eq(500),
        "malformed login must not 500: #{last_response.body}"
      expect(rl_redis.get('reset_request:attempts:ip:203.0.113.0')).to eq('1')
    end
  end

  describe 'shipped default (no reset_request_rate_limit config at all)' do
    it 'is ON, at the module defaults, for an install that never configured it' do
      # The gap this change closes is specifically that the DEFAULT deployment
      # was unprotected, so it is not enough to show the limiter works when a
      # spec turns it on with custom caps: an install whose config.yaml predates
      # #3872 has no reset_request_rate_limit key at all, and must still be
      # throttled. reset_request_rate_limit_enabled? treats absent config as
      # enabled; this drives that path end to end at DEFAULT_MAX_PER_IP.
      new_conf = YAML.load(YAML.dump(OT.conf))
      new_conf['site']['authentication'].delete('reset_request_rate_limit')
      OT.send(:conf=, new_conf)

      cap = Onetime::Security::ResetRequestRateLimiter::DEFAULT_MAX_PER_IP

      cap.times do |i|
        expect(request_password_reset(unique_login("default-#{i}")).status).to eq(200),
          "Request #{i + 1}/#{cap} should pass under the default cap"
      end

      expect(request_password_reset(unique_login('default-over')).status).to eq(429)
    end
  end

  describe 'suite default (limiter disabled by test config)' do
    it 'does not throttle when site.authentication.reset_request_rate_limit is disabled' do
      # No enable_limiter call: this runs under spec/config.test.yaml, which
      # ships enabled:false — repeated probes stay on the generic success and
      # write no limiter keys.
      3.times do
        expect(request_password_reset(unique_login('off')).status).to eq(200)
      end
      expect(rl_redis.keys('reset_request:attempts:*')).to be_empty
      expect(rl_redis.keys('reset_request:locked:*')).to be_empty
    end
  end
end
