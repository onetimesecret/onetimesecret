# apps/web/auth/spec/integration/full/sso_link_confirm_mailbox_proof_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# Issue: #3840 Phase 4 — MAILBOX-PROOF linking for PASSWORDLESS SSO accounts.
#        An UNAUTHENTICATED SSO sign-in whose IdP email matches an EXISTING
#        PASSWORDLESS account on the PLATFORM surface can no longer be helped by
#        Phase 3's password interstitial (there is no password to challenge).
#        Phase 4 instead mints a single-use Onetime::SsoLinkVerification, EMAILS
#        the token to the account's ON-FILE address, and redirects the browser
#        TOKEN-LESSLY to /signin?auth_notice=link_verification_sent. Clicking the
#        emailed link opens the SPA confirm page, which:
#          GET  /auth/sso-link-confirm/:token -> { provider, email } (display only,
#               NEVER consumes)
#          POST /auth/sso-link-confirm { token } -> atomic single-use consume ->
#               re-verify ownership + watermark -> MFA gate ->
#               Auth::Operations::BindSsoIdentity -> rodauth.login('sso_link_confirm')
#
#        INVARIANT: email may LOCATE an account; only a demonstrated credential may
#        BIND. Here the credential is MAILBOX CONTROL — the token travels ONLY via
#        the emailed link, NEVER in the callback redirect, so completing an SSO
#        round-trip that merely asserts the victim's email discloses nothing that
#        lets a caller self-consume the token.
#
# WHAT IT LOCKS IN (production code, ALL uncommitted working-tree at time of
#   writing — see the concurrent-writer note in the run report):
#     config/hooks/omniauth.rb (the `elsif platform_surface` mailbox branch),
#     routes/sso_link_confirm.rb, operations/confirm_sso_link.rb,
#     operations/bind_sso_identity.rb, models/sso_link_verification.rb.
#
#   1. passwordless PLATFORM callback -> TOKEN-LESS link_verification_sent redirect
#      AND an email enqueued to the on-file address; GET display is non-consuming;
#      POST binds (provider,issuer,uid), logs in (after_login), fires
#      :sso_link_verification_confirmed.
#   2. GET is non-consuming: GET twice, POST still succeeds.
#   3. single-use: second POST -> 401 link_expired.
#   4. TTL/expiry: gone token -> GET 404 / POST 401 link_expired.
#   5. soft cross-device bind: POST from a DIFFERENT sid still SUCCEEDS and fires
#      :sso_link_verification_cross_device (info) — never a hard reject.
#   6. conflict: (provider,issuer,uid) owned by ANOTHER account -> 409 link_conflict,
#      no rebind.
#   7. watermark invalidation: a credential change after issuance -> 409
#      link_invalidated.
#   8. refusal fail-closed: tenant surface, a delivery failure, OR an unresolvable
#      Customer -> account_exists_link_required and NO usable token remains.
#      "Delivery failure" covers the NON-RAISING shapes too — the mail layer
#      dispatching nothing, a suppressed recipient, EMAILER_MODE=disabled — because
#      each of those returns normally and would otherwise be reported as "sent".
#      "Unresolvable Customer" is the issuance/confirm SYMMETRY case: confirm rejects
#      that state (:unreadable -> 409), so issuing would mail a permanently
#      unredeemable link.
#   9. MFA-deferred: pending second factor -> mfa_required, identity NOT bound
#      (PENDING — needs an AUTH_MFA_ENABLED boot; see the example).
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTHENTICATION_MODE=full, AUTH_DATABASE_URL (SQLite in-memory; rake sets it)
#
# RUN:
#   RACK_ENV=test AUTHENTICATION_MODE=full AUTH_DATABASE_URL=sqlite::memory: \
#     ORGS_SSO_ENABLED=true LANG=en_US.UTF-8 \
#     bundle exec rspec \
#     apps/web/auth/spec/integration/full/sso_link_confirm_mailbox_proof_spec.rb \
#     --tag '~postgres_database'
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../support/oauth_flow_helper'

RSpec.describe 'SSO mailbox-proof link confirm (#3840 Phase 4)', type: :integration do
  include Rack::Test::Methods

  def app
    Onetime::Application::Registry.generate_rack_url_map
  end

  before(:all) do
    require 'onetime'
    require 'onetime/application/registry'
    require 'onetime/auth_config'
    # The delivery examples stub Onetime::Mail / Mailer directly; the hook only
    # requires the mail stack lazily, so make sure the constants exist first.
    require 'onetime/mail'

    Onetime.auth_config.reload! if Onetime.respond_to?(:auth_config) && Onetime.auth_config.respond_to?(:reload!)
    Onetime::Application::Registry.reset! if Onetime::Application::Registry.respond_to?(:reset!)

    Onetime.boot!(:test, force: true)

    Onetime::Application::Registry.prepare_application_registry

    mounts = Onetime::Application::Registry.mount_mappings.keys
    raise "Auth app not mounted post-boot: #{mounts.inspect}" unless mounts.any? { |m| m.include?('/auth') }
  end

  let(:identities) { auth_db[:account_identities] }

  # ==========================================================================
  # Helpers (mirror omniauth_signin_interstitial_spec.rb / omniauth_connect_link_spec.rb)
  # ==========================================================================

  # Leaves session[:validated_omniauth_domain_id] nil == the PLATFORM path, so a
  # non-tenant callback proceeds on platform credentials rather than redirecting to
  # sso_not_configured.
  def enable_platform_fallback
    allow(Onetime.auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
  end

  # Seed a VERIFIED account WITHOUT a password (a PASSWORDLESS / SSO-only account —
  # the Phase 4 subject). Also seeds the paired Customer so the watermark probe
  # (Customer#last_password_update, via load_by_extid_or_email) resolves.
  def seed_passwordless_account(email)
    normalized = OT::Utils.normalize_email(email)
    customer   = Onetime::Customer.new(email: normalized)
    customer.save
    auth_db[:accounts].insert(
      email: normalized,
      status_id: AuthTestConstants::STATUS_VERIFIED,
      external_id: customer.extid,
    )
  end

  # Seed a VERIFIED PASSWORDLESS account whose paired Customer CANNOT be resolved:
  # the row carries an external_id no Customer holds, and no Customer exists at the
  # address either — so Customer.load_by_extid_or_email (the identifier logic BOTH
  # the issuance hook and ConfirmSsoLink#watermark_state use) returns nil.
  #
  # This is the terminal state of the field case the issuance gate exists for: in
  # production `accounts.email` is citext (case-insensitive compare, case-PRESERVING
  # storage) while the Customer email index is a case-SENSITIVE Redis hash, so a
  # legacy mixed-case row that migrations/007_normalize_customer_emails.rb skipped
  # probes the index and misses. That exact shape cannot be staged in this harness
  # (SQLite compares TEXT case-sensitively, so the account itself would not be
  # located), and a dangling external_id reaches the same nil through the same call —
  # which is all the gate keys on.
  def seed_account_without_customer(email)
    auth_db[:accounts].insert(
      email: OT::Utils.normalize_email(email),
      status_id: AuthTestConstants::STATUS_VERIFIED,
      external_id: "cust-missing-#{SecureRandom.hex(8)}",
    )
  end

  def setup_mock_auth(email:, uid:, provider: :oidc)
    OmniAuth.config.test_mode               = true
    OmniAuth.config.allowed_request_methods = [:get, :post]
    OmniAuth.config.mock_auth[provider]     = OmniAuth::AuthHash.new(
      {
        provider: provider.to_s,
        uid: uid,
        info: { email: email, name: 'Mailbox User', email_verified: true },
        credentials: { token: 'mock_access_token', expires_at: Time.now.to_i + 3600, expires: true },
        extra: { raw_info: { sub: uid, email: email, name: 'Mailbox User', email_verified: true } },
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

  # Drive the UNAUTHENTICATED SSO callback and return the response.
  def sso_callback(email:, uid:, provider: :oidc)
    setup_mock_auth(email: email, uid: uid, provider: provider)
    clear_body_headers
    post "/auth/sso/#{provider}/callback"
    last_response
  end

  # Fetch a CSRF token from the app bootstrap. The verification lives in Redis, not
  # the session, so establishing a fresh session here does not disturb it — and (for
  # the cross-device example) it deliberately makes the POST's current_sid DIFFER
  # from the token's snapshotted sid.
  def fetch_csrf_token
    clear_body_headers
    header 'Accept', 'application/json'
    get '/auth'
    last_response.headers['X-CSRF-Token']
  end

  # GET /auth/sso-link-confirm/:token — the display-only consent context.
  def get_confirm(token)
    clear_body_headers
    header 'Accept', 'application/json'
    get "/auth/sso-link-confirm/#{token}"
    last_response
  end

  # POST /auth/sso-link-confirm { token } — the atomic consume + bind + login.
  def post_confirm(token:)
    csrf = fetch_csrf_token
    clear_body_headers
    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', csrf if csrf
    post '/auth/sso-link-confirm', JSON.generate(token: token)
    last_response
  end

  # Mint a verification directly — the POST endpoint can be exercised without a full
  # SSO round-trip, since the token carries the snapshot the op reloads. account_id,
  # sid, and password_watermark are caller-supplied so tests can drive the conflict,
  # cross-device, and watermark branches deterministically.
  def mint_verification(email:, uid:, account_id:, provider: 'oidc',
                        issuer: 'https://issuer.example.com', sid: nil, password_watermark: 0)
    Onetime::SsoLinkVerification.issue(
      provider: provider,
      issuer: issuer,
      uid: uid,
      email: OT::Utils.normalize_email(email),
      account_id: account_id,
      sid: sid,
      password_watermark: password_watermark,
    )
  end

  # Stub the templated publisher and CAPTURE every enqueue_email call. Returns the
  # capture buffer. Returning true means the message was QUEUED — the only outcome
  # the hook accepts as "delivered" without delivering inline itself — so the flow
  # takes the link_verification_sent redirect. (Unstubbed, the hook would render +
  # deliver a real email in this harness; deterministic capture is cleaner and is
  # how reset_password_request_enumeration_spec.rb isolates delivery.)
  def capture_link_emails
    captured = []
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email) do |template, data, **opts|
      captured << { template: template, data: data, opts: opts }
      true
    end
    captured
  end

  # The token is delivered ONLY through the emailed confirm_url (never the redirect),
  # so extract it from the captured email payload — mirroring what the user's inbox
  # would receive.
  def token_from_confirm_url(url)
    url.to_s.split('/sso-link-confirm/').last.to_s.split(/[?#]/).first
  end

  # Advance the account's credential watermark the way a password set/reset/change
  # would (UpdatePasswordMetadata stamps Customer#last_password_update). The op's
  # watermark_advanced? re-reads exactly this value.
  def advance_password_watermark(email, to: Time.now.to_i)
    cust = Onetime::Customer.find_by_email(OT::Utils.normalize_email(email))
    cust.last_password_update = to
    cust.save
    cust
  end

  # Trust off -> an existing account reaches the H-3 / mint branch rather than being
  # auto-linked by email. Platform fallback on -> a non-tenant callback stays on the
  # platform surface.
  before do
    enable_platform_fallback
    allow(Onetime.auth_config).to receive(:trust_email_for_linking?).and_return(false)
  end

  # ==========================================================================
  # (1) HAPPY PATH — full round trip through the REAL callback + REAL DB.
  # ==========================================================================

  describe 'happy path (passwordless platform account)' do
    it 'emails a token-less redirect, GET displays without consuming, POST binds and logs in' do
      email      = "mp-ok-#{SecureRandom.hex(6)}@company.example.com"
      uid        = "sub-#{SecureRandom.hex(8)}"
      account_id = seed_passwordless_account(email)
      normalized = OT::Utils.normalize_email(email)

      captured = capture_link_emails
      allow(Auth::Logging).to receive(:log_auth_event).and_call_original

      begin
        # -- Issuance ---------------------------------------------------------
        response = sso_callback(email: email, uid: uid)
        skip 'OmniAuth route not registered (OIDC discovery not available at boot)' if response.status == 404

        expect(response.status).to eq(302)
        # TOKEN-LESS informational redirect (the mailbox-proof property).
        expect(response.location.to_s).to include('/signin?auth_notice=link_verification_sent'),
          "Passwordless platform account must divert to the mailbox notice. Location: #{response.location.inspect}"
        expect(response.location.to_s).not_to include('account_exists_link_required')

        # Exactly one link email, to the ON-FILE address, carrying the token in the
        # confirm_url (and NOWHERE in the redirect).
        expect(captured.size).to eq(1), "Expected one link email, got: #{captured.inspect}"
        mail = captured.first
        expect(mail[:template]).to eq(:sso_link_verification)
        # :none, NOT :sync — the hook refuses a fallback whose outcome it cannot
        # read (Publisher discards the sync delivery's boolean), so a `true` here
        # can only mean genuinely QUEUED. It delivers inline itself otherwise.
        expect(mail[:opts][:fallback]).to eq(:none)
        expect(mail[:data][:email_address]).to eq(normalized)
        expect(mail[:data][:provider].to_s).to eq('oidc')

        token = token_from_confirm_url(mail[:data][:confirm_url])
        expect(token).not_to be_empty
        expect(response.location.to_s).not_to include(token),
          'The token must NEVER ride the callback redirect — only the email.'

        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:sso_link_verification_issued, hash_including(provider: 'oidc', account_id: account_id))

        # -- GET display (non-consuming) -------------------------------------
        ctx = get_confirm(token)
        expect(ctx.status).to eq(200)
        body = JSON.parse(ctx.body)
        expect(body['provider']).to eq('oidc')
        expect(body['email']).to eq(normalized)
        # Never surface the account id, uid, issuer, sid, or watermark.
        %w[account_id uid issuer sid password_watermark].each do |leak|
          expect(body).not_to have_key(leak)
        end

        # -- POST confirm -> bind + login ------------------------------------
        result = post_confirm(token: token)
        expect(result.status).to eq(200),
          "Expected a Rodauth login response, got #{result.status}: #{result.body}"
        expect(JSON.parse(result.body)).to have_key('success')

        # The bind: exactly one (provider, uid) row, on the located account.
        rows = identities.where(provider: 'oidc', uid: uid).all
        expect(rows.size).to eq(1), "Expected one bound row, got #{rows.inspect}"
        expect(rows.first[:account_id]).to eq(account_id)
        expect(rows.first[:issuer]).not_to be_nil

        # after_login ran: a 200 { success } is only THROWN by rodauth.login, which
        # runs login_session + after_login (Redis session blob via SyncSession,
        # active_sessions) before emitting login_response. Corroborate with the
        # confirmed audit and the consumed single-use token. (The op logs the token's
        # STRING account_id here, vs the hook's Integer one on :issued — an incidental
        # type difference, so match on provider only.)
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:sso_link_verification_confirmed, hash_including(provider: 'oidc'))
        expect(Onetime::SsoLinkVerification.load(token)).to be_nil
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # (2) GET IS NON-CONSUMING — GET twice, POST still succeeds.
  # ==========================================================================

  describe 'GET /auth/sso-link-confirm/:token is non-consuming' do
    it 'returns the display context on repeated GETs and leaves the token usable for POST' do
      email      = "mp-get-#{SecureRandom.hex(6)}@company.example.com"
      uid        = "sub-#{SecureRandom.hex(8)}"
      account_id = seed_passwordless_account(email)

      verification = mint_verification(email: email, uid: uid, account_id: account_id)

      2.times do
        ctx = get_confirm(verification.token)
        expect(ctx.status).to eq(200)
        expect(JSON.parse(ctx.body)['email']).to eq(OT::Utils.normalize_email(email))
      end

      # The token survived both GETs — the POST still consumes + binds.
      result = post_confirm(token: verification.token)
      expect(result.status).to eq(200), "Expected success after non-consuming GETs, got #{result.status}: #{result.body}"
      expect(identities.where(provider: 'oidc', uid: uid).count).to eq(1)
    end
  end

  # ==========================================================================
  # (3) SINGLE-USE — second POST is refused.
  # ==========================================================================

  describe 'single-use token consumption' do
    it 'refuses a second POST reusing an already-consumed token (401 link_expired)' do
      email      = "mp-once-#{SecureRandom.hex(6)}@company.example.com"
      uid        = "sub-#{SecureRandom.hex(8)}"
      account_id = seed_passwordless_account(email)

      verification = mint_verification(email: email, uid: uid, account_id: account_id)

      first = post_confirm(token: verification.token)
      expect(first.status).to eq(200), "First confirm should succeed, got #{first.status}: #{first.body}"

      second = post_confirm(token: verification.token)
      expect(second.status).to eq(401)
      expect(JSON.parse(second.body)['error_code']).to eq('link_expired')

      # And no duplicate bind resulted from the retry.
      expect(identities.where(provider: 'oidc', uid: uid).count).to eq(1)
    end
  end

  # ==========================================================================
  # (4) TTL / EXPIRY — a gone token refuses on both verbs.
  # ==========================================================================
  #
  # Familia expiration deletes the Redis key when the TTL lapses, so simulating
  # expiry by deleting the key exercises the SAME load-nil path the real timeout
  # produces (matches how the Phase 3 spec drives "unknown token").

  describe 'expired / missing token' do
    it 'GET returns 404 link_expired and POST returns 401 link_expired' do
      email      = "mp-ttl-#{SecureRandom.hex(6)}@company.example.com"
      uid        = "sub-#{SecureRandom.hex(8)}"
      account_id = seed_passwordless_account(email)

      verification = mint_verification(email: email, uid: uid, account_id: account_id)
      verification.delete! # simulate the TTL lapse (key gone)

      ctx = get_confirm(verification.token)
      expect(ctx.status).to eq(404)
      expect(JSON.parse(ctx.body)['error_code']).to eq('link_expired')

      result = post_confirm(token: verification.token)
      expect(result.status).to eq(401)
      expect(JSON.parse(result.body)['error_code']).to eq('link_expired')

      expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0)
    end
  end

  # ==========================================================================
  # (5) SOFT CROSS-DEVICE BIND — a sid mismatch is logged, never rejected.
  # ==========================================================================
  #
  # Mailbox proof is inherently cross-device (the user may click on their phone), so
  # a POST whose current_sid differs from the token's snapshotted sid must still
  # SUCCEED. The op fires :sso_link_verification_cross_device (info) for observability.
  # The token is minted with a KNOWN sid; the POST's current_sid is the harness
  # session cookie (a fresh 64-hex from fetch_csrf_token) -> guaranteed different.

  describe 'soft cross-device binding' do
    it 'binds successfully from a different sid and fires the cross-device info audit' do
      email      = "mp-xd-#{SecureRandom.hex(6)}@company.example.com"
      uid        = "sub-#{SecureRandom.hex(8)}"
      account_id = seed_passwordless_account(email)

      allow(Auth::Logging).to receive(:log_auth_event).and_call_original

      verification = mint_verification(
        email: email, uid: uid, account_id: account_id, sid: "device-a-#{SecureRandom.hex(8)}",
      )

      result = post_confirm(token: verification.token)

      # Soft binding: SUCCEEDS despite the sid mismatch.
      expect(result.status).to eq(200), "Cross-device confirm must succeed, got #{result.status}: #{result.body}"
      expect(identities.where(provider: 'oidc', uid: uid).count).to eq(1)

      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:sso_link_verification_cross_device, hash_including(provider: 'oidc'))
    end
  end

  # ==========================================================================
  # (6) CONFLICT — the identity is already owned by a DIFFERENT account.
  # ==========================================================================
  #
  # The bind primitive verifies the pre-existing (provider, issuer, uid) row belongs
  # to the account we are confirming. A row owned by ANOTHER account is a conflict
  # (409 link_conflict), never a silent idempotent success onto someone else's
  # identity. Defence-in-depth: the mint only happens when no row exists, so this
  # models a row appearing between issuance and confirm.

  describe 'identity already owned by another account (link_conflict)' do
    it 'refuses with 409 link_conflict and binds nothing onto the confirming account' do
      email_a   = "mp-owner-a-#{SecureRandom.hex(6)}@company.example.com"
      email_b   = "mp-owner-b-#{SecureRandom.hex(6)}@company.example.com"
      uid       = "sub-#{SecureRandom.hex(8)}"
      issuer    = 'https://issuer.example.com'
      account_a = seed_passwordless_account(email_a)
      account_b = seed_passwordless_account(email_b)

      # Account B already owns this exact (provider, issuer, uid).
      identities.insert(account_id: account_b, provider: 'oidc', issuer: issuer, uid: uid)

      # The verification snapshots account A (which email_a re-locates, so the
      # ownership re-check passes and execution reaches BindSsoIdentity).
      verification = mint_verification(email: email_a, uid: uid, account_id: account_a, issuer: issuer)
      result       = post_confirm(token: verification.token)

      expect(result.status).to eq(409), "Expected link_conflict, got #{result.status}: #{result.body}"
      expect(JSON.parse(result.body)['error_code']).to eq('link_conflict')

      # Still exactly one row — owned by B — and nothing bound onto A.
      rows = identities.where(provider: 'oidc', uid: uid).all
      expect(rows.size).to eq(1)
      expect(rows.first[:account_id]).to eq(account_b)
      expect(identities.where(account_id: account_a).count).to eq(0)
    end
  end

  # ==========================================================================
  # (7) WATERMARK INVALIDATION — a credential change voids the token.
  # ==========================================================================
  #
  # The token snapshots Customer#last_password_update at issuance. Any credential
  # change (password set/reset/change stamps the watermark via UpdatePasswordMetadata)
  # between issuance and confirm must invalidate it (409 link_invalidated).

  describe 'credential-change invalidation (link_invalidated)' do
    it 'refuses with 409 link_invalidated when the password watermark advanced after issuance' do
      email      = "mp-wm-#{SecureRandom.hex(6)}@company.example.com"
      uid        = "sub-#{SecureRandom.hex(8)}"
      account_id = seed_passwordless_account(email)

      # Snapshot watermark == 0 (freshly seeded passwordless customer), then advance
      # it AFTER issuance — modelling a credential change during the email round-trip.
      verification = mint_verification(email: email, uid: uid, account_id: account_id, password_watermark: 0)
      advance_password_watermark(email, to: Time.now.to_i)

      result = post_confirm(token: verification.token)

      expect(result.status).to eq(409), "Expected link_invalidated, got #{result.status}: #{result.body}"
      expect(JSON.parse(result.body)['error_code']).to eq('link_invalidated')

      # Nothing bound; and the single-use token was consumed up front (no oracle).
      expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0)
      expect(Onetime::SsoLinkVerification.load(verification.token)).to be_nil
    end
  end

  # ==========================================================================
  # (8) REFUSAL FAIL-CLOSED — no usable token when linking cannot proceed.
  # ==========================================================================

  describe 'refusal is fail-closed' do
    # Drive the passwordless platform callback under a delivery condition that must
    # NOT be reported as "sent", and assert the whole fail-closed contract: the H-3
    # refusal, NO link_verification_sent notice, no :issued audit, an audited send
    # failure, and NO live token left behind. The block installs the condition (the
    # normalized on-file address is yielded for per-address stubs) AFTER the account
    # is seeded but BEFORE the callback runs.
    def expect_fail_closed_delivery(label)
      email      = "mp-#{label}-#{SecureRandom.hex(6)}@company.example.com"
      uid        = "sub-#{SecureRandom.hex(8)}"
      normalized = OT::Utils.normalize_email(email)
      seed_passwordless_account(email)

      allow(Auth::Logging).to receive(:log_auth_event).and_call_original

      # Capture the exact token that was minted so we can prove it no longer resolves.
      minted = nil
      allow(Onetime::SsoLinkVerification).to receive(:issue).and_wrap_original do |orig, **kw|
        minted = orig.call(**kw)
        minted
      end

      yield normalized

      begin
        response = sso_callback(email: email, uid: uid)
        skip 'OmniAuth route not registered' if response.status == 404

        expect(response.status).to eq(302)
        expect(response.location.to_s).to include('/signin?auth_error=account_exists_link_required'),
          "Undelivered mail must fall through to the H-3 refusal. Location: #{response.location.inspect}"
        expect(response.location.to_s).not_to include('link_verification_sent')

        # The send failure was audited, the "check your inbox" audit was NOT, and the
        # just-minted token was deleted.
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:sso_link_verification_send_FAILED, hash_including(provider: 'oidc'))
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:sso_link_verification_issued, anything)
        expect(minted).not_to be_nil
        expect(Onetime::SsoLinkVerification.load(minted.token)).to be_nil,
          'An undelivered link must not leave a live, un-notified token behind.'
      ensure
        teardown_mock_auth
      end
    end

    # -- (8a) delivery RAISES --------------------------------------------------
    #
    # If the link email cannot be delivered, the just-issued token is consumed and
    # the callback falls through to the UNCHANGED H-3 refusal — never leaving a live
    # token whose recipient inbox got no mail.
    it 'consumes the token and keeps the H-3 refusal when email delivery raises' do
      expect_fail_closed_delivery('fail') do
        allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_raise(StandardError.new('smtp unreachable'))
      end
    end

    # -- (8b) delivery RETURNS without sending ---------------------------------
    #
    # The dangerous shape: nothing raises. Publisher reports "not queued" (jobs
    # disabled / RabbitMQ down) and the inline delivery returns nil because the mail
    # layer dispatched nothing (Delivery::Base#deliver returns nil for a suppressed
    # recipient, Delivery::Disabled always does). A returned nil is NOT a send, so it
    # must fail closed exactly like the raise — this is what the pre-fix code got
    # wrong, unconditionally claiming success from a normal return.
    it 'consumes the token and refuses when the mail layer returns without dispatching anything' do
      expect_fail_closed_delivery('nodispatch') do
        allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(false)
        allow(Onetime::Mail).to receive(:deliver).and_return(nil)
      end
    end

    # -- (8c) suppressed recipient ---------------------------------------------
    #
    # A suppressed address is skipped silently by every send — including the QUEUED
    # one, which could never report back to the callback. Probed up front, so nothing
    # is queued and the user is never told to check an inbox that gets nothing.
    it 'refuses without queuing anything when the on-file address is suppressed' do
      expect_fail_closed_delivery('suppressed') do |normalized|
        allow(Onetime::EmailSuppression).to receive(:suppressed?).and_call_original
        allow(Onetime::EmailSuppression).to receive(:suppressed?).with(normalized).and_return(true)
        # Would have claimed success had the hook queued it anyway.
        allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(true)
      end

      expect(Onetime::Jobs::Publisher).not_to have_received(:enqueue_email)
    end

    # -- (8d) delivery disabled install-wide -----------------------------------
    #
    # EMAILER_MODE=disabled/none makes every delivery a silent no-op
    # (Delivery::Disabled), on the queued path too. Mailbox proof is impossible on
    # such an install, so the branch must refuse rather than mint a token nobody can
    # ever receive.
    it 'refuses without queuing anything when email delivery is disabled install-wide' do
      expect_fail_closed_delivery('disabled') do
        allow(Onetime::Mail::Mailer).to receive(:determine_provider).and_return('disabled')
        allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(true)
      end

      expect(Onetime::Jobs::Publisher).not_to have_received(:enqueue_email)
    end

    # -- (8e) tenant surface --------------------------------------------------
    #
    # A passwordless account reached via a TENANT callback must NEVER be offered
    # mailbox linking: a tenant admin controls their IdP and could otherwise trigger
    # link emails to arbitrary platform addresses. The `elsif platform_surface` guard
    # makes tenant callbacks fall through to the H-3 refusal — no verification minted,
    # no email, no :sso_link_verification_issued.
    describe 'tenant-surface callback (surface isolation)', :oauth_flow do
      include OAuthFlowHelper

      it 'refuses (H-3) and mints NO verification on the tenant surface' do
        run_id = "mp-tenant-#{SecureRandom.hex(4)}"
        host   = "secrets-#{run_id}.tenant.example.com"
        email  = "victim-#{run_id}@company.example.com"
        uid    = "sub-#{SecureRandom.hex(8)}"

        seed_passwordless_account(email)
        setup_oauth_test_domain(host)

        allow(Auth::Logging).to receive(:log_auth_event).and_call_original
        allow(Onetime::SsoLinkVerification).to receive(:issue).and_call_original
        allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_call_original
        setup_mock_auth(email: email, uid: uid)

        begin
          clear_body_headers
          header 'Host', host
          post '/auth/sso/oidc'
          skip "OmniAuth route not registered for #{host}" if last_response.status == 404
          expect(last_response.status).to eq(302)

          clear_body_headers
          header 'Host', host
          post '/auth/sso/oidc/callback'

          expect(last_response.status).to eq(302)
          expect(last_response.location.to_s).to include('/signin?auth_error=account_exists_link_required'),
            "Tenant callback for a passwordless account must keep the H-3 refusal. Location: #{last_response.location.inspect}"
          expect(last_response.location.to_s).not_to include('link_verification_sent')

          # No mailbox verification path was taken on the tenant surface.
          expect(Onetime::SsoLinkVerification).not_to have_received(:issue)
          expect(Onetime::Jobs::Publisher).not_to have_received(:enqueue_email)
          expect(Auth::Logging).not_to have_received(:log_auth_event)
            .with(:sso_link_verification_issued, anything)
          expect(Auth::Logging).to have_received(:log_auth_event)
            .with(:omniauth_link_refused_existing_account, hash_including(provider: 'oidc'))
          expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0)
        ensure
          teardown_mock_auth
        end
      end
    end

    # -- (8f) unresolvable Customer -------------------------------------------
    #
    # ISSUANCE/CONFIRM SYMMETRY. ConfirmSsoLink#watermark_state fails SECURE on an
    # unresolvable Customer (nil -> :unreadable -> 409 link_error), and it re-derives
    # the identifier with the SAME external_id-first logic the hook used at issuance —
    # so a Customer that does not resolve at issuance will not resolve at confirm
    # either. Minting anyway would mail a link guaranteed to 409 on EVERY click,
    # permanently: this branch is passwordless-only, so the H-3 "sign in with your
    # existing method" recovery does not exist for these accounts. The hook therefore
    # gates issuance on the same resolution and falls through to the H-3 refusal — an
    # actionable message now, rather than an unredeemable email later.
    it 'refuses (H-3) and mints NO verification when the account Customer does not resolve' do
      email = "mp-nocust-#{SecureRandom.hex(6)}@company.example.com"
      uid   = "sub-#{SecureRandom.hex(8)}"
      seed_account_without_customer(email)

      allow(Auth::Logging).to receive(:log_auth_event).and_call_original
      allow(Onetime::SsoLinkVerification).to receive(:issue).and_call_original
      allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_call_original
      allow(Onetime::Mail).to receive(:deliver).and_call_original

      begin
        response = sso_callback(email: email, uid: uid)
        skip 'OmniAuth route not registered' if response.status == 404

        expect(response.status).to eq(302)
        expect(response.location.to_s).to include('/signin?auth_error=account_exists_link_required'),
          "An unresolvable Customer must refuse at issuance. Location: #{response.location.inspect}"
        expect(response.location.to_s).not_to include('link_verification_sent')

        # Nothing minted, nothing mailed — on either delivery path.
        expect(Onetime::SsoLinkVerification).not_to have_received(:issue)
        expect(Onetime::Jobs::Publisher).not_to have_received(:enqueue_email)
        expect(Onetime::Mail).not_to have_received(:deliver)

        # Audited as the operator-actionable data problem it is, NOT as "sent".
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:sso_link_verification_customer_unresolved, hash_including(provider: 'oidc'))
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:sso_link_verification_issued, anything)
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_link_refused_existing_account, hash_including(provider: 'oidc'))

        expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0)
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # (9) MFA-DEFERRED bind (needs an AUTH_MFA_ENABLED harness).
  # ==========================================================================
  #
  # When the located account has a pending second factor the identity bind must be
  # DEFERRED (binding an MFA-exempt SSO path before 2FA would attach an MFA-bypassing
  # login): the op returns second_factor_pending, the route logs the user in via
  # rodauth.login('sso_link_confirm') which THROWS the SAME mfa_required body
  # POST /auth/login emits, and the (provider,issuer,uid) row stays UNLINKED this
  # round — but the authorized bind tuple is STASHED inside the login block
  # (DeferredSsoBind.defer, #3858) and COMPLETED by after_two_factor_authentication
  # once the OTP succeeds (#3877), exactly like the password interstitial. Without
  # that stash an MFA passwordless account would re-hit this flow on every SSO
  # sign-in and never link.
  #
  # Exercising this end-to-end needs the OTP feature loaded (AUTH_MFA_ENABLED) so
  # rodauth.respond_to?(:otp_auth_route) is true and after_login emits mfa_required.
  # This shared integration harness boots ONCE (before(:all)) with MFA disabled and
  # cannot toggle the Rodauth feature set per-example (the same boot-time-feature
  # constraint that pends the Phase 3 interstitial MFA example). Left PENDING so the
  # gap stays visible; the defer→complete wiring is covered in isolation by
  # deferred_sso_bind_spec.rb. A full end-to-end assertion needs an AUTH_MFA_ENABLED
  # full-boot lane.
  describe 'MFA account defers the identity bind, completing it after 2FA (#3877)' do
    it 'returns mfa_required, stashes the bind, and links after OTP (needs an AUTH_MFA_ENABLED harness)'
  end
end
