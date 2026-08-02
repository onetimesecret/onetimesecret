# apps/web/auth/spec/integration/full/create_account_rate_limit_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — account-creation rate limiting in FULL mode (#3948)
# =============================================================================
#
# Covers the FULL-mode half of finding #4 of the 2026-07-30 audit. In full mode
# the Auth app is mounted at /auth (apps/web/auth/application.rb) and
# Rack::URLMap dispatches longest-prefix-first, so POST /auth/create-account is
# served by Rodauth's create_account route — the simple-mode logic class
# (AccountAPI::Logic::Account::CreateAccount, where the sibling spec's limiter
# call lives) is never instantiated. Full mode is what production runs, so this
# is the path that has to be throttled for the finding to be closed at all.
#
# The before_create_account_route hook (config/hooks/create_account.rb) enforces
# Onetime::Security::CreateAccountRateLimiter at the top of the route: ahead of
# the POST body, ahead of the db[:accounts] lookup and
# Onetime::Customer.email_exists? check in before_create_account, and ahead of
# the account INSERT.
#
# These tests assert the four properties that distinguish a correct
# implementation from one that merely returns 429 somewhere:
#
#   1. the cap bites across DISTINCT submitted addresses (only an IP-keyed tier
#      can do that — every request in the abuse pattern carries a fresh
#      address);
#   2. the key written is exactly create_account:locked:ip:<masked-ip> — the
#      privacy-masked address IPPrivacyMiddleware resolved, never a raw
#      REMOTE_ADDR and never a global bucket that one caller could use to shut
#      off signup deployment-wide;
#   3. a throttled request creates NO accounts row and NO Customer, which is
#      the datastore-growth half of the finding;
#   4. the invite-signup path — Auth::Config.create_account via
#      :internal_request — is NOT charged budget, even when an IP is present in
#      the synthesized env. It is already throttled by InviteTokenRateLimiter
#      and is not the unauthenticated-flood primitive this bounds.
#
# Sibling coverage: spec/integration/simple/create_account_rate_limit_spec.rb
# (same limiter, simple-mode call site) and
# try/unit/security/create_account_rate_limiter_try.rb (unit, including the
# audit-write bound and the collapsed-IP operator hint).
#
# The suite-wide test config ships the limiter DISABLED (spec/config.test.yaml)
# so other full-mode specs are not throttled; each example here enables it
# in-process with small caps and restores the config after.
#
# REQUIREMENTS:
# - Valkey running on port 2163: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   RACK_ENV=test AUTHENTICATION_MODE=full AUTH_DATABASE_URL='sqlite::memory:' \
#     ORGS_SSO_ENABLED=true bundle exec rspec \
#     apps/web/auth/spec/integration/full/create_account_rate_limit_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require 'rack/test'

RSpec.describe 'Account-creation rate limiting — full mode (#3948 finding #4)', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    # Boot the full app so the REAL Auth::Config — with the rate-limit hook
    # wired in via config/hooks/create_account.rb — is loaded and mounted at
    # /auth.
    boot_onetime_app
  end

  before do
    unless defined?(Auth::Database) && Auth::Database.connection
      skip 'Auth database not configured (run with AUTH_DATABASE_URL set)'
    end

    # Isolate from real delivery: an allowed signup dispatches a welcome /
    # verification email. Everything upstream still runs for real.
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw).and_return(true)

    @saved_conf     = YAML.load(YAML.dump(OT.conf))
    @created_emails = []
    clear_limiter_keys
  end

  after do
    OT.send(:conf=, @saved_conf) if @saved_conf
    clear_limiter_keys

    Array(@created_emails).each do |email|
      purge_account(email)
      Onetime::Customer.find_by_email(email)&.destroy!
    rescue StandardError => e
      warn "[create-account limiter spec] cleanup failed for #{email}: #{e.message}"
    end
  end

  # Delete an accounts row and everything that references it. The allowed
  # signups here are REAL account creations, so the row has children (password
  # hash, verification key, audit log, ...) and a bare delete trips the FK
  # constraint. The child set differs between the SQLite and PostgreSQL
  # migration lanes, so it is discovered from the schema rather than hardcoded.
  def purge_account(email)
    db  = Auth::Database.connection
    row = db[:accounts].where(email: email).first
    return unless row

    db.tables.each do |table|
      next if table == :accounts

      db.foreign_key_list(table).each do |fk|
        next unless fk[:table].to_s == 'accounts'

        db[table].where(fk[:columns].first => row[:id]).delete
      end
    rescue Sequel::Error
      next
    end

    db[:accounts].where(id: row[:id]).delete
  end

  # The counters live on the Customer shard (see
  # CreateAccountRateLimiter#create_account_redis), which is not necessarily the
  # logical DB the suite helpers flush.
  let(:rl_redis) { Onetime::Customer.dbclient }

  def clear_limiter_keys
    stale = rl_redis.keys('create_account:attempts:*') +
            rl_redis.keys('create_account:locked:*')
    rl_redis.del(*stale) unless stale.empty?
  end

  # Enable the limiter in-process with an example-specific cap
  # (spec/config.test.yaml ships it disabled). Restored from @saved_conf above.
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

  # Fresh session + CSRF token per request: an attacker is not obliged to reuse
  # a session, so the limiter must bite regardless of session identity. `from:`
  # drives REMOTE_ADDR; IPPrivacyMiddleware resolves and masks it into
  # env['otto.client_ip'], which is what the limiter keys on.
  #
  # login-confirm and password-confirm are both required by this deploy's
  # Rodauth config; omitting either turns every under-cap signup into a 422 that
  # writes no account row, which would make the "nothing is written for a
  # throttled request" assertions below pass vacuously. Sending them keeps the
  # allowed path a REAL account creation.
  def post_signup(login, from:, password: 'TestPassword123!')
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
    post '/auth/create-account',
      JSON.generate(
        login: login,
        'login-confirm' => login,
        password: password,
        'password-confirm' => password,
        shrimp: token,
      ),
      rack_env
    last_response
  end

  # The /24 (IPv4) mask IPPrivacyMiddleware applies before the app sees the
  # address — the bucket is that masked network, never the raw source.
  def masked(ip)
    "#{ip.split('.').first(3).join('.')}.0"
  end

  it 'runs the full-mode path (the Auth app owns /auth/create-account)' do
    expect(Onetime.auth_config.full_enabled?).to be true
    expect(Onetime::Application::Registry.mount_mappings.key?('/auth')).to be true
    # The hook, not the logic class, is what can possibly be enforcing here:
    # the limiter module is mixed into the Rodauth class, and OUR block is what
    # `_before_create_account_route` compiles to.
    #
    # Assert the source_location, not merely that the method is defined:
    # Rodauth's `before` definer class_evals a `def _before_create_account_route;
    # nil end` stub for every class carrying the :create_account feature
    # (rodauth-2.44.0/lib/rodauth.rb:257), so `private_method_defined?` is true
    # whether or not we registered anything. The file the method actually came
    # from is the part that discriminates.
    expect(Auth::Config.ancestors).to include(Onetime::Security::CreateAccountRateLimiter)
    hook_source = Auth::Config.instance_method(:_before_create_account_route).source_location&.first
    expect(hook_source).to end_with('apps/web/auth/config/hooks/create_account.rb')
  end

  describe 'per-IP cap' do
    let(:source_a) { '203.0.113.10' }
    let(:source_b) { '198.51.100.20' }

    it 'caps signup volume from one source across DIFFERENT addresses (the abuse pattern)' do
      enable_limiter(max_per_ip: 2)

      2.times do |i|
        email    = unique_test_email("burst-#{i}")
        @created_emails << email
        response = post_signup(email, from: source_a)
        expect(response.status).to eq(200),
          "Under-cap signup #{i + 1} should pass, got #{response.status}: #{response.body}"
      end

      # Assert the EXACT key, not merely that something locked. A constant or
      # global bucket and a raw-REMOTE_ADDR key would both satisfy a glob count;
      # this pins the subject to the privacy-masked address the middleware
      # resolved. Every signup above used a distinct address, so only an
      # IP-keyed tier can be what engaged.
      expect(rl_redis.keys('create_account:locked:ip:*'))
        .to eq(["create_account:locked:ip:#{masked(source_a)}"])

      response = post_signup(unique_test_email('burst-over'), from: source_a)
      expect(response.status).to eq(429),
        "Over-cap signup must be throttled, got #{response.status}: #{response.body}"
      body = JSON.parse(response.body)
      expect(body['error_type']).to eq('LimitExceeded')
      expect(body['retry_after']).to be_a(Integer)
      expect(body['max_attempts']).to eq(2)

      # The delay must also reach the HTTP header proxies and clients actually
      # read (RFC 9110 §10.2.3). Set by Onetime::Middleware::RetryAfterHeader
      # from the value the Roda error handler stashes via ErrorCorrelation — the
      # same mechanism the simple-mode Otto stack uses, so the two modes cannot
      # drift.
      expect(response.headers['retry-after']).to eq(body['retry_after'].to_s)
    end

    it 'isolates sources: one locked-out network does not throttle another' do
      enable_limiter(max_per_ip: 1)

      first = unique_test_email('iso-a')
      @created_emails << first
      post_signup(first, from: source_a)

      expect(post_signup(unique_test_email('iso-a-over'), from: source_a).status).to eq(429)

      second   = unique_test_email('iso-b')
      @created_emails << second
      response = post_signup(second, from: source_b)
      expect(response.status).to eq(200),
        "A different source must be unaffected, got #{response.status}: #{response.body}"
    end
  end

  describe 'ordering: nothing is written for a throttled request' do
    let(:source) { '192.0.2.30' }

    it 'creates NO accounts row and NO Customer for a throttled signup' do
      enable_limiter(max_per_ip: 1)

      first = unique_test_email('order')
      @created_emails << first
      # The allowed sibling proves the route really does write on this path, so
      # the absences asserted below are the limiter's doing and not a signup
      # that would have failed anyway.
      expect(post_signup(first, from: source).status).to eq(200)
      expect(Auth::Database.connection[:accounts].where(email: first).first).not_to be_nil

      blocked = unique_test_email('order-blocked')
      @created_emails << blocked
      response = post_signup(blocked, from: source)
      expect(response.status).to eq(429)

      # The datastore-growth half of the finding: a limiter wired after the
      # INSERT would leave the row behind despite the 429.
      #
      # This does NOT discriminate route-hook placement from before_create_account
      # placement — that hook also runs before save_account, so a limiter there
      # would likewise leave no row. What the route hook additionally buys is
      # running ahead of the ACCOUNT LOOKUP (hooks/account.rb's db[:accounts]
      # query and Customer.email_exists?), which is asserted separately below.
      expect(Auth::Database.connection[:accounts].where(email: blocked).first).to be_nil
      expect(Onetime::Customer.find_by_email(blocked)).to be_nil
    end

    it 'never reaches the account lookup for a throttled signup' do
      enable_limiter(max_per_ip: 1)

      # This is what route-hook placement buys over before_create_account, which
      # would also leave no row behind: a throttled probe never executes the
      # existence check at all (hooks/account.rb queries db[:accounts] and then
      # Onetime::Customer.email_exists?). On a route whose response contract is
      # that new and existing addresses answer identically, not running the
      # lookup is the strongest form of that guarantee.
      # Counted rather than asserted with have_received(:once): an allowed
      # signup calls email_exists? several times (the hook check, then customer
      # provisioning downstream), so the meaningful assertion is that a
      # throttled request adds ZERO calls, not that the total is any one number.
      lookups = 0
      allow(Onetime::Customer).to receive(:email_exists?).and_wrap_original do |orig, *args, &blk|
        lookups += 1
        orig.call(*args, &blk)
      end

      first = unique_test_email('lookup')
      @created_emails << first
      expect(post_signup(first, from: source).status).to eq(200)

      # The allowed sibling pins the spy to a call site that really is on this
      # path — without it, the assertion below would hold for a typo'd method
      # name just as well.
      baseline = lookups
      expect(baseline).to be_positive

      expect(post_signup(unique_test_email('lookup-blocked'), from: source).status).to eq(429)
      expect(lookups).to eq(baseline)
    end

    it 'never writes a key derived from the submitted address' do
      enable_limiter(max_per_ip: 3)

      email = unique_test_email('nokey')
      @created_emails << email
      post_signup(email, from: source)

      # An address-keyed bucket would be an enumeration oracle on a route whose
      # contract is that existing and new accounts respond identically.
      local_part = email.split('@').first
      expect(rl_redis.keys('create_account:*').grep(/#{Regexp.escape(local_part)}|@/)).to be_empty
    end
  end

  describe 'internal requests (the invite-signup path)' do
    let(:test_suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }
    let(:owner_email) { "invite_owner_#{test_suffix}@onetimesecret.com" }
    let(:invited_email) { "invitee_#{test_suffix}@onetimesecret.com" }

    let(:owner) { Onetime::Customer.create!(email: owner_email, role: 'customer') }
    let(:organization) do
      Onetime::Organization.create!(
        "Create-Account Limiter Org #{test_suffix}",
        owner,
        owner_email,
        is_default: true,
      )
    end
    let(:invitation) do
      Onetime::OrganizationMembership.create_invitation!(
        organization: organization,
        email: invited_email,
        inviter: owner,
        role: 'member',
      )
    end

    after do
      Auth::Database.connection[:accounts].where(email: invited_email).delete
      invitation&.destroy_with_index_cleanup!
      organization&.destroy!
      owner&.destroy!
      Onetime::Customer.find_by_email(invited_email)&.destroy!
    rescue StandardError
      # Non-fatal cleanup error
    end

    # handle_internal_request runs the SAME route block with a synthesized env
    # whose REQUEST_METHOD is 'POST', so a bare request.post? guard would charge
    # invite signups against a signup bucket. The env here deliberately carries
    # a resolvable client IP: without one the limiter would no-op via
    # create_account_ip_keys returning nil, and this example would pass on an
    # accident of the synthesized env rather than on the internal_request? guard
    # actually being there.
    it 'does not charge budget for Auth::Config.create_account, even with a client IP in env' do
      enable_limiter(max_per_ip: 1)
      expect(invitation.pending?).to be(true)

      Auth::Config.create_account(
        login: invited_email,
        password: 'TestPassword123!',
        params: { 'invite_token' => invitation.token },
        env: { 'otto.client_ip' => '203.0.113.77', 'REMOTE_ADDR' => '203.0.113.77' },
      )

      # The invite signup still works (the guard skips the limiter, it does not
      # abort the route)...
      expect(Auth::Database.connection[:accounts].where(email: invited_email).first).not_to be_nil

      # ...and consumed no budget at all: neither an attempts counter nor a
      # lockout flag exists for that IP, so the very first HTTP signup from it
      # is still allowed.
      expect(rl_redis.keys('create_account:*')).to be_empty
    end
  end

  describe 'suite default (limiter disabled by test config)' do
    it 'does not throttle when site.authentication.create_account_rate_limit is disabled' do
      # No enable_limiter call: this runs under spec/config.test.yaml, which
      # ships enabled:false — repeated signups write no limiter keys.
      3.times do |i|
        email    = unique_test_email("off-#{i}")
        @created_emails << email
        response = post_signup(email, from: '198.51.100.77')
        expect(response.status).to eq(200),
          "Signup #{i + 1} should pass with the limiter off, got #{response.status}: #{response.body}"
      end

      expect(rl_redis.keys('create_account:attempts:*')).to be_empty
      expect(rl_redis.keys('create_account:locked:*')).to be_empty
    end
  end
end
