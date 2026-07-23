# apps/web/auth/spec/integration/full/omniauth_signin_interstitial_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# Issue: #3840 Phase 3 (#3838 item 1b) — sign-in interstitial (password-challenge
#        linking). An UNAUTHENTICATED SSO sign-in whose IdP email matches an
#        EXISTING account that HAS a password no longer dead-ends at the H-3
#        refusal. Instead account_from_omniauth mints a single-use
#        Onetime::SsoLinkChallenge and redirects to the SPA interstitial
#        (/link-sso/:token); the user re-enters their EXISTING password at
#        POST /auth/link-sso, which verifies it, binds (provider, issuer, uid),
#        and establishes the login session via Rodauth's own machinery.
#
#        INVARIANT: email may LOCATE an account; only a demonstrated credential
#        (here, the existing password) may BIND. SSO-only accounts (no password)
#        keep the H-3 refusal unchanged — there is nothing to challenge.
#
# WHAT IT LOCKS IN (production code: config/hooks/omniauth.rb H-3 branch +
#   routes/link_sso.rb + models/sso_link_challenge.rb):
#   a. password-holding existing account -> 302 to /link-sso/:token (NOT
#      account_exists_link_required); a challenge is minted; :omniauth_link_
#      challenge_issued fires.
#   b. GET /auth/link-sso/:token -> { provider, email } (display only).
#   c. POST /auth/link-sso with the CORRECT password -> identity row bound with
#      the right (provider, issuer, uid) on the account, and the user is logged
#      in (Rodauth login response).
#   d. POST with the WRONG password -> refused (invalid_password), NO bind, and
#      the token is CONSUMED (single-use closes the no-lockout password oracle).
#   e. missing/expired/invalid token -> refused (link_expired), no bind.
#   f. SSO-only account (no password) -> UNCHANGED H-3 refusal; no interstitial,
#      no challenge minted.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTHENTICATION_MODE=full, AUTH_DATABASE_URL (SQLite in-memory; rake sets it)
#
# RUN:
#   RACK_ENV=test AUTHENTICATION_MODE=full AUTH_DATABASE_URL=sqlite::memory: \
#     ORGS_SSO_ENABLED=true LANG=en_US.UTF-8 \
#     bundle exec rspec \
#     apps/web/auth/spec/integration/full/omniauth_signin_interstitial_spec.rb \
#     --tag '~postgres_database'
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../support/oauth_flow_helper'

RSpec.describe 'OmniAuth sign-in interstitial (#3840 Phase 3)', type: :integration do
  include Rack::Test::Methods

  def app
    Onetime::Application::Registry.generate_rack_url_map
  end

  before(:all) do
    require 'onetime'
    require 'onetime/application/registry'
    require 'onetime/auth_config'

    Onetime.auth_config.reload! if Onetime.respond_to?(:auth_config) && Onetime.auth_config.respond_to?(:reload!)
    Onetime::Application::Registry.reset! if Onetime::Application::Registry.respond_to?(:reset!)

    Onetime.boot!(:test, force: true)

    Onetime::Application::Registry.prepare_application_registry

    mounts = Onetime::Application::Registry.mount_mappings.keys
    raise "Auth app not mounted post-boot: #{mounts.inspect}" unless mounts.any? { |m| m.include?('/auth') }
  end

  let(:identities) { auth_db[:account_identities] }

  # ==========================================================================
  # Helpers (mirrors omniauth_connect_link_spec.rb)
  # ==========================================================================

  # Leaves session[:validated_omniauth_domain_id] nil == the PLATFORM path, and
  # lets a non-tenant callback proceed on platform credentials instead of
  # redirecting to sso_not_configured.
  def enable_platform_fallback
    allow(Onetime.auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
  end

  # Seed a VERIFIED account WITHOUT a password (SSO-only account).
  def seed_existing_account(email)
    normalized = OT::Utils.normalize_email(email)
    customer   = Onetime::Customer.new(email: normalized)
    customer.save
    auth_db[:accounts].insert(
      email: normalized,
      status_id: AuthTestConstants::STATUS_VERIFIED,
      external_id: customer.extid,
    )
  end

  # Seed a VERIFIED account WITH an Argon2 password hash. Cost params match the
  # test config in config/features/argon2.rb.
  def seed_account_with_password(email, password: AuthTestConstants::TEST_PASSWORD)
    account_id = seed_existing_account(email)
    require 'argon2'
    hasher     = Argon2::Password.new(t_cost: 1, m_cost: 5, p_cost: 1)
    auth_db[:account_password_hashes].insert(id: account_id, password_hash: hasher.create(password))
    account_id
  end

  def setup_mock_auth(email:, uid:, provider: :oidc)
    OmniAuth.config.test_mode               = true
    OmniAuth.config.allowed_request_methods = [:get, :post]
    OmniAuth.config.mock_auth[provider]     = OmniAuth::AuthHash.new(
      {
        provider: provider.to_s,
        uid: uid,
        info: { email: email, name: 'Interstitial User', email_verified: true },
        credentials: { token: 'mock_access_token', expires_at: Time.now.to_i + 3600, expires: true },
        extra: { raw_info: { sub: uid, email: email, name: 'Interstitial User', email_verified: true } },
      },
    )
  end

  def teardown_mock_auth
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.clear
  end

  # Content-Type/Content-Length leak from a prior JSON POST and make the next
  # bodyless request try to parse an empty JSON body. Clear them.
  def clear_body_headers
    header 'Content-Type', nil
    header 'Content-Length', nil
  end

  # Drive the UNAUTHENTICATED SSO callback and return the response. No login and
  # no connect intent — this is the plain sign-in that resolves to an existing
  # account by email.
  def sso_callback(email:, uid:, provider: :oidc)
    setup_mock_auth(email: email, uid: uid, provider: provider)
    clear_body_headers
    post "/auth/sso/#{provider}/callback"
    last_response
  end

  # Extract the challenge token from a /link-sso/:token redirect Location.
  def token_from_location(location)
    location.to_s.split('/link-sso/').last.to_s.split(/[?#]/).first
  end

  # Fetch a CSRF token from the app bootstrap (mirrors csrf_login). The challenge
  # lives in Redis, not the session, so establishing a fresh session here does
  # not disturb it.
  def fetch_csrf_token
    clear_body_headers
    header 'Accept', 'application/json'
    get '/auth'
    last_response.headers['X-CSRF-Token']
  end

  def get_link_context(token)
    clear_body_headers
    header 'Accept', 'application/json'
    get "/auth/link-sso/#{token}"
    last_response
  end

  def post_link_sso(token:, password:)
    csrf = fetch_csrf_token
    clear_body_headers
    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', csrf if csrf
    post '/auth/link-sso', JSON.generate(token: token, password: password)
    last_response
  end

  # Trust off -> an existing account reaches the H-3/interstitial branch rather
  # than being auto-linked by email.
  before do
    enable_platform_fallback
    allow(Onetime.auth_config).to receive(:trust_email_for_linking?).and_return(false)
  end

  # ==========================================================================
  # (a) password-holding account -> interstitial redirect + challenge minted
  # ==========================================================================

  describe 'password-holding existing account' do
    it 'redirects to the interstitial (not the H-3 refusal) and mints a challenge' do
      email = "pw-#{SecureRandom.hex(6)}@company.example.com"
      uid   = "sub-#{SecureRandom.hex(8)}"
      seed_account_with_password(email)

      allow(Auth::Logging).to receive(:log_auth_event).and_call_original

      begin
        response = sso_callback(email: email, uid: uid)
        skip 'OmniAuth route not registered (OIDC discovery not available at boot)' if response.status == 404

        expect(response.status).to eq(302)
        expect(response.location.to_s).not_to include('account_exists_link_required'),
          "Password account must divert to the interstitial. Location: #{response.location.inspect}"
        expect(response.location.to_s).to match(%r{/link-sso/}),
          "Expected a /link-sso/:token redirect. Location: #{response.location.inspect}"

        token = token_from_location(response.location)
        expect(token).not_to be_empty

        # The challenge exists in Redis and snapshots this callback.
        challenge = Onetime::SsoLinkChallenge.load(token)
        expect(challenge).not_to be_nil
        expect(challenge.provider).to eq('oidc')
        expect(challenge.uid).to eq(uid)
        expect(challenge.email).to eq(OT::Utils.normalize_email(email))

        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_link_challenge_issued, hash_including(provider: 'oidc'))
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_link_refused_existing_account, anything)
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # (b) GET /auth/link-sso/:token -> { provider, email }
  # ==========================================================================

  describe 'GET /auth/link-sso/:token' do
    it 'returns the provider and email for display (no secrets)' do
      email = "ctx-#{SecureRandom.hex(6)}@company.example.com"
      uid   = "sub-#{SecureRandom.hex(8)}"
      seed_account_with_password(email)

      begin
        response = sso_callback(email: email, uid: uid)
        skip 'OmniAuth route not registered' if response.status == 404
        token = token_from_location(response.location)

        ctx = get_link_context(token)
        expect(ctx.status).to eq(200)
        body = JSON.parse(ctx.body)
        expect(body['provider']).to eq('oidc')
        expect(body['email']).to eq(OT::Utils.normalize_email(email))
        # Never surface account id, uid, or issuer.
        expect(body).not_to have_key('account_id')
        expect(body).not_to have_key('uid')
        expect(body).not_to have_key('issuer')
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # (c) correct password -> identity bound + logged in
  # ==========================================================================

  describe 'POST /auth/link-sso with the correct password' do
    it 'binds (provider, issuer, uid) to the account and logs the user in' do
      email      = "ok-#{SecureRandom.hex(6)}@company.example.com"
      uid        = "sub-#{SecureRandom.hex(8)}"
      account_id = seed_account_with_password(email)

      begin
        response = sso_callback(email: email, uid: uid)
        skip 'OmniAuth route not registered' if response.status == 404
        token = token_from_location(response.location)

        result = post_link_sso(token: token, password: AuthTestConstants::TEST_PASSWORD)

        expect(result.status).to eq(200),
          "Expected a Rodauth login response, got #{result.status}: #{result.body}"
        body = JSON.parse(result.body)
        expect(body).to have_key('success')

        # The bind: exactly one (provider, uid) row, on the proven account.
        rows = identities.where(provider: 'oidc', uid: uid).all
        expect(rows.size).to eq(1), "Expected one bound row, got #{rows.inspect}"
        expect(rows.first[:account_id]).to eq(account_id)
        expect(rows.first[:issuer]).not_to be_nil

        # The single-use token is consumed on success.
        expect(Onetime::SsoLinkChallenge.load(token)).to be_nil
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # (d) wrong password -> refuse, no bind, token consumed
  # ==========================================================================

  describe 'POST /auth/link-sso with the wrong password' do
    it 'refuses, binds nothing, and consumes the single-use token' do
      email      = "bad-#{SecureRandom.hex(6)}@company.example.com"
      uid        = "sub-#{SecureRandom.hex(8)}"
      account_id = seed_account_with_password(email)

      begin
        response = sso_callback(email: email, uid: uid)
        skip 'OmniAuth route not registered' if response.status == 404
        token = token_from_location(response.location)

        result = post_link_sso(token: token, password: 'wrong-password-entirely')

        expect(result.status).to eq(401)
        body = JSON.parse(result.body)
        expect(body['error_code']).to eq('invalid_password')

        # No identity bound.
        expect(identities.where(account_id: account_id).count).to eq(0)
        expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0)

        # Single-use: the token was consumed up front, so it can't be retried
        # (this is what closes the no-lockout password oracle).
        expect(Onetime::SsoLinkChallenge.load(token)).to be_nil
        expect(get_link_context(token).status).to eq(404)
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # (e) missing/expired/invalid token -> refuse
  # ==========================================================================

  describe 'invalid or expired token' do
    it 'refuses GET for an unknown token' do
      expect(get_link_context("nonexistent-#{SecureRandom.hex(8)}").status).to eq(404)
    end

    it 'refuses POST for an unknown token without binding anything' do
      result = post_link_sso(token: "nonexistent-#{SecureRandom.hex(8)}", password: AuthTestConstants::TEST_PASSWORD)
      expect(result.status).to eq(401)
      expect(JSON.parse(result.body)['error_code']).to eq('link_expired')
    end

    it 'refuses POST when token or password is missing' do
      result = post_link_sso(token: '', password: '')
      expect(result.status).to eq(400)
      expect(JSON.parse(result.body)['error_code']).to eq('invalid_request')
    end
  end

  # ==========================================================================
  # (f) SSO-only account -> UNCHANGED H-3 refusal (no interstitial, no token)
  # ==========================================================================

  describe 'SSO-only account (no password)' do
    it 'keeps the H-3 refusal and does not mint a challenge' do
      email = "ssoonly-#{SecureRandom.hex(6)}@company.example.com"
      uid   = "sub-#{SecureRandom.hex(8)}"
      seed_existing_account(email) # no password

      allow(Auth::Logging).to receive(:log_auth_event).and_call_original

      begin
        response = sso_callback(email: email, uid: uid)
        skip 'OmniAuth route not registered' if response.status == 404

        expect(response.status).to eq(302)
        expect(response.location.to_s).to include('/signin?auth_error=account_exists_link_required'),
          "SSO-only account must keep the H-3 refusal. Location: #{response.location.inspect}"
        expect(response.location.to_s).not_to match(%r{/link-sso/})

        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_link_refused_existing_account, hash_including(provider: 'oidc'))
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_link_challenge_issued, anything)
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # (g) TENANT-surface callback for a password account -> REFUSE (Finding 1)
  # ==========================================================================
  #
  # SECURITY REGRESSION (#3840 Phase 3 adversarial review, Finding 1): an
  # UNAUTHENTICATED TENANT SSO callback whose asserted email matches an existing
  # PASSWORD-HOLDING PLATFORM account must NOT be offered the interstitial. A
  # tenant admin controls their own IdP and can assert ANY email, and
  # before_omniauth_callback_route (omniauth_tenant.rb) stamps
  # session[:validated_omniauth_domain_id] on EVERY tenant callback — so an
  # unauthenticated tenant callback (no login, no connect intent) falls straight
  # through the connect/refuse branches to the email branch with the tenant key
  # SET. Without the platform-surface guard on the mint branch this would mint a
  # challenge and turn the tenant surface into an un-lockable password-guessing
  # oracle against arbitrary platform accounts (a successful guess binding the
  # tenant IdP identity onto the victim). The guard makes it fall through to the
  # UNCHANGED H-3 refusal instead: NO /link-sso redirect, NO challenge, NO
  # :omniauth_link_challenge_issued event.

  describe 'tenant-surface callback for a password account (surface isolation)', :oauth_flow do
    include OAuthFlowHelper

    it 'refuses (H-3) and mints NO challenge — no interstitial oracle on the tenant surface' do
      run_id = "tenant-pw-#{SecureRandom.hex(4)}"
      host   = "secrets-#{run_id}.tenant.example.com"
      email  = "victim-#{run_id}@company.example.com"
      uid    = "sub-#{SecureRandom.hex(8)}"

      # A PLATFORM account that HAS a password (the takeover target the tenant IdP
      # would try to bind onto by asserting this email).
      seed_account_with_password(email)

      # Registered tenant domain so the callback validates and the tenant hook
      # stamps session[:validated_omniauth_domain_id].
      setup_oauth_test_domain(host)

      allow(Auth::Logging).to receive(:log_auth_event).and_call_original
      setup_mock_auth(email: email, uid: uid)

      begin
        # UNAUTHENTICATED initiation from the tenant host (no login, no connect):
        # the request phase stores the tenant domain id in the session so the
        # callback below validates and re-stamps validated_omniauth_domain_id.
        clear_body_headers
        header 'Host', host
        post '/auth/sso/oidc'
        skip "OmniAuth route not registered for #{host}" if last_response.status == 404
        expect(last_response.status).to eq(302)

        # Callback from the SAME tenant host -> validated_omniauth_domain_id is set,
        # so the mint branch's platform-surface guard refuses.
        clear_body_headers
        header 'Host', host
        post '/auth/sso/oidc/callback'

        expect(last_response.status).to eq(302)
        expect(last_response.location.to_s).to include('/signin?auth_error=account_exists_link_required'),
          "Tenant callback for a password account must keep the H-3 refusal, not mint an interstitial. Location: #{last_response.location.inspect}"
        expect(last_response.location.to_s).not_to match(%r{/link-sso/}),
          'The tenant surface must NEVER be offered the password interstitial'

        # No challenge minted; the located account gets no identity row.
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_link_challenge_issued, anything)
        expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0)

        # The UNCHANGED H-3 refusal fired instead.
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_link_refused_existing_account, hash_including(provider: 'oidc'))
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # (h) POST /auth/link-sso is rate limited (Finding 2)
  # ==========================================================================
  #
  # SECURITY (#3840 Phase 3 adversarial review, Finding 2): valid_login_and_password?
  # is a Rodauth INTERNAL request that does NOT increment lockout counters, so
  # single-use tokens cap guesses per token but NOT in aggregate across freshly
  # minted tokens (cheap wherever the IdP does not strongly bind email to a vetted
  # subject). POST /auth/link-sso runs the canonical Onetime::Security::LoginRateLimiter
  # (email + IP) BEFORE consuming the token, so once the located account is locked
  # no further guesses land — while a lone first attempt is unaffected.

  describe 'POST /auth/link-sso rate limiting' do
    # Pre-lock the SAME Redis keys the endpoint checks, independent of whatever
    # client IP the Rack stack resolves: lock the per-email GLOBAL backstop (keyed
    # on email only), which the endpoint's check enforces for any IP. Uses the
    # canonical limiter via #extend (no bespoke throttle, no new constant).
    def lock_login_rate_limit(email)
      limiter = Object.new.extend(Onetime::Security::LoginRateLimiter)
      Onetime::Security::LoginRateLimiter::GLOBAL_MAX_ATTEMPTS.times do
        limiter.record_failed_login_attempt!(email, nil)
      end
    end

    # Mint a challenge directly — the POST throttle can be exercised without a full
    # SSO round-trip, since the token only carries the snapshot the POST reloads.
    def mint_challenge(email:, uid:, account_id:)
      Onetime::SsoLinkChallenge.issue(
        provider: 'oidc',
        issuer: 'https://issuer.example.com',
        uid: uid,
        email: OT::Utils.normalize_email(email),
        account_id: account_id,
      )
    end

    it 'refuses with 429 link_rate_limited once locked; a single attempt is unaffected' do
      email      = "rl-#{SecureRandom.hex(6)}@company.example.com"
      uid        = "sub-#{SecureRandom.hex(8)}"
      account_id = seed_account_with_password(email)
      normalized = OT::Utils.normalize_email(email)

      # A lone wrong-password POST is a normal 401 — the limiter does NOT trip on
      # the first try.
      first  = mint_challenge(email: email, uid: uid, account_id: account_id)
      result = post_link_sso(token: first.token, password: 'wrong-password-entirely')
      expect(result.status).to eq(401)
      expect(JSON.parse(result.body)['error_code']).to eq('invalid_password')

      # Lock the account, then a subsequent POST is refused BEFORE the token is
      # consumed (the throttle precedes single-use deletion).
      lock_login_rate_limit(normalized)
      locked = mint_challenge(email: email, uid: uid, account_id: account_id)
      result = post_link_sso(token: locked.token, password: AuthTestConstants::TEST_PASSWORD)

      expect(result.status).to eq(429),
        "A locked account must be throttled, got #{result.status}: #{result.body}"
      body = JSON.parse(result.body)
      expect(body['error_code']).to eq('link_rate_limited')
      expect(body['retry_after']).to be_a(Integer)

      # No bind happened, and the throttled attempt did NOT consume the token.
      expect(identities.where(account_id: account_id).count).to eq(0)
      expect(Onetime::SsoLinkChallenge.load(locked.token)).not_to be_nil
    end
  end
end
