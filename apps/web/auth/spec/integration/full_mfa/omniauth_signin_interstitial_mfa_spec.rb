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

# Must be set before the suite's FIRST boot (FullModeSuiteDatabase.setup! runs
# from a config-level before(:context) hook, ahead of any group-level hook) so
# config.rb loads the Rodauth OTP feature set. The rake lane already exports it;
# this load-time set makes a direct `rspec <this file>` invocation work too.
ENV['AUTH_MFA_ENABLED'] = 'true'

require 'rotp'

RSpec.describe 'OmniAuth sign-in interstitial: deferred bind after MFA (#3877)',
  :full_auth_mode, type: :integration do
  include Rack::Test::Methods

  def app
    Onetime::Application::Registry.generate_rack_url_map
  end

  before(:all) do
    # Hard-fail (not skip): this lane EXISTS to cover the MFA path, so a boot
    # without the OTP feature is harness breakage, not an environment quirk.
    otp_loaded = Auth::Config.method_defined?(:otp_auth_route) ||
                 Auth::Config.private_method_defined?(:otp_auth_route)
    unless otp_loaded
      raise 'Rodauth OTP feature not loaded — this suite must boot with ' \
            'AUTH_MFA_ENABLED=true in a fresh process (run via ' \
            '`bundle exec rake spec:integration:full:mfa`; Auth::Config is one-shot)'
    end
  end

  let(:identities) { auth_db[:account_identities] }

  # ==========================================================================
  # Helpers (mirror integration/full/omniauth_signin_interstitial_spec.rb)
  # ==========================================================================

  def enable_platform_fallback
    allow(Onetime.auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
  end

  def seed_account_with_password(email, password: AuthTestConstants::TEST_PASSWORD)
    normalized = OT::Utils.normalize_email(email)
    customer   = Onetime::Customer.new(email: normalized)
    customer.save
    account_id = auth_db[:accounts].insert(
      email: normalized,
      status_id: AuthTestConstants::STATUS_VERIFIED,
      external_id: customer.extid,
    )
    require 'argon2'
    hasher = Argon2::Password.new(t_cost: 1, m_cost: 5, p_cost: 1)
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

  def clear_body_headers
    header 'Content-Type', nil
    header 'Content-Length', nil
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

  def fetch_csrf_token
    clear_body_headers
    header 'Accept', 'application/json'
    get '/auth'
    last_response.headers['X-CSRF-Token']
  end

  # JSON POST with the CSRF token in both header and body (shrimp), matching
  # what the SPA sends and what the other integration specs do.
  def json_post(path, params = {})
    csrf = fetch_csrf_token
    clear_body_headers
    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', csrf if csrf
    post path, JSON.generate(params.merge(shrimp: csrf))
    last_response
  end

  def post_link_sso(token:, password:)
    json_post('/auth/link-sso', token: token, password: password)
  end

  def json_body
    JSON.parse(last_response.body)
  rescue JSON::ParserError
    {}
  end

  # ==========================================================================
  # OTP provisioning — through Rodauth's OWN JSON setup flow, exactly as the
  # SPA does it, so the stored key shape (HMAC) matches production:
  #   phase 1: POST /auth/otp-setup {}            -> 422 + { otp_setup (the
  #            HMAC'd key the authenticator uses), otp_raw_secret }
  #   phase 2: POST /auth/otp-setup {otp_setup, otp_raw_secret, otp_code,
  #            password}                          -> 200, recovery codes added
  # Returns [authenticator secret (the otp_setup value), recovery codes] —
  # auto_add_recovery_codes? is on, and the app's after hook surfaces the
  # generated codes in the phase-2 JSON response (hooks/mfa.rb).
  # ==========================================================================

  def provision_totp(email, password: AuthTestConstants::TEST_PASSWORD)
    json_post('/auth/login', login: email, password: password)
    expect(last_response.status).to eq(200),
      "Precondition failed: password login for OTP setup (#{last_response.status}: #{last_response.body})"

    json_post('/auth/otp-setup', {})
    expect(last_response.status).to eq(422),
      "Phase-1 otp-setup should return the generated secret with a field error (#{last_response.status}: #{last_response.body})"
    setup_body = json_body
    secret     = setup_body['otp_setup']
    raw_secret = setup_body['otp_raw_secret']
    expect(secret).not_to be_nil
    expect(raw_secret).not_to be_nil

    json_post(
      '/auth/otp-setup',
      otp_setup: secret,
      otp_raw_secret: raw_secret,
      otp_code: ROTP::TOTP.new(secret).now,
      password: password,
    )
    expect(last_response.status).to eq(200),
      "Phase-2 otp-setup should confirm the secret (#{last_response.status}: #{last_response.body})"
    recovery_codes = Array(json_body['recovery_codes'])

    # Drop the setup session entirely: the interstitial flow below must start
    # from an UNAUTHENTICATED browser, like a user on a fresh device.
    clear_cookies
    [secret, recovery_codes]
  end

  # Rodauth's OTP reuse guard (otp_update_last_use) rejects any code within one
  # interval (30s) of last_use — and setup just stamped last_use=now. Rewind it
  # so the auth step can accept a fresh code immediately instead of sleeping
  # out the window in the test.
  #
  # One rewind covers a failed-then-retry sequence: Rodauth stamps last_use
  # only on SUCCESSFUL validation (`otp_valid_code? && otp_update_last_use`
  # short-circuits), so a rejected code leaves the rewound value in place and
  # the subsequent good code is still accepted without a second rewind.
  def allow_immediate_otp_reuse!(account_id)
    auth_db[:account_otp_keys].where(id: account_id).update(last_use: Time.now - 300)
  end

  # A code guaranteed to be rejected RIGHT NOW: Rodauth validates with
  # otp_drift (30s), so the previous and next interval's codes are accepted
  # too — a candidate must differ from all three, not just the current code.
  # Counter-based so every candidate stays six digits by construction (at most
  # four iterations: the valid set has exactly three elements).
  def wrong_otp_code(secret)
    totp  = ROTP::TOTP.new(secret)
    now   = Time.now.to_i
    valid = [totp.at(now - 30), totp.at(now), totp.at(now + 30)]
    (0..valid.size).each do |i|
      candidate = i.to_s.rjust(6, '0')
      return candidate unless valid.include?(candidate)
    end
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
