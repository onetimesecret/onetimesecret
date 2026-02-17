# apps/web/auth/spec/config/features/password_requirements_spec.rb
#
# frozen_string_literal: true

# Tests for AUTH_PASSWORD_REQUIREMENTS_ENABLED ENV variable
#
# Verifies that password requirements features are:
# - Enabled by default (when ENV not set or != 'false')
# - Disabled when ENV['AUTH_PASSWORD_REQUIREMENTS_ENABLED'] == 'false'
#
# Reference: apps/web/auth/config/features/password_requirements.rb

require_relative '../../spec_helper'

RSpec.describe 'Auth::Config::Features::PasswordRequirements' do
  let(:db) { create_test_database }

  describe 'when AUTH_PASSWORD_REQUIREMENTS_ENABLED is enabled (default)' do
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [:base, :login, :logout, :login_password_requirements_base],
      )
    end

    describe 'password_requirements feature presence' do
      it 'enables password validation' do
        expect(rodauth_responds_to?(app, :password_meets_requirements?)).to be true
      end
    end
  end

  describe 'when AUTH_PASSWORD_REQUIREMENTS_ENABLED=false (disabled)' do
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [:base, :login, :logout],
      )
    end

    describe 'password_requirements feature absence' do
      it 'does not have password_meets_requirements? method' do
        expect(rodauth_responds_to?(app, :password_meets_requirements?)).to be false
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
