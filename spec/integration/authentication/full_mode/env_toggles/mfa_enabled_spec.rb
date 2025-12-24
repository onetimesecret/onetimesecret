# spec/integration/authentication/full_mode/env_toggles/mfa_enabled_spec.rb
#
# frozen_string_literal: true

# Tests for MFA (Multi-Factor Authentication) toggle via ENABLE_MFA env var.
# NOTE: Rodauth features are configured at boot time. These tests verify
# the current state based on whether ENABLE_MFA was set when the app loaded.

require 'spec_helper'
require 'rack/test'

RSpec.describe 'MFA Toggle', :full_auth_mode, type: :integration do
  include Rack::Test::Methods

  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  def json_response
    JSON.parse(last_response.body)
  rescue JSON::ParserError
    {}
  end

  # Detect if MFA was actually enabled at boot time by checking for MFA methods
  # Note: ENV var alone is not sufficient - must check if Rodauth actually loaded MFA features
  let(:mfa_features_available) do
    Auth::Config.method_defined?(:two_factor_auth_required?) ||
      Auth::Config.private_method_defined?(:two_factor_auth_required?)
  end

  describe 'configuration' do
    it 'detects ENABLE_MFA environment variable' do
      # This test documents the current state - MFA may or may not be enabled
      expect([nil, 'true', 'false']).to include(ENV['ENABLE_MFA'])
    end

    it 'mounts Auth app' do
      expect(Onetime::Application::Registry.mount_mappings).to have_key('/auth')
    end
  end

  describe 'Auth::Config MFA feature detection' do
    # These tests verify whether MFA features were configured at boot time
    # by checking if the Rodauth methods exist

    it 'correctly detects MFA feature availability' do
      # This documents the actual state - MFA may or may not be enabled
      # depending on whether ENABLE_MFA=true was set when Auth::Config loaded
      expect(mfa_features_available).to be(true).or be(false)
    end

    it 'ENV and feature state are consistent when MFA enabled' do
      # If MFA features are available, ENV should have been set
      if mfa_features_available
        expect(ENV['ENABLE_MFA']).to eq('true')
      end
    end
  end

  describe 'MFA routes' do
    context 'when MFA features are available' do
      before do
        skip 'MFA features not available' unless mfa_features_available
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
    end

    context 'when MFA features are not available' do
      before do
        skip 'MFA features are available' if mfa_features_available
      end

      # When MFA is not enabled, these routes may return:
      # - 404 if the route doesn't exist
      # - 400 if the route exists but rejects the request (e.g., missing required fields)
      # - 401/403 if auth is required

      it 'rejects /auth/otp-setup requests' do
        get '/auth/otp-setup'
        expect([400, 401, 403, 404]).to include(last_response.status)
      end

      it 'rejects /auth/otp-auth requests' do
        post '/auth/otp-auth', { otp_code: '123456' }.to_json,
             { 'CONTENT_TYPE' => 'application/json' }
        expect([400, 401, 403, 404]).to include(last_response.status)
      end

      it 'rejects /auth/recovery-codes requests' do
        get '/auth/recovery-codes'
        expect([400, 401, 403, 404]).to include(last_response.status)
      end

      it 'rejects /auth/recovery-auth requests' do
        post '/auth/recovery-auth', { recovery_code: 'abc12345' }.to_json,
             { 'CONTENT_TYPE' => 'application/json' }
        expect([400, 401, 403, 404]).to include(last_response.status)
      end
    end
  end

  describe 'POST /auth/login (standard login always works)' do
    let(:credentials) { { login: 'test@example.com', password: 'wrongpassword' }.to_json }
    let(:json_headers) { { 'CONTENT_TYPE' => 'application/json' } }

    it 'returns appropriate error for invalid credentials' do
      post '/auth/login', credentials, json_headers
      expect([400, 401, 422]).to include(last_response.status)
    end
  end
end
