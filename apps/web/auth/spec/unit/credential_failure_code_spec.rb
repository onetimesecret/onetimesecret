# apps/web/auth/spec/unit/credential_failure_code_spec.rb
#
# frozen_string_literal: true

# The one seam between Rodauth's error reasons and the stable failure codes
# (#4469): apps/web/auth/credential_failure_code.rb, called from the
# set_error_reason override in config/overrides/failure_code.rb.
#
# No Rodauth instance and no boot: the policy is a table plus one function
# over a Hash, which is all the override hands it. What is locked in:
#
#   - a rejected credential replaces whatever the router stashed;
#   - a login-required refusal keeps the router's anonymous reason;
#   - every other Rodauth reason withdraws the stash, so an unrelated 401
#     (an invalid key) stays uncoded;
#   - the credential codes are never finer than `invalid_credentials`, so
#     Rodauth's `no matching login` / `invalid password` split is not
#     reproduced on the wire as a code.
#
# Run:
#   bundle exec rspec apps/web/auth/spec/unit/credential_failure_code_spec.rb

require_relative '../spec_helper'
require_relative '../../credential_failure_code'

RSpec.describe Auth::CredentialFailureCode do
  let(:env_key) { Onetime::SessionFailureCode::ENV_KEY }

  def env_with(reason)
    reason ? { env_key => reason } : {}
  end

  describe 'vocabulary' do
    it 'maps every credential reason to a code in the credential scope' do
      described_class::CREDENTIAL_REASONS.each_value do |code|
        expect(Onetime::SessionFailureCode.credential?(code)).to be(true), "#{code} is not a credential code"
      end
    end

    it 'never distinguishes an unknown login from a wrong password' do
      expect(described_class::CREDENTIAL_REASONS.fetch(:no_matching_login))
        .to eq(described_class::CREDENTIAL_REASONS.fetch(:invalid_password))
    end

    it 'maps every session reason to an evaluator reason, or keeps the stash' do
      described_class::SESSION_REASONS.each_value do |mapped|
        next if mapped.nil?

        expect(Onetime::SessionFailureCode::SESSION_REASON_SCOPES).to have_key(mapped)
      end
    end

    it 'names the 403 refusals it leaves uncoded, and does not map them' do
      described_class::UNCODED_403_REASONS.each do |reason|
        expect(described_class::CREDENTIAL_REASONS).not_to have_key(reason)
        expect(described_class::SESSION_REASONS).not_to have_key(reason)
      end
    end

    it 'keeps the three tables disjoint' do
      keys = described_class::CREDENTIAL_REASONS.keys +
             described_class::SESSION_REASONS.keys +
             described_class::UNCODED_403_REASONS
      expect(keys.tally.select { |_reason, count| count > 1 }).to be_empty
    end
  end

  describe '.record' do
    it 'stashes invalid_credentials for a rejected login, replacing the anonymous stash' do
      env = env_with(:session_missing)

      expect(described_class.record(env, :no_matching_login)).to eq(:invalid_credentials)
      expect(env[env_key]).to eq(:invalid_credentials)

      env = env_with(:session_missing)
      expect(described_class.record(env, :invalid_password)).to eq(:invalid_credentials)
    end

    it 'stashes invalid_credentials for a rejected password confirmation on a logged-in request' do
      env = env_with(nil)

      expect(described_class.record(env, :invalid_password)).to eq(:invalid_credentials)
    end

    it 'stashes invalid_credentials for a rejected second factor or passkey' do
      %i[invalid_otp_auth_code invalid_recovery_code invalid_webauthn_auth_param].each do |reason|
        expect(described_class.record(env_with(nil), reason)).to eq(reason && :invalid_credentials)
      end
    end

    it 'keeps the router stash for a login-required refusal' do
      env = env_with(:not_authenticated)

      expect(described_class.record(env, :login_required)).to eq(:not_authenticated)
      expect(env[env_key]).to eq(:not_authenticated)
    end

    it 'leaves a login-required refusal uncoded when nothing was stashed' do
      env = env_with(nil)

      expect(described_class.record(env, :login_required)).to be_nil
      expect(env).not_to have_key(env_key)
    end

    it 'stashes awaiting_mfa for a route that needs the second factor' do
      expect(described_class.record(env_with(nil), :two_factor_need_authentication)).to eq(:awaiting_mfa)
    end

    it 'withdraws the stash for any other reason so the response stays uncoded' do
      %i[
        invalid_verify_account_key
        invalid_reset_password_key
        invalid_email_auth_key
        invalid_unlock_account_key
        already_logged_in
        two_factor_not_setup
        two_factor_already_authenticated
        duplicate_webauthn_id
        account_locked_out
        unverified_account
      ].each do |reason|
        env = env_with(:session_missing)

        expect(described_class.record(env, reason)).to be_nil
        expect(env).not_to have_key(env_key), "#{reason} left a stash behind"
      end
    end

    it 'withdraws the stash for a nil reason' do
      env = env_with(:session_missing)

      expect(described_class.record(env, nil)).to be_nil
      expect(env).to be_empty
    end

    it 'accepts a String reason' do
      expect(described_class.record(env_with(nil), 'invalid_password')).to eq(:invalid_credentials)
    end

    it 'tolerates a non-Hash env (an internal request with no Rack env)' do
      expect { described_class.record(nil, :invalid_password) }.not_to raise_error
      expect(described_class.record(nil, :invalid_password)).to be_nil
    end
  end
end
