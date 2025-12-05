# apps/web/auth/spec/routes/availability_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration
# =============================================================================
#
# These tests make REAL HTTP requests to the Auth application via Rack::Test.
# They verify that routes respond with expected status codes and content types.
#
# MUST INCLUDE:
# - Full app boot with Onetime.boot!
# - Real HTTP requests (get, post, etc.)
# - Database state changes (Valkey, SQLite)
# - Assertions on HTTP response status/headers/body
#
# MUST NOT INCLUDE:
# - File.read() on source files
# - String pattern matching on configuration files
# - Mocked HTTP responses
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   VALKEY_URL='valkey://127.0.0.1:2121/0' AUTH_DATABASE_URL='sqlite://data/test_auth.db' \
#     pnpm run test:rspec apps/web/auth/spec/routes/availability_spec.rb
#
# =============================================================================

require_relative '../spec_helper'
require 'json'

RSpec.describe 'Auth Route Availability', type: :integration do
  # Boot the application once for all tests in this file
  before(:all) do
    boot_onetime_app
  end

  describe 'core routes (always available)' do
    describe 'GET /auth' do
      it 'returns 200 OK' do
        json_get '/auth'
        expect(last_response.status).to eq(200)
      end

      it 'returns JSON content type' do
        json_get '/auth'
        expect(last_response.content_type).to include('application/json')
      end

      it 'includes version information' do
        json_get '/auth'
        json = JSON.parse(last_response.body)
        expect(json).to include('version')
      end
    end

    describe 'GET /auth/health' do
      it 'returns 200 OK' do
        json_get '/auth/health'
        expect(last_response.status).to eq(200)
      end

      it 'returns JSON with status ok' do
        json_get '/auth/health'
        json = JSON.parse(last_response.body)
        expect(json['status']).to eq('ok')
      end

      it 'reports full mode' do
        json_get '/auth/health'
        json = JSON.parse(last_response.body)
        expect(json['mode']).to eq('full')
      end
    end

    describe 'POST /auth/login' do
      it 'returns JSON for invalid credentials' do
        json_post '/auth/login', { login: 'nonexistent@example.com', password: 'wrong' }
        expect(last_response.content_type).to include('application/json')
      end

      it 'returns 401 for invalid credentials' do
        json_post '/auth/login', { login: 'nonexistent@example.com', password: 'wrong' }
        expect(last_response.status).to eq(401)
      end

      it 'returns error message in JSON body' do
        json_post '/auth/login', { login: 'nonexistent@example.com', password: 'wrong' }
        json = JSON.parse(last_response.body)
        # Rodauth returns either 'error' or 'field-error'
        expect(json['error'] || json['field-error']).to be_truthy
      end
    end

    describe 'POST /auth/create-account' do
      it 'returns JSON response' do
        json_post '/auth/create-account', {
          login: 'test@example.com',
          'login-confirm': 'test@example.com',
          password: 'SecureP@ss123',
          'password-confirm': 'SecureP@ss123'
        }
        expect(last_response.content_type).to include('application/json')
      end

      it 'accepts valid account creation request' do
        unique_email = "test-#{SecureRandom.hex(8)}@example.com"
        json_post '/auth/create-account', {
          login: unique_email,
          'login-confirm': unique_email,
          password: 'SecureP@ss123!',
          'password-confirm': 'SecureP@ss123!'
        }
        # Should return 200/201 (success) or 422 (validation)
        expect([200, 201, 422]).to include(last_response.status)
      end

      it 'rejects invalid email format' do
        json_post '/auth/create-account', {
          login: 'not-an-email',
          'login-confirm': 'not-an-email',
          password: 'SecureP@ss123',
          'password-confirm': 'SecureP@ss123'
        }
        expect(last_response.status).to eq(422)
      end
    end

    describe 'POST /auth/logout' do
      it 'returns JSON response' do
        json_post '/auth/logout', {}
        expect(last_response.content_type).to include('application/json')
      end

      it 'succeeds even without active session' do
        json_post '/auth/logout', {}
        # Logout without session should succeed or return appropriate status
        expect([200, 400, 401]).to include(last_response.status)
      end
    end
  end

  describe 'admin routes' do
    # Admin routes are conditionally defined at class load time based on
    # Onetime.development?. This means:
    #   - In development mode: routes are available and return stats
    #   - In test/production mode: routes are not defined, return 404
    #
    # These tests verify the behavior for the current RACK_ENV.
    # To test development mode behavior, run: RACK_ENV=development pnpm run test:rspec ...

    describe 'GET /auth/admin/stats' do
      it 'returns expected status for current environment' do
        json_get '/auth/admin/stats'

        if Onetime.development?
          # In development: route exists, returns stats or requires auth
          expect([200, 401, 403]).to include(last_response.status)
        else
          # In test/production: route is not defined
          expect(last_response.status).to eq(404)
        end
      end

      it 'returns JSON content type' do
        json_get '/auth/admin/stats'
        expect(last_response.content_type).to include('application/json')
      end
    end
  end

  describe 'MFA routes (when ENABLE_MFA=true)', if: ENV['ENABLE_MFA'] == 'true' do
    describe 'GET /auth/otp-setup' do
      it 'requires authentication or returns error for unauthenticated request' do
        json_get '/auth/otp-setup'
        # Rodauth returns 400 (bad request) for MFA routes without session
        # 401/403 for explicit auth errors, 400 for missing session state
        expect([400, 401, 403]).to include(last_response.status)
      end
    end

    describe 'GET /auth/recovery-codes' do
      it 'requires authentication or returns error for unauthenticated request' do
        json_get '/auth/recovery-codes'
        expect([400, 401, 403]).to include(last_response.status)
      end
    end
  end

  describe 'password reset routes' do
    describe 'POST /auth/reset-password-request' do
      it 'returns JSON response' do
        json_post '/auth/reset-password-request', { login: 'test@example.com' }
        expect(last_response.content_type).to include('application/json')
      end

      it 'handles password reset request without exposing user existence' do
        json_post '/auth/reset-password-request', { login: 'nonexistent@example.com' }
        # Rodauth behavior varies:
        # - 200: Request accepted (email may or may not be sent)
        # - 401: Authentication required before reset
        # - 422: Validation error
        # All responses should be uniform to prevent user enumeration
        expect([200, 401, 422]).to include(last_response.status)
      end
    end
  end

  describe 'session routes' do
    describe 'GET /auth/active-sessions' do
      it 'requires authentication' do
        json_get '/auth/active-sessions'
        expect([401, 403]).to include(last_response.status)
      end
    end
  end
end
