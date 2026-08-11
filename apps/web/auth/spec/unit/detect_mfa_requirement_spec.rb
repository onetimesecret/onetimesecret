# apps/web/auth/spec/unit/detect_mfa_requirement_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::DetectMfaRequirement
#
# Pure-function operation. No external dependencies. Tests the decision logic
# given primitive inputs.
#
# Specifically covers the via_omniauth bypass added for issue #3114: SSO
# logins must NOT trigger the MFA flow even if the account has OTP configured.
# The IdP is trusted to enforce authentication factors.

require_relative '../../operations/detect_mfa_requirement'

RSpec.describe Auth::Operations::DetectMfaRequirement do
  describe '#mfa_required?' do
    context 'when account has neither OTP nor recovery codes' do
      it 'returns false' do
        decision = described_class.call(
          account_id: 1,
          has_otp_secret: false,
          has_recovery_codes: false,
        )
        expect(decision.requires_mfa?).to be(false)
        expect(decision.reason).to eq('no_mfa_configured')
      end
    end

    context 'when account has OTP secret' do
      it 'returns true' do
        decision = described_class.call(
          account_id: 1,
          has_otp_secret: true,
          has_recovery_codes: false,
        )
        expect(decision.requires_mfa?).to be(true)
        expect(decision.reason).to eq('otp_configured')
      end
    end

    context 'when account has OTP + recovery codes' do
      it 'returns true' do
        decision = described_class.call(
          account_id: 1,
          has_otp_secret: true,
          has_recovery_codes: true,
        )
        expect(decision.requires_mfa?).to be(true)
        expect(decision.reason).to eq('otp_and_recovery_configured')
      end
    end

    context 'when mfa_policy is :required' do
      it 'returns true even without OTP' do
        decision = described_class.call(
          account_id: 1,
          has_otp_secret: false,
          has_recovery_codes: false,
          mfa_policy: :required,
        )
        expect(decision.requires_mfa?).to be(true)
        expect(decision.reason).to eq('policy_required')
      end
    end

    context 'when mfa_policy is :disabled' do
      it 'returns false even with OTP configured' do
        decision = described_class.call(
          account_id: 1,
          has_otp_secret: true,
          has_recovery_codes: true,
          mfa_policy: :disabled,
        )
        expect(decision.requires_mfa?).to be(false)
        expect(decision.reason).to eq('policy_disabled')
      end
    end

    # ========================================================================
    # WebAuthn as a second factor (passkeys / security keys)
    # ========================================================================
    #
    # An account with >= 1 row in account_webauthn_keys must be gated exactly
    # like an OTP account. The caller (hooks/login.rb) is responsible for
    # passing has_webauthn: true only when the webauthn feature is loaded.

    context 'when account has WebAuthn credentials only' do
      it 'returns true with :webauthn as the only method' do
        decision = described_class.call(
          account_id: 1,
          has_otp_secret: false,
          has_recovery_codes: false,
          has_webauthn: true,
        )
        expect(decision.requires_mfa?).to be(true)
        expect(decision.mfa_methods).to eq([:webauthn])
        expect(decision.has_webauthn?).to be(true)
        expect(decision.primary_method).to eq(:webauthn)
        expect(decision.reason).to eq('webauthn_configured')
      end
    end

    context 'when account has WebAuthn + OTP' do
      it 'returns true with OTP ranked first (established primary UX)' do
        decision = described_class.call(
          account_id: 1,
          has_otp_secret: true,
          has_recovery_codes: false,
          has_webauthn: true,
        )
        expect(decision.requires_mfa?).to be(true)
        expect(decision.mfa_methods).to eq([:otp, :webauthn])
        expect(decision.primary_method).to eq(:otp)
        expect(decision.reason).to eq('otp_and_webauthn_configured')
      end
    end

    context 'when account has WebAuthn + recovery codes' do
      it 'ranks webauthn (a real factor) above the backup codes' do
        decision = described_class.call(
          account_id: 1,
          has_otp_secret: false,
          has_recovery_codes: true,
          has_webauthn: true,
        )
        expect(decision.requires_mfa?).to be(true)
        expect(decision.mfa_methods).to eq([:webauthn, :recovery_codes])
        expect(decision.reason).to eq('webauthn_and_recovery_configured')
      end
    end

    context 'when has_webauthn is omitted (default false)' do
      it 'preserves pre-webauthn behavior for existing callers' do
        decision = described_class.call(
          account_id: 1,
          has_otp_secret: false,
          has_recovery_codes: false,
        )
        expect(decision.requires_mfa?).to be(false)
        expect(decision.has_webauthn?).to be(false)
        expect(decision.reason).to eq('no_mfa_configured')
      end
    end

    context 'when mfa_policy is :disabled with WebAuthn configured' do
      it 'honors the policy override over the webauthn factor' do
        decision = described_class.call(
          account_id: 1,
          has_otp_secret: false,
          has_recovery_codes: false,
          has_webauthn: true,
          mfa_policy: :disabled,
        )
        expect(decision.requires_mfa?).to be(false)
        expect(decision.reason).to eq('policy_disabled')
      end
    end

    # ========================================================================
    # Passkey-FIRST-factor bypass (webauthn-login)
    # ========================================================================
    #
    # POST /auth/webauthn-login authenticates WITH the passkey as the primary
    # credential (authenticated_by contains 'webauthn' when after_login runs).
    # Demanding a second factor then is unsatisfiable — Rodauth's webauthn-auth
    # completion route rejects re-use of the login type
    # (require_two_factor_not_authenticated type-match), so a webauthn-only
    # account would loop between login and an uncompletable /mfa-verify.
    # Outcome pinned here: passkey-first logins are FULLY authenticated.

    context 'when via_webauthn_login is true (passkey was the first factor)' do
      it 'does not require MFA for a webauthn-only account (no login loop)' do
        decision = described_class.call(
          account_id: 1,
          has_otp_secret: false,
          has_recovery_codes: false,
          has_webauthn: true,
          via_webauthn_login: true,
        )
        expect(decision.requires_mfa?).to be(false),
          'passkey-first login must not demand the passkey again'
        expect(decision.sync_session_now?).to be(true)
        expect(decision.reason).to eq('webauthn_login_bypass')
      end

      it 'does not require MFA even when the account ALSO has OTP configured' do
        # Policy: a passkey (possession + local gesture) fully authenticates;
        # no OTP top-up after a passkey login.
        decision = described_class.call(
          account_id: 1,
          has_otp_secret: true,
          has_recovery_codes: true,
          has_webauthn: true,
          via_webauthn_login: true,
        )
        expect(decision.requires_mfa?).to be(false)
        expect(decision.reason).to eq('webauthn_login_bypass')
      end

      it 'wins over an explicit :required policy (the demanded factor was presented)' do
        decision = described_class.call(
          account_id: 1,
          has_otp_secret: false,
          has_recovery_codes: false,
          has_webauthn: true,
          mfa_policy: :required,
          via_webauthn_login: true,
        )
        expect(decision.requires_mfa?).to be(false)
        expect(decision.reason).to eq('webauthn_login_bypass')
      end

      it 'keeps sso_bypass as the reported reason when both bypasses apply' do
        # Precedence only affects the reason string — the outcome is identical.
        decision = described_class.call(
          account_id: 1,
          has_otp_secret: false,
          has_recovery_codes: false,
          has_webauthn: true,
          via_omniauth: true,
          via_webauthn_login: true,
        )
        expect(decision.requires_mfa?).to be(false)
        expect(decision.reason).to eq('sso_bypass')
      end
    end

    context 'when via_webauthn_login defaults to false (password first factor)' do
      it 'still requires the passkey challenge for accounts with credentials' do
        # Outcome (2): password login with passkeys registered triggers the
        # challenge exactly as before.
        decision = described_class.call(
          account_id: 1,
          has_otp_secret: false,
          has_recovery_codes: false,
          has_webauthn: true,
        )
        expect(decision.requires_mfa?).to be(true)
        expect(decision.mfa_methods).to eq([:webauthn])
      end
    end

    # ========================================================================
    # SSO bypass (issue #3114)
    # ========================================================================
    #
    # Project policy: SSO logins bypass MFA. The IdP is trusted to enforce
    # authentication factors. This avoids stranding existing accounts (e.g.,
    # legacy password+OTP setups) when the user later signs in via SSO.

    context 'when via_omniauth is true' do
      it 'returns false even when account has OTP configured' do
        decision = described_class.call(
          account_id: 1,
          has_otp_secret: true,
          has_recovery_codes: true,
          via_omniauth: true,
        )
        expect(decision.requires_mfa?).to be(false),
          'SSO logins must bypass MFA regardless of account OTP state'
        expect(decision.reason).to eq('sso_bypass')
      end

      it 'returns false even when mfa_policy is :required' do
        # SSO bypass wins over explicit policy. The IdP enforces factors,
        # so an account-level "require MFA" policy is satisfied by the IdP.
        decision = described_class.call(
          account_id: 1,
          has_otp_secret: false,
          has_recovery_codes: false,
          mfa_policy: :required,
          via_omniauth: true,
        )
        expect(decision.requires_mfa?).to be(false),
          'SSO bypass must short-circuit even explicit :required policy'
        expect(decision.reason).to eq('sso_bypass')
      end

      it 'returns false for accounts without any MFA configured' do
        decision = described_class.call(
          account_id: 1,
          has_otp_secret: false,
          has_recovery_codes: false,
          via_omniauth: true,
        )
        expect(decision.requires_mfa?).to be(false)
        expect(decision.reason).to eq('sso_bypass')
      end

      it 'returns false even when account has WebAuthn credentials' do
        # The SSO bypass must survive the webauthn extension unchanged: the
        # IdP is trusted to enforce factors, passkeys included.
        decision = described_class.call(
          account_id: 1,
          has_otp_secret: false,
          has_recovery_codes: false,
          has_webauthn: true,
          via_omniauth: true,
        )
        expect(decision.requires_mfa?).to be(false),
          'SSO logins must bypass MFA regardless of webauthn credential state'
        expect(decision.reason).to eq('sso_bypass')
      end
    end

    context 'when via_omniauth defaults to false' do
      it 'preserves pre-existing behavior for password logins' do
        # No via_omniauth argument passed → defaults to false → MFA logic runs.
        decision = described_class.call(
          account_id: 1,
          has_otp_secret: true,
          has_recovery_codes: false,
        )
        expect(decision.requires_mfa?).to be(true)
        expect(decision.reason).to eq('otp_configured')
      end
    end
  end

  describe 'input validation' do
    it 'raises when via_omniauth is not a boolean' do
      expect {
        described_class.call(
          account_id: 1,
          has_otp_secret: true,
          has_recovery_codes: false,
          via_omniauth: 'yes',
        )
      }.to raise_error(Auth::Operations::DetectMfaRequirement::InvalidInput, /via_omniauth/)
    end

    it 'raises when has_webauthn is not a boolean' do
      expect {
        described_class.call(
          account_id: 1,
          has_otp_secret: false,
          has_recovery_codes: false,
          has_webauthn: 1,
        )
      }.to raise_error(Auth::Operations::DetectMfaRequirement::InvalidInput, /has_webauthn/)
    end

    it 'raises when via_webauthn_login is not a boolean' do
      expect {
        described_class.call(
          account_id: 1,
          has_otp_secret: false,
          has_recovery_codes: false,
          via_webauthn_login: nil.to_s,
        )
      }.to raise_error(Auth::Operations::DetectMfaRequirement::InvalidInput, /via_webauthn_login/)
    end
  end
end
