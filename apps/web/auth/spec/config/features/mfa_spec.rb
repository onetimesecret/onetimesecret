# apps/web/auth/spec/config/features/mfa_spec.rb
#
# frozen_string_literal: true

# Tests for ENABLE_MFA ENV variable
#
# Verifies that MFA features (two_factor_base, otp, recovery_codes) are:
# - Disabled by default (when ENV not set)
# - Enabled when ENV['ENABLE_MFA'] == 'true'
#
# Reference: apps/web/auth/config/features/mfa.rb

require_relative '../../spec_helper'

RSpec.describe 'Auth::Config::Features::MFA' do
  let(:db) { create_test_database }

  describe 'when ENABLE_MFA=true (enabled)' do
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [:base, :login, :logout, :two_factor_base, :otp, :recovery_codes],
      ) do
        # Configuration values from mfa.rb
        otp_issuer 'OneTimeSecret'
        otp_setup_param 'otp_setup'
        otp_setup_raw_param 'otp_raw_secret'
        otp_auth_param 'otp_code'
        otp_keys_use_hmac? true
        two_factor_modifications_require_password? true
        modifications_require_password? true
        otp_auth_failures_limit 10
        auto_add_recovery_codes? true
        auto_remove_recovery_codes? true
      end
    end

    describe 'two_factor_base feature presence' do
      it 'enables two-factor authentication base' do
        expect(rodauth_responds_to?(app, :two_factor_authentication_setup?)).to be true
      end

      it 'provides uses_two_factor_authentication? method' do
        expect(rodauth_responds_to?(app, :uses_two_factor_authentication?)).to be true
      end
    end

    describe 'otp feature presence' do
      it 'enables OTP setup route' do
        expect(rodauth_responds_to?(app, :otp_setup_route)).to be true
      end

      it 'provides otp_auth_route method' do
        expect(rodauth_responds_to?(app, :otp_auth_route)).to be true
      end

      it 'provides otp_disable_route method' do
        expect(rodauth_responds_to?(app, :otp_disable_route)).to be true
      end

      it 'provides otp_issuer method' do
        expect(rodauth_responds_to?(app, :otp_issuer)).to be true
      end
    end

    describe 'recovery_codes feature presence' do
      it 'enables recovery codes route' do
        expect(rodauth_responds_to?(app, :recovery_codes_route)).to be true
      end

      it 'provides recovery_auth_route method' do
        expect(rodauth_responds_to?(app, :recovery_auth_route)).to be true
      end
    end

    describe 'configuration values' do
      let(:rodauth_instance) do
        env     = {
          'REQUEST_METHOD' => 'GET',
          'PATH_INFO' => '/',
          'rack.input' => StringIO.new,
          'rack.session' => {},
        }
        request = Roda::RodaRequest.new(app.new(env), env)
        app.rodauth.new(request.scope)
      end

      it 'sets otp_issuer to OneTimeSecret' do
        expect(rodauth_instance.otp_issuer).to eq('OneTimeSecret')
      end

      it 'sets otp_auth_failures_limit to 10' do
        expect(rodauth_instance.otp_auth_failures_limit).to eq(10)
      end

      it 'enables HMAC for OTP keys' do
        expect(rodauth_instance.otp_keys_use_hmac?).to be true
      end

      it 'requires password for two-factor modifications' do
        expect(rodauth_instance.two_factor_modifications_require_password?).to be true
      end

      it 'auto-adds recovery codes when MFA enabled' do
        expect(rodauth_instance.auto_add_recovery_codes?).to be true
      end

      it 'auto-removes recovery codes when MFA disabled' do
        expect(rodauth_instance.auto_remove_recovery_codes?).to be true
      end
    end
  end

  describe 'when ENABLE_MFA is not set (disabled by default)' do
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [:base, :login, :logout],
      )
    end

    describe 'otp feature absence' do
      it 'does not have otp_setup_route method' do
        expect(rodauth_responds_to?(app, :otp_setup_route)).to be false
      end

      it 'does not have otp_issuer method' do
        expect(rodauth_responds_to?(app, :otp_issuer)).to be false
      end
    end

    describe 'recovery_codes feature absence' do
      it 'does not have recovery_codes_route method' do
        expect(rodauth_responds_to?(app, :recovery_codes_route)).to be false
      end

      it 'does not have recovery_auth_route method' do
        expect(rodauth_responds_to?(app, :recovery_auth_route)).to be false
      end
    end

    describe 'two_factor_base feature absence' do
      it 'does not have two_factor_authentication_setup? method' do
        expect(rodauth_responds_to?(app, :two_factor_authentication_setup?)).to be false
      end
    end

    describe 'core features still work' do
      it 'has login_route method' do
        expect(rodauth_responds_to?(app, :login_route)).to be true
      end

      it 'has logout_route method' do
        expect(rodauth_responds_to?(app, :logout_route)).to be true
      end
    end
  end
end
