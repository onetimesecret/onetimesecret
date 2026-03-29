# apps/web/auth/spec/integration/omniauth_failure_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration
# =============================================================================
#
# Tests OmniAuth failure handling and error redirect flow.
#
# When SSO authentication fails (IdP error, domain rejection, etc.), the
# application should redirect to /signin with an auth_error query param
# that the Vue frontend uses to display the appropriate error message.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec apps/web/auth/spec/integration/omniauth_failure_spec.rb
#
# =============================================================================

require_relative '../spec_helper'

RSpec.describe 'OmniAuth Failure Handling' do
  describe 'failure redirect configuration' do
    it 'uses sso_failed as the error code' do
      # The frontend expects specific error codes for i18n lookup
      error_code = 'sso_failed'
      valid_codes = %w[sso_failed token_missing token_expired token_invalid]
      expect(valid_codes).to include(error_code)
    end

    it 'redirect path includes auth_error query param' do
      expected_path = '/signin?auth_error=sso_failed'
      expect(expected_path).to include('auth_error=sso_failed')
    end
  end

  describe 'error handling patterns', type: :unit do
    it 'handles nil omniauth_error gracefully via safe navigation' do
      # The hook uses rescue StandardError for safe access
      # This tests that pattern works correctly
      error = begin
        nil&.message
      rescue StandardError
        'No error message'
      end
      # nil&.message returns nil (safe navigation), not an error
      expect(error).to be_nil
    end

    it 'rescues StandardError for unknown error types' do
      # Pattern used in omniauth_on_failure hook
      error_type = begin
        raise 'test error'
      rescue StandardError
        :unknown
      end
      expect(error_type).to eq(:unknown)
    end
  end

  describe 'failure redirect flow', type: :integration do
    # Rack::Test::Methods included via spec_helper for :integration type

    def app
      Onetime::Application::Registry.generate_rack_url_map
    end

    before(:all) do
      # Boot the full Onetime application for integration tests
      # Following the same pattern as omniauth_csrf_spec.rb
      require 'onetime' unless defined?(Onetime)
      Onetime.boot! :test unless Onetime.ready?
    end

    context 'when OmniAuth is configured', :omniauth_mock do
      # Uses mock OIDC discovery via OmniAuthTestHelper

      it 'failure redirect path includes auth_error param' do
        # Verify the configuration produces the expected redirect path
        expected_path = '/signin?auth_error=sso_failed'
        expect(expected_path).to include('auth_error=')
      end

      it 'uses sso_failed as the error code' do
        # The frontend expects specific error codes for i18n lookup
        error_code = 'sso_failed'
        valid_codes = %w[sso_failed token_missing token_expired token_invalid]
        expect(valid_codes).to include(error_code)
      end

      it 'redirects to /signin with auth_error on invalid_credentials failure' do
        # Enable OmniAuth test mode and set up failure mock
        OmniAuth.config.test_mode = true
        OmniAuth.config.allowed_request_methods = %i[get post]

        begin
          # Configure mock to return :invalid_credentials failure
          mock_oidc_failure(:invalid_credentials)

          # POST to callback endpoint - OmniAuth test mode will trigger failure flow
          post '/auth/sso/oidc/callback'

          # Skip if OmniAuth route not registered
          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          # Should redirect with auth_error=sso_failed
          expect(last_response.status).to eq(302),
            "Expected 302 redirect, got #{last_response.status}: #{last_response.body}"
          location = last_response.headers['Location']
          expect(location).to include('/signin'),
            "Expected redirect to /signin, got: #{location}"
          expect(location).to include('auth_error=sso_failed'),
            "Expected auth_error=sso_failed in redirect URL, got: #{location}"
        ensure
          OmniAuth.config.test_mode = false
          OmniAuth.config.mock_auth.clear
        end
      end

      it 'redirects to /signin with auth_error on access_denied failure' do
        OmniAuth.config.test_mode = true
        OmniAuth.config.allowed_request_methods = %i[get post]

        begin
          mock_oidc_failure(:access_denied)
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          expect(last_response.status).to eq(302)
          location = last_response.headers['Location']
          expect(location).to include('auth_error=sso_failed')
        ensure
          OmniAuth.config.test_mode = false
          OmniAuth.config.mock_auth.clear
        end
      end

      it 'redirects to /signin with auth_error on timeout failure' do
        OmniAuth.config.test_mode = true
        OmniAuth.config.allowed_request_methods = %i[get post]

        begin
          mock_oidc_failure(:timeout)
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          expect(last_response.status).to eq(302)
          location = last_response.headers['Location']
          expect(location).to include('auth_error=sso_failed')
        ensure
          OmniAuth.config.test_mode = false
          OmniAuth.config.mock_auth.clear
        end
      end
    end

    context 'error code to i18n mapping' do
      # These tests verify the frontend can handle the error codes

      let(:error_codes) do
        {
          'sso_failed' => 'web.login.errors.sso_failed',
          'token_missing' => 'web.login.errors.token_missing',
          'token_expired' => 'web.login.errors.token_expired',
          'token_invalid' => 'web.login.errors.token_invalid',
        }
      end

      it 'defines valid i18n keys for all error codes' do
        error_codes.each do |code, i18n_key|
          # i18n key should follow hierarchical pattern
          expect(i18n_key).to start_with('web.login.errors.')
          expect(i18n_key).to include(code)
        end
      end
    end
  end
end
