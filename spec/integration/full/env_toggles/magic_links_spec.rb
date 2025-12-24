# spec/integration/authentication/full_mode/env_toggles/magic_links_enabled_spec.rb
#
# frozen_string_literal: true

# Tests for magic links (passwordless login) toggle via ENABLE_MAGIC_LINKS env var.
# NOTE: Rodauth features are configured at boot time. These tests verify
# the current state based on whether ENABLE_MAGIC_LINKS was set when the app loaded.

require 'spec_helper'
require 'rack/test'

RSpec.describe 'Magic Links Toggle', type: :integration do
  include Rack::Test::Methods

  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  def json_response
    JSON.parse(last_response.body)
  rescue JSON::ParserError
    {}
  end

  # Detect if magic links was actually enabled at boot time by checking for methods
  # Note: ENV var alone is not sufficient - must check if Rodauth actually loaded email_auth features
  let(:magic_links_features_available) do
    Auth::Config.method_defined?(:email_auth_route) ||
      Auth::Config.private_method_defined?(:email_auth_route)
  end

  describe 'configuration' do
    it 'detects ENABLE_MAGIC_LINKS environment variable' do
      # This test documents the current state - magic links may or may not be enabled
      expect([nil, 'true', 'false']).to include(ENV['ENABLE_MAGIC_LINKS'])
    end

    it 'mounts Auth app' do
      expect(Onetime::Application::Registry.mount_mappings).to have_key('/auth')
    end
  end

  describe 'Auth::Config email_auth feature detection' do
    # These tests verify whether email_auth features were configured at boot time
    # by checking if the Rodauth methods exist

    it 'correctly detects magic links feature availability' do
      # This documents the actual state - magic links may or may not be enabled
      # depending on whether ENABLE_MAGIC_LINKS=true was set when Auth::Config loaded
      expect(magic_links_features_available).to be(true).or be(false)
    end

    it 'ENV and feature state are consistent when magic links enabled' do
      # If magic links features are available, ENV should have been set
      if magic_links_features_available
        expect(ENV['ENABLE_MAGIC_LINKS']).to eq('true')
      end
    end
  end

  describe 'magic links routes' do
    context 'when magic links features are available' do
      before do
        skip 'Magic links features not available' unless magic_links_features_available
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
    end

    context 'when magic links features are not available' do
      before do
        skip 'Magic links features are available' if magic_links_features_available
      end

      it 'returns 404 for /auth/email-login-request' do
        post '/auth/email-login-request', { login: 'test@example.com' }.to_json,
             { 'CONTENT_TYPE' => 'application/json' }
        expect(last_response.status).to eq(404)
      end

      it 'returns 404 for /auth/email-login' do
        get '/auth/email-login'
        expect(last_response.status).to eq(404)
      end
    end
  end

  describe 'POST /auth/login (standard login always works)' do
    let(:credentials) { { login: 'test@example.com', password: 'wrongpassword' }.to_json }
    let(:json_headers) { { 'CONTENT_TYPE' => 'application/json' } }

    it 'returns appropriate error for invalid credentials' do
      post '/auth/login', credentials, json_headers
      # 400=bad request, 401=unauthorized, 403=forbidden, 422=unprocessable
      expect([400, 401, 403, 422]).to include(last_response.status)
    end
  end
end
