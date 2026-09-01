# spec/integration/all/colonel_rate_limit_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — rate limiting on the colonel API surface (#4329)
# =============================================================================
#
# FINDING: the rate-limiter registry was perimeter-only (login, feedback, reset,
# signup). Nothing — no middleware, no `limit_action`, no `RateLimit.incr` —
# covered /api/colonel/*. A scripted compromise of a colonel session could purge
# at wire speed and, because the operator audit trail trims at a 10 000-event
# count cap with NO TTL, evict the evidence of its own actions while doing it.
#
# CODE PATH under test, end to end through the real Rack::URLMap:
#
#   ColonelAPI::AuthStrategies::SessionAuthStrategy#build_metadata
#     -> ColonelAPI::Logic::Base#initialize        (colonel:mutation, every verb)
#     -> <verb>#raise_concerns, LAST line          (colonel:destructive, TIER 1)
#     -> GetSessionDetail/DeleteSession            (colonel:handle_resolve)
#     -> Onetime::Security::ColonelRateLimiter     (the Lua CHECK_AND_RECORD)
#     -> Onetime::LimitExceeded -> 429 + Retry-After (RetryAfterHeader)
#
# The unit-level siblings own the pieces this file cannot see: which requests
# are charged and with what subject
# (apps/api/colonel/spec/logic/colonel/rate_limit_hook_spec.rb), the guard-order
# guarantee that a REJECTED destructive attempt costs nothing
# (.../destructive_budget_order_spec.rb), and the limiter body itself — key
# shapes, TTLs, lockout, the single audit write
# (try/unit/security/colonel_rate_limiter_try.rb).
#
# What only THIS file can prove: that the charge survives the whole stack, that
# the 429 reaches the client in the documented shape, and that lockout recovery
# behaves over the wire — POST /ratelimit/reset is a TIER 2 verb that needs no
# elevation, so it stays reachable while locked out, but a colonel may NOT clear
# their OWN colonel_* bucket over HTTP (a leaked cookie could loop out of its own
# lockout); a PEER colonel's reset is what clears it end to end.
#
# spec/config.test.yaml ships site.admin.rate_limit.enabled:false so the colonel
# suites (many endpoints, one process, ONE acting colonel) do not throttle
# themselves; every example here enables the buckets it needs in-process with a
# small cap and restores the config afterwards.
#
# REQUIREMENTS:
# - Valkey running on port 2163: pnpm run test:database:start
#
# RUN:
#   RACK_ENV=test AUTHENTICATION_MODE=simple bundle exec rspec \
#     spec/integration/all/colonel_rate_limit_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require_relative '../integration_spec_helper'
require 'colonel/application'

RSpec.describe 'Colonel API rate limiting (#4329)', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    require 'onetime'
    Onetime.boot! :test
    # Without this, Rack::URLMap has no /api/* entries and every request 404s at
    # the map level — which would look exactly like a limiter denial.
    Onetime::Application::Registry.prepare_application_registry
  end

  # Memoized: repeated generate_rack_url_map calls corrupt middleware state.
  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  # The counters live on the Customer shard (ColonelRateLimiter's own client),
  # which is not necessarily the logical DB the integration helper flushes.
  let(:rl_redis) { Onetime::Customer.dbclient }

  def clear_colonel_limiter_keys
    stale = rl_redis.keys('colonel:*:attempts:*') + rl_redis.keys('colonel:*:locked:*')
    rl_redis.del(*stale) unless stale.empty?
  end

  before do
    @saved_conf = YAML.load(YAML.dump(OT.conf))
    clear_colonel_limiter_keys
  end

  after do
    OT.send(:conf=, @saved_conf) if @saved_conf
    clear_colonel_limiter_keys
  end

  # Enable exactly the buckets an example needs. Anything not named is left
  # DISABLED, so one bucket's 429 can never be mistaken for another's.
  def enable_buckets(**buckets)
    new_conf = YAML.load(YAML.dump(OT.conf))
    admin    = ((new_conf['site'] ||= {})['admin'] ||= {})

    admin['rate_limit'] = { 'enabled' => true }.merge(
      buckets.to_h do |section, settings|
        [section.to_s, { 'enabled' => true, 'window' => 300, 'lockout' => 300 }.merge(
          settings.to_h { |key, value| [key.to_s, value] },
        ),]
      end,
    )
    OT.send(:conf=, new_conf)
  end

  def create_customer(role: 'customer')
    cust          = Onetime::Customer.create!(email: "#{role}-#{SecureRandom.hex(6)}@example.com")
    cust.role     = role
    cust.verified = 'true'
    cust.save
    cust
  end

  let(:colonel) { create_customer(role: 'colonel') }
  let(:target)  { create_customer }

  # Otto's session auth strategy reads env['rack.session']; injecting the hash is
  # the established pattern here (colonel_host_allowlist_spec.rb).
  def signed_in_as(user)
    env 'rack.session', {
      'external_id' => user.extid,
      'authenticated' => true,
      'session_id' => SecureRandom.hex(16),
    }
  end

  # Setup failure must be LOUD: a nil CSRF token draws a 403 from the CSRF
  # middleware and would surface as a misleading status assertion further down.
  def csrf_token
    # Clear the body headers a previous POST left behind, or rack-test sends
    # this GET with a JSON content type and no body and the multipart validator
    # raises on the nil input stream.
    header 'Content-Type', nil
    header 'Content-Length', nil
    header 'X-OTS-Confirm', nil
    header 'Accept', 'application/json'
    get '/api/colonel/info'
    token = last_response.headers['X-CSRF-Token']
    raise "CSRF setup failed: GET /api/colonel/info returned #{last_response.status}" if token.to_s.empty?

    token
  end

  def colonel_get(path)
    header 'Content-Type', nil
    header 'Content-Length', nil
    header 'X-OTS-Confirm', nil
    header 'Accept', 'application/json'
    get path
    last_response
  end

  # POST with the CSRF token the stack just handed us and the #4326 confirmation
  # header. `confirm: nil` sends no header, i.e. an unconfirmed attempt.
  def colonel_post(path, body = {}, confirm: nil)
    token = csrf_token
    header 'Content-Type', 'application/json'
    header 'X-CSRF-Token', token
    header 'X-OTS-Confirm', confirm
    post path, JSON.generate(body.merge(shrimp: token))
    raise "CSRF rejected by the stack (403): #{last_response.body}" if last_response.status == 403 &&
                                                                      last_response.body.to_s == 'Forbidden'

    last_response
  end

  # A TIER 1 verb that is idempotent and needs no per-call fixture: revoking all
  # of a session-less account's sessions succeeds and revokes nothing, so a burst
  # of them isolates the limiter from every other moving part.
  def revoke_all(confirm: target.email)
    colonel_post("/api/colonel/users/#{target.extid}/sessions/revoke-all", {}, confirm: confirm)
  end

  def error_body
    JSON.parse(last_response.body)
  end

  before { signed_in_as(colonel) }

  describe 'the broad colonel:mutation bucket' do
    it 'throttles a burst of mutating requests and reports the documented 429 shape' do
      enable_buckets(mutation: { 'max_attempts' => 3 }, destructive: { 'max_attempts' => 1000 })

      3.times do |i|
        expect(revoke_all.status).to eq(200), "call #{i + 1} should pass: #{last_response.body}"
      end

      response = revoke_all
      expect(response.status).to eq(429), "the over-cap call should be throttled: #{response.body}"
      expect(error_body['error_type']).to eq('LimitExceeded')
      expect(error_body['error']).to match(/Too many admin actions/)
      expect(error_body['max_attempts']).to eq(3)
      expect(error_body['retry_after']).to be_a(Integer)
      # RetryAfterHeader (#3956) turns the body field into the RFC 9110 header
      # for every LimitExceeded, this limiter included.
      expect(response.headers['Retry-After'].to_i).to be_positive
    end

    it 'keys the bucket on the acting colonel PUBLIC extid, never on a session id' do
      enable_buckets(mutation: { 'max_attempts' => 2 }, destructive: { 'max_attempts' => 1000 })

      2.times { revoke_all }
      expect(revoke_all.status).to eq(429)

      # The exact key, not merely "something locked": a session-keyed bucket
      # would put the live bearer credential in a Redis key name (#4330), and a
      # global bucket would let one colonel throttle every other one.
      expect(rl_redis.keys('colonel:mutation:locked:*'))
        .to eq(["colonel:mutation:locked:#{colonel.extid}"])
    end

    # The console fetches several reads on every screen; a limiter there would
    # break the dashboard, so only mutations are charged here.
    it 'never charges an ordinary colonel READ' do
      enable_buckets(mutation: { 'max_attempts' => 1 })

      5.times { expect(colonel_get('/api/colonel/info').status).to eq(200) }
      expect(rl_redis.keys('colonel:mutation:*')).to be_empty
    end
  end

  describe 'the tight colonel:destructive bucket' do
    it 'caps TIER 1 verbs independently of the broad bucket' do
      enable_buckets(destructive: { 'max_attempts' => 3, 'lockout' => 900 })

      3.times do |i|
        expect(revoke_all.status).to eq(200), "call #{i + 1} should pass: #{last_response.body}"
      end

      response = revoke_all
      expect(response.status).to eq(429)
      expect(error_body['error']).to match(/Too many destructive admin actions/)
      expect(error_body['max_attempts']).to eq(3)
      expect(response.headers['Retry-After'].to_i).to be_positive
    end

    # The M-1 guarantee, over the wire: the charge is the LAST line of
    # raise_concerns, so an attempt refused for a missing/wrong confirmation
    # consumes nothing. Otherwise anyone holding the cookie could impose a
    # 15-minute destructive lockout on the operator with cheap 403s.
    it 'does not charge a request the confirmation gate refused' do
      enable_buckets(destructive: { 'max_attempts' => 2 })

      3.times do
        expect(revoke_all(confirm: nil).status).to eq(403)
      end
      expect(error_body['error_code']).to eq('confirmation_required')
      expect(rl_redis.keys('colonel:destructive:*')).to be_empty

      # The budget is intact: two real actions still land.
      2.times { expect(revoke_all.status).to eq(200) }
      expect(revoke_all.status).to eq(429)
    end

    # SELF-RESET IS REFUSED (#4329 review). POST /ratelimit/reset is TIER 2 —
    # confirmation but no step-up — so it stays reachable while locked out, but a
    # colonel may NOT clear their OWN colonel_* bucket over HTTP: a leaked cookie
    # could otherwise reset its own lockout in a loop and defeat the bucket. The
    # confirmation token here (kind:subject) is caller-supplied and proves nothing,
    # so the interlock — not the token — is what stops the loop. Recovery of one's
    # own lockout is CLI-only; a peer colonel over HTTP is the other path (below).
    it 'refuses a colonel clearing their OWN colonel_destructive bucket, and the lockout holds' do
      enable_buckets(destructive: { 'max_attempts' => 2 })

      2.times { revoke_all }
      expect(revoke_all.status).to eq(429)

      reset = colonel_post(
        '/api/colonel/ratelimit/reset',
        { kind: 'colonel_destructive', subject: colonel.extid },
        confirm: "colonel_destructive:#{colonel.extid}",
      )
      expect(reset.status).to eq(422), "self-reset must be refused: #{reset.body}"
      expect(error_body['error']).to match(/clear your own colonel rate limiter/i)

      # The lockout is untouched: the operator is still throttled.
      expect(revoke_all.status).to eq(429),
        "the refused self-reset must not have cleared the bucket: #{last_response.body}"
    end

    # PEER RECOVERY, end to end. A SECOND colonel can clear the locked-out
    # colonel's destructive bucket — the operator-recovery case the self-reset
    # refusal deliberately leaves open — and the reset does clear the bucket.
    it 'lets a PEER colonel clear the locked-out colonel destructive bucket' do
      enable_buckets(destructive: { 'max_attempts' => 2 })

      2.times { revoke_all }
      expect(revoke_all.status).to eq(429)

      peer = create_customer(role: 'colonel')
      signed_in_as(peer)
      reset = colonel_post(
        '/api/colonel/ratelimit/reset',
        { kind: 'colonel_destructive', subject: colonel.extid },
        confirm: "colonel_destructive:#{colonel.extid}",
      )
      expect(reset.status).to eq(200), "a peer reset should be reachable: #{reset.body}"
      expect(JSON.parse(reset.body).dig('record', 'cleared')).to be true

      # Back as the freed colonel: the bucket is clear, so the operator can act.
      signed_in_as(colonel)
      expect(revoke_all.status).to eq(200), "the operator should be able to act again: #{last_response.body}"
    end
  end

  describe 'the colonel:handle_resolve bucket' do
    # The one exception to "colonel reads are never limited": resolving an
    # opaque session handle can fall back to a bounded 10 000-key SCAN plus as
    # many HMACs (#4330).
    it 'caps session-handle lookups, including the ones that 404' do
      enable_buckets(handle_resolve: { 'max_attempts' => 3 })
      handle = '0123456789abcdef0123456789abcdef'

      3.times do |i|
        expect(colonel_get("/api/colonel/sessions/#{handle}").status).to eq(404),
          "lookup #{i + 1} should reach the resolver: #{last_response.body}"
      end

      response = colonel_get("/api/colonel/sessions/#{handle}")
      expect(response.status).to eq(429)
      expect(error_body['error']).to match(/Too many session lookups/)
      expect(error_body['max_attempts']).to eq(3)
    end

    it 'leaves every other colonel read unthrottled' do
      enable_buckets(handle_resolve: { 'max_attempts' => 1 })
      handle = '0123456789abcdef0123456789abcdef'

      colonel_get("/api/colonel/sessions/#{handle}")
      expect(colonel_get("/api/colonel/sessions/#{handle}").status).to eq(429)

      expect(colonel_get('/api/colonel/info').status).to eq(200)
      expect(colonel_get('/api/colonel/sessions').status).to eq(200)
    end
  end

  describe 'when the limiters are disabled' do
    it 'writes no keys and never throttles (the spec/config.test.yaml posture)' do
      # The parent flag off, every bucket nominally on: this is what the rest of
      # the colonel suite relies on to avoid throttling itself.
      new_conf = YAML.load(YAML.dump(OT.conf))
      admin    = ((new_conf['site'] ||= {})['admin'] ||= {})
      admin['rate_limit'] = {
        'enabled' => false,
        'mutation' => { 'enabled' => true, 'max_attempts' => 1 },
        'destructive' => { 'enabled' => true, 'max_attempts' => 1 },
        'handle_resolve' => { 'enabled' => true, 'max_attempts' => 1 },
      }
      OT.send(:conf=, new_conf)

      4.times { expect(revoke_all.status).to eq(200) }
      expect(rl_redis.keys('colonel:*')).to be_empty
    end
  end
end
