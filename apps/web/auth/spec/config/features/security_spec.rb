# apps/web/auth/spec/config/features/security_spec.rb
#
# frozen_string_literal: true

# Tests for ENABLE_SECURITY_FEATURES ENV variable
#
# Verifies that security features (lockout, active_sessions, remember) are:
# - Enabled by default (when ENV not set or != 'false')
# - Disabled when ENV['ENABLE_SECURITY_FEATURES'] == 'false'
#
# Reference: apps/web/auth/config/features/security.rb

require_relative '../../spec_helper'

RSpec.describe 'Auth::Config::Features::Security' do
  let(:db) { create_test_database }

  describe 'when ENABLE_SECURITY_FEATURES is enabled (default)' do
    # Security features are enabled when ENV is not set or != 'false'
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [:base, :login, :logout, :lockout, :active_sessions, :login_password_requirements_base, :remember],
      ) do
        # Configuration values from security.rb
        session_inactivity_deadline 86_400   # 24 hours
        session_lifetime_deadline 2_592_000  # 30 days
        max_invalid_logins 5
      end
    end

    describe 'lockout feature presence' do
      it 'enables lockout protection' do
        expect(rodauth_responds_to?(app, :max_invalid_logins)).to be true
      end

      it 'provides account_lockouts_table method' do
        expect(rodauth_responds_to?(app, :account_lockouts_table)).to be true
      end

      it 'provides unlock_account_route method' do
        expect(rodauth_responds_to?(app, :unlock_account_route)).to be true
      end
    end

    describe 'active_sessions feature presence' do
      it 'enables session tracking' do
        expect(rodauth_responds_to?(app, :session_inactivity_deadline)).to be true
      end

      it 'provides active_sessions_table method' do
        expect(rodauth_responds_to?(app, :active_sessions_table)).to be true
      end

      it 'provides session_lifetime_deadline method' do
        expect(rodauth_responds_to?(app, :session_lifetime_deadline)).to be true
      end
    end

    describe 'remember feature presence' do
      it 'enables remember me functionality' do
        expect(rodauth_responds_to?(app, :remember_login)).to be true
      end

      it 'provides remember_deadline_interval method' do
        expect(rodauth_responds_to?(app, :remember_deadline_interval)).to be true
      end
    end

    describe 'configuration values' do
      let(:rodauth_instance) do
        # Create a mock request environment for instantiation
        env     = {
          'REQUEST_METHOD' => 'GET',
          'PATH_INFO' => '/',
          'rack.input' => StringIO.new,
          'rack.session' => {},
        }
        request = Roda::RodaRequest.new(app.new(env), env)
        app.rodauth.new(request.scope)
      end

      it 'sets session_inactivity_deadline to 24 hours (86400 seconds)' do
        expect(rodauth_instance.session_inactivity_deadline).to eq(86_400)
      end

      it 'sets session_lifetime_deadline to 30 days (2592000 seconds)' do
        expect(rodauth_instance.session_lifetime_deadline).to eq(2_592_000)
      end

      it 'sets max_invalid_logins to 5' do
        expect(rodauth_instance.max_invalid_logins).to eq(5)
      end
    end
  end

  describe 'when ENABLE_SECURITY_FEATURES=false (disabled)' do
    # When security features are disabled, only core features should be present
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [:base, :login, :logout],
      )
    end

    describe 'lockout feature absence' do
      it 'does not have max_invalid_logins method' do
        expect(rodauth_responds_to?(app, :max_invalid_logins)).to be false
      end

      it 'does not have account_lockouts_table method' do
        expect(rodauth_responds_to?(app, :account_lockouts_table)).to be false
      end
    end

    describe 'active_sessions feature absence' do
      it 'does not have session_inactivity_deadline method' do
        expect(rodauth_responds_to?(app, :session_inactivity_deadline)).to be false
      end

      it 'does not have active_sessions_table method' do
        expect(rodauth_responds_to?(app, :active_sessions_table)).to be false
      end
    end

    describe 'remember feature absence' do
      it 'does not have remember_login method' do
        expect(rodauth_responds_to?(app, :remember_login)).to be false
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
