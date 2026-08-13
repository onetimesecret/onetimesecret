# apps/web/auth/spec/routes/link_sso_second_factor_pending_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Route module (non-integration)
# =============================================================================
#
# Auth::Routes::LinkSso#link_sso_second_factor_pending? — the pre-login MFA
# prediction that gates the SSO identity bind on FULL authentication (#3858).
#
# WHAT IT LOCKS IN (mirrors the hooks/login.rb per-feature gating exactly):
#   - A webauthn-only account IS predicted second-factor-pending when the
#     webauthn feature is loaded — so the bind is DEFERRED, never direct.
#     Without this, a webauthn-only account would be predicted no-MFA and
#     direct-bound while its second factor is still pending, reopening for
#     webauthn the MFA-bypassing bind path #3858 closed for OTP.
#   - A factor whose completion route is NOT loaded never gates: webauthn rows
#     with the webauthn feature off (and OTP/recovery rows with theirs off)
#     get the same no-MFA outcome as before.
#   - No two-factor feature loaded => always false (bind proceeds), rows or not.
#
# The helper reads only rodauth.db + rodauth.respond_to?(<route method>), so a
# stub rodauth exposes exactly that surface while MfaStateChecker and
# DetectMfaRequirement run for REAL against rows seeded in the in-memory
# SQLite schema (same bare-host pattern as the #mask_uid boundary examples in
# integration/full/identities_routes_spec.rb). The full POST flow (challenge,
# password proof, rate limiter, rodauth.login) stays in
# spec/integration/full/omniauth_signin_interstitial_spec.rb.
# =============================================================================

require_relative '../spec_helper'
require_relative '../support/route_test_app_helper'
require_relative '../../routes/link_sso'
require_relative '../../operations/mfa_state_checker'
require_relative '../../operations/detect_mfa_requirement'

RSpec.describe 'Auth::Routes::LinkSso#link_sso_second_factor_pending?' do
  include RouteTestAppHelper

  let(:db) { create_test_database }
  let(:account_id) { seed_route_test_account(db) }

  let(:host_class) do
    Class.new do
      include Auth::Routes::LinkSso
      attr_accessor :rodauth
    end
  end

  # Evaluate the helper against a rodauth whose loaded feature-route methods
  # are exactly `loaded_routes` (respond_to? is true only for stubbed
  # messages, so unlisted routes read as feature-not-loaded).
  def second_factor_pending?(loaded_routes)
    fake = double('rodauth', db: db)
    loaded_routes.each { |route| allow(fake).to receive(route).and_return(route.to_s) }

    host         = host_class.new
    host.rodauth = fake
    host.send(:link_sso_second_factor_pending?, account_id)
  end

  def seed_webauthn_credential
    db[:account_webauthn_keys].insert(
      account_id: account_id,
      webauthn_id: "cred-#{SecureRandom.hex(4)}",
      public_key: 'pk-material',
      sign_count: 0,
      last_use: Time.now.utc,
    )
  end

  def seed_otp_secret
    db[:account_otp_keys].insert(id: account_id, key: 'JBSWY3DPEHPK3PXP')
  end

  def seed_recovery_code
    db[:account_recovery_codes].insert(id: account_id, code: SecureRandom.hex(8))
  end

  describe 'webauthn as a second factor (#3858 reopened path)' do
    it 'predicts pending for a webauthn-only account when the webauthn feature is loaded' do
      seed_webauthn_credential

      expect(second_factor_pending?([:webauthn_auth_route])).to be(true)
    end

    it 'predicts pending for a webauthn-only account in a full-featured deploy' do
      seed_webauthn_credential

      expect(
        second_factor_pending?([:otp_auth_route, :recovery_auth_route, :webauthn_auth_route]),
      ).to be(true)
    end

    it 'ignores webauthn credentials when the webauthn feature is not loaded' do
      seed_webauthn_credential

      expect(second_factor_pending?([:otp_auth_route, :recovery_auth_route])).to be(false)
    end
  end

  describe 'per-feature gating parity with hooks/login.rb' do
    it 'returns false when no two-factor feature is loaded, regardless of stored factors' do
      seed_webauthn_credential
      seed_otp_secret

      expect(second_factor_pending?([])).to be(false)
    end

    it 'still predicts pending for an OTP account when the OTP feature is loaded' do
      seed_otp_secret

      expect(second_factor_pending?([:otp_auth_route])).to be(true)
    end

    it 'gates recovery codes on their own route being loaded' do
      seed_recovery_code

      expect(second_factor_pending?([:otp_auth_route, :recovery_auth_route])).to be(true)
      expect(second_factor_pending?([:otp_auth_route])).to be(false)
    end

    it 'returns false when features are loaded but the account has no factors' do
      expect(
        second_factor_pending?([:otp_auth_route, :recovery_auth_route, :webauthn_auth_route]),
      ).to be(false)
    end
  end
end
