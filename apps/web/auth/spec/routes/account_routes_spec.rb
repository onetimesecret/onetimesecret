# apps/web/auth/spec/routes/account_routes_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Route module (non-integration)
# =============================================================================
#
# Passkey additions to the account routes (apps/web/auth/routes/account.rb):
#
#   - GET /auth/account: build_account_info now includes passkeys_count
#     (fills the dangling frontend contract — src/schemas/contracts/auth.ts
#     declares it optional and SecurityOverview.vue reads it with ?? 0).
#
#   - GET /auth/mfa-status: additive otp_enabled + webauthn_enabled booleans
#     for the MFA challenge page. The existing `enabled` computation is
#     UNCHANGED — it means "TOTP-family MFA on" (OTP or recovery codes) and
#     must keep ignoring webauthn, otherwise a webauthn-only-MFA account
#     would auto-complete auth.
#
# Runs in the spec:apps:web_auth lane (no Valkey, no app boot) via a mini Roda
# app hosting the production route module — see support/route_test_app_helper.rb.
# =============================================================================

require_relative '../spec_helper'
require_relative '../support/route_test_app_helper'
require_relative '../../routes/account'

RSpec.describe 'Account routes passkey additions (Auth::Routes::Account)' do
  include Rack::Test::Methods
  include RouteTestAppHelper

  let(:recovery_codes_limit_stub) { 16 }
  let(:db) { create_test_database }

  # Default app: ALL second-factor features loaded. mfa-status gates
  # webauthn_enabled on rodauth.respond_to?(:webauthn_auth_route), so the
  # webauthn feature must be enabled for the truthy cases; the
  # feature-not-loaded context below overrides `app` without it.
  let(:app) do
    build_route_test_app(
      db: db,
      route_module: Auth::Routes::Account,
      handler: :handle_account_routes,
      features: [:base, :login, :logout, :otp, :recovery_codes, :webauthn],
    )
  end

  let(:account_id) { seed_route_test_account(db) }

  before do
    # mfa-status references Auth::Config::Features::MFA::RECOVERY_CODES_LIMIT
    # at response-build time; Auth::Config is one-shot and not loaded in this
    # lane, so pin the constant here.
    stub_const('Auth::Config::Features::MFA::RECOVERY_CODES_LIMIT', recovery_codes_limit_stub)
  end

  def login(id)
    post '/test-login', account_id: id
    expect(last_response.status).to eq(200)
  end

  def seed_passkey(account_id, webauthn_id: "cred-#{SecureRandom.hex(4)}")
    db[:account_webauthn_keys].insert(
      account_id: account_id,
      webauthn_id: webauthn_id,
      public_key: 'pk-material',
      sign_count: 0,
      last_use: Time.utc(2026, 1, 1, 12, 0, 0),
    )
  end

  def seed_otp_key(account_id)
    db[:account_otp_keys].insert(
      id: account_id,
      key: 'JBSWY3DPEHPK3PXP',
      num_failures: 0,
      last_use: Time.utc(2026, 1, 2, 8, 30, 0),
    )
  end

  def seed_recovery_code(account_id, code: SecureRandom.hex(8))
    db[:account_recovery_codes].insert(id: account_id, code: code)
  end

  # ==========================================================================
  # GET /account — passkeys_count
  # ==========================================================================

  describe 'GET /account passkeys_count' do
    it 'returns 0 when the account has no webauthn credentials' do
      login(account_id)
      get '/account'

      expect(last_response.status).to eq(200)
      body = json_body
      expect(body['passkeys_count']).to eq(0)
      # Neighboring fields are untouched.
      expect(body['id']).to eq(account_id)
      expect(body['has_password']).to be(false)
      expect(body['mfa_enabled']).to be(false)
    end

    it 'returns the number of registered webauthn credentials' do
      seed_passkey(account_id, webauthn_id: 'cred-a')
      seed_passkey(account_id, webauthn_id: 'cred-b')
      # Another account's credential must not be counted.
      seed_passkey(seed_route_test_account(db), webauthn_id: 'cred-other')

      login(account_id)
      get '/account'

      expect(last_response.status).to eq(200)
      expect(json_body['passkeys_count']).to eq(2)
    end
  end

  # ==========================================================================
  # GET /mfa-status — otp_enabled / webauthn_enabled truth table
  # ==========================================================================

  describe 'GET /mfa-status factor booleans' do
    def mfa_status
      login(account_id)
      get '/mfa-status'
      expect(last_response.status).to eq(200)
      json_body
    end

    it 'reports neither factor when the account has no OTP and no passkeys' do
      body = mfa_status

      expect(body['otp_enabled']).to be(false)
      expect(body['webauthn_enabled']).to be(false)
      expect(body['enabled']).to be(false)
    end

    it 'reports otp_enabled only when the account has an OTP key' do
      seed_otp_key(account_id)

      body = mfa_status

      expect(body['otp_enabled']).to be(true)
      expect(body['webauthn_enabled']).to be(false)
      expect(body['enabled']).to be(true)
      expect(body['last_used_at']).to eq('2026-01-02T08:30:00Z')
    end

    it 'reports webauthn_enabled but keeps enabled false for a webauthn-only account' do
      seed_passkey(account_id)

      body = mfa_status

      expect(body['otp_enabled']).to be(false)
      expect(body['webauthn_enabled']).to be(true)
      # CRITICAL: `enabled` means TOTP-family MFA and must keep ignoring
      # webauthn — the challenge page uses webauthn_enabled to offer the
      # passkey factor instead of auto-completing auth.
      expect(body['enabled']).to be(false)
    end

    it 'reports both factors when the account has OTP and passkeys' do
      seed_otp_key(account_id)
      seed_passkey(account_id)

      body = mfa_status

      expect(body['otp_enabled']).to be(true)
      expect(body['webauthn_enabled']).to be(true)
      expect(body['enabled']).to be(true)
    end

    it 'keeps enabled true for recovery-codes-only accounts (existing behavior)' do
      seed_recovery_code(account_id)

      body = mfa_status

      expect(body['otp_enabled']).to be(false)
      expect(body['webauthn_enabled']).to be(false)
      expect(body['enabled']).to be(true)
      expect(body['recovery_codes_remaining']).to eq(1)
    end

    it 'emits the full additive response shape' do
      body = mfa_status

      expect(body.keys).to match_array(
        %w[enabled otp_enabled webauthn_enabled last_used_at recovery_codes_remaining recovery_codes_limit],
      )
      expect(body['recovery_codes_limit']).to eq(recovery_codes_limit_stub)
    end
  end

  # ==========================================================================
  # Feature-not-loaded gating (AUTH_WEBAUTHN_ENABLED=false with leftover rows)
  # ==========================================================================
  #
  # mfa-status must NOT advertise a passkey factor whose completion route
  # (/auth/webauthn-auth) is unmounted — the SPA would offer "Use a passkey
  # instead" and POST into a 404. passkeys_count is the deliberate opposite:
  # management/visibility data that keeps reporting existing credentials.

  describe 'with the webauthn feature not loaded' do
    let(:app) do
      build_route_test_app(
        db: db,
        route_module: Auth::Routes::Account,
        handler: :handle_account_routes,
        features: [:base, :login, :logout, :otp, :recovery_codes],
      )
    end

    it 'reports webauthn_enabled false on mfa-status despite leftover credential rows' do
      seed_passkey(account_id)

      login(account_id)
      get '/mfa-status'

      expect(last_response.status).to eq(200)
      body = json_body
      expect(body['webauthn_enabled']).to be(false)
      expect(body['enabled']).to be(false)
    end

    it 'still reports passkeys_count on account info (visibility is not feature-gated)' do
      seed_passkey(account_id)

      login(account_id)
      get '/account'

      expect(last_response.status).to eq(200)
      expect(json_body['passkeys_count']).to eq(1)
    end
  end
end
