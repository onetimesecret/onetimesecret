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
  # regardless of session identity.
  def request_password_reset(login)
    clear_cookies

    header 'Content-Type', nil
    header 'Content-Length', nil
    header 'Accept', 'application/json'
    get '/'
    token = last_response.headers['X-CSRF-Token']

    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', token if token
    post '/auth/reset-password-request', JSON.generate(login: login, shrimp: token)
    last_response
  end

  it 'runs the simple-mode path (the Auth app is not mounted)' do
    expect(Onetime.auth_config.full_enabled?).to be false
    expect(Onetime::Application::Registry.mount_mappings.key?('/auth')).to be false
  end

  describe 'per-IP tier' do
    it 'caps request volume from one source across DIFFERENT logins (the enumeration sampling pattern)' do
      enable_limiter(max_per_ip: 2, max_per_email: 100)

      2.times do |i|
        response = request_password_reset(unique_login("sample-#{i}"))
        expect(response.status).to eq(200),
          "Under-cap request #{i + 1} should pass, got #{response.status}: #{response.body}"
        expect(JSON.parse(response.body)['success']).to match(/email has been sent/i)
      end

      # The cap-hitting request locked the per-IP tier (attempts key cleared,
      # lockout flag set) — proving the IP tier, not the per-login backstop, is
      # what engaged: every probe used a distinct login.
      expect(rl_redis.keys('reset_request:locked:ip:*').size).to eq(1)

      response = request_password_reset(unique_login('sample-2'))
      expect(response.status).to eq(429),
        "Over-cap request must be throttled, got #{response.status}: #{response.body}"
      body     = JSON.parse(response.body)
      expect(body['error_type']).to eq('LimitExceeded')
      expect(body['retry_after']).to be_a(Integer)
      expect(body['max_attempts']).to eq(2)
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
