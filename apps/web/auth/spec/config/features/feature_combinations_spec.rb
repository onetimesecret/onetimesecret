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
    # ENV['ENABLE_HARDENING'] != 'false' (default ON)
    # ENV['ENABLE_ACTIVE_SESSIONS'] != 'false' (default ON)
    # ENV['ENABLE_REMEMBER_ME'] != 'false' (default ON)
    # ENV['ENABLE_MFA'] = 'true'
    # ENV['ENABLE_EMAIL_AUTH'] = 'true'
    # ENV['ENABLE_WEBAUTHN'] = 'true'
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

  describe 'MFA without hardening features' do
    # Simulates ENV['ENABLE_HARDENING'] = 'false'
    # plus ENV['ENABLE_MFA'] = 'true'
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

  describe 'WebAuthn without MFA' do
    # Simulates ENV['ENABLE_WEBAUTHN'] = 'true'
    # with ENV['ENABLE_MFA'] not set (default disabled)
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
    # Simulates ENV['ENABLE_EMAIL_AUTH'] = 'true'
    # plus ENV['ENABLE_WEBAUTHN'] = 'true'
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
    # ENV['ENABLE_HARDENING'] = 'false'
    # ENV['ENABLE_ACTIVE_SESSIONS'] = 'false'
    # ENV['ENABLE_REMEMBER_ME'] = 'false'
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
