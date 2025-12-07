# spec/integration/authentication/full_mode/env_toggles/mfa_enabled_spec.rb
#
# frozen_string_literal: true

# Tests for MFA (Multi-Factor Authentication) toggle via ENABLE_MFA env var.
# When enabled, OTP and recovery code routes become available.

require 'spec_helper'
require 'rack/test'
require 'climate_control'

RSpec.describe 'MFA Toggle', :full_auth_mode do
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
    # Enable MFA for these tests
    ENV['ENABLE_MFA'] = 'true'
    require 'onetime'
    require 'onetime/config'
    Onetime.boot! :test
    require 'onetime/auth_config'
    require 'onetime/middleware'
    require 'onetime/application/registry'
    Onetime::Application::Registry.reset!
    Onetime::Application::Registry.prepare_application_registry
    require 'auth/config'
  end

  after(:all) do
    ENV.delete('ENABLE_MFA')
  end

  describe 'configuration' do
    it 'has MFA ENV set to true' do
      expect(ENV['ENABLE_MFA']).to eq('true')
    end

    it 'mounts Auth app' do
      expect(Onetime::Application::Registry.mount_mappings).to have_key('/auth')
    end
  end

  describe 'Auth::Config MFA features' do
    it 'has OTP setup route method' do
      has_method = Auth::Config.method_defined?(:otp_setup_route) ||
                   Auth::Config.private_method_defined?(:otp_setup_route)
      expect(has_method).to be true
    end

    it 'has recovery codes route method' do
      has_method = Auth::Config.method_defined?(:recovery_codes_route) ||
                   Auth::Config.private_method_defined?(:recovery_codes_route)
      expect(has_method).to be true
    end

    it 'has two_factor_authentication_setup? method' do
      has_method = Auth::Config.method_defined?(:two_factor_authentication_setup?) ||
                   Auth::Config.private_method_defined?(:two_factor_authentication_setup?)
      expect(has_method).to be true
    end
  end

  describe 'GET /auth/otp-setup' do
    before { get '/auth/otp-setup' }

    it 'returns valid HTTP status' do
      # 200=success, 302=redirect, 400=bad request, 401/403=auth required
      expect([200, 302, 400, 401, 403]).to include(last_response.status)
    end

    it 'returns valid content type or redirect' do
      content_type = last_response.headers['Content-Type']
      is_json = content_type&.include?('application/json')
      is_html = content_type&.include?('text/html')
      is_redirect = last_response.status == 302
      expect(is_json || is_html || is_redirect).to be true
    end
  end

  describe 'POST /auth/otp-auth' do
    let(:otp_data) { { otp_code: '123456' }.to_json }
    let(:json_headers) { { 'CONTENT_TYPE' => 'application/json' } }

    it 'returns valid HTTP status (route exists)' do
      post '/auth/otp-auth', otp_data, json_headers
      expect([200, 400, 401, 403, 422]).to include(last_response.status)
    end
  end

  describe 'GET /auth/recovery-codes' do
    it 'returns valid HTTP status (route exists)' do
      get '/auth/recovery-codes'
      # 200=success, 302=redirect, 400=bad request, 401/403=auth required
      expect([200, 302, 400, 401, 403]).to include(last_response.status)
    end
  end

  describe 'POST /auth/recovery-auth' do
    let(:recovery_data) { { recovery_code: 'abc12345' }.to_json }
    let(:json_headers) { { 'CONTENT_TYPE' => 'application/json' } }

    it 'returns valid HTTP status (route exists)' do
      post '/auth/recovery-auth', recovery_data, json_headers
      expect([200, 400, 401, 403, 422]).to include(last_response.status)
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
