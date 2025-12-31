# spec/integration/authentication/full_mode/env_toggles/security_features_spec.rb
#
# frozen_string_literal: true

# Tests for security features toggle via ENABLE_SECURITY_FEATURES env var.
# When enabled (default), security features like lockout and active sessions
# are available.

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

  # NOTE: Do NOT require 'auth/config' here - it must be loaded AFTER the database
  # stub is in place, which FullModeSuiteDatabase.setup! handles via prepare_application_registry.
  # The :full_auth_mode tag (derived from spec/integration/full/ path) triggers this setup.

  describe 'default configuration (security enabled)' do
    it 'has security features enabled by default' do
      # ENV['ENABLE_SECURITY_FEATURES'] != 'false' means enabled
      expect(ENV['ENABLE_SECURITY_FEATURES']).not_to eq('false')
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
    let(:credentials) { { login: 'test@example.com', password: 'wrongpassword' }.to_json }
    let(:json_headers) { { 'CONTENT_TYPE' => 'application/json' } }

    it 'returns appropriate error status' do
      post '/auth/login', credentials, json_headers
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
