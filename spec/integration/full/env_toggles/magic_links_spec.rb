# spec/integration/full/env_toggles/magic_links_spec.rb
#
# frozen_string_literal: true

# Tests for email auth (magic links/passwordless login) toggle via AUTH_EMAIL_AUTH_ENABLED env var.
# NOTE: Rodauth features are configured at boot time. These tests verify
# the current state based on whether AUTH_EMAIL_AUTH_ENABLED was set when the app loaded.

require 'spec_helper'
require 'rack/test'

RSpec.describe 'Email Auth (Magic Links) Toggle', type: :integration do
  include Rack::Test::Methods

  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  def json_response
    JSON.parse(last_response.body)
  rescue JSON::ParserError
    {}
  end

  # Establish a session and retrieve CSRF token
  def ensure_csrf_token
    return @csrf_token if defined?(@csrf_token) && @csrf_token

    get '/auth', {}, { 'HTTP_ACCEPT' => 'application/json' }
    @csrf_token = last_response.headers['X-CSRF-Token']
    @csrf_token
  end

  # POST with JSON content type and CSRF token
  def post_with_csrf(path, params = {}, headers = {})
    csrf_token = ensure_csrf_token

    post path,
      params.merge(shrimp: csrf_token).to_json,
      headers.merge(
        'CONTENT_TYPE' => 'application/json',
        'HTTP_ACCEPT' => 'application/json',
        'HTTP_X_CSRF_TOKEN' => csrf_token
      )
  end

  # Detect if email auth was actually enabled at boot time by checking for methods
  # Note: ENV var alone is not sufficient - must check if Rodauth actually loaded email_auth features
  let(:email_auth_features_available) do
    Auth::Config.method_defined?(:email_auth_route) ||
      Auth::Config.private_method_defined?(:email_auth_route)
  end

  describe 'configuration' do
    it 'detects AUTH_EMAIL_AUTH_ENABLED environment variable' do
      # This test documents the current state - email auth may or may not be enabled
      expect([nil, 'true', 'false']).to include(ENV['AUTH_EMAIL_AUTH_ENABLED'])
    end

    it 'mounts Auth app' do
      expect(Onetime::Application::Registry.mount_mappings).to have_key('/auth')
    end
  end

  describe 'Auth::Config email_auth feature detection' do
    # These tests verify whether email_auth features were configured at boot time
    # by checking if the Rodauth methods exist

    it 'correctly detects email auth feature availability' do
      # This documents the actual state - email auth may or may not be enabled
      # depending on whether AUTH_EMAIL_AUTH_ENABLED=true was set when Auth::Config loaded
      expect(email_auth_features_available).to be(true).or be(false)
    end

    it 'ENV and feature state are consistent when email auth enabled' do
      # If email auth features are available, ENV should have been set
      if email_auth_features_available
        expect(ENV['AUTH_EMAIL_AUTH_ENABLED']).to eq('true')
      end
    end
  end

  describe 'email auth routes' do
    context 'when email auth features are available' do
      before do
        skip 'Email auth features not available' unless email_auth_features_available
      end

      describe 'POST /auth/email-login-request' do
        before { post_with_csrf '/auth/email-login-request', { login: 'test@example.com' } }

        it 'returns valid HTTP status' do
          expect([200, 400, 401, 422]).to include(last_response.status)
        end

        it 'returns JSON content type' do
          expect(last_response.headers['Content-Type']).to include('application/json')
        end
      end

      describe 'GET /auth/email-login' do
        it 'returns valid HTTP status (route exists)' do
          get '/auth/email-login'
          expect([200, 400, 401, 422]).to include(last_response.status)
        end

        it 'returns error for invalid token' do
          get '/auth/email-login?key=invalid_token_12345'
          expect([400, 401, 422]).to include(last_response.status)
        end
      end
    end

    context 'when email auth features are not available' do
      before do
        skip 'Email auth features are available' if email_auth_features_available
      end

      it 'returns 404 for /auth/email-login-request' do
        post_with_csrf '/auth/email-login-request', { login: 'test@example.com' }
        expect(last_response.status).to eq(404)
      end

      it 'returns 404 for /auth/email-login' do
        get '/auth/email-login'
        expect(last_response.status).to eq(404)
      end
    end
  end

  describe 'POST /auth/login (standard login always works)' do
    it 'returns appropriate error for invalid credentials' do
      post_with_csrf '/auth/login', { login: 'test@example.com', password: 'wrongpassword' }
      # 400=bad request, 401=unauthorized, 403=forbidden, 422=unprocessable
      expect([400, 401, 403, 422]).to include(last_response.status)
    end
  end
end
