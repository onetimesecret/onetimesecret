# apps/web/auth/spec/integration/full_mfa/sso_link_confirm_mailbox_proof_mfa_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode + AUTH_MFA_ENABLED=true — DEDICATED LANE)
# =============================================================================
#
# Issue: #3840 Phase 4 (#3877 Phase 4.A) — the MAILBOX-PROOF deferred SSO bind,
#        end to end, when the located account has a pending second factor.
#
# The confirm endpoint must NOT bind the (provider, issuer, uid) identity when
# the login it establishes leaves a second factor pending: SSO logins are
# MFA-EXEMPT, so a pre-2FA bind would attach an MFA-bypassing login path to the
# account. Auth::Operations::ConfirmSsoLink instead returns second_factor_pending
# (still consuming the single-use token), routes/sso_link_confirm.rb logs the
# user in via rodauth.login('sso_link_confirm') — which THROWS the SAME
# mfa_required body POST /auth/login emits — and STASHES the authorized bind
# tuple inside the login block (Auth::Operations::DeferredSsoBind.defer). The
# bind is completed by after_two_factor_authentication (config/hooks/mfa.rb) once
# the second factor succeeds. Without that stash an MFA-enabled account would
# re-hit the mailbox flow on every SSO sign-in and NEVER link (the exact failure
# greptile flagged as P1 against the pre-#3877 snapshot, which returned the
# deferred result WITHOUT issuer/uid).
#
# WHAT IT LOCKS IN (the sequence the shared full/ harness cannot reach —
#   full/sso_link_confirm_mailbox_proof_spec.rb left it PENDING):
#   a. POST /auth/sso-link-confirm for an OTP-enabled account -> the SAME
#      mfa_required body POST /auth/login emits, the single-use token is
#      CONSUMED, and NO identity row exists yet (the MFA-bypass guard).
#   b. POST /auth/otp-auth with a valid TOTP code -> the deferred bind lands:
#      exactly one identity row, on the proven account, with the token's
#      (provider, issuer, uid), and :sso_deferred_bind_completed fires with
#      outcome :ok.
#   c. The RECOVERY-CODE second factor completes the bind too. NOTE the modest
#      scope: the hook's factor-agnosticism itself is already pinned by
#      full_mfa/omniauth_signin_interstitial_mfa_spec.rb (d), and the completion
#      path is shared and route-agnostic once the stash is written — so this
#      example cannot fail unless (b) also fails. What it does pin is that
#      nothing in the MAILBOX-written stash (routes/sso_link_confirm.rb, keyed
#      off the verification token rather than an interstitial challenge) is
#      specific to the otp-auth route that happens to consume it. Kept because
#      it is nearly free next to this lane's fixed cost (own process, full-mode
#      migration) and makes the mailbox contract readable without reading the
#      interstitial spec — not because it adds independent failure detection.
#
# WHY SEED A PASSWORD FOR A "PASSWORDLESS" SUBJECT: the mailbox-proof flow is
# ISSUED only for passwordless accounts (config/hooks/omniauth.rb), but the
# CONFIRM route/op never inspect password presence — the deferral is identical
# for password and passwordless accounts. Provisioning a PRODUCTION-SHAPED OTP
# key is only possible through Rodauth's real setup flow: this deploy sets
# otp_keys_use_hmac? true (the stored key is HMAC'd, so a hand-inserted raw
# secret would not validate) and two_factor_modifications_require_password? true
# (setup requires the account password). So the subject is seeded WITH a password
# purely as the OTP-provisioning vehicle, then the verification is MINTED
# DIRECTLY and confirmed via mailbox proof — which is exactly the realistic
# "legacy password+MFA account now using SSO" state config/hooks/login.rb calls
# out. The bind path under test (confirm -> defer -> otp-auth -> complete) is the
# code greptile flagged, and it is unaffected by whether a password hash exists.
#
# WHY A DEDICATED LANE: Auth::Config is one-shot per process
# (apps/web/auth/docs/auth-config-one-shot.md) — the shared full-mode
# integration process boots with MFA off and can never load the Rodauth OTP
# feature set afterwards. This directory (integration/full_mfa/) is excluded from
# the shared spec:integration:full glob and runs in its OWN process with
# AUTH_MFA_ENABLED=true via `rake spec:integration:full:mfa` (chained from
# spec:integration:full). The :full_auth_mode tag is set EXPLICITLY below because
# the path-derived tag only matches /integration/full/.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
#
# RUN:
#   bundle exec rake spec:integration:full:mfa
# or directly (fresh process required):
#   RACK_ENV=test AUTHENTICATION_MODE=full AUTH_DATABASE_URL=sqlite::memory: \
#     ORGS_SSO_ENABLED=true AUTH_MFA_ENABLED=true LANG=en_US.UTF-8 \
#     bundle exec rspec \
#     apps/web/auth/spec/integration/full_mfa/sso_link_confirm_mailbox_proof_mfa_spec.rb
# =============================================================================

require_relative '../../spec_helper'

# Sets AUTH_MFA_ENABLED at load time (before the suite's first boot) and brings
# Rack::Test, `app`, `identities`, the OTP-feature guard, and the OTP
# provisioning machinery. See the helper's header.
require_relative '../../support/mfa_flow_helper'

RSpec.describe 'SSO mailbox-proof link confirm: deferred bind after MFA (#3840 Phase 4 / #3877)',
  :full_auth_mode, type: :integration do
  include MfaFlowHelper

  # ==========================================================================
  # Route driving for THIS flow (mirrors
  # integration/full/sso_link_confirm_mailbox_proof_spec.rb). The shared OTP
  # machinery lives in support/mfa_flow_helper.rb.
  # ==========================================================================

  # GET /auth/sso-link-confirm/:token — the display-only consent context.
  def get_confirm(token)
    clear_body_headers
    header 'Accept', 'application/json'
    get "/auth/sso-link-confirm/#{token}"
    last_response
  end

  # POST /auth/sso-link-confirm { token } — the atomic consume + (deferred) bind
  # + login handoff. Carries shrimp in the body like json_post; the custom route
  # accepts the header token too, but sending both matches the SPA.
  def post_confirm(token:)
    csrf = fetch_csrf_token
    clear_body_headers
    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', csrf if csrf
    post '/auth/sso-link-confirm', JSON.generate(token: token, shrimp: csrf)
    last_response
  end

  # Mint a verification directly — the POST endpoint carries the snapshot the op
  # reloads, so it needs no SSO round-trip. Default watermark 0 matches a freshly
  # seeded Customer (never had last_password_update stamped), so watermark_state
  # resolves :unchanged.
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

  # Drive the mailbox-proof confirm up to the MFA hand-off: mint a verification,
  # POST it, and assert the deferral contract — mfa_required, the token CONSUMED
  # (single-use), and NOTHING bound while the second factor is pending. Returns
  # the token's issuer for the post-2FA assertion.
  def confirm_step_expecting_mfa(email:, uid:, account_id:)
    verification = mint_verification(email: email, uid: uid, account_id: account_id)
    issuer       = verification.issuer

    result = post_confirm(token: verification.token)
    expect(result.status).to eq(200),
      "Expected the login response with the MFA hand-off, got #{result.status}: #{result.body}"
    body = json_body
    expect(body['mfa_required']).to eq(true),
      "An OTP-enabled account must be handed off to MFA, got: #{body.inspect}"

    # THE GUARD: nothing is bound while the second factor is pending — a bound row
    # here would be an MFA-bypassing SSO path.
    expect(identities.where(account_id: account_id).count).to eq(0),
      'No identity may be bound before the second factor completes'
    expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0)

    # Single-use: the token is CONSUMED at the confirm step, not re-armed by the
    # deferral — the stash in the partial MFA session carries the bind.
    expect(Onetime::SsoLinkVerification.load(verification.token)).to be_nil

    issuer
  end

  # Trust off keeps an existing account on the mint branch; platform fallback on
  # keeps a non-tenant callback on the platform surface. Neither is strictly
  # needed here (we mint directly) but mirrors the sibling specs' baseline.
  before do
    allow(Onetime.auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
    allow(Onetime.auth_config).to receive(:trust_email_for_linking?).and_return(false)
  end

  # ==========================================================================
  # (a)+(b) the deferred bind completes after the second factor succeeds
  # ==========================================================================

  it 'defers the bind at confirm and completes it after OTP verifies' do
    email      = "mp-mfa-ok-#{SecureRandom.hex(6)}@company.example.com"
    uid        = "sub-#{SecureRandom.hex(8)}"
    account_id = seed_account_with_password(email)
    secret, _codes = provision_totp(email)

    allow(Auth::Logging).to receive(:log_auth_event).and_call_original

    issuer = confirm_step_expecting_mfa(email: email, uid: uid, account_id: account_id)

    # Complete the second factor in the SAME session the hand-off prepared.
    allow_immediate_otp_reuse!(account_id)
    json_post('/auth/otp-auth', otp_code: ROTP::TOTP.new(secret).now)
    expect(last_response.status).to eq(200),
      "OTP verification should succeed, got #{last_response.status}: #{last_response.body}"

    # The deferred bind landed: exactly one row, on the proven account, with the
    # token's (provider, issuer, uid).
    rows = identities.where(provider: 'oidc', uid: uid).all
    expect(rows.size).to eq(1), "Expected exactly one bound row, got #{rows.inspect}"
    expect(rows.first[:account_id]).to eq(account_id)
    expect(rows.first[:issuer]).to eq(issuer)

    expect(Auth::Logging).to have_received(:log_auth_event)
      .with(:sso_deferred_bind_completed, hash_including(outcome: :ok, account_id: account_id))
  end

  # ==========================================================================
  # (c) the recovery-code factor completes the mailbox-proof deferral too
  # ==========================================================================

  it 'completes the deferred bind when the second factor is a recovery code' do
    email      = "mp-mfa-recovery-#{SecureRandom.hex(6)}@company.example.com"
    uid        = "sub-#{SecureRandom.hex(8)}"
    account_id = seed_account_with_password(email)
    _secret, recovery_codes = provision_totp(email)
    expect(recovery_codes).not_to be_empty,
      'Precondition failed: phase-2 otp-setup should surface auto-generated recovery codes'

    allow(Auth::Logging).to receive(:log_auth_event).and_call_original

    issuer = confirm_step_expecting_mfa(email: email, uid: uid, account_id: account_id)

    # The mailbox-written stash is consumed by whichever 2FA route runs: swap
    # otp-auth for recovery-auth and the bind still lands. See header note (c)
    # for why this is a readability guard rather than independent coverage.
    json_post('/auth/recovery-auth', 'recovery-code' => recovery_codes.first)
    expect(last_response.status).to eq(200),
      "Recovery-code auth should succeed, got #{last_response.status}: #{last_response.body}"

    rows = identities.where(provider: 'oidc', uid: uid).all
    expect(rows.size).to eq(1), "Expected exactly one bound row, got #{rows.inspect}"
    expect(rows.first[:account_id]).to eq(account_id)
    expect(rows.first[:issuer]).to eq(issuer)

    expect(Auth::Logging).to have_received(:log_auth_event)
      .with(:sso_deferred_bind_completed, hash_including(outcome: :ok, account_id: account_id))
      .once
  end
end
