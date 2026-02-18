# apps/web/auth/spec/config/features/feature_combinations_spec.rb
#
# frozen_string_literal: true

# Tests for feature combinations
#
# Verifies that multiple conditional features can coexist without conflicts
# and that feature order dependencies are satisfied.
#
# Reference: apps/web/auth/config.rb

require_relative '../../spec_helper'

require_relative '../../support/auth_test_constants'
include AuthTestConstants

RSpec.describe 'Rodauth Feature Combinations' do
  let(:db) { create_test_database }

  describe 'all features enabled simultaneously' do
    # Simulates all features enabled:
    # ENV['AUTH_LOCKOUT_ENABLED'] != 'false' (default ON)
    # ENV['AUTH_PASSWORD_REQUIREMENTS_ENABLED'] != 'false' (default ON)
    # ENV['AUTH_ACTIVE_SESSIONS_ENABLED'] != 'false' (default ON)
    # ENV['AUTH_REMEMBER_ME_ENABLED'] != 'false' (default ON)
    # ENV['AUTH_MFA_ENABLED'] = 'true'
    # ENV['AUTH_EMAIL_AUTH_ENABLED'] = 'true'
    # ENV['AUTH_WEBAUTHN_ENABLED'] = 'true'
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [
          # Core features (always enabled)
          :base, :login, :logout,
          # Security features
          :lockout, :active_sessions, :remember, :login_password_requirements_base,
          # MFA features
          :two_factor_base, :otp, :recovery_codes,
          # Passwordless
          :email_auth,
          # WebAuthn
          :webauthn, :webauthn_login, :webauthn_modify_email
        ],
      ) do
        # Security configuration
        session_inactivity_deadline 86_400
        session_lifetime_deadline 2_592_000
        max_invalid_logins 5

        # MFA configuration
        otp_issuer 'OneTimeSecret'
        otp_auth_failures_limit MFA_OTP_AUTH_FAILURES_LIMIT
        otp_keys_use_hmac? true

        # Passwordless configuration
        email_auth_route 'email-login'
        email_auth_request_route 'email-login-request'

        # WebAuthn configuration
        webauthn_rp_name 'OnetimeSecret'
        webauthn_setup_timeout 60_000
        webauthn_user_verification 'preferred'
      end
    end

    describe 'all features coexist' do
      it 'has security features' do
        expect(rodauth_responds_to?(app, :max_invalid_logins)).to be true
        expect(rodauth_responds_to?(app, :session_inactivity_deadline)).to be true
        expect(rodauth_responds_to?(app, :remember_login)).to be true
      end

      it 'has MFA features' do
        expect(rodauth_responds_to?(app, :otp_setup_route)).to be true
        expect(rodauth_responds_to?(app, :recovery_codes_route)).to be true
        expect(rodauth_responds_to?(app, :two_factor_authentication_setup?)).to be true
      end

      it 'has passwordless features' do
        expect(rodauth_responds_to?(app, :email_auth_route)).to be true
        expect(rodauth_responds_to?(app, :create_email_auth_key)).to be true
      end

      it 'has WebAuthn features' do
        expect(rodauth_responds_to?(app, :webauthn_setup_route)).to be true
        expect(rodauth_responds_to?(app, :webauthn_login_route)).to be true
      end
    end

    describe 'MFA and WebAuthn as alternative 2FA methods' do
      it 'provides both OTP and WebAuthn authentication routes' do
        expect(rodauth_responds_to?(app, :otp_auth_route)).to be true
        expect(rodauth_responds_to?(app, :webauthn_auth_route)).to be true
      end

      it 'shares two_factor_base methods' do
        expect(rodauth_responds_to?(app, :uses_two_factor_authentication?)).to be true
        expect(rodauth_responds_to?(app, :two_factor_authentication_setup?)).to be true
      end
    end
  end

  describe 'MFA without lockout' do
    # Simulates ENV['AUTH_LOCKOUT_ENABLED'] = 'false'
    # plus ENV['AUTH_MFA_ENABLED'] = 'true'
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [
          :base, :login, :logout,
          :two_factor_base, :otp, :recovery_codes
        ],
      ) do
        otp_issuer 'OneTimeSecret'
        otp_auth_failures_limit MFA_OTP_AUTH_FAILURES_LIMIT
      end
    end

    it 'has MFA features' do
      expect(rodauth_responds_to?(app, :otp_setup_route)).to be true
      expect(rodauth_responds_to?(app, :recovery_codes_route)).to be true
    end

    it 'does not have lockout feature' do
      expect(rodauth_responds_to?(app, :max_invalid_logins)).to be false
    end

    it 'does not have active sessions feature' do
      expect(rodauth_responds_to?(app, :session_inactivity_deadline)).to be false
    end
  end

  describe 'lockout without password requirements' do
    # Simulates ENV['AUTH_LOCKOUT_ENABLED'] != 'false' (default ON)
    # plus ENV['AUTH_PASSWORD_REQUIREMENTS_ENABLED'] = 'false'
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [
          :base, :login, :logout,
          :lockout
        ],
      ) do
        max_invalid_logins 5
      end
    end

    it 'has lockout feature' do
      expect(rodauth_responds_to?(app, :max_invalid_logins)).to be true
    end

    it 'does not have password requirements feature' do
      expect(rodauth_responds_to?(app, :password_meets_requirements?)).to be false
    end
  end

  describe 'password requirements without lockout' do
    # Simulates ENV['AUTH_LOCKOUT_ENABLED'] = 'false'
    # plus ENV['AUTH_PASSWORD_REQUIREMENTS_ENABLED'] != 'false' (default ON)
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [
          :base, :login, :logout,
          :login_password_requirements_base
        ],
      )
    end

    it 'has password requirements feature' do
      expect(rodauth_responds_to?(app, :password_meets_requirements?)).to be true
    end

    it 'does not have lockout feature' do
      expect(rodauth_responds_to?(app, :max_invalid_logins)).to be false
    end
  end

  describe 'MFA without password requirements' do
    # Simulates ENV['AUTH_PASSWORD_REQUIREMENTS_ENABLED'] = 'false'
    # plus ENV['AUTH_MFA_ENABLED'] = 'true'
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [
          :base, :login, :logout,
          :two_factor_base, :otp, :recovery_codes
        ],
      ) do
        otp_issuer 'OneTimeSecret'
        otp_auth_failures_limit MFA_OTP_AUTH_FAILURES_LIMIT
      end
    end

    it 'has MFA features' do
      expect(rodauth_responds_to?(app, :otp_setup_route)).to be true
    end

    it 'does not have password requirements feature' do
      expect(rodauth_responds_to?(app, :password_meets_requirements?)).to be false
    end
  end

  describe 'WebAuthn without MFA' do
    # Simulates ENV['AUTH_WEBAUTHN_ENABLED'] = 'true'
    # with ENV['AUTH_MFA_ENABLED'] not set (default disabled)
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [
          :base, :login, :logout,
          :webauthn, :webauthn_login
        ],
      ) do
        webauthn_rp_name 'OnetimeSecret'
        webauthn_setup_timeout 60_000
      end
    end

    it 'has WebAuthn features' do
      expect(rodauth_responds_to?(app, :webauthn_setup_route)).to be true
      expect(rodauth_responds_to?(app, :webauthn_login_route)).to be true
    end

    it 'does not have OTP features' do
      expect(rodauth_responds_to?(app, :otp_setup_route)).to be false
    end
  end

  describe 'email auth and WebAuthn together' do
    # Simulates ENV['AUTH_EMAIL_AUTH_ENABLED'] = 'true'
    # plus ENV['AUTH_WEBAUTHN_ENABLED'] = 'true'
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [
          :base, :login, :logout,
          :email_auth,
          :webauthn, :webauthn_login
        ],
      ) do
        email_auth_route 'email-login'
        webauthn_rp_name 'OnetimeSecret'
      end
    end

    it 'has passwordless features' do
      expect(rodauth_responds_to?(app, :email_auth_route)).to be true
    end

    it 'has WebAuthn features' do
      expect(rodauth_responds_to?(app, :webauthn_setup_route)).to be true
      expect(rodauth_responds_to?(app, :webauthn_login_route)).to be true
    end

    it 'provides multiple passwordless login options' do
      # Both methods allow login without password
      expect(rodauth_responds_to?(app, :create_email_auth_key)).to be true
      expect(rodauth_responds_to?(app, :webauthn_login_route)).to be true
    end
  end

  describe 'minimal configuration (all optional features disabled)' do
    # Simulates all features disabled:
    # ENV['AUTH_LOCKOUT_ENABLED'] = 'false'
    # ENV['AUTH_PASSWORD_REQUIREMENTS_ENABLED'] = 'false'
    # ENV['AUTH_ACTIVE_SESSIONS_ENABLED'] = 'false'
    # ENV['AUTH_REMEMBER_ME_ENABLED'] = 'false'
    # with no other optional features enabled
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [:base, :login, :logout],
      )
    end

    it 'still has core login/logout' do
      expect(rodauth_responds_to?(app, :login_route)).to be true
      expect(rodauth_responds_to?(app, :logout_route)).to be true
    end

    it 'does not have any optional features' do
      # Security
      expect(rodauth_responds_to?(app, :max_invalid_logins)).to be false
      # MFA
      expect(rodauth_responds_to?(app, :otp_setup_route)).to be false
      # Passwordless
      expect(rodauth_responds_to?(app, :email_auth_route)).to be false
      # WebAuthn
      expect(rodauth_responds_to?(app, :webauthn_setup_route)).to be false
    end
  end
end
