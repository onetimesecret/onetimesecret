# apps/web/auth/spec/integration/full_mfa/omniauth_signin_interstitial_mfa_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode + AUTH_MFA_ENABLED=true — DEDICATED LANE)
# =============================================================================
#
# Issue: #3877 (#3840 Phase 4.A) — the deferred SSO identity bind, end to end.
#
# The link-sso interstitial must NOT bind the (provider, issuer, uid) identity
# when the password login leaves a second factor pending: SSO logins are
# MFA-EXEMPT, so a pre-2FA bind would attach an MFA-bypassing login path to the
# account. The authorized bind is instead stashed in the partial MFA session
# (Auth::Operations::DeferredSsoBind.defer, written inside the rodauth.login
# block) and completed by after_two_factor_authentication once the second
# factor succeeds.
#
# WHAT IT LOCKS IN (the sequence the shared-harness spec cannot reach):
#   a. POST /auth/link-sso with the CORRECT password for an OTP-enabled account
#      -> the SAME mfa_required body POST /auth/login emits, the single-use
#      challenge is consumed, and NO identity row exists yet (the MFA-bypass
#      guard from PR #3870 review Item 1).
#   b. POST /auth/otp-auth with a valid TOTP code -> the deferred bind lands:
#      exactly one identity row, on the proven account, with the challenge's
#      (provider, issuer, uid), and :sso_deferred_bind_completed fires with
#      outcome :ok.
#   c. A FAILED second-factor attempt binds nothing and does NOT lose the
#      pending bind — the next successful attempt still completes it.
#   d. The RECOVERY-CODE second factor completes the bind too:
#      after_two_factor_authentication is factor-agnostic, so the deferred
#      bind must land for any factor Rodauth accepts, not just TOTP.
#
# WHY A DEDICATED LANE: Auth::Config is one-shot per process
# (apps/web/auth/docs/auth-config-one-shot.md) — the shared full-mode
# integration process boots with MFA off and can never load the Rodauth OTP
# feature set afterwards. This directory (integration/full_mfa/) is excluded
# from the shared spec:integration:full glob and runs in its OWN process with
# AUTH_MFA_ENABLED=true via `rake spec:integration:full:mfa` (invoked
# automatically at the end of spec:integration:full). The :full_auth_mode tag
# is set EXPLICITLY below because the path-derived tag only matches
# /integration/full/.
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
#     apps/web/auth/spec/integration/full_mfa/omniauth_signin_interstitial_mfa_spec.rb
# =============================================================================

require_relative '../../spec_helper'

# Sets AUTH_MFA_ENABLED at load time (before the suite's first boot) and brings
# Rack::Test, `app`, `identities`, the OTP-feature guard, and the OTP
# provisioning machinery. See the helper's header.
require_relative '../../support/mfa_flow_helper'

RSpec.describe 'OmniAuth sign-in interstitial: deferred bind after MFA (#3877)',
  :full_auth_mode, type: :integration do
  include MfaFlowHelper

  # ==========================================================================
  # Route driving for THIS flow (mirrors
  # integration/full/omniauth_signin_interstitial_spec.rb). The shared OTP
  # machinery lives in support/mfa_flow_helper.rb.
  # ==========================================================================

  def enable_platform_fallback
    allow(Onetime.auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
  end

  def setup_mock_auth(email:, uid:, provider: :oidc)
    OmniAuth.config.test_mode               = true
    OmniAuth.config.allowed_request_methods = [:get, :post]
    OmniAuth.config.mock_auth[provider]     = OmniAuth::AuthHash.new(
      {
        provider: provider.to_s,
        uid: uid,
        info: { email: email, name: 'MFA Interstitial User', email_verified: true },
        credentials: { token: 'mock_access_token', expires_at: Time.now.to_i + 3600, expires: true },
        extra: { raw_info: { sub: uid, email: email, name: 'MFA Interstitial User', email_verified: true } },
      },
    )
  end

  def teardown_mock_auth
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.clear
  end

  def sso_callback(email:, uid:, provider: :oidc)
    setup_mock_auth(email: email, uid: uid, provider: provider)
    clear_body_headers
    post "/auth/sso/#{provider}/callback"
    last_response
  end

  def token_from_location(location)
    location.to_s.split('/link-sso/').last.to_s.split(/[?#]/).first
  end

  def post_link_sso(token:, password:)
    json_post('/auth/link-sso', token: token, password: password)
  end

  # Drive the SSO callback for an OTP-enabled password account up to the point
  # where the interstitial has verified the password and handed off to MFA.
  # Returns [challenge_issuer, token]. Skips (like the shared-harness specs)
  # when the OmniAuth route is not registered at boot.
  def password_step_expecting_mfa(email:, uid:, account_id:)
    response = sso_callback(email: email, uid: uid)
    skip 'OmniAuth route not registered (OIDC discovery not available at boot)' if response.status == 404

    expect(response.status).to eq(302)
    expect(response.location.to_s).to match(%r{/link-sso/}),
      "Expected the interstitial redirect. Location: #{response.location.inspect}"
    token = token_from_location(response.location)

    challenge = Onetime::SsoLinkChallenge.load(token)
    expect(challenge).not_to be_nil
    issuer = challenge.issuer

    result = post_link_sso(token: token, password: AuthTestConstants::TEST_PASSWORD)
    expect(result.status).to eq(200),
      "Expected the login response with the MFA hand-off, got #{result.status}: #{result.body}"
    body = json_body
    expect(body['mfa_required']).to eq(true),
      "An OTP-enabled account must be handed off to MFA, got: #{body.inspect}"

    # THE GUARD (PR #3870 review Item 1): nothing is bound while the second
    # factor is pending — a bound row here would be an MFA-bypassing SSO path.
    expect(identities.where(account_id: account_id).count).to eq(0),
      'No identity may be bound before the second factor completes'
    expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0)

    # Single-use: the challenge is consumed at the password step, NOT re-armed
    # by the deferral — the stash in the partial MFA session carries the bind.
    expect(Onetime::SsoLinkChallenge.load(token)).to be_nil

    [issuer, token]
  end

  before do
    enable_platform_fallback
    allow(Onetime.auth_config).to receive(:trust_email_for_linking?).and_return(false)
  end

  # ==========================================================================
  # (a)+(b) the deferred bind completes after the second factor succeeds
  # ==========================================================================

  it 'defers the bind at the password step and completes it after OTP verifies' do
    email      = "mfa-ok-#{SecureRandom.hex(6)}@company.example.com"
    uid        = "sub-#{SecureRandom.hex(8)}"
    account_id = seed_account_with_password(email)
    secret, _codes = provision_totp(email)

    allow(Auth::Logging).to receive(:log_auth_event).and_call_original

    begin
      issuer, _token = password_step_expecting_mfa(email: email, uid: uid, account_id: account_id)

      # Complete the second factor in the SAME session the hand-off prepared.
      allow_immediate_otp_reuse!(account_id)
      json_post('/auth/otp-auth', otp_code: ROTP::TOTP.new(secret).now)
      expect(last_response.status).to eq(200),
        "OTP verification should succeed, got #{last_response.status}: #{last_response.body}"

      # The deferred bind landed: exactly one row, on the proven account, with
      # the challenge's (provider, issuer, uid).
      rows = identities.where(provider: 'oidc', uid: uid).all
      expect(rows.size).to eq(1), "Expected exactly one bound row, got #{rows.inspect}"
      expect(rows.first[:account_id]).to eq(account_id)
      expect(rows.first[:issuer]).to eq(issuer)

      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:sso_deferred_bind_completed, hash_including(outcome: :ok, account_id: account_id))
    ensure
      teardown_mock_auth
    end
  end

  # ==========================================================================
  # (c) a failed second factor binds nothing and does not lose the bind
  # ==========================================================================

  it 'binds nothing on a failed OTP attempt; the next successful attempt completes the bind' do
    email      = "mfa-retry-#{SecureRandom.hex(6)}@company.example.com"
    uid        = "sub-#{SecureRandom.hex(8)}"
    account_id = seed_account_with_password(email)
    secret, _codes = provision_totp(email)

    allow(Auth::Logging).to receive(:log_auth_event).and_call_original

    begin
      issuer, _token = password_step_expecting_mfa(email: email, uid: uid, account_id: account_id)

      # A wrong code must not complete the login — and must not bind.
      allow_immediate_otp_reuse!(account_id)
      json_post('/auth/otp-auth', otp_code: wrong_otp_code(secret))

      # Pin the SPECIFIC rejection, not just "non-200": Rodauth's OTP failure
      # path is 401 (invalid_key_error_status) with a field-error on the OTP
      # param. A 404 from a routing regression or a 401 from an earlier guard
      # (require_login, lockout) would prove nothing about the MFA gate and
      # must not pass this example vacuously.
      expect(last_response.status).to eq(401),
        "A wrong OTP code must be rejected with 401, got #{last_response.status}: #{last_response.body}"
      body = json_body
      expect(body['field-error']).to be_an(Array),
        "Expected Rodauth's field-error on the OTP param, got: #{body.inspect}"
      expect(body['field-error'].first).to eq('otp_code')
      expect(body['error']).not_to be_nil

      # The rejection came from OTP VALIDATION itself — the app's
      # after_otp_authentication_failure hook fired for this account.
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:mfa_verification_failure, hash_including(account_id: account_id))

      # Positive intermediate state: nothing bound anywhere, and the deferred
      # completion hook never ran (not even with a non-:ok outcome).
      expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0),
        'A failed second factor must not bind the identity'
      expect(identities.where(account_id: account_id).count).to eq(0)
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:sso_deferred_bind_completed, any_args)

      # The pending bind survives the failed attempt: the next successful
      # factor still completes it (the stash is consumed on SUCCESS, not on
      # the first attempt).
      json_post('/auth/otp-auth', otp_code: ROTP::TOTP.new(secret).now)
      expect(last_response.status).to eq(200),
        "OTP retry should succeed, got #{last_response.status}: #{last_response.body}"

      rows = identities.where(provider: 'oidc', uid: uid).all
      expect(rows.size).to eq(1)
      expect(rows.first[:account_id]).to eq(account_id)
      expect(rows.first[:issuer]).to eq(issuer)
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:sso_deferred_bind_completed, hash_including(outcome: :ok, account_id: account_id))
        .once
    ensure
      teardown_mock_auth
    end
  end

  # ==========================================================================
  # (d) the recovery-code factor completes the bind too
  # ==========================================================================

  it 'completes the deferred bind when the second factor is a recovery code' do
    email      = "mfa-recovery-#{SecureRandom.hex(6)}@company.example.com"
    uid        = "sub-#{SecureRandom.hex(8)}"
    account_id = seed_account_with_password(email)
    _secret, recovery_codes = provision_totp(email)
    expect(recovery_codes).not_to be_empty,
      'Precondition failed: phase-2 otp-setup should surface auto-generated recovery codes'

    allow(Auth::Logging).to receive(:log_auth_event).and_call_original

    begin
      issuer, _token = password_step_expecting_mfa(email: email, uid: uid, account_id: account_id)

      # after_two_factor_authentication fires for ANY accepted factor, so the
      # deferred bind must land via /auth/recovery-auth exactly as via OTP —
      # this locks in the hook's factor-agnostic placement (hooks/mfa.rb).
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
    ensure
      teardown_mock_auth
    end
  end
end
