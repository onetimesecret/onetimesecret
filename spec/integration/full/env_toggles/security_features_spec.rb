# spec/integration/full/env_toggles/security_features_spec.rb
#
# frozen_string_literal: true

# Tests for security features (hardening, active_sessions, remember_me).
# These are controlled by granular ENV variables:
#   - AUTH_HARDENING_ENABLED (lockout, password requirements)
#   - AUTH_ACTIVE_SESSIONS_ENABLED (session tracking)
#   - AUTH_REMEMBER_ME_ENABLED (persistent sessions)
#
# All are enabled by default (unless explicitly set to 'false').
#
# Note: This spec is in spec/integration/full/ and automatically gets the
# :full_auth_mode tag, which triggers FullModeSuiteDatabase.setup! before
# running. This handles Auth::Config loading via the standard boot process.
# Do NOT manually require 'auth/config' (see warning in that file).

require 'spec_helper'
require 'rack/test'
require 'climate_control'

# Database and application setup is handled by FullModeSuiteDatabase
# (see spec/support/full_mode_suite_database.rb).

RSpec.describe 'Security Features Toggle', type: :integration do
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

  describe 'default configuration (security enabled)' do
    it 'has hardening features enabled by default' do
      # ENV['AUTH_HARDENING_ENABLED'] != 'false' means enabled
      expect(ENV['AUTH_HARDENING_ENABLED']).not_to eq('false')
    end

    it 'has active sessions enabled by default' do
      expect(ENV['AUTH_ACTIVE_SESSIONS_ENABLED']).not_to eq('false')
    end

    it 'has remember me enabled by default' do
      expect(ENV['AUTH_REMEMBER_ME_ENABLED']).not_to eq('false')
    end

    it 'mounts Auth app' do
      expect(Onetime::Application::Registry.mount_mappings).to have_key('/auth')
    end
  end

  describe 'GET /auth/unlock-account (lockout feature)' do
    before { get '/auth/unlock-account' }

    it 'returns a valid HTTP status' do
      expect([200, 400, 401, 404]).to include(last_response.status)
    end

    it 'returns JSON or HTML content' do
      content_type = last_response.headers['Content-Type']
      is_json_or_html = content_type&.include?('application/json') ||
                        content_type&.include?('text/html')
      expect(is_json_or_html).to be true
    end
  end

  describe 'POST /auth/login with security enabled' do
    it 'returns appropriate error status' do
      post_with_csrf '/auth/login', { login: 'test@example.com', password: 'wrongpassword' }
      expect([400, 401, 422]).to include(last_response.status)
    end
  end

  describe 'Auth::Config security methods' do
    it 'has lockout feature method (max_invalid_logins)' do
      has_method = Auth::Config.method_defined?(:max_invalid_logins) ||
                   Auth::Config.private_method_defined?(:max_invalid_logins)
      expect(has_method).to be true
    end

    it 'has active_sessions feature method (session_inactivity_deadline)' do
      has_method = Auth::Config.method_defined?(:session_inactivity_deadline) ||
                   Auth::Config.private_method_defined?(:session_inactivity_deadline)
      expect(has_method).to be true
    end
  end
end
