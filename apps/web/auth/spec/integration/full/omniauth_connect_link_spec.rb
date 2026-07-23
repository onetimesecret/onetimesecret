# apps/web/auth/spec/integration/full/omniauth_connect_link_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# Issue: #3840 Phase 2 — authenticated identity connect ("connect SSO from
#        account settings"). Binding requires TWO signals: an ACTIVE
#        AUTHENTICATED SESSION *and* an account-bound CONNECT INTENT set at
#        initiation (the panel POSTs connect=1, captured by
#        omniauth_request_validation_phase into session[:sso_connect_intent]).
#        logged_in? alone is NOT enough — that would let a second-tab / shared-
#        browser sign-in silently bind the arriving identity to the session
#        account. The IdP email plays NO role: we bind to the LOGGED-IN account,
#        never to an email-located one (email matching is the pre-account-
#        hijacking anti-pattern).
#
# WHY THIS FILE EXISTS:
#   The authenticated-bind branch in account_from_omniauth
#   (apps/web/auth/config/hooks/omniauth.rb) can only be validated end-to-end:
#   it depends on rodauth.logged_in? being true AND a matching connect-intent
#   nonce being present DURING the omniauth callback, and on the gem's
#   create_omniauth_identity upserting the row onto the already-authenticated
#   (session) account. This file drives the REAL Rodauth request+callback
#   through the Rack stack (a password login establishes the session, then a
#   connect=1 request phase sets the intent) and asserts the persisted side
#   effects — the account_identities row, the redirect, the audit event — that
#   only the production machinery produces.
#
# WHAT IT LOCKS IN (production code: apps/web/auth/config/hooks/omniauth.rb):
#   1. logged-in + connect intent on the PLATFORM surface
#        -> account_from_omniauth returns the SESSION account, the gem persists
#           the (provider, issuer, uid) row bound to it, and the
#           :omniauth_identity_connected warn event fires. No refusal.
#   2. logged-in + connect intent, IdP asserts a DIFFERENT account's email
#        -> binds to the SESSION account anyway; the other (victim) account gets
#           NO row and is untouched; no duplicate account. :omniauth_identity_
#           connected fires with the SESSION account_id. Proves email is ignored.
#   2b. logged-in but NO connect intent (second-tab / shared-browser sign-in)
#        -> treated as unauthenticated: falls through to H-3, session account
#           gets NO row, :omniauth_identity_connected never fires. The P1 fix.
#   3. UNAUTHENTICATED + existing account (trust off)
#        -> unchanged H-3 refusal. Proves the branch is gated on session+intent
#           (:omniauth_identity_connected never fires when not logged in).
#   4. logged-in + connect intent on the PLATFORM surface + TENANT callback
#        -> REFUSED (surface isolation): a tenant callback must not bind a
#           tenant-issuer identity onto a platform session. Reason tenant_surface.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTHENTICATION_MODE=full, AUTH_DATABASE_URL (SQLite in-memory; rake sets it)
#
# RUN:
#   RACK_ENV=test AUTHENTICATION_MODE=full AUTH_DATABASE_URL=sqlite::memory: \
#     ORGS_SSO_ENABLED=true LANG=en_US.UTF-8 \
#     bundle exec rspec apps/web/auth/spec/integration/full/omniauth_connect_link_spec.rb \
#     --tag '~postgres_database'
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../support/oauth_flow_helper'

RSpec.describe 'OmniAuth authenticated identity connect (#3840 Phase 2)', type: :integration do
  include Rack::Test::Methods

  # Password is AuthTestConstants::TEST_PASSWORD (shared across spec files so a
  # top-level constant isn't redefined when both specs load in one process).

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
  # Helpers
  # ==========================================================================

  # Leaves session[:validated_omniauth_domain_id] nil == the PLATFORM path.
  def enable_platform_fallback
    allow(Onetime.auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
  end

  # Seed a VERIFIED account WITHOUT a password (SSO-only / victim account).
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

  # Seed a VERIFIED account WITH an Argon2 password hash so csrf_login can
  # establish a real authenticated session for it. Cost params match the test
  # config in config/features/argon2.rb.
  def seed_account_with_password(email, password: AuthTestConstants::TEST_PASSWORD)
    account_id = seed_existing_account(email)
    require 'argon2'
    hasher     = Argon2::Password.new(t_cost: 1, m_cost: 5, p_cost: 1)
    auth_db[:account_password_hashes].insert(id: account_id, password_hash: hasher.create(password))
    account_id
  end

  # Establish a session, fetch the CSRF token, then POST a JSON login. The full
  # Rack app enforces CSRF, so the shrimp token is required.
  def csrf_login(email, password: AuthTestConstants::TEST_PASSWORD)
    clear_body_headers
    header 'Accept', 'application/json'
    get '/auth'
    token = last_response.headers['X-CSRF-Token']

    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', token if token
    post '/auth/login', JSON.generate(login: email, password: password, shrimp: token)
    token
  end

  # Content-Type/Content-Length leak from a prior JSON POST and make the next
  # bodyless callback POST try to parse an empty JSON body. Clear them.
  def clear_body_headers
    header 'Content-Type', nil
    header 'Content-Length', nil
  end

  def setup_mock_auth(email:, uid:, provider: :oidc)
    OmniAuth.config.test_mode               = true
    OmniAuth.config.allowed_request_methods = [:get, :post]
    OmniAuth.config.mock_auth[provider]     = OmniAuth::AuthHash.new(
      {
        provider: provider.to_s,
        uid: uid,
        info: { email: email, name: 'Connect User', email_verified: true },
        credentials: { token: 'mock_access_token', expires_at: Time.now.to_i + 3600, expires: true },
        extra: { raw_info: { sub: uid, email: email, name: 'Connect User', email_verified: true } },
      },
    )
  end

  def teardown_mock_auth
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.clear
  end

  # Run the SSO REQUEST phase carrying the connect-intent signal (connect=1),
  # exactly as the Connected Identities panel does at initiation. In OmniAuth
  # test mode this triggers omniauth_request_validation_phase, which — when the
  # caller is logged in — stashes session[:sso_connect_intent] = <session
  # account id> in the session cookie. The subsequent callback consumes it and,
  # only then, takes the bind branch. Cookie sessions can't be poked directly
  # (see oauth_flow_helper#inject_oauth_session), so this real initiation is how
  # the intent is threaded. Returns the request-phase status so callers can skip
  # when the provider route isn't registered (404).
  def initiate_sso_connect(provider: :oidc, host: nil)
    clear_body_headers
    header 'Host', host if host
    post "/auth/sso/#{provider}", { connect: '1' }
    last_response.status
  end

  # ==========================================================================
  # Scenario 1 — logged-in on the platform surface -> bind to session account
  # ==========================================================================

  describe 'logged-in on the platform surface' do
    before { enable_platform_fallback }

    it 'binds the new IdP identity to the session account and fires the connect event' do
      email      = "connect-#{SecureRandom.hex(6)}@company.example.com"
      uid        = "sub-#{SecureRandom.hex(8)}"
      account_id = seed_account_with_password(email)

      # Establish the credential: an authenticated session for THIS account.
      csrf_login(email)
      expect(last_response.status).to be_between(200, 302),
        "Precondition failed: password login did not succeed (#{last_response.status}: #{last_response.body})"

      allow(Auth::Logging).to receive(:log_auth_event).and_call_original
      setup_mock_auth(email: email, uid: uid)
      begin
        # Establish account-bound connect intent via the real initiation POST
        # (connect=1). Without it the bind branch is not taken (see the no-intent
        # scenario below) — the intent nonce is now REQUIRED to bind.
        skip 'OmniAuth route not registered (OIDC discovery not available at boot)' if initiate_sso_connect == 404

        clear_body_headers
        post '/auth/sso/oidc/callback'

        skip 'OmniAuth route not registered (OIDC discovery not available at boot)' if last_response.status == 404

        expect(last_response.location.to_s).not_to include('identity_connect_conflict'),
          "Self-bind must NOT refuse. Location: #{last_response.location.inspect}"
        expect(last_response.location.to_s).not_to include('account_exists_link_required'),
          "Self-bind must NOT hit the H-3 refusal. Location: #{last_response.location.inspect}"
        expect(last_response.status).to eq(302),
          "Expected a post-login redirect, got #{last_response.status}: #{last_response.body}"

        # The bind: exactly one (provider, uid) row, bound to the session account.
        rows = identities.where(provider: 'oidc', uid: uid).all
        expect(rows.size).to eq(1),
          "Expected exactly one bound identity row, got #{rows.size}: #{rows.inspect}"
        expect(rows.first[:account_id]).to eq(account_id),
          'Bound identity must attach to the already-authenticated account'
        # Issuer was resolved and persisted (Phase 0 column, never NULL).
        expect(rows.first[:issuer]).not_to be_nil

        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_identity_connected, hash_including(provider: 'oidc', account_id: account_id))
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_identity_connect_refused, anything)
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # Scenario 2 — logged-in, IdP asserts a DIFFERENT account's email
  #              -> bind to the SESSION account; the victim is untouched
  # ==========================================================================
  #
  # The security property: email plays NO role. The session is the
  # authorization, so an IdP that lies about the email (emitting a victim's
  # address to try to reach the victim's account) still only binds to the
  # ACTOR's own session account. The victim gets no row and is never routed to.

  describe 'logged-in, IdP asserts a different account email (email is ignored)' do
    before { enable_platform_fallback }

    it 'binds to the session account and leaves the other account untouched' do
      actor_email  = "actor-#{SecureRandom.hex(6)}@company.example.com"
      victim_email = "victim-#{SecureRandom.hex(6)}@company.example.com"
      uid          = "sub-#{SecureRandom.hex(8)}"

      actor_id        = seed_account_with_password(actor_email)
      victim_id       = seed_existing_account(victim_email)
      accounts_before = auth_db[:accounts].count

      # Logged in as the ACTOR, but the IdP asserts the VICTIM's email.
      csrf_login(actor_email)
      expect(last_response.status).to be_between(200, 302)

      allow(Auth::Logging).to receive(:log_auth_event).and_call_original
      setup_mock_auth(email: victim_email, uid: uid)
      begin
        # Intent is established by the ACTOR (its session) at initiation; the IdP
        # later asserting the victim's email cannot change which account the
        # intent is bound to.
        skip 'OmniAuth route not registered' if initiate_sso_connect == 404

        clear_body_headers
        post '/auth/sso/oidc/callback'

        skip 'OmniAuth route not registered' if last_response.status == 404

        expect(last_response.location.to_s).not_to include('identity_connect_conflict'),
          "Authenticated connect must NOT refuse. Location: #{last_response.location.inspect}"
        expect(last_response.status).to eq(302),
          "Expected a post-login redirect, got #{last_response.status}: #{last_response.body}"

        # The bind attaches to the ACTOR's session account, NOT the victim whose
        # email the IdP asserted.
        rows = identities.where(provider: 'oidc', uid: uid).all
        expect(rows.size).to eq(1),
          "Expected exactly one bound identity row, got #{rows.size}: #{rows.inspect}"
        expect(rows.first[:account_id]).to eq(actor_id),
          'Bound identity must attach to the authenticated (session) account'

        # The victim account is untouched — no row, no hijack.
        expect(identities.where(account_id: victim_id).count).to eq(0),
          'No identity may be bound to the account whose email the IdP asserted'
        # No duplicate account created.
        expect(auth_db[:accounts].count).to eq(accounts_before),
          'Connect must NOT create a duplicate account'

        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_identity_connected, hash_including(provider: 'oidc', account_id: actor_id))
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_identity_connect_refused, anything)
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # Scenario 2b — logged-in but NO connect intent -> must NOT bind (the P1 fix)
  # ==========================================================================
  #
  # The core security property added in this PR: logged_in? alone is NOT connect
  # intent. A plain SSO sign-in arriving on an already-authenticated session
  # (second tab, shared browser) must be treated exactly like an unauthenticated
  # caller — it must NEVER silently bind the arriving IdP identity to the session
  # account. Here the IdP asserts a DIFFERENT existing account's email (trust
  # off), so the fall-through lands on the H-3 refusal; the session account is
  # left with no row.

  describe 'logged-in but WITHOUT connect intent (must not bind)' do
    before { enable_platform_fallback }

    it 'does not bind onto the session account and falls through to the H-3 refusal' do
      actor_email = "actor-nointent-#{SecureRandom.hex(6)}@company.example.com"
      other_email = "other-#{SecureRandom.hex(6)}@company.example.com"
      uid         = "sub-#{SecureRandom.hex(8)}"

      actor_id = seed_account_with_password(actor_email)
      seed_existing_account(other_email) # a DIFFERENT existing account

      csrf_login(actor_email)
      expect(last_response.status).to be_between(200, 302)

      # Trust off -> the email branch for an existing account is the H-3 refusal.
      allow(Onetime.auth_config).to receive(:trust_email_for_linking?).and_return(false)
      allow(Auth::Logging).to receive(:log_auth_event).and_call_original

      setup_mock_auth(email: other_email, uid: uid)
      begin
        # DELIBERATELY skip initiate_sso_connect: this is the second-tab / shared
        # browser case — a callback arrives on the authenticated session with NO
        # account-bound connect intent. It must be handled as unauthenticated.
        clear_body_headers
        post '/auth/sso/oidc/callback'

        skip 'OmniAuth route not registered' if last_response.status == 404

        expect(last_response.status).to eq(302)
        expect(last_response.location.to_s).to include('/signin?auth_error=account_exists_link_required'),
          "No-intent callback must fall through to H-3, not bind. Location: #{last_response.location.inspect}"

        # THE CRUX: the arriving identity did NOT attach to the session account.
        expect(identities.where(account_id: actor_id).count).to eq(0),
          'A plain sign-in without connect intent must NOT bind onto the session account'
        # And no identity row exists at all (H-3 refuses to create one).
        expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0)

        # The connect event never fires; the intent-absent + H-3 events do.
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_identity_connected, anything)
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_connect_intent_absent, hash_including(provider: 'oidc'))
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_link_refused_existing_account, hash_including(provider: 'oidc'))
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # Scenario 3 — UNAUTHENTICATED -> unchanged H-3 refusal (regression)
  # ==========================================================================

  describe 'unauthenticated (regression: new branch is gated on logged_in?)' do
    before { enable_platform_fallback }

    it 'falls through to the existing H-3 refusal and never fires the connect event' do
      email = "anon-#{SecureRandom.hex(6)}@company.example.com"
      uid   = "sub-#{SecureRandom.hex(8)}"
      seed_existing_account(email)

      # No login. trust flag defaults off -> H-3 refusal path.
      allow(Onetime.auth_config).to receive(:trust_email_for_linking?).and_return(false)
      allow(Auth::Logging).to receive(:log_auth_event).and_call_original

      setup_mock_auth(email: email, uid: uid)
      begin
        post '/auth/sso/oidc/callback'

        skip 'OmniAuth route not registered' if last_response.status == 404

        expect(last_response.status).to eq(302)
        expect(last_response.location.to_s).to include('/signin?auth_error=account_exists_link_required'),
          "Unauthenticated flow must keep the H-3 refusal. Location: #{last_response.location.inspect}"

        expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0)

        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_link_refused_existing_account, hash_including(provider: 'oidc'))
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_identity_connected, anything)
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_identity_connect_refused, anything)
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # Scenario 4 — logged-in on PLATFORM, TENANT callback -> REFUSE (isolation)
  # ==========================================================================
  #
  # Surface isolation is checked BEFORE the session-account bind and is
  # independent of the IdP email: a tenant callback must never bind a
  # tenant-issuer identity onto a PLATFORM session (validated_omniauth_domain_id
  # is set by the tenant hook on tenant callbacks only).

  describe 'logged-in on platform, tenant callback (surface isolation)', :oauth_flow do
    include OAuthFlowHelper

    it 'refuses to bind on the tenant surface' do
      run_id = "connect-tenant-#{SecureRandom.hex(4)}"
      host   = "secrets-#{run_id}.tenant.example.com"
      email  = "tenant-actor-#{run_id}@tenant.example.com"
      uid    = "sub-#{SecureRandom.hex(8)}"

      seed_account_with_password(email)

      # Establish a PLATFORM session for this account.
      csrf_login(email)
      expect(last_response.status).to be_between(200, 302)

      # Registered tenant domain so the tenant callback validates.
      setup_oauth_test_domain(host)

      allow(Auth::Logging).to receive(:log_auth_event).and_call_original
      OmniAuth.config.test_mode               = true
      OmniAuth.config.allowed_request_methods = [:get, :post]
      OmniAuth.config.mock_auth[:oidc]        = OmniAuth::AuthHash.new(
        {
          provider: 'oidc',
          uid: uid,
          info: { email: email, name: 'Tenant Actor', email_verified: true },
          extra: { raw_info: { sub: uid, email: email, email_verified: true } },
        },
      )

      begin
        # Initiate from the tenant host WITH connect intent so the tenant hook
        # records the context AND the callback reaches the intent-gated bind
        # branch — where surface isolation then refuses. (Without intent the
        # callback would fall through to the email branches and never assert the
        # tenant_surface refusal this scenario is about.)
        clear_body_headers
        header 'Host', host
        post '/auth/sso/oidc', { connect: '1' }

        skip "OmniAuth route not registered for #{host}" if last_response.status == 404
        expect(last_response.status).to eq(302)

        # Callback from the SAME host -> validated_omniauth_domain_id gets set,
        # so the connect branch sees a NON-platform surface and refuses.
        clear_body_headers
        header 'Host', host
        post '/auth/sso/oidc/callback'

        expect(last_response.status).to eq(302)
        expect(last_response.location.to_s).to include('/signin?auth_error=identity_connect_conflict'),
          "Tenant callback must refuse the bind. Location: #{last_response.location.inspect}"

        expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0),
          'Surface isolation must NOT create a tenant identity row'

        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_identity_connect_refused, hash_including(provider: 'oidc', reason: 'tenant_surface'))
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_identity_connected, anything)
      ensure
        teardown_mock_auth
      end
    end
  end
end
