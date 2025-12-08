# spec/integration/authentication/full_mode/env_toggles/magic_links_enabled_spec.rb
#
# frozen_string_literal: true

# Tests for magic links (passwordless login) toggle via ENABLE_MAGIC_LINKS env var.
# When enabled, email-based authentication routes become available.

require 'spec_helper'
require 'rack/test'
require 'climate_control'

# Database and application setup is handled by FullModeSuiteDatabase
# (see spec/support/full_mode_suite_database.rb).

RSpec.describe 'Magic Links Toggle', :full_auth_mode do
  include Rack::Test::Methods

  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  def json_response
    JSON.parse(last_response.body)
  rescue JSON::ParserError
    {}
  end

  before(:all) do
    # Enable magic links for these tests
    ENV['ENABLE_MAGIC_LINKS'] = 'true'
    require 'auth/config'
  end

  after(:all) do
    ENV.delete('ENABLE_MAGIC_LINKS')
  end

  describe 'configuration' do
    it 'has magic links ENV set to true' do
      expect(ENV['ENABLE_MAGIC_LINKS']).to eq('true')
    end

    it 'mounts Auth app' do
      expect(Onetime::Application::Registry.mount_mappings).to have_key('/auth')
    end
  end

  describe 'Auth::Config email_auth feature' do
    it 'has email_auth_route method' do
      has_method = Auth::Config.method_defined?(:email_auth_route) ||
                   Auth::Config.private_method_defined?(:email_auth_route)
      expect(has_method).to be true
    end

    it 'has create_email_auth_key method' do
      has_method = Auth::Config.method_defined?(:create_email_auth_key) ||
                   Auth::Config.private_method_defined?(:create_email_auth_key)
      expect(has_method).to be true
    end
  end

  describe 'POST /auth/email-login-request' do
    let(:email_data) { { login: 'test@example.com' }.to_json }
    let(:json_headers) { { 'CONTENT_TYPE' => 'application/json' } }

    before { post '/auth/email-login-request', email_data, json_headers }

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

  describe 'POST /auth/login (standard login still works)' do
    let(:credentials) { { login: 'test@example.com', password: 'wrongpassword' }.to_json }
    let(:json_headers) { { 'CONTENT_TYPE' => 'application/json' } }

    it 'returns appropriate error for invalid credentials' do
      post '/auth/login', credentials, json_headers
      expect([400, 401, 422]).to include(last_response.status)
    end
  end
end
