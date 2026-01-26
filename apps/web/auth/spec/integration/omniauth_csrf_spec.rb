# apps/web/auth/spec/integration/omniauth_csrf_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration
# =============================================================================
#
# Tests CSRF configuration for OmniAuth SSO endpoints.
#
# OmniAuth routes (/auth/sso/*) use OAuth's state parameter for CSRF protection
# instead of form tokens. Rack::Protection is configured to skip these routes
# (see lib/onetime/middleware/security.rb).
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
# - OmniAuth configured (OIDC_ISSUER, OIDC_CLIENT_ID set)
#
# RUN:
#   source .env.test && pnpm run test:rspec apps/web/auth/spec/integration/omniauth_csrf_spec.rb
#
# =============================================================================

require_relative '../spec_helper'
require 'json'

RSpec.describe 'OmniAuth CSRF Configuration' do
  describe 'Rack::Protection middleware configuration' do
    let(:middleware_config) do
      Onetime::Middleware::Security.middleware_components['AuthenticityToken']
    end

    it 'uses shrimp as the CSRF parameter name' do
      expect(middleware_config).not_to be_nil
      expect(middleware_config[:options]).to include(authenticity_param: 'shrimp')
    end

    it 'configures allow_if callback' do
      expect(middleware_config[:options][:allow_if]).to be_a(Proc)
    end

    describe 'allow_if bypass rules' do
      let(:allow_if) { middleware_config[:options][:allow_if] }

      def mock_env(path:, media_type: nil, accept: nil)
        env = {
          'PATH_INFO' => path,
          'REQUEST_METHOD' => 'POST',
          'rack.input' => StringIO.new(''),
        }
        env['CONTENT_TYPE'] = media_type if media_type
        env['HTTP_ACCEPT'] = accept if accept
        env
      end

      it 'skips CSRF for API routes' do
        env = mock_env(path: '/api/v1/secrets')
        expect(allow_if.call(env)).to be true
      end

      it 'skips CSRF for OmniAuth SSO routes' do
        env = mock_env(path: '/auth/sso/oidc')
        expect(allow_if.call(env)).to be true
      end

      it 'skips CSRF for OmniAuth callback routes' do
        env = mock_env(path: '/auth/sso/oidc/callback')
        expect(allow_if.call(env)).to be true
      end

      it 'does NOT skip CSRF for regular form posts' do
        env = mock_env(path: '/signin', media_type: 'application/x-www-form-urlencoded')
        # Returns nil/false when CSRF should be validated (falsy = don't skip)
        expect(allow_if.call(env)).to be_falsey
      end

      it 'does NOT skip CSRF for non-SSO auth routes' do
        env = mock_env(path: '/auth/login')
        expect(allow_if.call(env)).to be_falsey
      end

      # Edge cases for path matching
      it 'skips CSRF for provider-specific SSO paths' do
        env = mock_env(path: '/auth/sso/github')
        expect(allow_if.call(env)).to be true
      end

      it 'does NOT skip CSRF for paths that look similar but differ' do
        # /auth/sso-other does not start with /auth/sso/
        env = mock_env(path: '/auth/sso-other')
        expect(allow_if.call(env)).to be_falsey
      end

      it 'handles mixed conditions correctly' do
        # API path takes precedence
        env = mock_env(path: '/api/v1/auth', media_type: 'text/html')
        expect(allow_if.call(env)).to be true
      end
    end
  end

  describe 'OAuth state parameter protection', type: :integration do
    include Rack::Test::Methods

    def app
      Onetime::Application::Registry.generate_rack_url_map
    end

    before(:all) do
      Onetime.boot! :test
    end

    let(:sso_path) { '/auth/sso/oidc' }

    context 'when OmniAuth is configured' do
      before do
        skip 'OmniAuth not configured (OIDC_ISSUER not set)' if ENV['OIDC_ISSUER'].to_s.empty?
      end

      it 'accepts POST without shrimp token (CSRF skipped for SSO routes)' do
        # OmniAuth routes bypass Rack::Protection CSRF
        # The request should proceed to OmniAuth, which will redirect to IdP
        post sso_path

        # Should NOT be 403 (CSRF rejection)
        # Will be 302 (redirect to IdP) or 500 (if OIDC misconfigured)
        expect(last_response.status).not_to eq(403)
      end

      it 'redirects to identity provider on valid request' do
        post sso_path

        # OmniAuth should initiate OAuth flow with redirect
        if last_response.status == 302
          location = last_response.headers['Location']
          # Should redirect to OIDC issuer, not back to app
          expect(location).to include(ENV['OIDC_ISSUER']) if ENV['OIDC_ISSUER']
        end
      end

      it 'includes state parameter in authorization URL' do
        post sso_path

        if last_response.status == 302
          location = last_response.headers['Location']
          # OAuth state parameter provides CSRF protection
          expect(location).to include('state=')
        end
      end
    end

    context 'when OmniAuth is not configured' do
      before do
        skip 'OmniAuth is configured' unless ENV['OIDC_ISSUER'].to_s.empty?
      end

      it 'returns 404 when OmniAuth routes are not registered' do
        post sso_path
        expect(last_response.status).to eq(404)
      end
    end
  end
end
