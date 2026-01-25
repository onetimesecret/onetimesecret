# apps/web/auth/spec/config/features/active_sessions_spec.rb
#
# frozen_string_literal: true

# Tests for AUTH_ACTIVE_SESSIONS_ENABLED ENV variable
#
# Verifies that active sessions feature is:
# - Enabled by default (when ENV not set or != 'false')
# - Disabled when ENV['AUTH_ACTIVE_SESSIONS_ENABLED'] == 'false'
#
# Reference: apps/web/auth/config/features/active_sessions.rb

require_relative '../../spec_helper'

RSpec.describe 'Auth::Config::Features::ActiveSessions' do
  let(:db) { create_test_database }

  describe 'when AUTH_ACTIVE_SESSIONS_ENABLED is enabled (default)' do
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [:base, :login, :logout, :active_sessions],
      ) do
        session_inactivity_deadline 86_400   # 24 hours
        session_lifetime_deadline 2_592_000  # 30 days
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

    describe 'configuration values' do
      let(:rodauth_instance) do
        env = {
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
    end
  end

  describe 'when AUTH_ACTIVE_SESSIONS_ENABLED=false (disabled)' do
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [:base, :login, :logout],
      )
    end

    describe 'active_sessions feature absence' do
      it 'does not have session_inactivity_deadline method' do
        expect(rodauth_responds_to?(app, :session_inactivity_deadline)).to be false
      end

      it 'does not have active_sessions_table method' do
        expect(rodauth_responds_to?(app, :active_sessions_table)).to be false
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
