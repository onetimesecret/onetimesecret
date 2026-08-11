# apps/web/auth/spec/unit/login_mfa_auth_route_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Config::Hooks::Login.mfa_auth_route — the completion
# route selection behind json_response[:mfa_auth_url] in the after_login hook.
#
# Review finding (2026-08-11): the previous selection used exact array
# equality (mfa_methods == [:webauthn]), but passkey registration under
# AUTH_MFA_ENABLED=true AUTO-MINTS recovery codes (Rodauth's
# add_webauthn_credential override in recovery_codes.rb calls
# auto_add_missing_recovery_codes, and the app sets auto_add_recovery_codes?
# true) — so the NORMAL passkey-only account presents [:webauthn,
# :recovery_codes] and fell into the OTP branch, pointing at a factor the
# account cannot satisfy. These tests pin predicate-based selection.
#
# The hook prepends the mount prefix (request.script_name, '/auth') to the
# returned segment; that half is request-state and lives in the hook itself.

require 'rodauth'

# hooks/login.rb uses the compact `module Auth::Config::Hooks` form; create the
# namespace chain unless the real app already defined it (see the equivalent
# guard + rationale in spec/config/env_feature_loading_spec.rb).
module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)
Auth::Config.const_set(:Hooks, Module.new) unless Auth::Config.const_defined?(:Hooks, false)

require_relative '../../config/hooks/login'
require_relative '../../operations/detect_mfa_requirement'

RSpec.describe 'Auth::Config::Hooks::Login.mfa_auth_route' do
  subject(:picker) { Auth::Config::Hooks::Login }

  let(:otp_route)      { 'otp-auth' }
  let(:webauthn_route) { 'webauthn-auth' }

  # Build a REAL Decision through the operation so the methods list is the one
  # production computes, not a hand-rolled approximation.
  def decision(otp: false, recovery: false, webauthn: false)
    Auth::Operations::DetectMfaRequirement.call(
      account_id: 1,
      has_otp_secret: otp,
      has_recovery_codes: recovery,
      has_webauthn: webauthn,
    )
  end

  def pick(dec, **overrides)
    picker.mfa_auth_route(
      dec,
      otp_route: overrides.fetch(:otp_route, otp_route),
      webauthn_route: overrides.fetch(:webauthn_route, webauthn_route),
    )
  end

  it 'picks the OTP route when OTP is configured' do
    expect(pick(decision(otp: true))).to eq(otp_route)
  end

  it 'picks the OTP route when OTP and webauthn are both configured (OTP precedence)' do
    expect(pick(decision(otp: true, recovery: true, webauthn: true))).to eq(otp_route)
  end

  it 'picks the webauthn route for a passkey-only account' do
    expect(pick(decision(webauthn: true))).to eq(webauthn_route)
  end

  it 'picks the webauthn route for passkey + auto-minted recovery codes (the regression)' do
    dec = decision(webauthn: true, recovery: true)
    expect(dec.mfa_methods).to eq([:webauthn, :recovery_codes]) # the real shape
    expect(pick(dec)).to eq(webauthn_route),
      'an OTP URL here would point at a factor the account cannot satisfy'
  end

  it 'falls back to the OTP route for recovery-codes-only accounts' do
    # Recovery-code entry lives on the OTP verify page; the after_login caller
    # only reaches this branch when the OTP/recovery features are loaded.
    expect(pick(decision(recovery: true))).to eq(otp_route)
  end

  it 'works with a nil otp_route when webauthn is the available factor (webauthn-only deploy)' do
    expect(pick(decision(webauthn: true), otp_route: nil)).to eq(webauthn_route)
  end
end
