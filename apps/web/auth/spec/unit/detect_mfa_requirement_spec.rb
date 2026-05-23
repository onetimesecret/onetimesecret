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
  end
end
