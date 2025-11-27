# apps/web/auth/spec/config/features/passwordless_spec.rb
#
# frozen_string_literal: true

# Tests for ENABLE_MAGIC_LINKS ENV variable
#
# Verifies that passwordless/magic link features (email_auth) are:
# - Disabled by default (when ENV not set)
# - Enabled when ENV['ENABLE_MAGIC_LINKS'] == 'true'
#
# Reference: apps/web/auth/config/features/passwordless.rb

require_relative '../../spec_helper'

RSpec.describe 'Auth::Config::Features::Passwordless' do
  let(:db) { create_test_database }

  describe 'when ENABLE_MAGIC_LINKS=true (enabled)' do
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [:base, :login, :logout, :email_auth]
      ) do
        # Configuration values from passwordless.rb
        email_auth_deadline_interval(15 * 60)        # 15 minutes
        email_auth_skip_resend_email_within 30       # 30 seconds
        email_auth_route 'email-login'
        email_auth_request_route 'email-login-request'
        email_auth_session_key 'email_auth_key'
        email_auth_email_subject 'Login Link'

        # Flash messages for JSON responses
        email_auth_request_error_flash 'Error requesting login link'
        email_auth_email_sent_notice_flash 'Login link sent to your email'
        email_auth_email_recently_sent_error_flash 'Login link was recently sent, please check your email'
        email_auth_error_flash 'Login link has expired or is invalid'
      end
    end

    describe 'email_auth feature presence' do
      it 'enables email auth route' do
        expect(rodauth_responds_to?(app, :email_auth_route)).to be true
      end

      it 'provides email_auth_request_route method' do
        expect(rodauth_responds_to?(app, :email_auth_request_route)).to be true
      end

      it 'provides create_email_auth_key method' do
        expect(rodauth_responds_to?(app, :create_email_auth_key)).to be true
      end

      it 'provides email_auth_email_link method' do
        expect(rodauth_responds_to?(app, :email_auth_email_link)).to be true
      end

      it 'provides email_auth_deadline_interval method' do
        expect(rodauth_responds_to?(app, :email_auth_deadline_interval)).to be true
      end
    end

    describe 'configuration values' do
      let(:rodauth_instance) do
        env = {
          'REQUEST_METHOD' => 'GET',
          'PATH_INFO' => '/',
          'rack.input' => StringIO.new,
          'rack.session' => {}
        }
        request = Roda::RodaRequest.new(app.new(env), env)
        app.rodauth.new(request.scope)
      end

      it 'sets email_auth_route to email-login' do
        expect(rodauth_instance.email_auth_route).to eq('email-login')
      end

      it 'sets email_auth_request_route to email-login-request' do
        expect(rodauth_instance.email_auth_request_route).to eq('email-login-request')
      end

      it 'sets email_auth_deadline_interval to 15 minutes (900 seconds)' do
        expect(rodauth_instance.email_auth_deadline_interval).to eq(900)
      end

      it 'sets email_auth_session_key to email_auth_key' do
        expect(rodauth_instance.email_auth_session_key).to eq('email_auth_key')
      end

      it 'sets email_auth_email_subject to Login Link' do
        expect(rodauth_instance.email_auth_email_subject).to eq('Login Link')
      end
    end
  end

  describe 'when ENABLE_MAGIC_LINKS is not set (disabled by default)' do
    let(:app) do
      create_rodauth_app(
        db: db,
        features: [:base, :login, :logout]
      )
    end

    describe 'email_auth feature absence' do
      it 'does not have email_auth_route method' do
        expect(rodauth_responds_to?(app, :email_auth_route)).to be false
      end

      it 'does not have email_auth_request_route method' do
        expect(rodauth_responds_to?(app, :email_auth_request_route)).to be false
      end

      it 'does not have create_email_auth_key method' do
        expect(rodauth_responds_to?(app, :create_email_auth_key)).to be false
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
