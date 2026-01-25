# apps/web/auth/spec/config/features/hardening_spec.rb
#
# frozen_string_literal: true

# Tests for AUTH_HARDENING_ENABLED ENV variable
#
# Verifies that hardening features (lockout, password_requirements) are:
# - Enabled by default (when ENV not set or != 'false')
# - Disabled when ENV['AUTH_HARDENING_ENABLED'] == 'false'
#
# Reference: apps/web/auth/config/features/hardening.rb

require_relative '../../spec_helper'

RSpec.describe 'Auth::Config::Features::Hardening' do
  let(:db) { create_test_database }

  describe 'when AUTH_HARDENING_ENABLED is enabled (default)' do
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [:base, :login, :logout, :lockout, :login_password_requirements_base],
      ) do
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

    describe 'password_requirements feature presence' do
      it 'enables password validation' do
        expect(rodauth_responds_to?(app, :password_meets_requirements?)).to be true
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

      it 'sets max_invalid_logins to 5' do
        expect(rodauth_instance.max_invalid_logins).to eq(5)
      end
    end
  end

  describe 'when AUTH_HARDENING_ENABLED=false (disabled)' do
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
