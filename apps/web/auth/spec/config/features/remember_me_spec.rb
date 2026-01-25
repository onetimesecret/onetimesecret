# apps/web/auth/spec/config/features/remember_me_spec.rb
#
# frozen_string_literal: true

# Tests for AUTH_REMEMBER_ME_ENABLED ENV variable
#
# Verifies that remember me feature is:
# - Enabled by default (when ENV not set or != 'false')
# - Disabled when ENV['AUTH_REMEMBER_ME_ENABLED'] == 'false'
#
# Reference: apps/web/auth/config/features/remember_me.rb

require_relative '../../spec_helper'

RSpec.describe 'Auth::Config::Features::RememberMe' do
  let(:db) { create_test_database }

  describe 'when AUTH_REMEMBER_ME_ENABLED is enabled (default)' do
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [:base, :login, :logout, :remember],
      )
    end

    describe 'remember feature presence' do
      it 'enables remember me functionality' do
        expect(rodauth_responds_to?(app, :remember_login)).to be true
      end

      it 'provides remember_deadline_interval method' do
        expect(rodauth_responds_to?(app, :remember_deadline_interval)).to be true
      end

      it 'provides remember_cookie_key method' do
        expect(rodauth_responds_to?(app, :remember_cookie_key)).to be true
      end
    end
  end

  describe 'when AUTH_REMEMBER_ME_ENABLED=false (disabled)' do
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [:base, :login, :logout],
      )
    end

    describe 'remember feature absence' do
      it 'does not have remember_login method' do
        expect(rodauth_responds_to?(app, :remember_login)).to be false
      end

      it 'does not have remember_deadline_interval method' do
        expect(rodauth_responds_to?(app, :remember_deadline_interval)).to be false
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
