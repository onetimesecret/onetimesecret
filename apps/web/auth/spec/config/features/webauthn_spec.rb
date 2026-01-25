# apps/web/auth/spec/config/features/webauthn_spec.rb
#
# frozen_string_literal: true

# Tests for AUTH_WEBAUTHN_ENABLED ENV variable
#
# Verifies that WebAuthn features (webauthn, webauthn_login, webauthn_modify_email) are:
# - Disabled by default (when ENV not set)
# - Enabled when ENV['AUTH_WEBAUTHN_ENABLED'] == 'true'
#
# Reference: apps/web/auth/config/features/webauthn.rb

require_relative '../../spec_helper'

RSpec.describe 'Auth::Config::Features::WebAuthn' do
  let(:db) { create_test_database }

  describe 'when AUTH_WEBAUTHN_ENABLED=true (enabled)' do
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [:base, :login, :logout, :webauthn, :webauthn_login, :webauthn_modify_email],
      ) do
        # Configuration values from webauthn.rb
        webauthn_rp_name 'OnetimeSecret'
        webauthn_setup_timeout 60_000     # 60 seconds
        webauthn_auth_timeout 60_000      # 60 seconds
        webauthn_user_verification 'preferred'
        webauthn_setup_route 'webauthn-setup'
        webauthn_auth_route 'webauthn-auth'
        webauthn_remove_route 'webauthn-remove'

        # Flash messages for JSON responses
        webauthn_setup_error_flash 'Error setting up biometric/security key'
        webauthn_auth_error_flash 'Biometric/security key authentication failed'
        webauthn_invalid_remove_param_message 'Invalid security key credential'
        webauthn_invalid_auth_param_message 'Invalid authentication data'
        webauthn_invalid_setup_param_message 'Invalid registration data'
      end
    end

    describe 'webauthn feature presence' do
      it 'enables WebAuthn setup route' do
        expect(rodauth_responds_to?(app, :webauthn_setup_route)).to be true
      end

      it 'provides webauthn_remove_route method' do
        expect(rodauth_responds_to?(app, :webauthn_remove_route)).to be true
      end

      it 'provides webauthn_rp_name method' do
        expect(rodauth_responds_to?(app, :webauthn_rp_name)).to be true
      end

      it 'provides webauthn_setup_timeout method' do
        expect(rodauth_responds_to?(app, :webauthn_setup_timeout)).to be true
      end
    end

    describe 'webauthn_login feature presence' do
      it 'enables WebAuthn login route' do
        expect(rodauth_responds_to?(app, :webauthn_login_route)).to be true
      end

      it 'provides webauthn_auth_route method' do
        expect(rodauth_responds_to?(app, :webauthn_auth_route)).to be true
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

      it 'sets webauthn_rp_name to OnetimeSecret' do
        expect(rodauth_instance.webauthn_rp_name).to eq('OnetimeSecret')
      end

      it 'sets webauthn_setup_timeout to 60 seconds (60000 ms)' do
        expect(rodauth_instance.webauthn_setup_timeout).to eq(60_000)
      end

      it 'sets webauthn_auth_timeout to 60 seconds (60000 ms)' do
        expect(rodauth_instance.webauthn_auth_timeout).to eq(60_000)
      end

      it 'sets webauthn_user_verification to preferred' do
        expect(rodauth_instance.webauthn_user_verification).to eq('preferred')
      end

      it 'sets webauthn_setup_route to webauthn-setup' do
        expect(rodauth_instance.webauthn_setup_route).to eq('webauthn-setup')
      end

      it 'sets webauthn_auth_route to webauthn-auth' do
        expect(rodauth_instance.webauthn_auth_route).to eq('webauthn-auth')
      end

      it 'sets webauthn_remove_route to webauthn-remove' do
        expect(rodauth_instance.webauthn_remove_route).to eq('webauthn-remove')
      end
    end
  end

  describe 'when AUTH_WEBAUTHN_ENABLED is not set (disabled by default)' do
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [:base, :login, :logout],
      )
    end

    describe 'webauthn feature absence' do
      it 'does not have webauthn_setup_route method' do
        expect(rodauth_responds_to?(app, :webauthn_setup_route)).to be false
      end

      it 'does not have webauthn_rp_name method' do
        expect(rodauth_responds_to?(app, :webauthn_rp_name)).to be false
      end
    end

    describe 'webauthn_login feature absence' do
      it 'does not have webauthn_login_route method' do
        expect(rodauth_responds_to?(app, :webauthn_login_route)).to be false
      end

      it 'does not have webauthn_auth_route method' do
        expect(rodauth_responds_to?(app, :webauthn_auth_route)).to be false
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
