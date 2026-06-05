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
# - ORGS_SSO_ENABLED=true (for redirect/state tests; CSRF bypass tests run regardless)
#
# RUN:
#   ORGS_SSO_ENABLED=true pnpm run test:rspec apps/web/auth/spec/integration/full/omniauth_csrf_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
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

      # DomainStrategy class vars are normally set when the middleware is
      # first instantiated (i.e., on the first Rack request). The
      # canonical_host let evaluates BEFORE any request, so initialize
      # eagerly to avoid a nil fallback that mismatches the hook's check.
      domains_config = OT.conf&.dig('features', 'domains') || {}
      Onetime::Middleware::DomainStrategy.initialize_from_config(domains_config)
    end

    let(:sso_path) { '/auth/sso/oidc' }

    # Use the canonical domain so tenant resolution falls through to platform
    # credentials. Rack::Test defaults to example.org, which is neither a
    # registered CustomDomain nor the canonical domain, triggering the
    # sso_not_configured redirect.
    let(:canonical_host) do
      Onetime::Middleware::DomainStrategy.canonical_domain || 'localhost:3000'
    end

    context 'when OmniAuth is configured', :omniauth_mock do

      it 'accepts POST without shrimp token (CSRF skipped for SSO routes)' do
        # OmniAuth routes bypass Rack::Protection CSRF
        # The request should proceed to OmniAuth, which will redirect to IdP
        header 'Host', canonical_host
        post sso_path

        # Should NOT be 403 (CSRF rejection)
        # Will be 302 (redirect to IdP) or 404 (if route not registered)
        expect(last_response.status).not_to eq(403)
      end

      it 'redirects to identity provider on valid request' do
        unless Onetime.auth_config.orgs_sso_enabled? || Onetime.auth_config.sso_enabled?
          skip 'SSO not enabled at boot — route not registered'
        end

        header 'Host', canonical_host
        post sso_path

        expect(last_response.status).not_to eq(404),
          "#{sso_path} returned 404 — SSO is enabled but route not registered"

        location = last_response.headers['Location']

        expect(last_response.status).to eq(302)
        expected_issuer = ENV['OIDC_ISSUER'] || PLACEHOLDER_OIDC_ISSUER
        expect(location).to include(expected_issuer)
      end

      it 'includes state parameter in authorization URL' do
        unless Onetime.auth_config.orgs_sso_enabled? || Onetime.auth_config.sso_enabled?
          skip 'SSO not enabled at boot — route not registered'
        end

        header 'Host', canonical_host
        post sso_path

        expect(last_response.status).not_to eq(404),
          "#{sso_path} returned 404 — SSO is enabled but route not registered"

        location = last_response.headers['Location']

        expect(last_response.status).to eq(302)
        expect(location).to include('state=')
      end
    end

    context 'when OmniAuth is not configured' do
      before do
        if Onetime.auth_config.orgs_sso_enabled? || Onetime.auth_config.sso_enabled?
          skip 'SSO is enabled — routes are registered'
        end
      end

      it 'returns 404 when OmniAuth routes are not registered' do
        post sso_path
        expect(last_response.status).to eq(404)
      end
    end
  end
end
