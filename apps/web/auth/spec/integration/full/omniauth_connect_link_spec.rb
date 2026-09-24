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
#        omniauth_request_validation_phase into the short-TTL sidecar key
#        sidecar:<sid>:sso_connect_intent — single-use per #3859).
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
#   1b. logged-in + connect intent, IdP asserts NO email claim at all
#        -> still binds on (provider, issuer, uid). The absence of an email
#           cannot block a bind that never consults one; the invalid_email
#           refusal is create-path-only and must not be reachable here.
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
#   5. (#4411) connect=1 on an authenticated session WITHOUT a recent full
#      re-authentication proof (absent, consumed, stale, other account, other
#      surface, or a non-local primary such as a magic link)
#        -> the request phase mints NO intent, logs
#           :omniauth_connect_reauth_required, and redirects to /reauth with
#           the Connected Identities panel as the return path. The proof is
#           single-use: one ceremony admits exactly one initiation.
#   6. (#4411) the callback refuses an intent whose recorded surface differs
#      from the callback's, and treats a pre-#4411 bare-id intent as absent.
#   7. (#3849) on a tenant host, a remember cookie never restores a session
#      (nothing calls load_memory) and a mailbox-proof primary records no
#      proof: neither can mint an intent.
#   8. (#3849) a tenant A session presented to the tenant B callback, and a
#      live intent whose stashed tenant context disagrees with the callback
#      host, both consume the intent and bind nothing; with trusted-email
#      linking ON, every refused tenant gate still creates no identity,
#      account, membership, or linking challenge.
#   9. (#3849) a successful tenant Connect on an account still owning an
#      unarchived personal default workspace adopts the tenant org as
#      default_org_id and archives that workspace (JoinDomainOrganization's
#      already_member path), leaving the membership untouched.
#  10. (#4433) a registered custom-domain callback using platform fallback has
#      no validated tenant domain and is refused as a surface mismatch, with no
#      bind or account switch and no replayable intent.
#
# REQUIREMENTS:
# - Valkey running on port 2163: pnpm run test:database:start
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
require 'onetime/operations/sessions/store'

RSpec.describe 'OmniAuth authenticated identity connect (#3840 Phase 2)', type: :integration do
  include Rack::Test::Methods

  # Password is AuthTestConstants::TEST_PASSWORD (shared across spec files so a
  # top-level constant isn't redefined when both specs load in one process).

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

  # Registered custom-domain hosts must classify :custom, which only happens
  # with the domains axis ON and a PARSEABLE canonical host installed. Both
  # used to be inherited from the ambient DOMAINS_ENABLED of whatever shell
  # ran the suite; declaring it here makes the file green in either.
  #
  # Declared AFTER the forced reboot above on purpose: `boot!(:test, force: true)`
  # reloads OT.conf and rebuilds Onetime::Runtime.features, which is exactly
  # what this context overrides.
  include_context 'domains enabled'

  let(:identities) { auth_db[:account_identities] }

  # ==========================================================================
  # Helpers
  # ==========================================================================

  # seed_existing_account (the SSO-only / victim account) and
  # seed_account_with_password (the subject csrf_login can authenticate as)
  # come from support/account_seed_helper.rb.

  # clear_body_headers (support/auth_request_helper.rb) and setup_mock_auth /
  # teardown_mock_auth (support/omniauth_test_helper.rb) are shared.
  #
  # setup_mock_auth(email: nil, ...) below models an IdP that asserts NO email
  # claim: the shared helper OMITS the key from info/raw_info rather than
  # setting it to nil — that is what a minimal-scope OIDC response actually
  # looks like, and it makes omniauth_email nil via the gem's
  # `omniauth_info[info_key] if omniauth_info` accessor (rodauth-omniauth 0.6.2
  # omniauth_base.rb:69).

  # Run the SSO REQUEST phase carrying the connect-intent signal (connect=1),
  # exactly as the Connected Identities panel does at initiation. In OmniAuth
  # test mode this triggers omniauth_request_validation_phase, which — when the
  # caller is logged in — writes the account-bound intent nonce as the
  # short-TTL sidecar key sidecar:<sid>:sso_connect_intent (#3859). The
  # subsequent callback consumes it and, only then, takes the bind branch.
  # Returns the request-phase status so callers can skip when the provider
  # route isn't registered (404).
  def initiate_sso_connect(provider: :oidc, host: nil)
    clear_body_headers
    header 'Host', host if host
    post "/auth/sso/#{provider}", { connect: '1' }
    last_response.status
  end

  # The plain (64-hex) session id behind the current Rack::Test cookie jar —
  # the sid the sidecar keys are derived from. The cookie value IS the sid
  # (Onetime::Session stores it unencrypted; only the blob is ciphered).
  def current_sid
    rack_mock_session.cookie_jar['onetime.session']
  end

  def intent_live?(sid)
    Onetime::SessionSidecar.exists?(sid, 'sso_connect_intent')
  end

  # The recent-full-re-authentication proof (#4410) the request phase consumes
  # before minting an intent (#4411). A password login records one, so the
  # happy-path scenarios above pass the gate on the login itself; the #4411
  # scenarios below remove or replace it to drive each refusal.
  def reauth_proof_live?(sid)
    Onetime::SessionSidecar.exists?(sid, 'recent_reauth')
  end

  def clear_reauth_proof(sid)
    Onetime::SessionSidecar.delete(sid, 'recent_reauth')
  end

  # Overwrite the proof with a hand-built payload. Defaults are a fresh,
  # canonical-surface password ceremony for `account_id`; each scenario varies
  # exactly one binding.
  def seed_reauth_proof(sid, account_id, at: Time.now.utc.to_i, surface: Onetime::SessionSurface::CANONICAL,
                        methods: %w[password])
    clear_reauth_proof(sid)
    Onetime::SessionSidecar.write(
      sid,
      'recent_reauth',
      { 'account_id' => Integer(account_id), 'at' => at, 'surface' => surface, 'methods' => methods },
    )
  end

  def expect_reauth_required_redirect
    expect(last_response.status).to eq(302),
      "Expected the request phase to redirect to re-authentication, got #{last_response.status}: #{last_response.body}"
    expect(last_response.location.to_s).to include(Auth::Config::Hooks::OmniAuth.connect_reauth_redirect),
      "Expected a redirect to the re-authentication view, got: #{last_response.location.inspect}"
  end

  # Read / rewrite the live Rack session blob through the same Store + Codec
  # the session admin verbs use (the pattern in
  # spec/integration/full/active_sessions_spec.rb), so the router and Rodauth
  # read the key back exactly as a request would have left it. Rack's
  # SessionHash stringifies keys, so callers pass string keys.
  def session_blob(sid)
    db    = Familia.dbclient
    dbkey = Onetime::Operations::Sessions::Store.find_key(db, sid)
    raise "No session blob stored for sid #{sid.inspect}" unless dbkey

    Onetime::Operations::Sessions::Store.load_data(db, dbkey, codec: Onetime::SessionCodec.from_config)
  end

  def stash_in_session_blob(sid, key, value)
    db        = Familia.dbclient
    dbkey     = Onetime::Operations::Sessions::Store.find_key(db, sid)
    raise "No session blob stored for sid #{sid.inspect}" unless dbkey

    codec     = Onetime::SessionCodec.from_config
    data      = Onetime::Operations::Sessions::Store.load_data(db, dbkey, codec: codec)
    data[key] = value
    db.set(dbkey, codec.encode(data), keepttl: true)
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

        sid = current_sid
        expect(intent_live?(sid)).to be(true),
          'Connect initiation must set the intent sidecar key'
        # #4411: the password login recorded a recent-reauth proof, and the
        # initiation SPENT it — one ceremony, one intent.
        expect(reauth_proof_live?(sid)).to be(false),
          'Connect initiation must consume the recent re-authentication proof'

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

        # Single-use (#3859): the successful bind CONSUMED the nonce (atomic
        # GETDEL) — nothing is left for a later callback to replay.
        expect(intent_live?(sid)).to be(false),
          'The consumed intent must not survive the bind'
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # Scenario 1b — logged-in connect, IdP asserts NO email claim -> still binds
  # ==========================================================================
  #
  # The corollary of "the IdP email plays NO role": if email is not an input to
  # the bind decision, its ABSENCE cannot block the bind. An IdP scoped to
  # openid-only (no email/profile) emits an auth hash with no email claim, and
  # connecting such a provider from account settings must still work — the
  # session is the authorization, the uid is the identifier.
  #
  # This is a REGRESSION GUARD, not a happy-path duplicate. The connect branch
  # currently survives a nil email only incidentally:
  #   - normalize_email(nil) -> '' (Utils::Strings, .to_s.strip) rather than a
  #     raise, and the '' is used ONLY for the obscured audit-log field;
  #   - the invalid_email refusal lives in before_omniauth_create_account, which
  #     the gem runs on the CREATE path only — the connect branch returns an
  #     account, so omniauth_create_account (and that hook) never runs.
  # Both are one refactor away from breaking: hoisting the email-shape check out
  # of before_omniauth_create_account, or making normalized_email load-bearing
  # above the connect branch, would turn every no-email-claim connect into a
  # /signin?auth_error=invalid_email dead-end with no way to attach the provider.
  # Nothing else in the suite exercises a nil omniauth_email, so pin it here.

  describe 'logged-in connect, IdP asserts no email claim' do
    before { enable_platform_fallback }

    it 'binds on the uid alone and never hits the invalid_email refusal' do
      email      = "connect-noemail-#{SecureRandom.hex(6)}@company.example.com"
      uid        = "sub-#{SecureRandom.hex(8)}"
      account_id = seed_account_with_password(email)

      csrf_login(email)
      expect(last_response.status).to be_between(200, 302),
        "Precondition failed: password login did not succeed (#{last_response.status}: #{last_response.body})"

      accounts_before = auth_db[:accounts].count

      allow(Auth::Logging).to receive(:log_auth_event).and_call_original
      # THE VARIABLE UNDER TEST: no email claim anywhere in the auth hash.
      setup_mock_auth(email: nil, uid: uid)
      begin
        skip 'OmniAuth route not registered (OIDC discovery not available at boot)' if initiate_sso_connect == 404

        sid = current_sid
        expect(intent_live?(sid)).to be(true),
          'Connect initiation must set the intent sidecar key'

        clear_body_headers
        post '/auth/sso/oidc/callback'

        skip 'OmniAuth route not registered (OIDC discovery not available at boot)' if last_response.status == 404

        # The crux: a missing email claim must not be read as an INVALID one.
        expect(last_response.location.to_s).not_to include('auth_error=invalid_email'),
          "A connect needs no email claim. Location: #{last_response.location.inspect}"
        expect(last_response.location.to_s).not_to include('identity_connect_conflict'),
          "Connect must NOT refuse. Location: #{last_response.location.inspect}"
        expect(last_response.status).to eq(302),
          "Expected a post-login redirect, got #{last_response.status}: #{last_response.body}"

        # The bind happened on (provider, issuer, uid) — no email involved.
        rows = identities.where(provider: 'oidc', uid: uid).all
        expect(rows.size).to eq(1),
          "Expected exactly one bound identity row, got #{rows.size}: #{rows.inspect}"
        expect(rows.first[:account_id]).to eq(account_id),
          'Bound identity must attach to the already-authenticated account'
        expect(rows.first[:issuer]).not_to be_nil

        # An emailless callback must never reach the JIT-create path (a nil login
        # would violate the accounts.email NOT NULL/unique index).
        expect(auth_db[:accounts].count).to eq(accounts_before),
          'Connect must NOT create an account'

        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_identity_connected, hash_including(provider: 'oidc', account_id: account_id))
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_invalid_email, anything)
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_identity_connect_refused, anything)

        expect(intent_live?(sid)).to be(false),
          'The consumed intent must not survive the bind'
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

    it 'does not bind onto the session account (a no-intent callback is treated as unauthenticated)' do
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
        # The redirect target is incidental to this test's property (no intent =>
        # no bind). The located account is passwordless, so it now takes the Phase 4
        # mailbox path (asserted in sso_link_confirm_mailbox_proof_spec.rb); we do
        # NOT pin the location here.

        # THE CRUX: the arriving identity did NOT attach to the session account.
        expect(identities.where(account_id: actor_id).count).to eq(0),
          'A plain sign-in without connect intent must NOT bind onto the session account'
        # And no identity row is bound at all (no direct-bind, no issuance-time bind).
        expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0)

        # The connect event never fires; the intent-absent event does.
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_identity_connected, anything)
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_connect_intent_absent, hash_including(provider: 'oidc'))
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # Scenario 2b' — the fail-closed rescue covers Connect lookups only (#4431)
  # ==========================================================================
  #
  # authorize_omniauth_connect used to rescue StandardError method-wide, so an
  # error in the intent-absent branch — reached by every ordinary sign-in
  # callback on a logged-in session — was reported to the user as
  # identity_connect_conflict although no Connect was requested. The two
  # examples pin both sides of the boundary: outside it nothing is
  # reclassified, inside it a lookup failure still refuses before any bind.

  describe 'scope of the Connect lookup rescue (#4431)' do
    before { enable_platform_fallback }

    it 'keeps a no-intent callback on the ordinary path when the intent-absent log raises' do
      actor_email = "actor-lograise-#{SecureRandom.hex(6)}@company.example.com"
      other_email = "other-#{SecureRandom.hex(6)}@company.example.com"
      uid         = "sub-#{SecureRandom.hex(8)}"

      actor_id = seed_account_with_password(actor_email)
      seed_existing_account(other_email)

      csrf_login(actor_email)
      expect(last_response.status).to be_between(200, 302)

      allow(Onetime.auth_config).to receive(:trust_email_for_linking?).and_return(false)
      allow(Auth::Logging).to receive(:log_auth_event).and_call_original
      allow(Auth::Logging).to receive(:log_auth_event)
        .with(:omniauth_connect_intent_absent, anything).and_raise(RuntimeError, 'log sink down')
      allow(OT).to receive(:le).and_call_original

      setup_mock_auth(email: other_email, uid: uid)
      begin
        clear_body_headers
        post '/auth/sso/oidc/callback'

        skip 'OmniAuth route not registered' if last_response.status == 404

        # Not vacuous: the raising branch was reached.
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_connect_intent_absent, anything)
        expect(OT).to have_received(:le).with(/intent-absent log failed: RuntimeError/)

        # The ordinary path answered: a redirect, and not the Connect refusal.
        expect(last_response.status).to eq(302)
        expect(last_response.location.to_s).not_to include('identity_connect_conflict')
        expect(last_response.location.to_s).not_to include('identity_connect_wrong_domain')
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_identity_connect_refused, anything)
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_connect_lookup_error, anything)

        # And it is still not a Connect: nothing binds onto the session account.
        expect(identities.where(account_id: actor_id).count).to eq(0)
        expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0)
      ensure
        teardown_mock_auth
      end
    end

    it 'still refuses as lookup_error, binding nothing, when a lookup raises after a valid intent' do
      email      = "connect-lookupraise-#{SecureRandom.hex(6)}@company.example.com"
      uid        = "sub-#{SecureRandom.hex(8)}"
      account_id = seed_account_with_password(email)

      csrf_login(email)
      expect(last_response.status).to be_between(200, 302)

      allow(Auth::Logging).to receive(:log_auth_event).and_call_original
      setup_mock_auth(email: email, uid: uid)
      begin
        skip 'OmniAuth route not registered (OIDC discovery not available at boot)' if initiate_sso_connect == 404

        sid = current_sid
        expect(intent_live?(sid)).to be(true)

        # The session gate ahead of the /auth router loads the same Customer;
        # failing it there is a 401 that never reaches the hook. Fail only the
        # hook's own lookup, which is the one under test.
        allow(Onetime::Customer).to receive(:find_by_extid).and_wrap_original do |original, *args|
          from_hook = caller.first(30).any? { |frame| frame.include?('config/hooks/omniauth_connect.rb') }
          raise 'customer store down' if from_hook

          original.call(*args)
        end

        clear_body_headers
        post '/auth/sso/oidc/callback'

        expect(last_response.status).to eq(302)
        expect(last_response.location.to_s).to include('auth_error=identity_connect_conflict')
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_connect_lookup_error, hash_including(error_class: 'RuntimeError'))
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_identity_connect_refused, hash_including(reason: 'lookup_error'))
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_identity_connected, anything)

        expect(identities.where(account_id: account_id).count).to eq(0)
        expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0)
        expect(intent_live?(sid)).to be(false), 'a refused Connect still consumes its intent'
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # Scenario 2c — ABANDONED connect: expired intent must not bind (#3859)
  # ==========================================================================
  #
  # The single-use gap: the nonce's only clearing site used to be the consume
  # in account_from_omniauth, so a connect ABANDONED at the IdP (cancel, IdP
  # error, closed tab) left the intent live for the next callback on the same
  # session — even a plain connect=0 sign-in — to bind on. The nonce now lives
  # as a short-TTL sidecar key: an abandoned intent simply expires, and a miss
  # at the callback is default-deny. Deleting the key here models the TTL
  # expiry without waiting out the clock.

  describe 'abandoned connect, intent expired (must not bind)' do
    before { enable_platform_fallback }

    it 'sets a short-TTL intent at initiation and refuses to bind once it has expired' do
      actor_email = "actor-abandon-#{SecureRandom.hex(6)}@company.example.com"
      other_email = "other-#{SecureRandom.hex(6)}@company.example.com"
      uid         = "sub-#{SecureRandom.hex(8)}"

      actor_id = seed_account_with_password(actor_email)
      seed_existing_account(other_email)

      csrf_login(actor_email)
      expect(last_response.status).to be_between(200, 302)

      allow(Onetime.auth_config).to receive(:trust_email_for_linking?).and_return(false)
      allow(Auth::Logging).to receive(:log_auth_event).and_call_original

      setup_mock_auth(email: other_email, uid: uid)
      begin
        # Initiate a connect — the intent goes live as a sidecar key whose TTL
        # is bounded to one IdP round-trip (SessionSidecar::FIELDS, 300s).
        skip 'OmniAuth route not registered' if initiate_sso_connect == 404

        sid = current_sid
        expect(intent_live?(sid)).to be(true),
          'Precondition failed: connect initiation must set the intent sidecar key'
        ttl = Familia.dbclient.ttl("sidecar:#{sid}:sso_connect_intent")
        expect(ttl).to be_between(1, 300),
          "Intent TTL must be bounded to one IdP round-trip, got #{ttl}"

        # ABANDON: the connect's callback never runs. Model the TTL firing by
        # removing the key directly (same observable state as expiry).
        Onetime::SessionSidecar.delete(sid, 'sso_connect_intent')

        # A later plain sign-in callback on the SAME authenticated session must
        # find nothing to consume and fall through to the H-3 refusal.
        clear_body_headers
        post '/auth/sso/oidc/callback'

        expect(last_response.status).to eq(302)
        # Redirect target is incidental here (expired intent => no bind); the
        # passwordless located account now takes the Phase 4 mailbox path, so the
        # location is not pinned (see sso_link_confirm_mailbox_proof_spec.rb).

        # THE CRUX: the abandoned intent granted nothing to the later callback.
        expect(identities.where(account_id: actor_id).count).to eq(0),
          'An expired connect intent must NOT let a later callback bind onto the session account'
        expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0)
        expect(intent_live?(sid)).to be(false)

        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_identity_connected, anything)
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_connect_intent_absent, hash_including(provider: 'oidc', had_intent: false))
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # Scenario 2d — ABANDONED connect, then a plain sign-in WITHIN the TTL
  # ==========================================================================
  #
  # The exact #3859 exploit shape, closed deterministically (not just by the
  # TTL): Alice initiates a connect and abandons at the IdP; still within the
  # intent's TTL, a plain (connect=0) SSO sign-in starts on the same
  # still-authenticated session — the shared-machine case. Every callback's
  # flow passes through omniauth_request_validation_phase first (it mints the
  # state the callback validates), and a non-connect initiation DELETES any
  # dangling intent there, so the plain sign-in's own callback can never
  # consume the leftover nonce.

  describe 'abandoned connect, then plain sign-in within the TTL (must not bind)' do
    before { enable_platform_fallback }

    it 'clears the dangling intent at the plain request phase and does not bind' do
      actor_email = "actor-dangling-#{SecureRandom.hex(6)}@company.example.com"
      other_email = "other-#{SecureRandom.hex(6)}@company.example.com"
      uid         = "sub-#{SecureRandom.hex(8)}"

      actor_id = seed_account_with_password(actor_email)
      seed_existing_account(other_email)

      csrf_login(actor_email)
      expect(last_response.status).to be_between(200, 302)

      allow(Onetime.auth_config).to receive(:trust_email_for_linking?).and_return(false)
      allow(Auth::Logging).to receive(:log_auth_event).and_call_original

      setup_mock_auth(email: other_email, uid: uid)
      begin
        # Alice initiates a connect... and abandons it (no callback).
        skip 'OmniAuth route not registered' if initiate_sso_connect == 404

        sid = current_sid
        expect(intent_live?(sid)).to be(true),
          'Precondition failed: connect initiation must set the intent sidecar key'

        # Within the TTL, a PLAIN sign-in starts on the same session. Its
        # request phase must kill the dangling intent.
        clear_body_headers
        post '/auth/sso/oidc'
        expect(last_response.status).to eq(302)
        expect(intent_live?(sid)).to be(false),
          'A non-connect request phase must delete a dangling connect intent'

        # The plain sign-in's callback finds no intent — no bind, H-3 refusal.
        clear_body_headers
        post '/auth/sso/oidc/callback'

        expect(last_response.status).to eq(302)
        # Redirect target is incidental (dangling intent cleared => no bind); the
        # passwordless located account now takes the Phase 4 mailbox path, so the
        # location is not pinned (see sso_link_confirm_mailbox_proof_spec.rb).

        expect(identities.where(account_id: actor_id).count).to eq(0),
          'A dangling connect intent must NOT let a plain sign-in bind onto the session account'
        expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0)

        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_identity_connected, anything)
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_connect_intent_absent, hash_including(provider: 'oidc', had_intent: false))
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # Scenario 3 — UNAUTHENTICATED, PASSWORDLESS account -> Phase 4 mailbox link
  # ==========================================================================
  #
  # The connect branch is gated on logged_in? + intent, so an unauthenticated
  # callback never binds. For an existing PASSWORDLESS account there is no password
  # to challenge, so Phase 4 emails a single-use mailbox-proof link (superseding the
  # old H-3 refusal); a password-HOLDING account instead diverts to the Phase 3
  # sign-in interstitial (/link-sso/:token). Both linking flows are covered
  # end-to-end in omniauth_signin_interstitial_spec.rb and
  # sso_link_confirm_mailbox_proof_spec.rb — here we only assert this callback never
  # direct-binds and, being passwordless, takes the mailbox path (not the challenge).

  describe 'unauthenticated, passwordless account (connect branch gated; Phase 4 mailbox link)' do
    before { enable_platform_fallback }

    it 'diverts to the Phase 4 mailbox link email, mints no challenge, and fires no connect event' do
      email = "anon-#{SecureRandom.hex(6)}@company.example.com"
      uid   = "sub-#{SecureRandom.hex(8)}"
      seed_existing_account(email) # passwordless -> nothing to challenge

      # No login, trust off. A passwordless PLATFORM account no longer dead-ends at
      # the H-3 refusal — Phase 4 emails a single-use mailbox-proof link instead.
      allow(Onetime.auth_config).to receive(:trust_email_for_linking?).and_return(false)
      # Stub the templated publisher to CAPTURE the enqueue and keep the :sync send
      # deterministic (true == delivered, so the hook takes the notice redirect).
      link_emails = []
      allow(Onetime::Jobs::Publisher).to receive(:enqueue_email) do |template, data, **_opts|
        link_emails << { template: template, data: data }
        true
      end
      allow(Auth::Logging).to receive(:log_auth_event).and_call_original

      setup_mock_auth(email: email, uid: uid)
      begin
        post '/auth/sso/oidc/callback'

        skip 'OmniAuth route not registered' if last_response.status == 404

        expect(last_response.status).to eq(302)
        expect(last_response.location.to_s).to include('/signin?auth_notice=link_verification_sent'),
          "Passwordless account must divert to the mailbox notice. Location: #{last_response.location.inspect}"
        # NOT the Phase 3 password interstitial (no password = no challenge).
        expect(last_response.location.to_s).not_to match(%r{/link-sso/})

        # A single-use verification email went to the on-file address; NO identity
        # row is bound at issuance (mailbox proof binds only on confirm).
        expect(link_emails.size).to eq(1), "Expected one link email, got: #{link_emails.inspect}"
        expect(link_emails.first[:template]).to eq(:sso_link_verification)
        expect(link_emails.first[:data][:email_address]).to eq(OT::Utils.normalize_email(email))
        expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0)

        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:sso_link_verification_issued, hash_including(provider: 'oidc'))
        # No password challenge, and the connect branch stays gated (unauthenticated).
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_link_challenge_issued, anything)
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
  #
  # #4409 moved the first refusal upstream: the auth router destroys a session
  # whose recorded surface (platform) differs from the request surface (tenant)
  # before any Rodauth route runs, so the tenant initiation records no connect
  # intent and the callback arrives ANONYMOUS. The hook-level
  # `identity_connect_wrong_domain` branch is now defence-in-depth behind that
  # gate; what the round trip observes is the anonymous existing-account
  # refusal on the tenant surface.

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

        # The platform session never reached the tenant initiation: the
        # router refused it for the surface (#4409) and cleared it.
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:session_surface_mismatch, hash_including(path: '/sso/oidc', outcome: :continued_anonymous))

        # Callback from the SAME host -> validated_omniauth_domain_id gets set.
        # With no authenticated session and no intent, the hook takes the
        # unauthenticated email branch: the asserted email matches an existing
        # account, and on the tenant surface that is refused outright.
        clear_body_headers
        header 'Host', host
        post '/auth/sso/oidc/callback'

        expect(last_response.status).to eq(302)
        expect(last_response.location.to_s).to include('/signin?auth_error=tenant_sso_link_unavailable'),
          "Tenant callback must refuse the bind. Location: #{last_response.location.inspect}"

        expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0),
          'Surface isolation must NOT create a tenant identity row'

        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_link_refused_existing_account, hash_including(provider: 'oidc', surface: 'tenant'))
        # The connect branch was never entered, so neither its refusal nor a
        # bind can have been recorded.
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_identity_connect_refused, anything)
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_identity_connected, anything)
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # Scenario 4b — custom-domain platform fallback callback -> REFUSE (#4433)
  # ==========================================================================
  #
  # enable_platform_fallback below is scoped to the REQUEST phase: it lets
  # OmniAuthTenant.handle_missing_tenant_config allow the /auth/sso/oidc
  # kickoff through. The callback refusal asserted here does NOT consult
  # allow_platform_fallback_for_tenants? — omniauth_connect.rb:113 rejects
  # any custom-surface Connect without validated_omniauth_domain_id
  # regardless of fallback policy. Do not read this example as pinning
  # fallback-specific callback behavior; it pins the surface-mismatch gate.

  describe 'registered custom-domain platform fallback callback (#4433)', :oauth_flow do
    include OAuthFlowHelper

    let(:host) { "fallback-connect-#{SecureRandom.hex(6)}.tenant.example.com" }
    let(:actor_email) { unique_test_email('fallback-connect-actor') }
    let(:other_email) { unique_test_email('fallback-connect-other') }
    let(:uid) { "fallback-connect-sub-#{SecureRandom.hex(8)}" }
    let!(:actor_id) { seed_account_with_password(actor_email) }

    before do
      @fallback_tenant = setup_oauth_test_domain(host)
      Onetime::CustomDomain::SsoConfig.delete_for_domain!(@fallback_tenant[:domain].identifier)
      Onetime::CustomDomain::SigninConfig.create!(
        domain_id: @fallback_tenant[:domain].identifier, enabled: true, signin_enabled: true, sso_enabled: true,
      )
      seed_account_with_password(other_email)
      enable_platform_fallback

      header 'Host', host
      csrf_login(actor_email)
      expect(last_request.env['rack.session']['account_id']).to eq(actor_id)

      allow(Onetime.auth_config).to receive(:trust_email_for_linking?).and_return(false)
      allow(Auth::Logging).to receive(:log_auth_event).and_call_original
      setup_mock_auth(email: other_email, uid: uid)
    end

    after do
      teardown_mock_auth
      Onetime::CustomDomain::SigninConfig.delete_for_domain!(@fallback_tenant[:domain].identifier) if @fallback_tenant
    end

    it 'refuses the unvalidated custom surface, preserves the account, and consumes the intent' do
      expect(Onetime::CustomDomain::SsoConfig.find_by_domain_id(@fallback_tenant[:domain].identifier)).to be_nil
      expect(initiate_sso_connect(host: host)).to eq(302)

      sid    = current_sid
      intent = Onetime::SessionSidecar.read(sid, 'sso_connect_intent')
      expect(intent).to include(
        'account_id' => actor_id,
        'surface' => { 'kind' => 'custom', 'id' => @fallback_tenant[:domain].identifier },
      )
      expect(session_blob(sid)).not_to include('omniauth_tenant_domain_id', 'validated_omniauth_domain_id')
      accounts_before = auth_db[:accounts].count

      clear_body_headers
      header 'Host', host
      post '/auth/sso/oidc/callback'

      expect_auth_error_redirect('identity_connect_wrong_domain')
      expect(last_request.env['rack.session']['account_id']).to eq(actor_id),
        'A refused fallback callback must not switch the authenticated account'
      expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0)
      expect(auth_db[:accounts].count).to eq(accounts_before)
      expect(intent_live?(sid)).to be(false), 'The refused intent must be consumed'
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:omniauth_identity_connect_refused, hash_including(provider: 'oidc', reason: 'surface_mismatch'))
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:omniauth_identity_connected, anything)

      clear_body_headers
      header 'Host', host
      post '/auth/sso/oidc/callback'

      expect(intent_live?(sid)).to be(false)
      expect(last_request.env['rack.session']['account_id']).to eq(actor_id)
      expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0),
        'A second callback must not replay the refused Connect intent'
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:omniauth_connect_intent_absent, hash_including(provider: 'oidc', had_intent: false))
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:omniauth_identity_connected, anything)
    end
  end

  # ==========================================================================
  # Scenario 5 — #4411: connect=1 WITHOUT recent full re-authentication
  # ==========================================================================
  #
  # An authenticated session plus connect=1 is intent, not proof. Attaching a
  # login identity changes the account's authenticators, so the request phase
  # mints an intent ONLY after Onetime::RecentReauth.satisfied? consumes a
  # fresh proof for this account on this surface. Each example below removes
  # or replaces the proof the password login recorded, and asserts the same
  # fail-closed outcome: no intent, a warn event, a redirect to /reauth that
  # returns to the Connected Identities panel — and, for the callback that
  # follows, no bind.

  describe 'connect initiation without recent full re-authentication (#4411)' do
    let(:actor_email) { "actor-reauth-#{SecureRandom.hex(6)}@company.example.com" }
    let(:other_email) { "other-#{SecureRandom.hex(6)}@company.example.com" }
    let!(:actor_id) { seed_account_with_password(actor_email) }
    let!(:other_id) { seed_existing_account(other_email) }

    before do
      enable_platform_fallback
      csrf_login(actor_email)
      unless (200..302).cover?(last_response.status)
        raise "Precondition failed: password login did not succeed (#{last_response.status}: #{last_response.body})"
      end
      # A completed password login records the proof; every example starts
      # from that known-good state and then breaks exactly one binding.
      raise 'Precondition failed: a password login must record a recent-reauth proof' unless reauth_proof_live?(current_sid)

      allow(Onetime.auth_config).to receive(:trust_email_for_linking?).and_return(false)
      allow(Auth::Logging).to receive(:log_auth_event).and_call_original
      setup_mock_auth(email: other_email, uid: "sub-#{SecureRandom.hex(8)}")
    end

    after { teardown_mock_auth }

    # Drive connect=1 and assert the request phase refused: no intent minted,
    # the proof (whatever state it was in) is gone, the event fired, and the
    # user was sent to re-authenticate.
    def expect_initiation_refused(sid)
      skip 'OmniAuth route not registered' if initiate_sso_connect == 404

      expect_reauth_required_redirect
      expect(intent_live?(sid)).to be(false),
        'A refused initiation must NOT leave a connect intent live'
      expect(reauth_proof_live?(sid)).to be(false),
        'The gate consumes the proof whether or not it satisfied'
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:omniauth_connect_reauth_required, hash_including(provider: 'oidc', account_id: actor_id))
    end

    it 'refuses when the session carries no proof (the ordinary authenticated session)' do
      sid = current_sid
      clear_reauth_proof(sid)

      expect_initiation_refused(sid)

      # The callback that follows an abandoned refusal finds nothing to bind on.
      clear_body_headers
      post '/auth/sso/oidc/callback'

      expect(last_response.status).to eq(302)
      expect(identities.where(account_id: actor_id).count).to eq(0),
        'A connect refused at initiation must NOT bind at the callback'
      expect(identities.where(provider: 'oidc').count).to eq(0)
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:omniauth_identity_connected, anything)
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:omniauth_connect_intent_absent, hash_including(provider: 'oidc', had_intent: false))
    end

    it 'refuses a second initiation on the same proof (single-use, replay)' do
      sid = current_sid

      # First initiation spends the login's proof and mints an intent.
      skip 'OmniAuth route not registered' if initiate_sso_connect == 404
      expect(last_response.status).to eq(302)
      expect(last_response.location.to_s).not_to include(Auth::Config::Hooks::OmniAuth::REAUTH_PATH),
        "First initiation must pass the gate. Location: #{last_response.location.inspect}"
      expect(intent_live?(sid)).to be(true)
      expect(reauth_proof_live?(sid)).to be(false)

      # Abandon it (model the IdP round-trip never completing), then try again
      # without re-authenticating: the spent proof admits nothing.
      Onetime::SessionSidecar.delete(sid, 'sso_connect_intent')

      expect_initiation_refused(sid)
    end

    it 'refuses a proof older than CONNECT_MAX_AGE (stale)' do
      sid = current_sid
      seed_reauth_proof(sid, actor_id, at: Time.now.utc.to_i - Onetime::RecentReauth::CONNECT_MAX_AGE - 1)

      expect_initiation_refused(sid)
    end

    it 'refuses a proof recorded for a different account' do
      sid = current_sid
      seed_reauth_proof(sid, other_id)

      expect_initiation_refused(sid)
    end

    it 'refuses a proof recorded on a different surface' do
      sid = current_sid
      seed_reauth_proof(sid, actor_id, surface: { 'kind' => 'custom', 'id' => "cd-#{SecureRandom.hex(4)}" })

      expect_initiation_refused(sid)
    end

    it 'refuses mailbox proof (a magic-link primary is not a local credential)' do
      sid = current_sid
      seed_reauth_proof(sid, actor_id, methods: %w[email_auth])

      expect_initiation_refused(sid)
    end

    it 'admits a fresh proof for this account on this surface' do
      sid = current_sid
      seed_reauth_proof(sid, actor_id)

      skip 'OmniAuth route not registered' if initiate_sso_connect == 404

      expect(last_response.status).to eq(302)
      expect(last_response.location.to_s).not_to include(Auth::Config::Hooks::OmniAuth::REAUTH_PATH),
        "A fresh proof must pass the gate. Location: #{last_response.location.inspect}"
      expect(intent_live?(sid)).to be(true)
      expect(reauth_proof_live?(sid)).to be(false)
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:omniauth_connect_reauth_required, anything)
    end
  end

  # ==========================================================================
  # Scenario 5b — custom-host local re-authentication -> initiation -> callback
  # ==========================================================================

  describe 'custom-host password re-authentication and Connect callback', :oauth_flow do
    include OAuthFlowHelper

    it 'records an exact-surface proof through POST /auth/reauth and completes Connect' do
      host       = "reauth-connect-#{SecureRandom.hex(6)}.tenant.example.com"
      email      = unique_test_email('tenant-reauth')
      uid        = "reauth-sub-#{SecureRandom.hex(8)}"
      account_id = seed_account_with_password(email)
      tenant     = setup_oauth_test_domain(host)
      customer   = Onetime::Customer.find_by_extid(auth_db[:accounts].where(id: account_id).get(:external_id))
      membership = Onetime::OrganizationMembership.ensure_membership(
        tenant[:org], customer, role: 'member', domain_scope_id: tenant[:domain].objid, provisioning_source: 'sso',
      )
      Onetime::CustomDomain::SigninConfig.create!(
        domain_id: tenant[:domain].identifier, enabled: true, signin_enabled: true, sso_enabled: true,
      )

      header 'Host', host
      csrf_login(email)
      sid = current_sid
      clear_reauth_proof(sid)

      set_cookie = last_response.headers['set-cookie'].to_s
      expect(set_cookie).to include('onetime.session=')
      expect(set_cookie).not_to match(/(?:^|;)\s*Domain=/i),
        "Tenant session cookie must be host-only, got: #{set_cookie.inspect}"

      clear_body_headers
      header 'Accept', 'application/json'
      get '/auth/reauth-offer'
      expect(last_response.status).to eq(200)
      expect(json_body['surface']).to eq('kind' => 'custom', 'id' => tenant[:domain].identifier)
      expect(json_body['methods']).to include('password')

      csrf_json_post(
        '/auth/reauth', method: 'password', password: AuthTestConstants::TEST_PASSWORD,
      )
      expect(last_response.status).to eq(200)
      expect(json_body).to include('success' => 'Re-authentication complete')
      expect(Onetime::SessionSidecar.read(sid, Onetime::RecentReauth::KEY)).to include(
        'account_id' => account_id,
        'surface' => { 'kind' => 'custom', 'id' => tenant[:domain].identifier },
        'methods' => %w[password],
      )

      allow(Auth::Operations::JoinDomainOrganization).to receive(:new).and_call_original
      setup_mock_auth(email: unique_test_email('asserted-victim'), uid: uid)
      begin
        expect(initiate_sso_connect(host: host)).to eq(302)
        expect(intent_live?(sid)).to be(true)
        expect(reauth_proof_live?(sid)).to be(false)

        clear_body_headers
        header 'Host', host
        post '/auth/sso/oidc/callback'

        expect(last_response.status).to eq(302)
        expect(identities.where(provider: 'oidc', uid: uid).all)
          .to contain_exactly(hash_including(account_id: account_id))
        expect(Auth::Operations::JoinDomainOrganization).to have_received(:new)
          .with(customer: an_object_having_attributes(objid: customer.objid), domain_id: tenant[:domain].identifier)
        persisted = Onetime::OrganizationMembership.find_by_org_customer(tenant[:org].objid, customer.objid)
        expect(persisted.objid).to eq(membership.objid)
        expect(persisted.domain_scope_id).to eq(tenant[:domain].objid)
        expect(intent_live?(sid)).to be(false)
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # Scenario 5c — #3849: tenant-host sessions that cannot mint an intent
  # ==========================================================================
  #
  # The matrix row "remembered and email-authenticated sessions cannot mint
  # an intent", pinned against what the mounted stack does rather than a
  # seeded proof (Scenario 5 covers the gate's own method check).
  #
  # REMEMBER: the feature is enabled (config/features/remember_me.rb) and
  # POST /auth/remember issues a real cookie, but nothing in the app calls
  # rodauth.load_memory, so a browser presenting only the remember cookie is
  # ANONYMOUS on the auth router. The initiation therefore takes the plain
  # non-connect path: no session, no proof consulted, no intent, no reauth
  # redirect. (If load_memory is ever wired up, this example must move to the
  # reauth-refusal assertion: a restored session records no proof either.)
  #
  # MAILBOX PROOF: a magic-link login is not mountable in this lane
  # (spec/auth.test.yaml pins email_auth: false, and Auth::Config configures
  # once per process — lib/tasks/spec.rake 'full:mfa' runs its own process
  # for the same reason), so the example completes the REAL login route with
  # the primary Rodauth would report after login('email_auth'): only the
  # authenticated_by reader is stubbed, on the one Rodauth instance serving
  # the login POST, so login_session, the surface stamp, the active-session
  # join and after_login (hooks/login.rb) all run unchanged. after_login's
  # LOCAL_PRIMARIES guard then skips the proof, and RecentReauth.record
  # itself refuses the same primary — both guards are pinned.

  describe 'tenant-host sessions that cannot mint an intent (#3849)', :oauth_flow do
    include OAuthFlowHelper

    let(:host) { "nomint-#{SecureRandom.hex(6)}.tenant.example.com" }
    let(:email) { unique_test_email('tenant-nomint') }
    let!(:account_id) { seed_account_with_password(email) }

    before do
      @tenant = setup_oauth_test_domain(host)
      Onetime::CustomDomain::SigninConfig.create!(
        domain_id: @tenant[:domain].identifier, enabled: true, signin_enabled: true, sso_enabled: true,
      )
      header 'Host', host
      allow(Auth::Logging).to receive(:log_auth_event).and_call_original
      setup_mock_auth(email: email, uid: "sub-#{SecureRandom.hex(8)}")
    end

    after { teardown_mock_auth }

    def login_as_mailbox_primary(email)
      allow(Auth::Config).to receive(:new).and_wrap_original do |original, *args|
        instance = original.call(*args)
        allow(instance).to receive(:authenticated_by).and_return(%w[email_auth])
        instance
      end
      csrf_login(email)
    ensure
      allow(Auth::Config).to receive(:new).and_call_original
    end

    it 'never restores a remember-cookie session, so a remembered browser cannot mint an intent' do
      expect(Auth::Config.method_defined?(:load_memory)).to be(true), 'remember feature must be enabled'
      csrf_login(email)
      login_sid       = current_sid
      csrf_json_post('/auth/remember', remember: 'remember')
      expect(last_response.status).to eq(200), "POST /auth/remember: #{last_response.status} #{last_response.body}"
      # "<obfuscated account id>_<key>" (account_id_obfuscation is wired, so
      # the prefix is not the raw integer id).
      remember_cookie = rack_mock_session.cookie_jar['_remember']
      expect(remember_cookie).to match(/\A[^_]+_\S+\z/)
      expect(auth_db[:account_remember_keys].where(id: account_id).count).to eq(1)

      # A new browser session: the session cookie is gone, the remember
      # cookie is presented. The request that could call load_memory does not.
      rack_mock_session.cookie_jar.delete('onetime.session')
      clear_body_headers
      header 'Accept', 'application/json'
      get '/auth'
      expect(last_request.env['rack.session']['account_id']).to be_nil,
        'A remember cookie alone must not restore an authenticated session'
      expect(rack_mock_session.cookie_jar['_remember']).to eq(remember_cookie)

      expect(initiate_sso_connect(host: host)).to eq(302)
      expect(last_request.env['rack.session']['account_id']).to be_nil
      expect(last_response.location.to_s).not_to include(Auth::Config::Hooks::OmniAuth::REAUTH_PATH),
        "An anonymous initiation takes the plain sign-in path. Location: #{last_response.location.inspect}"
      expect(intent_live?(login_sid)).to be(false)
      expect(intent_live?(current_sid)).to be(false)
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:omniauth_connect_reauth_required, anything)
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:session_surface_mismatch, anything)
    end

    it 'records no proof for a mailbox-proof primary, so the connect initiation is refused' do
      login_as_mailbox_primary(email)
      sid     = current_sid
      expect(session_blob(sid)['auth_method']).to eq('email_auth'),
        'Precondition failed: after_login must have seen the mailbox primary'
      expect(reauth_proof_live?(sid)).to be(false),
        'after_login must not record a proof for a non-local primary'
      # The recorder refuses the same primary on its own, against this
      # request's real session and surface.
      session = last_request.env['rack.session']
      expect(Onetime::SessionSurface.for_env(last_request.env))
        .to eq('kind' => 'custom', 'id' => @tenant[:domain].identifier)
      expect(Onetime::RecentReauth.record(session, last_request.env, account_id: account_id, methods: %w[email_auth]))
        .to be_nil
      expect(Onetime::SessionSidecar.read(sid, Onetime::RecentReauth::KEY)).to be_nil

      expect(initiate_sso_connect(host: host)).to eq(302)
      expect_reauth_required_redirect
      expect(intent_live?(sid)).to be(false)
      expect(Onetime::SessionSidecar.read(sid, Onetime::RecentReauth::KEY)).to be_nil
      expect(last_request.env['rack.session']['account_id']).to eq(account_id)
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:omniauth_connect_reauth_required, hash_including(provider: 'oidc', account_id: account_id))
    end
  end

  # ==========================================================================
  # Scenario 6 — #4411: the callback's own intent checks
  # ==========================================================================
  #
  # The intent carries the surface the gate verified. A callback arriving on
  # any other surface refuses (defence in depth behind the router's session-
  # surface gate), and an intent that is not the { account_id, surface, at }
  # shape — including the pre-#4411 bare account id — is treated as absent.

  describe 'tenant connect callback pipeline (#3849)', :oauth_flow do
    include OAuthFlowHelper

    let(:host) { "connect-#{SecureRandom.hex(6)}.tenant.example.com" }
    let(:actor_email) { unique_test_email('tenant-connect') }
    let(:other_email) { unique_test_email('asserted-email') }
    let!(:actor_id) { seed_account_with_password(actor_email) }
    let!(:other_id) { seed_account_with_password(other_email) }
    let(:customer) { Onetime::Customer.find_by_extid(auth_db[:accounts].where(id: actor_id).get(:external_id)) }
    let(:uid) { "connect-sub-#{SecureRandom.hex(8)}" }
    let(:tuple) { { provider: 'oidc', issuer: OmniAuthTestHelper::MOCK_ISSUER, uid: uid } }

    before do
      @tenant = setup_oauth_test_domain(host)
      Onetime::CustomDomain::SigninConfig.create!(
        domain_id: @tenant[:domain].identifier, enabled: true, signin_enabled: true, sso_enabled: true,
      )
      @membership = Onetime::OrganizationMembership.ensure_membership(
        @tenant[:org], customer, role: 'member',
        domain_scope_id: @tenant[:domain].objid, provisioning_source: 'sso',
      )
      header 'Host', host
      csrf_login(actor_email)
      expect(last_request.env['rack.session']['account_id']).to eq(actor_id)
      allow(Auth::Logging).to receive(:log_auth_event).and_call_original
      allow(Auth::Operations::JoinDomainOrganization).to receive(:new).and_call_original
      allow(Onetime.auth_config).to receive(:trust_email_for_linking?).and_return(false)
      setup_mock_auth(email: other_email, uid: uid)
      expect(initiate_sso_connect(host: host)).to eq(302)
      @connect_sid = last_request.env['rack.session'].id.public_id
      expect(intent_live?(@connect_sid)).to be(true), "Connect initiation redirected to #{last_response.location.inspect}"
      expect(reauth_proof_live?(@connect_sid)).to be(false)
      @accounts_before = auth_db[:accounts].count
    end

    after { teardown_mock_auth }

    def tenant_connect_callback
      clear_body_headers
      post '/auth/sso/oidc/callback'
      expect(last_response.status).to eq(302)
      expect(intent_live?(@connect_sid)).to be(false)
      expect(auth_db[:accounts].count).to eq(@accounts_before)
    end

    def expect_connect_refused(reason, code: 'identity_connect_wrong_domain')
      expect_auth_error_redirect(code)
      expect(last_request.env['rack.session']['account_id']).to eq(actor_id)
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:omniauth_identity_connect_refused, hash_including(reason: reason))
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:omniauth_identity_connected, anything)
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:omniauth_link_challenge_issued, anything)
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:sso_link_verification_issued, anything)
      expect(Auth::Operations::JoinDomainOrganization).not_to have_received(:new)
    end

    # A suspended Customer never reaches the Connect hook from a live
    # session: the auth router's customer-session gate destroys the Rack
    # session ahead of Rodauth (:account_suspended is a definitive
    # rejection), which purges the Connect intent with it. The callback then
    # runs as the anonymous request it now is, exactly as it does after the
    # router's surface-mismatch and revocation destroys. In production that
    # callback fails OmniAuth's state check, the state having gone with the
    # session; mock mode skips the check, so what the anonymous callback does
    # next is not asserted here. What is asserted: the session is gone, the
    # intent is gone, and nothing was bound to the suspended account.
    def expect_suspended_session_rejected(sid, account_id)
      expect(Auth::Logging).to have_received(:log_auth_event).with(
        :customer_session_rejected,
        hash_including(
          path: '/sso/oidc/callback',
          reason: :account_suspended,
          outcome: :continued_anonymous,
          account_id: account_id,
          sidecar_fields: ['sso_connect_intent'],
        ),
      )
      expect(intent_live?(sid)).to be(false)
      expect(Onetime::Operations::Sessions::Store.find_key(Familia.dbclient, sid)).to be_nil
      expect(identities.where(account_id: account_id).count).to eq(0)
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:omniauth_identity_connected, anything)
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:tenant_connect_membership_authorized, anything)
    end

    it 'binds an unclaimed exact tuple to the session account, ignoring another account email' do
      identities.insert(tuple.merge(uid: "other-#{uid}", account_id: other_id))
      expect(customer.signup_domain_id.to_s).to be_empty
      membership_id    = @membership.objid
      membership_scope = @membership.domain_scope_id
      tenant_connect_callback

      expect(identities.where(tuple).all).to contain_exactly(hash_including(account_id: actor_id))
      expect(identities.where(account_id: other_id).all)
        .to contain_exactly(hash_including(uid: "other-#{uid}", issuer: tuple[:issuer]))
      expect(last_request.env['rack.session']['account_id']).to eq(actor_id)
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:tenant_connect_membership_authorized, hash_including(domain_id: @tenant[:domain].identifier))
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:omniauth_identity_connected, hash_including(account_id: actor_id, issuer: tuple[:issuer]))
      persisted = Onetime::OrganizationMembership.find_by_org_customer(@tenant[:org].objid, customer.objid)
      expect(persisted.objid).to eq(membership_id)
      expect(persisted.domain_scope_id).to eq(membership_scope)
      expect(Auth::Operations::JoinDomainOrganization).to have_received(:new)
        .with(customer: an_object_having_attributes(objid: customer.objid), domain_id: @tenant[:domain].identifier)
    end

    it 'binds for an organization-scoped membership through the callback and preserves that scope' do
      @membership.domain_scope_id = nil
      @membership.save

      tenant_connect_callback

      expect(identities.where(tuple).all).to contain_exactly(hash_including(account_id: actor_id))
      persisted = Onetime::OrganizationMembership.find_by_org_customer(@tenant[:org].objid, customer.objid)
      expect(persisted.objid).to eq(@membership.objid)
      expect(persisted.domain_scope_id).to be_nil
      expect(persisted.org_scoped?).to be(true)
    end

    it 'binds for the organization owner through the callback' do
      owner = @oauth_test_fixtures.last[:owner]
      @membership.destroy!
      auth_db[:accounts].where(id: actor_id).update(external_id: owner.extid)

      tenant_connect_callback

      expect(identities.where(tuple).all).to contain_exactly(hash_including(account_id: actor_id))
      owner_membership = Onetime::OrganizationMembership.find_by_org_customer(@tenant[:org].objid, owner.objid)
      expect(owner_membership).to be_owner
    end

    it 'accepts a known same-account tuple idempotently and consumes intent before the gem shortcut' do
      identity_id = identities.insert(tuple.merge(account_id: actor_id))
      tenant_connect_callback

      expect(identities.where(tuple).all).to contain_exactly(hash_including(id: identity_id, account_id: actor_id))
      expect(last_request.env['rack.session']['account_id']).to eq(actor_id)
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:tenant_connect_membership_authorized, anything)
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:omniauth_identity_connected, hash_including(account_id: actor_id))
    end

    it 'refuses a known other-account tuple without switching the authenticated account' do
      identity_id = identities.insert(tuple.merge(account_id: other_id))
      tenant_connect_callback

      expect_connect_refused('identity_owned_elsewhere', code: 'identity_connect_conflict')
      expect(identities.where(tuple).all).to contain_exactly(hash_including(id: identity_id, account_id: other_id))
      expect(identities.where(account_id: actor_id).count).to eq(0)
    end

    # The tenant Connect kill switch (#4427) is not stubbed open anywhere in
    # this file: every tenant example runs against its production value.
    it 'is open in production' do
      allow(Auth::Operations::AuthorizeTenantConnect).to receive(:call).and_call_original
      expect(Auth::Config::Hooks::OmniAuthConnect.tenant_connect_enabled?).to be(true)
      identity_id = identities.insert(tuple.merge(account_id: actor_id))
      tenant_connect_callback

      expect(Auth::Operations::AuthorizeTenantConnect).to have_received(:call)
        .with(hash_including(domain_id: @tenant[:domain].identifier))
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:tenant_connect_membership_authorized, anything)
      expect(identities.where(tuple).all).to contain_exactly(hash_including(id: identity_id, account_id: actor_id))
    end

    it 'when closed, refuses ahead of the membership gate' do
      allow(Auth::Config::Hooks::OmniAuthConnect).to receive(:tenant_connect_enabled?).and_return(false)
      allow(Auth::Operations::AuthorizeTenantConnect).to receive(:call).and_call_original
      identities.insert(tuple.merge(account_id: actor_id))
      tenant_connect_callback

      expect_connect_refused('tenant_connect_prerequisites_incomplete')
      expect(Auth::Operations::AuthorizeTenantConnect).not_to have_received(:call)
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:tenant_connect_membership_authorized, anything)
      expect(identities.where(tuple).count).to eq(1)
    end

    it 'refuses as lookup_error when a gate raises before the bind, writing nothing' do
      allow(Auth::Operations::AuthorizeTenantConnect).to receive(:call).and_raise(RuntimeError, 'membership store down')
      tenant_connect_callback

      expect_connect_refused('lookup_error', code: 'identity_connect_conflict')
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:omniauth_connect_lookup_error, hash_including(error_class: 'RuntimeError'))
      expect(identities.where(tuple).count).to eq(0)
    end

    it 'does not report a bound identity as refused when a post-bind step fails' do
      allow(Auth::Logging).to receive(:log_auth_event)
        .with(:omniauth_identity_connected, anything).and_raise(RuntimeError, 'audit sink down')
      clear_body_headers
      post '/auth/sso/oidc/callback'

      expect(last_response.status).to eq(500)
      expect(intent_live?(@connect_sid)).to be(false)
      expect(identities.where(tuple).all).to contain_exactly(hash_including(account_id: actor_id))
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:omniauth_identity_connect_refused, anything)
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:omniauth_connect_lookup_error, anything)
    end

    %w[missing inactive sibling wrong_organization].each do |state|
      it "refuses #{state} membership before a known identity can bypass authorization" do
        identities.insert(tuple.merge(account_id: other_id))
        other_membership = nil
        case state
        when 'missing'
          @membership.destroy!
        when 'inactive'
          @membership.status = 'pending'
          @membership.save
        when 'sibling'
          sibling = Onetime::CustomDomain.new(
            display_domain: "sibling-#{SecureRandom.hex(6)}.tenant.example.com", org_id: @tenant[:org].org_id,
          )
          sibling.save
          @membership.domain_scope_id = sibling.objid
          @membership.save
        when 'wrong_organization'
          @membership.destroy!
          other_tenant = setup_oauth_test_domain("other-org-#{SecureRandom.hex(6)}.tenant.example.com")
          other_membership = Onetime::OrganizationMembership.ensure_membership(
            other_tenant[:org], customer, role: 'member', domain_scope_id: other_tenant[:domain].objid,
            provisioning_source: 'sso',
          )
        end
        tenant_connect_callback

        expect_connect_refused('tenant_membership_refused')
        expect(identities.where(tuple).all).to contain_exactly(hash_including(account_id: other_id))
        membership = Onetime::OrganizationMembership.find_by_org_customer(@tenant[:org].objid, customer.objid)
        if %w[missing wrong_organization].include?(state)
          expect(membership).to be_nil
          expect(other_membership&.active?).to be(true) if state == 'wrong_organization'
        else
          expect(membership.status).to eq(@membership.status)
          expect(membership.domain_scope_id).to eq(@membership.domain_scope_id)
        end
      end
    end

    it 'refuses an intent for a different exact domain even within the same organization' do
      sibling = Onetime::CustomDomain.new(
        display_domain: "intent-sibling-#{SecureRandom.hex(6)}.tenant.example.com", org_id: @tenant[:org].org_id,
      )
      sibling.save
      identities.insert(tuple.merge(account_id: other_id))
      Onetime::SessionSidecar.write(@connect_sid, 'sso_connect_intent', {
        'account_id' => actor_id, 'at' => Time.now.utc.to_i,
        'surface' => { 'kind' => 'custom', 'id' => sibling.identifier },
      })
      tenant_connect_callback

      expect_connect_refused('surface_mismatch')
      expect(identities.where(tuple).all).to contain_exactly(hash_including(account_id: other_id))
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:tenant_connect_membership_authorized, anything)
    end

    it 'refuses a session account closed during the IdP round trip, even for a known tuple' do
      identities.insert(tuple.merge(account_id: other_id))
      auth_db[:accounts].where(id: actor_id).update(status_id: Auth::AccountStatuses::CLOSED)
      tenant_connect_callback

      expect_connect_refused('session_account_missing', code: 'identity_connect_conflict')
      expect(identities.where(tuple).all).to contain_exactly(hash_including(account_id: other_id))
    end

    it 'consumes intent even when tenant email policy rejects before account resolution' do
      @tenant[:sso_config].allowed_domains = ['allowed.example.com']
      @tenant[:sso_config].save
      identities.insert(tuple.merge(account_id: other_id))
      tenant_connect_callback

      expect_auth_error_redirect('domain_not_allowed')
      expect(last_request.env['rack.session']['account_id']).to eq(actor_id)
      expect(identities.where(tuple).all).to contain_exactly(hash_including(account_id: other_id))
      expect(Auth::Operations::JoinDomainOrganization).not_to have_received(:new)
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:omniauth_identity_connected, anything)
    end

    # Break exactly one tenant gate so the callback refuses with `reason`.
    # The IdP asserts other_email (the victim) throughout, per the describe's
    # setup_mock_auth.
    def break_tenant_gate(reason)
      case reason
      when 'surface_mismatch'
        sibling       = Onetime::CustomDomain.new(
          display_domain: "nofallback-#{SecureRandom.hex(6)}.tenant.example.com", org_id: @tenant[:org].org_id,
        )
        sibling.save
        forged_intent = {
          'account_id' => actor_id,
          'at' => Time.now.utc.to_i,
          'surface' => { 'kind' => 'custom', 'id' => sibling.identifier },
        }
        Onetime::SessionSidecar.write(@connect_sid, 'sso_connect_intent', forged_intent)
      when 'tenant_connect_prerequisites_incomplete'
        # The kill switch is open in production; close it for this row only.
        allow(Auth::Config::Hooks::OmniAuthConnect).to receive(:tenant_connect_enabled?).and_return(false)
      when 'tenant_membership_refused'
        @membership.status = 'pending'
        @membership.save
      when 'identity_owned_elsewhere'
        identities.insert(tuple.merge(account_id: other_id))
      else
        raise ArgumentError, "unknown tenant gate #{reason.inspect}"
      end
    end

    # The "No fallback" row: with trusted-email linking ON and the victim's
    # email asserted, a refusal at any tenant gate must not divert into the
    # unauthenticated email branches (direct trust bind, password challenge,
    # mailbox proof) or the JIT create path.
    {
      'surface_mismatch' => 'identity_connect_wrong_domain',
      'tenant_connect_prerequisites_incomplete' => 'identity_connect_wrong_domain',
      'tenant_membership_refused' => 'identity_connect_wrong_domain',
      'identity_owned_elsewhere' => 'identity_connect_conflict',
    }.each do |reason, code|
      it "does not fall back to trusted-email linking after the #{reason} gate" do
        allow(Onetime.auth_config).to receive(:trust_email_for_linking?).and_return(true)
        allow(Onetime::SsoLinkChallenge).to receive(:issue).and_call_original
        allow(Onetime::SsoLinkVerification).to receive(:issue).and_call_original
        victim = Onetime::Customer.find_by_extid(auth_db[:accounts].where(id: other_id).get(:external_id))
        break_tenant_gate(reason)

        tenant_connect_callback

        expect_connect_refused(reason, code: code)
        expect(identities.where(account_id: actor_id).count).to eq(0)
        expect(identities.where(tuple).count).to eq(reason == 'identity_owned_elsewhere' ? 1 : 0)
        expect(Onetime::OrganizationMembership.find_by_org_customer(@tenant[:org].objid, victim.objid)).to be_nil
        persisted = Onetime::OrganizationMembership.find_by_org_customer(@tenant[:org].objid, customer.objid)
        expect(persisted.objid).to eq(@membership.objid)
        expect(persisted.status).to eq(@membership.status)
        expect(persisted.domain_scope_id).to eq(@membership.domain_scope_id)
        expect(Onetime::SsoLinkChallenge).not_to have_received(:issue)
        expect(Onetime::SsoLinkVerification).not_to have_received(:issue)
      end
    end

    it 'consumes a live intent before the tenant-context mismatch refusal and binds nothing' do
      # The router's surface gate (#4409) destroys an authenticated session
      # that arrives on any other host before Rodauth runs, so the tenant
      # hook's own mismatch (omniauth_tenant.rb, the 403 that
      # callback_validation_spec.rb reaches ANONYMOUSLY) cannot be reached
      # from a live session by changing Host — that path is the tenant A ->
      # tenant B example below. To reach the 403 with a live, matching intent,
      # rewrite the tenant context the request phase stashed in the session
      # blob so the callback on THIS host disagrees with it. The intent's
      # consumption is the property under test: the Connect wrapper runs
      # ahead of the tenant hook, so the refusal must not leave it replayable.
      other_tenant = setup_oauth_test_domain("mismatch-#{SecureRandom.hex(6)}.tenant.example.com")
      stash_in_session_blob(@connect_sid, 'omniauth_tenant_domain_id', other_tenant[:domain].identifier)
      victim       = Onetime::Customer.find_by_extid(auth_db[:accounts].where(id: other_id).get(:external_id))

      clear_body_headers
      post '/auth/sso/oidc/callback'

      expect(last_response.status).to eq(403), "Expected tenant_mismatch 403, got #{last_response.status}: #{last_response.body}"
      expect(last_response.body).to include('tenant_mismatch')
      expect(intent_live?(@connect_sid)).to be(false)
      expect(auth_db[:accounts].count).to eq(@accounts_before)
      expect(identities.where(tuple).count).to eq(0)
      expect(identities.where(account_id: actor_id).count).to eq(0)
      expect(Onetime::OrganizationMembership.find_by_org_customer(@tenant[:org].objid, victim.objid)).to be_nil
      expect(Onetime::OrganizationMembership.find_by_org_customer(@tenant[:org].objid, customer.objid).objid)
        .to eq(@membership.objid)
      expect(Auth::Operations::JoinDomainOrganization).not_to have_received(:new)
      mismatch = { expected_domain_id: other_tenant[:domain].identifier, actual_domain_id: @tenant[:domain].identifier }
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:omniauth_tenant_mismatch, hash_including(mismatch))
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:omniauth_identity_connected, anything)
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:tenant_connect_membership_authorized, anything)
    end

    it 'refuses a tenant A session presented to the tenant B callback and consumes its intent' do
      other_tenant = setup_oauth_test_domain("tenant-b-#{SecureRandom.hex(6)}.tenant.example.com")
      Onetime::CustomDomain::SigninConfig.create!(
        domain_id: other_tenant[:domain].identifier, enabled: true, signin_enabled: true, sso_enabled: true,
      )
      clear_body_headers
      header 'Host', other_tenant[:domain].display_domain
      header 'Cookie', "onetime.session=#{@connect_sid}"
      post '/auth/sso/oidc/callback'

      # The router's surface gate destroys the session ahead of Rodauth (the
      # intent goes with it), so the callback continues anonymous on tenant
      # B's host — where B's options were injected but no tenant flow is
      # pending. The tenant hook refuses that as tenant_context_missing
      # rather than letting it run as a platform sign-in (in production
      # OmniAuth's own state check, which mock mode skips, refuses it first).
      expect(last_response.status).to eq(403), "Expected tenant_context_missing 403, got #{last_response.status}: #{last_response.body}"
      expect(last_response.body).to include('tenant_context_missing')
      expect(intent_live?(@connect_sid)).to be(false)
      expect(auth_db[:accounts].count).to eq(@accounts_before)
      expect(identities.where(tuple).count).to eq(0)
      expect(identities.where(account_id: actor_id).count).to eq(0)
      mismatch = {
        path: '/sso/oidc/callback',
        outcome: :continued_anonymous,
        recorded_surface: { 'kind' => 'custom', 'id' => @tenant[:domain].identifier },
        request_surface: { 'kind' => 'custom', 'id' => other_tenant[:domain].identifier },
      }
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:session_surface_mismatch, hash_including(mismatch))
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:omniauth_identity_connected, anything)
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:tenant_connect_membership_authorized, anything)
    end

    it 'post-login: a successful Connect adopts the tenant org as default and archives the personal workspace' do
      # The Post-login row's "asserted separately" evidence. The account still
      # owns an unarchived personal default workspace (a legacy platform
      # signup); JoinDomainOrganization's already_member path repoints
      # default_org_id and archives it, without touching the membership.
      personal = Onetime::Organization.create!("Personal #{SecureRandom.hex(4)}", customer, customer.email)
      personal.is_default! true
      expect(personal.owner?(customer)).to be(true)
      expect(personal.archived?).to be(false)

      customer.default_org_id = personal.objid
      customer.save
      tenant_connect_callback

      expect(identities.where(tuple).all).to contain_exactly(hash_including(account_id: actor_id))
      expect(Auth::Operations::JoinDomainOrganization).to have_received(:new)
        .with(customer: an_object_having_attributes(objid: customer.objid), domain_id: @tenant[:domain].identifier)
      persisted = Onetime::OrganizationMembership.find_by_org_customer(@tenant[:org].objid, customer.objid)
      expect(persisted.objid).to eq(@membership.objid)
      expect(persisted.domain_scope_id).to eq(@membership.domain_scope_id)
      expect(Onetime::Customer.load(customer.objid).default_org_id).to eq(@tenant[:org].objid)
      expect(Onetime::Organization.load(personal.objid).archived?).to be(true)
    end

    it 'refuses a tenant session presented to the platform callback and consumes its intent' do
      allow(Auth::Logging).to receive(:log_auth_event).and_call_original
      clear_body_headers
      header 'Host', canonical_host
      header 'Cookie', "onetime.session=#{@connect_sid}"
      post '/auth/sso/oidc/callback'

      expect(last_response.status).to eq(302)
      expect(intent_live?(@connect_sid)).to be(false)
      expect(identities.where(tuple).count).to eq(0)
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:session_surface_mismatch, hash_including(path: '/sso/oidc/callback', outcome: :continued_anonymous))
    end

    it 'does not reuse a refused intent on a second callback' do
      @membership.status = 'pending'
      @membership.save
      tenant_connect_callback
      expect_connect_refused('tenant_membership_refused')

      @membership.status = 'active'
      @membership.save
      # The first callback consumed the pending tenant markers along with the
      # intent, so this second answer arrives on the tenant host with no
      # tenant flow pending. The Connect wrapper consumes (finds nothing)
      # ahead of the tenant hook, which then refuses the callback as
      # tenant_context_missing before any identity can bind — and before the
      # wrapper's own intent-absent note, which sits downstream of the halt.
      clear_body_headers
      post '/auth/sso/oidc/callback'
      expect(last_response.status).to eq(403), "Expected tenant_context_missing 403, got #{last_response.status}: #{last_response.body}"
      expect(last_response.body).to include('tenant_context_missing')
      expect(intent_live?(@connect_sid)).to be(false)
      expect(auth_db[:accounts].count).to eq(@accounts_before)
      expect(identities.where(tuple).count).to eq(0)
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:omniauth_identity_connected, anything)
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:tenant_connect_membership_authorized, anything)
    end

    %w[absent mismatched].each do |state|
      it "takes the ordinary tenant sign-in path for #{state} intent" do
        Onetime::SessionSidecar.delete(@connect_sid, 'sso_connect_intent')
        if state == 'mismatched'
          Onetime::SessionSidecar.write(@connect_sid, 'sso_connect_intent', {
            'account_id' => other_id, 'at' => Time.now.utc.to_i,
            'surface' => { 'kind' => 'custom', 'id' => @tenant[:domain].identifier },
          })
        end
        tenant_connect_callback

        expect_auth_error_redirect('tenant_sso_link_unavailable')
        expect(identities.where(tuple).count).to eq(0)
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_connect_intent_absent, hash_including(had_intent: state == 'mismatched'))
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_identity_connect_refused, anything)
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:tenant_connect_membership_authorized, anything)
      end
    end

    it 'refuses a missing session Customer before resolving a known tuple' do
      identities.insert(tuple.merge(account_id: other_id))
      auth_db[:accounts].where(id: actor_id).update(external_id: "ur#{SecureRandom.hex(8)}")
      tenant_connect_callback

      expect_connect_refused('session_customer_missing', code: 'identity_connect_conflict')
      expect(identities.where(tuple).all).to contain_exactly(hash_including(account_id: other_id))
    end

    it 'destroys a suspended session at the router, so its Connect intent binds nothing' do
      identities.insert(tuple.merge(account_id: other_id))
      customer.suspended = 'true'
      customer.save
      # Destroyed at the router, the callback continues anonymous on the
      # tenant host with no tenant flow pending, and the tenant hook refuses
      # it (tenant_context_missing). Nothing binds on either side of that.
      clear_body_headers
      post '/auth/sso/oidc/callback'
      expect(last_response.status).to eq(403), "Expected tenant_context_missing 403, got #{last_response.status}: #{last_response.body}"
      expect(last_response.body).to include('tenant_context_missing')
      expect(auth_db[:accounts].count).to eq(@accounts_before)

      expect_suspended_session_rejected(@connect_sid, actor_id)
      expect(identities.where(tuple).all).to contain_exactly(hash_including(account_id: other_id))
    end
  end

  describe 'platform connect principal gate (#3849)' do
    %w[missing suspended].each do |state|
      it "binds nothing for a #{state} Customer on a live platform session and consumes intent" do
        enable_platform_fallback
        email = unique_test_email('platform-principal')
        account_id = seed_account_with_password(email)
        csrf_login(email)
        setup_mock_auth(email: email)
        begin
          expect(initiate_sso_connect).to eq(302)
          sid = current_sid
          expect(intent_live?(sid)).to be(true)
          if state == 'missing'
            auth_db[:accounts].where(id: account_id).update(external_id: "ur#{SecureRandom.hex(8)}")
          else
            customer = Onetime::Customer.find_by_extid(auth_db[:accounts].where(id: account_id).get(:external_id))
            customer.suspended = 'true'
            customer.save
          end
          allow(Auth::Logging).to receive(:log_auth_event).and_call_original
          clear_body_headers
          post '/auth/sso/oidc/callback'

          expect(intent_live?(sid)).to be(false)
          expect(identities.where(account_id: account_id).count).to eq(0)
          if state == 'missing'
            expect_auth_error_redirect('identity_connect_conflict')
            expect(last_request.env['rack.session']['account_id']).to eq(account_id)
            expect(Auth::Logging).to have_received(:log_auth_event)
              .with(:omniauth_identity_connect_refused, hash_including(reason: 'session_customer_missing'))
          else
            # The router's customer-session gate destroys a suspended session
            # ahead of Rodauth, so the Connect hook's own suspension refusal
            # is not reached; the intent is purged with the session and the
            # callback continues anonymous (in production it then fails
            # OmniAuth's state check, which mock mode skips).
            expect(Onetime::Operations::Sessions::Store.find_key(Familia.dbclient, sid)).to be_nil
            expect(Auth::Logging).to have_received(:log_auth_event).with(
              :customer_session_rejected,
              hash_including(
                path: '/sso/oidc/callback',
                reason: :account_suspended,
                outcome: :continued_anonymous,
                account_id: account_id,
                sidecar_fields: ['sso_connect_intent'],
              ),
            )
            expect(Auth::Logging).not_to have_received(:log_auth_event)
              .with(:omniauth_identity_connected, anything)
          end
        ensure
          teardown_mock_auth
        end
      end
    end
  end

  describe 'callback intent binding (#4411)' do
    let(:actor_email) { "actor-intent-#{SecureRandom.hex(6)}@company.example.com" }
    let(:uid) { "sub-#{SecureRandom.hex(8)}" }
    let!(:actor_id) { seed_account_with_password(actor_email) }

    before do
      enable_platform_fallback
      csrf_login(actor_email)
      unless (200..302).cover?(last_response.status)
        raise "Precondition failed: password login did not succeed (#{last_response.status}: #{last_response.body})"
      end

      allow(Onetime.auth_config).to receive(:trust_email_for_linking?).and_return(false)
      allow(Auth::Logging).to receive(:log_auth_event).and_call_original
      setup_mock_auth(email: actor_email, uid: uid)
    end

    after { teardown_mock_auth }

    it 'refuses an intent whose recorded surface differs from the callback surface' do
      sid = current_sid
      Onetime::SessionSidecar.write(
        sid,
        'sso_connect_intent',
        {
          'account_id' => actor_id,
          'surface' => { 'kind' => 'custom', 'id' => "cd-#{SecureRandom.hex(4)}" },
          'at' => Time.now.utc.to_i,
        },
      )

      clear_body_headers
      post '/auth/sso/oidc/callback'

      skip 'OmniAuth route not registered' if last_response.status == 404

      expect(last_response.status).to eq(302)
      expect(last_response.location.to_s).to include('/signin?auth_error=identity_connect_wrong_domain'),
        "A surface-mismatched intent must refuse. Location: #{last_response.location.inspect}"
      expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0),
        'A surface-mismatched intent must NOT bind'
      expect(intent_live?(sid)).to be(false), 'The refused intent is consumed, never replayable'
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:omniauth_identity_connect_refused, hash_including(provider: 'oidc', reason: 'surface_mismatch'))
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:omniauth_identity_connected, anything)
    end

    it 'treats a pre-#4411 bare account-id intent as absent (never binds)' do
      sid = current_sid
      Onetime::SessionSidecar.write(sid, 'sso_connect_intent', actor_id)

      clear_body_headers
      post '/auth/sso/oidc/callback'

      skip 'OmniAuth route not registered' if last_response.status == 404

      expect(last_response.status).to eq(302)
      expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0),
        'A malformed intent must NOT bind'
      expect(intent_live?(sid)).to be(false)
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:omniauth_connect_intent_absent, hash_including(provider: 'oidc', had_intent: true))
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:omniauth_identity_connected, anything)
    end
  end
end
