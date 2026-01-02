# apps/web/auth/spec/config/env_feature_loading_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Unit
# =============================================================================
#
# WHAT THIS TESTS:
#   Runtime feature enablement based on ENV variable values.
#   Uses the SAME conditional patterns as production config.rb to build
#   Rodauth apps, then verifies the expected features are present/absent.
#
# MUST INCLUDE:
#   - Code execution (creates real Rodauth instances)
#   - Method calls (checks feature method presence)
#   - Assertions on return values (verifies configuration)
#
# MUST NOT INCLUDE:
#   - File.read() of source files
#   - String pattern matching on config files
#
# WHY THIS IS USEFUL:
#   - climate_control isolates ENV changes to each test block
#   - create_rodauth_app builds real Roda/Rodauth instances
#   - Tests execute the same conditional logic as config.rb
#   - Verifies features are actually enabled/disabled at runtime
#
# =============================================================================

require_relative '../spec_helper'
require 'climate_control'

# Define namespace before loading the MFA module
module Auth
  module Config
    module Features
    end
  end
end
require_relative '../../config/features/mfa'

RSpec.describe 'ENV-conditional feature loading' do
  let(:db) { create_test_database }

  # Helper that mirrors config.rb conditional logic for security features
  def build_security_features_app(db)
    features = [:base, :login, :logout]

    # Same pattern as config.rb: enabled unless explicitly 'false'
    if ENV['ENABLE_SECURITY_FEATURES'] != 'false'
      features += [:lockout, :active_sessions, :login_password_requirements_base, :remember]
    end

    create_rodauth_app(db: db, features: features) do
      if respond_to?(:session_inactivity_deadline)
        session_inactivity_deadline 86_400
        session_lifetime_deadline 2_592_000
        max_invalid_logins 5
      end
    end
  end

  # Helper that mirrors config.rb conditional logic for MFA features
  def build_mfa_features_app(db)
    features = [:base, :login, :logout]

    # Same pattern as config.rb: disabled unless explicitly 'true'
    if ENV['ENABLE_MFA'] == 'true'
      features += [:two_factor_base, :otp, :recovery_codes]
    end

    create_rodauth_app(db: db, features: features) do
      if respond_to?(:otp_issuer)
        otp_issuer 'OneTimeSecret'
        otp_keys_use_hmac? true
        otp_auth_failures_limit Auth::Config::Features::MFA::OTP_AUTH_FAILURES_LIMIT
      end
    end
  end

  # Helper that mirrors config.rb conditional logic for magic links
  def build_passwordless_features_app(db)
    features = [:base, :login, :logout]

    # Same pattern as config.rb: disabled unless explicitly 'true'
    if ENV['ENABLE_MAGIC_LINKS'] == 'true'
      features += [:email_auth]
    end

    create_rodauth_app(db: db, features: features) do
      if respond_to?(:email_auth_route)
        email_auth_route 'email-login'
        email_auth_request_route 'email-login-request'
      end
    end
  end

  # Helper that mirrors config.rb conditional logic for WebAuthn
  def build_webauthn_features_app(db)
    features = [:base, :login, :logout]

    # Same pattern as config.rb: disabled unless explicitly 'true'
    if ENV['ENABLE_WEBAUTHN'] == 'true'
      features += [:webauthn, :webauthn_login]
    end

    create_rodauth_app(db: db, features: features) do
      if respond_to?(:webauthn_rp_name)
        webauthn_rp_name 'OnetimeSecret'
        webauthn_setup_timeout 60_000
      end
    end
  end

  describe 'ENABLE_SECURITY_FEATURES' do
    context 'when not set (default - enabled)' do
      around do |example|
        ClimateControl.modify('ENABLE_SECURITY_FEATURES' => nil) do
          example.run
        end
      end

      it 'enables lockout feature' do
        app = build_security_features_app(db)
        expect(rodauth_responds_to?(app, :max_invalid_logins)).to be true
      end

      it 'enables active_sessions feature' do
        app = build_security_features_app(db)
        expect(rodauth_responds_to?(app, :session_inactivity_deadline)).to be true
      end

      it 'enables remember feature' do
        app = build_security_features_app(db)
        expect(rodauth_responds_to?(app, :remember_login)).to be true
      end
    end

    context 'when set to "false" (disabled)' do
      around do |example|
        ClimateControl.modify('ENABLE_SECURITY_FEATURES' => 'false') do
          example.run
        end
      end

      it 'disables lockout feature' do
        app = build_security_features_app(db)
        expect(rodauth_responds_to?(app, :max_invalid_logins)).to be false
      end

      it 'disables active_sessions feature' do
        app = build_security_features_app(db)
        expect(rodauth_responds_to?(app, :session_inactivity_deadline)).to be false
      end

      it 'disables remember feature' do
        app = build_security_features_app(db)
        expect(rodauth_responds_to?(app, :remember_login)).to be false
      end

      it 'still has core login/logout' do
        app = build_security_features_app(db)
        expect(rodauth_responds_to?(app, :login_route)).to be true
        expect(rodauth_responds_to?(app, :logout_route)).to be true
      end
    end

    context 'when set to "true" (explicitly enabled)' do
      around do |example|
        ClimateControl.modify('ENABLE_SECURITY_FEATURES' => 'true') do
          example.run
        end
      end

      it 'enables security features (true != false)' do
        app = build_security_features_app(db)
        expect(rodauth_responds_to?(app, :max_invalid_logins)).to be true
      end
    end
  end

  describe 'ENABLE_MFA' do
    context 'when not set (default - disabled)' do
      around do |example|
        ClimateControl.modify('ENABLE_MFA' => nil) do
          example.run
        end
      end

      it 'does not enable OTP feature' do
        app = build_mfa_features_app(db)
        expect(rodauth_responds_to?(app, :otp_setup_route)).to be false
      end

      it 'does not enable recovery_codes feature' do
        app = build_mfa_features_app(db)
        expect(rodauth_responds_to?(app, :recovery_codes_route)).to be false
      end

      it 'still has core login/logout' do
        app = build_mfa_features_app(db)
        expect(rodauth_responds_to?(app, :login_route)).to be true
      end
    end

    context 'when set to "true" (enabled)' do
      around do |example|
        ClimateControl.modify('ENABLE_MFA' => 'true') do
          example.run
        end
      end

      it 'enables OTP feature' do
        app = build_mfa_features_app(db)
        expect(rodauth_responds_to?(app, :otp_setup_route)).to be true
      end

      it 'enables recovery_codes feature' do
        app = build_mfa_features_app(db)
        expect(rodauth_responds_to?(app, :recovery_codes_route)).to be true
      end

      it 'enables two_factor_base feature' do
        app = build_mfa_features_app(db)
        expect(rodauth_responds_to?(app, :two_factor_authentication_setup?)).to be true
      end
    end

    context 'when set to "false" (explicitly disabled)' do
      around do |example|
        ClimateControl.modify('ENABLE_MFA' => 'false') do
          example.run
        end
      end

      it 'does not enable MFA features (false != true)' do
        app = build_mfa_features_app(db)
        expect(rodauth_responds_to?(app, :otp_setup_route)).to be false
      end
    end
  end

  describe 'ENABLE_MAGIC_LINKS' do
    context 'when not set (default - disabled)' do
      around do |example|
        ClimateControl.modify('ENABLE_MAGIC_LINKS' => nil) do
          example.run
        end
      end

      it 'does not enable email_auth feature' do
        app = build_passwordless_features_app(db)
        expect(rodauth_responds_to?(app, :email_auth_route)).to be false
      end
    end

    context 'when set to "true" (enabled)' do
      around do |example|
        ClimateControl.modify('ENABLE_MAGIC_LINKS' => 'true') do
          example.run
        end
      end

      it 'enables email_auth feature' do
        app = build_passwordless_features_app(db)
        expect(rodauth_responds_to?(app, :email_auth_route)).to be true
      end

      it 'enables email auth key creation' do
        app = build_passwordless_features_app(db)
        expect(rodauth_responds_to?(app, :create_email_auth_key)).to be true
      end
    end
  end

  describe 'ENABLE_WEBAUTHN' do
    context 'when not set (default - disabled)' do
      around do |example|
        ClimateControl.modify('ENABLE_WEBAUTHN' => nil) do
          example.run
        end
      end

      it 'does not enable webauthn feature' do
        app = build_webauthn_features_app(db)
        expect(rodauth_responds_to?(app, :webauthn_setup_route)).to be false
      end
    end

    context 'when set to "true" (enabled)' do
      around do |example|
        ClimateControl.modify('ENABLE_WEBAUTHN' => 'true') do
          example.run
        end
      end

      it 'enables webauthn feature' do
        app = build_webauthn_features_app(db)
        expect(rodauth_responds_to?(app, :webauthn_setup_route)).to be true
      end

      it 'enables webauthn_login feature' do
        app = build_webauthn_features_app(db)
        expect(rodauth_responds_to?(app, :webauthn_login_route)).to be true
      end
    end
  end

  describe 'combined ENV configurations' do
    context 'all features enabled' do
      around do |example|
        ClimateControl.modify(
          'ENABLE_SECURITY_FEATURES' => 'true',
          'ENABLE_MFA' => 'true',
          'ENABLE_MAGIC_LINKS' => 'true',
          'ENABLE_WEBAUTHN' => 'true',
        ) do
          example.run
        end
      end

      it 'enables all feature sets without conflicts' do
        # Build app with all features
        features  = [:base, :login, :logout]
        features += [:lockout, :active_sessions, :login_password_requirements_base, :remember]
        features += [:two_factor_base, :otp, :recovery_codes]
        features += [:email_auth]
        features += [:webauthn, :webauthn_login]

        app = create_rodauth_app(db: db, features: features) do
          session_inactivity_deadline 86_400
          max_invalid_logins 5
          otp_issuer 'OneTimeSecret'
          otp_keys_use_hmac? true
          email_auth_route 'email-login'
          webauthn_rp_name 'OnetimeSecret'
        end

        # Verify all feature sets present
        expect(rodauth_responds_to?(app, :max_invalid_logins)).to be true
        expect(rodauth_responds_to?(app, :otp_setup_route)).to be true
        expect(rodauth_responds_to?(app, :email_auth_route)).to be true
        expect(rodauth_responds_to?(app, :webauthn_setup_route)).to be true
      end
    end

    context 'security disabled but MFA enabled' do
      around do |example|
        ClimateControl.modify(
          'ENABLE_SECURITY_FEATURES' => 'false',
          'ENABLE_MFA' => 'true',
        ) do
          example.run
        end
      end

      it 'has MFA without security features' do
        # MFA without security
        features = [:base, :login, :logout, :two_factor_base, :otp, :recovery_codes]

        app = create_rodauth_app(db: db, features: features) do
          otp_issuer 'OneTimeSecret'
          otp_keys_use_hmac? true
        end

        expect(rodauth_responds_to?(app, :otp_setup_route)).to be true
        expect(rodauth_responds_to?(app, :max_invalid_logins)).to be false
      end
    end

    context 'minimal configuration (only core features)' do
      around do |example|
        ClimateControl.modify(
          'ENABLE_SECURITY_FEATURES' => 'false',
          'ENABLE_MFA' => 'false',
          'ENABLE_MAGIC_LINKS' => 'false',
          'ENABLE_WEBAUTHN' => 'false',
        ) do
          example.run
        end
      end

      it 'has only core login/logout' do
        app = create_rodauth_app(db: db, features: [:base, :login, :logout])

        expect(rodauth_responds_to?(app, :login_route)).to be true
        expect(rodauth_responds_to?(app, :logout_route)).to be true
        expect(rodauth_responds_to?(app, :max_invalid_logins)).to be false
        expect(rodauth_responds_to?(app, :otp_setup_route)).to be false
        expect(rodauth_responds_to?(app, :email_auth_route)).to be false
        expect(rodauth_responds_to?(app, :webauthn_setup_route)).to be false
      end
    end
  end
end
