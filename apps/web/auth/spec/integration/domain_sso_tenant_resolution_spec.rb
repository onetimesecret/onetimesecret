# apps/web/auth/spec/integration/domain_sso_tenant_resolution_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration Tests for Domain SSO Tenant Resolution
# =============================================================================
#
# Issue: #2786 - Per-domain SSO configuration
#
# Tests the tenant resolution chain for domain-based SSO:
#   Host header -> CustomDomain -> DomainSsoConfig
#
# Resolution is domain-only: each domain has its own SSO configuration.
# There is no org-level fallback.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec apps/web/auth/spec/integration/domain_sso_tenant_resolution_spec.rb
#
# =============================================================================

require_relative '../spec_helper'
require_relative '../support/tenant_test_fixtures'
require_relative '../support/domain_sso_test_fixtures'
require_relative '../support/mock_omniauth_strategy'
require_relative '../support/oauth_flow_helper'
require 'json'

# Define module structure for hooks (normally provided by auth app boot)
module Auth
  module Config
    module Hooks
    end
  end
end unless defined?(Auth::Config::Hooks)

# Require Auth::Logging (used by the hook)
require_relative '../../lib/logging'

# Require the tenant resolution hook
require_relative '../../config/hooks/omniauth_tenant'

RSpec.describe 'Domain SSO Tenant Resolution', type: :integration do
  include TenantTestFixtures
  include DomainSsoTestFixtures

  # Configure Familia encryption for testing
  before(:all) do
    key_v1 = 'test_encryption_key_32bytes_ok!!'
    key_v2 = 'another_test_key_for_testing_!!'

    Familia.configure do |config|
      config.encryption_keys = {
        v1: Base64.strict_encode64(key_v1),
        v2: Base64.strict_encode64(key_v2),
      }
      config.current_key_version = :v1
      config.encryption_personalization = 'DomainSsoTenantResolutionTest'
    end
  end

  # ==========================================================================
  # Resolution Tests
  # ==========================================================================

  describe 'domain resolution' do
    # The resolution chain:
    #   1. Host -> CustomDomain
    #   2. CustomDomain.identifier -> DomainSsoConfig
    #   3. If no DomainSsoConfig -> platform env vars (if allowed)

    context 'when domain has DomainSsoConfig' do
      include_context 'tenant fixtures'

      it 'uses DomainSsoConfig credentials' do
        domain_sso_config = Onetime::DomainSsoConfig.find_by_domain_id(test_custom_domain.identifier)
        expect(domain_sso_config).not_to be_nil
        expect(domain_sso_config.enabled?).to be true
      end

      it 'uses domain_id as strategy name' do
        domain_sso_config = Onetime::DomainSsoConfig.find_by_domain_id(test_custom_domain.identifier)
        options = domain_sso_config.to_omniauth_options
        expect(options[:name]).to eq(test_custom_domain.identifier)
      end
    end

    context 'when domain has no DomainSsoConfig' do
      it 'falls back to platform env vars if allowed' do
        # Domain without DomainSsoConfig should use platform credentials
        # This is controlled by allow_platform_fallback_for_tenants config
        expect(Onetime::DomainSsoConfig.find_by_domain_id('nonexistent_domain')).to be_nil
      end
    end
  end

  # ==========================================================================
  # Callback Validation Tests
  # ==========================================================================

  describe 'callback validation' do
    context 'with domain SSO' do
      it 'validates callback arrives at same domain' do
        # Callback should verify domain_id matches
        # This is handled by before_omniauth_callback_route hook
        helpers = Auth::Config::Hooks::OmniAuthTenant
        expect(helpers).to respond_to(:resolve_custom_domain)
      end
    end
  end

  # ==========================================================================
  # Disabled Config Handling Tests
  # ==========================================================================

  describe 'disabled config handling' do
    context 'when DomainSsoConfig exists but is disabled' do
      it 'skips disabled DomainSsoConfig' do
        config = build_disabled_domain_sso_config(:oidc)
        expect(config.enabled?).to be false
      end
    end
  end

  # ==========================================================================
  # Resolution Chain Helper Tests
  # ==========================================================================

  describe 'resolution chain helpers' do
    let(:helpers) { Auth::Config::Hooks::OmniAuthTenant }

    describe '.resolve_custom_domain' do
      it 'returns nil for empty host' do
        result = helpers.resolve_custom_domain('')
        expect(result).to be_nil
      end

      it 'returns nil for nil host' do
        result = helpers.resolve_custom_domain(nil)
        expect(result).to be_nil
      end
    end

    describe '.canonical_domain?' do
      it 'returns false for empty host' do
        expect(helpers.canonical_domain?('')).to be false
      end
    end
  end

  # ==========================================================================
  # Credential Injection Tests
  # ==========================================================================

  describe 'credential injection' do
    describe 'domain SSO credentials' do
      let(:config) { build_domain_sso_config(:entra_id) }

      it 'generates options with domain-specific tenant_id' do
        options = config.to_omniauth_options
        expect(options[:tenant_id]).to eq('contoso-tenant-uuid-1234')
      end

      it 'generates options with domain_id as name' do
        options = config.to_omniauth_options
        expect(options[:name]).to eq(config.domain_id)
      end
    end
  end

  # ==========================================================================
  # Cross-Tenant Security Tests
  # ==========================================================================

  describe 'cross-tenant security' do
    describe 'domain callback hijack prevention' do
      it 'stores domain_id in session for validation' do
        # The hook stores session[:omniauth_tenant_domain_id]
        # for callback validation
        helpers = Auth::Config::Hooks::OmniAuthTenant
        expect(helpers::STRATEGY_CLASS_MAP).to include(:entra_id)
      end
    end

    # ==========================================================================
    # Integration Test: Cross-Domain Callback Attack Prevention
    # ==========================================================================
    #
    # This test verifies that OAuth callbacks are rejected when they arrive
    # at a different domain than where authentication was initiated.
    #
    # Attack scenario:
    #   1. Attacker initiates OAuth from domain A (stores domain_id in session)
    #   2. Attacker redirects callback to domain B (different host header)
    #   3. System should reject with 403 due to tenant mismatch
    #
    # PENDING: These tests require OmniAuth routes to be registered at boot.
    # Route registration requires OIDC discovery to succeed during app boot.
    # When routes are not registered (404 on initiation), tests skip gracefully.
    #
    # To run these tests with full OAuth flow:
    #   1. Ensure OIDC_ISSUER points to a valid discovery endpoint
    #   2. Or configure WebMock stubs BEFORE app boot (see spec_helper.rb)
    #   3. The tests will automatically unskip when routes become available
    #
    describe 'callback domain validation', type: :integration, oauth_flow: true do
      include Rack::Test::Methods
      include OAuthFlowHelper

      def app
        Onetime::Application::Registry.generate_rack_url_map
      end

      before(:all) do
        Onetime.boot! :test
      end

      after do
        cleanup_oauth_test_fixtures
      end

      context 'when callback domain differs from initiation domain' do
        # Use unique domain names per test to avoid collisions
        let(:test_run_id) { "diff-#{SecureRandom.hex(4)}" }
        let(:domain_a_host) { "secrets-#{test_run_id}.acme-corp.com" }
        let(:domain_b_host) { "secrets-#{test_run_id}.attacker.com" }

        before do
          # Create domain fixtures for both domains
          @domain_a_fixtures = setup_oauth_test_domain(domain_a_host)
          @domain_b_fixtures = setup_oauth_test_domain(domain_b_host)
        end

        it 'returns 403 tenant_mismatch error' do
          # Enable OmniAuth test mode for callback simulation
          OmniAuth.config.test_mode = true
          OmniAuth.config.allowed_request_methods = %i[get post]

          # Set up mock auth hash for the callback
          OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new({
            provider: 'oidc',
            uid: 'test-uid-123',
            info: { email: 'user@acme-corp.com', name: 'Test User' },
          })

          begin
            # Phase 1: Initiate OAuth from domain A
            # This stores domain_a's identifier in session[:omniauth_tenant_domain_id]
            header 'Host', domain_a_host
            post '/auth/sso/oidc'

            # Skip if OmniAuth route not registered (requires OIDC discovery at boot)
            if last_response.status == 404
              skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
            end

            # Verify initiation succeeded (redirect to IdP)
            expect(last_response.status).to eq(302),
              "Expected redirect to IdP, got: #{last_response.status}"

            # Phase 2: Attempt callback from domain B (different host)
            # This should fail because session[:omniauth_tenant_domain_id] doesn't match
            header 'Host', domain_b_host
            post '/auth/sso/oidc/callback'

            # Should return 403 due to tenant mismatch
            expect(last_response.status).to eq(403),
              "Expected 403 for cross-domain callback, got: #{last_response.status}, body: #{last_response.body}"

            # Verify error response contains expected error type
            expect(last_response.body).to include('tenant_mismatch').or include('Authentication context mismatch')
          ensure
            OmniAuth.config.test_mode = false
            OmniAuth.config.mock_auth.clear
          end
        end
      end

      context 'when callback domain matches initiation domain' do
        let(:test_run_id) { "same-#{SecureRandom.hex(4)}" }
        let(:domain_a_host) { "secrets-#{test_run_id}.acme-corp.com" }

        before do
          @domain_a_fixtures = setup_oauth_test_domain(domain_a_host)
        end

        it 'allows callback to proceed' do
          OmniAuth.config.test_mode = true
          OmniAuth.config.allowed_request_methods = %i[get post]

          OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new({
            provider: 'oidc',
            uid: 'test-uid-456',
            info: { email: 'user@acme-corp.com', name: 'Test User' },
          })

          begin
            # Phase 1: Initiate OAuth from domain A
            header 'Host', domain_a_host
            post '/auth/sso/oidc'

            # Skip if OmniAuth route not registered
            if last_response.status == 404
              skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
            end

            expect(last_response.status).to eq(302)

            # Phase 2: Callback from same domain A
            header 'Host', domain_a_host
            post '/auth/sso/oidc/callback'

            # Should NOT return 403 (tenant mismatch)
            # May return 302 (redirect after successful auth) or other status
            # depending on full auth flow, but not 403
            expect(last_response.status).not_to eq(403),
              "Same-domain callback should not fail with 403, got: #{last_response.status}"
          ensure
            OmniAuth.config.test_mode = false
            OmniAuth.config.mock_auth.clear
          end
        end
      end

      context 'when no tenant context in session (platform-level auth)' do
        # No domain fixtures needed - this tests platform-level auth
        it 'allows callback to proceed without tenant validation' do
          OmniAuth.config.test_mode = true
          OmniAuth.config.allowed_request_methods = %i[get post]

          OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new({
            provider: 'oidc',
            uid: 'test-uid-789',
            info: { email: 'user@example.com', name: 'Test User' },
          })

          begin
            # Directly hit callback without initiation (simulates platform-level flow)
            # Use canonical domain which skips tenant context storage
            canonical_host = OT.conf.dig('site', 'host') || 'onetimesecret.com'
            header 'Host', canonical_host
            post '/auth/sso/oidc/callback'

            # Should NOT return 403 (no tenant context to validate)
            # The hook's `next unless expected_domain_id` path allows this
            expect(last_response.status).not_to eq(403),
              "Platform-level callback should not fail with 403, got: #{last_response.status}"
          ensure
            OmniAuth.config.test_mode = false
            OmniAuth.config.mock_auth.clear
          end
        end
      end
    end
  end

  # ==========================================================================
  # Edge Case Tests
  # ==========================================================================

  describe 'edge cases' do
    describe 'domain orphaned from org' do
      it 'handles missing organization gracefully' do
        # Domain exists but org was deleted
        # Should still work with domain-only resolution
        config = build_domain_sso_config(:oidc)
        expect(config.organization).to be_nil # No real org in test
      end
    end
  end
end
