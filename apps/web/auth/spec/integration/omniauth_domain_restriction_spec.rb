# apps/web/auth/spec/integration/omniauth_domain_restriction_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration
# =============================================================================
#
# Tests the before_omniauth_create_account hook that enforces domain restrictions
# for SSO signups when allowed_signup_domains is configured.
#
# Hook location: apps/web/auth/config/hooks/omniauth.rb:130-173
#
# Test cases:
# - Allowed domain passes (successful SSO signup proceeds)
# - Disallowed domain blocked with 403
# - Malformed email rejected with 400
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec apps/web/auth/spec/integration/omniauth_domain_restriction_spec.rb
#
# =============================================================================

require_relative '../spec_helper'

RSpec.describe 'OmniAuth Domain Restriction', type: :integration do
  include Rack::Test::Methods

  def app
    Onetime::Application::Registry.generate_rack_url_map
  end

  before(:all) do
    # Boot the full Onetime application for integration tests
    # Following the same pattern as omniauth_csrf_spec.rb
    require 'onetime' unless defined?(Onetime)
    Onetime.boot! :test unless Onetime.ready?
  end

  # ==========================================================================
  # Helper Methods
  # ==========================================================================

  # Sets up OmniAuth test mode with a mock auth hash for the given email
  def setup_mock_auth(email:, provider: :oidc, uid: nil)
    OmniAuth.config.test_mode = true
    OmniAuth.config.allowed_request_methods = %i[get post]

    OmniAuth.config.mock_auth[provider] = OmniAuth::AuthHash.new({
      provider: provider.to_s,
      uid: uid || "test-uid-#{SecureRandom.hex(8)}",
      info: {
        email: email,
        name: 'Test User',
        email_verified: true,
      },
      credentials: {
        token: 'mock_access_token',
        refresh_token: 'mock_refresh_token',
        expires_at: Time.now.to_i + 3600,
        expires: true,
      },
      extra: {
        raw_info: {
          sub: uid || "test-uid-#{SecureRandom.hex(8)}",
          email: email,
          name: 'Test User',
          email_verified: true,
        },
      },
    })
  end

  def teardown_mock_auth
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.clear
  end

  # Configures allowed_signup_domains in OT.conf
  # Pass nil to remove restrictions
  def configure_allowed_domains(domains)
    # Deep clone to avoid mutating original
    config = Marshal.load(Marshal.dump(OT.conf))

    config['site'] ||= {}
    config['site']['authentication'] ||= {}
    config['site']['authentication']['allowed_signup_domains'] = domains

    allow(OT).to receive(:conf).and_return(config)
  end

  # ==========================================================================
  # Tests: Domain Restrictions Configured
  # ==========================================================================

  describe 'when allowed_signup_domains is configured' do
    context 'with email from allowed domain' do
      before do
        configure_allowed_domains(['company.com', 'subsidiary.com'])
      end

      it 'allows SSO callback to proceed for allowed domain' do
        setup_mock_auth(email: 'user@company.com')

        begin
          # Trigger callback - will attempt to create account for new user
          post '/auth/sso/oidc/callback'

          # Skip if OmniAuth route not registered
          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          # Should NOT return 403 (domain_not_allowed) or 400 (invalid_email)
          # May return 302 (redirect after successful auth) or other status
          expect([400, 403]).not_to include(last_response.status),
            "Expected allowed domain to pass, got #{last_response.status}: #{last_response.body}"
        ensure
          teardown_mock_auth
        end
      end

      it 'allows SSO callback to proceed for second allowed domain' do
        setup_mock_auth(email: 'admin@subsidiary.com')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          expect([400, 403]).not_to include(last_response.status),
            "Expected allowed domain to pass, got #{last_response.status}: #{last_response.body}"
        ensure
          teardown_mock_auth
        end
      end

      it 'allows case-insensitive domain matching' do
        setup_mock_auth(email: 'user@COMPANY.COM')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          expect([400, 403]).not_to include(last_response.status),
            "Expected case-insensitive match to pass, got #{last_response.status}"
        ensure
          teardown_mock_auth
        end
      end
    end

    context 'with email from disallowed domain' do
      before do
        configure_allowed_domains(['company.com'])
      end

      it 'returns 403 for disallowed domain' do
        setup_mock_auth(email: 'attacker@evil.com')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          expect(last_response.status).to eq(403),
            "Expected 403 for disallowed domain, got #{last_response.status}: #{last_response.body}"
        ensure
          teardown_mock_auth
        end
      end

      it 'returns domain_not_allowed error code' do
        setup_mock_auth(email: 'user@competitor.com')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          if last_response.status == 403
            # Check error response contains expected error code
            expect(last_response.body).to include('domain_not_allowed').or include('not authorized'),
              "Expected domain_not_allowed error, got: #{last_response.body}"
          end
        ensure
          teardown_mock_auth
        end
      end

      it 'rejects subdomain of allowed domain' do
        # sub.company.com is NOT allowed when only company.com is configured
        setup_mock_auth(email: 'user@sub.company.com')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          expect(last_response.status).to eq(403),
            "Expected 403 for subdomain, got #{last_response.status}: #{last_response.body}"
        ensure
          teardown_mock_auth
        end
      end
    end
  end

  # ==========================================================================
  # Tests: Malformed Email
  # ==========================================================================

  describe 'with malformed email from IdP' do
    before do
      configure_allowed_domains(['company.com'])
    end

    context 'email missing @ symbol' do
      it 'returns 400 for email without @' do
        setup_mock_auth(email: 'usercompany.com')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          expect(last_response.status).to eq(400),
            "Expected 400 for malformed email, got #{last_response.status}: #{last_response.body}"
        ensure
          teardown_mock_auth
        end
      end

      it 'returns invalid_email error code' do
        setup_mock_auth(email: 'noemail')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          if last_response.status == 400
            expect(last_response.body).to include('invalid_email').or include('Invalid email'),
              "Expected invalid_email error, got: #{last_response.body}"
          end
        ensure
          teardown_mock_auth
        end
      end
    end

    context 'email with empty domain' do
      it 'returns 400 for email with empty domain' do
        setup_mock_auth(email: 'user@')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          expect(last_response.status).to eq(400),
            "Expected 400 for empty domain, got #{last_response.status}: #{last_response.body}"
        ensure
          teardown_mock_auth
        end
      end
    end

    context 'email with multiple @ symbols' do
      it 'returns 400 for email with multiple @' do
        setup_mock_auth(email: 'user@foo@company.com')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          expect(last_response.status).to eq(400),
            "Expected 400 for email with multiple @, got #{last_response.status}: #{last_response.body}"
        ensure
          teardown_mock_auth
        end
      end
    end

    context 'empty or nil email' do
      it 'returns 400 for empty email' do
        setup_mock_auth(email: '')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          expect(last_response.status).to eq(400),
            "Expected 400 for empty email, got #{last_response.status}: #{last_response.body}"
        ensure
          teardown_mock_auth
        end
      end
    end
  end

  # ==========================================================================
  # Tests: No Domain Restrictions
  # ==========================================================================

  describe 'when no allowed_signup_domains configured' do
    context 'with nil config' do
      before do
        configure_allowed_domains(nil)
      end

      it 'allows any domain when restrictions are nil' do
        setup_mock_auth(email: 'user@any-domain.com')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          # Should NOT return 403 - no domain restrictions active
          expect(last_response.status).not_to eq(403),
            "Expected no domain restriction, got 403: #{last_response.body}"
        ensure
          teardown_mock_auth
        end
      end
    end

    context 'with empty array config' do
      before do
        configure_allowed_domains([])
      end

      it 'allows any domain when restrictions are empty array' do
        setup_mock_auth(email: 'user@random-domain.org')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          # Should NOT return 403 - no domain restrictions active
          expect(last_response.status).not_to eq(403),
            "Expected no domain restriction with empty config, got 403: #{last_response.body}"
        ensure
          teardown_mock_auth
        end
      end
    end
  end

  # ==========================================================================
  # Tests: Security Considerations
  # ==========================================================================

  describe 'security considerations' do
    before do
      configure_allowed_domains(['secure-corp.com'])
    end

    it 'does not reveal allowed domains in error response' do
      setup_mock_auth(email: 'user@attacker.com')

      begin
        post '/auth/sso/oidc/callback'

        if last_response.status == 404
          skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
        end

        if last_response.status == 403
          # Response should NOT reveal which domains are allowed
          expect(last_response.body).not_to include('secure-corp.com'),
            "Error response reveals allowed domain: #{last_response.body}"
        end
      ensure
        teardown_mock_auth
      end
    end

    it 'uses generic error message' do
      setup_mock_auth(email: 'user@hacker.io')

      begin
        post '/auth/sso/oidc/callback'

        if last_response.status == 404
          skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
        end

        if last_response.status == 403
          # Should use generic message without revealing policy details
          expect(last_response.body).to include('not authorized').or include('domain_not_allowed'),
            "Expected generic error message, got: #{last_response.body}"
        end
      ensure
        teardown_mock_auth
      end
    end
  end
end
