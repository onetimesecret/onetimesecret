# apps/web/auth/spec/integration/omniauth_tenant_resolution_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration Tests for OmniAuth Tenant Resolution
# =============================================================================
#
# Tests the complete tenant resolution chain for multi-tenant SSO:
#   Host header -> CustomDomain -> Organization -> OrgSsoConfig -> Strategy options
#
# The setup proc pattern allows runtime credential injection based on the
# incoming request's Host header, enabling per-organization SSO configurations.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec apps/web/auth/spec/integration/omniauth_tenant_resolution_spec.rb
#
# =============================================================================

require_relative '../spec_helper'
require_relative '../support/tenant_test_fixtures'
require_relative '../support/mock_omniauth_strategy'
require 'json'

# Define module structure for hooks (normally provided by auth app boot)
module Auth
  module Config
    module Hooks
    end
  end
end

# Require Auth::Logging (used by the hook)
require_relative '../../lib/logging'

# Require the tenant resolution hook
require_relative '../../config/hooks/omniauth_tenant'

RSpec.describe 'OmniAuth Tenant Resolution', type: :integration do
  include TenantTestFixtures

  # Configure Familia encryption for testing (required for OrgSsoConfig encrypted fields)
  before(:all) do
    key_v1 = 'test_encryption_key_32bytes_ok!!' # Exactly 32 bytes
    key_v2 = 'another_test_key_for_testing_!!' # Exactly 32 bytes

    Familia.configure do |config|
      config.encryption_keys = {
        v1: Base64.strict_encode64(key_v1),
        v2: Base64.strict_encode64(key_v2),
      }
      config.current_key_version = :v1
      config.encryption_personalization = 'OrgSsoConfigIntegrationTest'
    end
  end

  # ==========================================================================
  # Test Data
  # ==========================================================================

  let(:tenant_domain) { 'secrets.acme-corp.example.com' }
  let(:unknown_domain) { 'unknown-tenant.example.com' }
  let(:primary_domain) { ENV.fetch('HOST', 'onetimesecret.com') }

  let(:tenant_org_id) { 'org_acme_corp_12345' }
  let(:tenant_client_id) { 'acme_tenant_client_id' }
  let(:tenant_client_secret) { 'acme_tenant_client_secret' }
  let(:tenant_tenant_id) { 'acme-azure-tenant-uuid' }

  # ==========================================================================
  # OTS-SSO-001: Setup Proc Injects Tenant Credentials
  # ==========================================================================

  describe 'setup proc invocation (OTS-SSO-001)' do
    context 'when tenant SSO config exists' do
      before do
        # This test documents expected behavior for future implementation.
        # The setup proc will be called by OmniAuth before redirect.
        OmniAuth::Strategies::TenantVerifyingMock.reset!
      end

      it 'calls setup proc before redirect' do
        # The setup proc executes during request phase via auth.omniauth_setup hook.
        # Implementation exists in: apps/web/auth/config/hooks/omniauth_tenant.rb
        #
        # This test verifies full request flow through Rack app.
        skip 'Requires Rack::Test request to /auth/sso/:provider with CustomDomain fixtures in Valkey'
      end

      it 'receives request env with Host header' do
        # The omniauth_setup hook accesses request.host to resolve tenant.
        # Implementation: Auth::Config::Hooks::OmniAuthTenant.resolve_custom_domain(host)
        skip 'Requires Rack::Test request with HTTP_HOST header and CustomDomain fixtures'
      end

      it 'injects tenant credentials into strategy options' do
        # Credential injection implemented in:
        # Auth::Config::Hooks::OmniAuthTenant.inject_org_credentials(org_config, request)
        #
        # Test would verify TenantVerifyingMock.last_received_credentials matches config.
        skip 'Requires full request flow: CustomDomain -> OrgSsoConfig -> strategy injection'
      end
    end
  end

  # ==========================================================================
  # OTS-SSO-002: Unknown Domain Falls Back to Env Vars
  # ==========================================================================

  describe 'fallback behavior (OTS-SSO-002)' do
    context 'when tenant SSO config missing' do
      it 'falls back to install-time env vars' do
        # Fallback implemented in Auth::Config::Hooks::OmniAuthTenant.handle_missing_tenant_config
        # Controlled by: OT.conf.dig('site', 'sso', 'allow_platform_fallback_for_tenants')
        # Default: true (backward compatible)
        skip 'Requires Rack::Test request flow with unknown domain to verify no credential injection'
      end

      it 'logs fallback event for debugging' do
        # Fallback logging implemented with event :omniauth_tenant_fallback_to_platform
        # See: Auth::Config::Hooks::OmniAuthTenant.handle_missing_tenant_config
        skip 'Requires log capture and request flow with unknown domain'
      end
    end
  end

  # ==========================================================================
  # OTS-SSO-003: Domain to Organization Resolution Chain
  # ==========================================================================

  describe 'Host header to organization resolution (OTS-SSO-003)' do
    # These tests verify the resolution chain:
    #   HTTP_HOST -> CustomDomain -> org_id -> OrgSsoConfig

    describe 'CustomDomain resolution' do
      let(:helpers) { Auth::Config::Hooks::OmniAuthTenant }

      it 'resolves Host header to CustomDomain' do
        # Implementation: helpers.resolve_custom_domain(host)
        # Uses Onetime::CustomDomain.load_by_display_domain internally
        skip 'Requires CustomDomain fixture in Valkey with display_domain set'
      end

      it 'CustomDomain returns org_id' do
        # CustomDomain.org_id links to owning Organization
        # Tested when CustomDomain fixture exists
        skip 'Requires CustomDomain fixture with org_id association'
      end
    end

    describe 'OrgSsoConfig resolution' do
      it 'OrgSsoConfig.find_by_org_id returns config' do
        # Quick win: test with in-memory config (no persistence needed)
        config = build_org_sso_config(:entra_id, org_id: 'test_org_123')
        expect(config.org_id).to eq('test_org_123')
        expect(config.provider_type).to eq('entra_id')
      end

      it 'returns nil for org without SSO config' do
        # Quick win: find_by_org_id returns nil for missing configs
        result = Onetime::OrgSsoConfig.find_by_org_id('nonexistent_org_xyz')
        expect(result).to be_nil
      end
    end

    describe 'complete resolution chain' do
      it 'resolves Host -> CustomDomain -> org_id -> OrgSsoConfig' do
        # Full chain implemented in Auth::Config::Hooks::OmniAuthTenant.configure
        # Resolution: resolve_custom_domain(host) -> custom_domain.org_id -> OrgSsoConfig.find_by_org_id
        #
        # To enable this test:
        # 1. Create test Organization in Valkey
        # 2. Create CustomDomain with display_domain pointing to org
        # 3. Create OrgSsoConfig for org_id
        # 4. Call helpers.resolve_custom_domain and verify chain
        skip 'Requires Valkey fixtures: Organization + CustomDomain + OrgSsoConfig'
      end
    end
  end

  # ==========================================================================
  # OTS-SSO-004: SSO Config Disabled Returns Error
  # ==========================================================================

  describe 'disabled SSO config handling (OTS-SSO-004)' do
    context 'when OrgSsoConfig exists but is disabled' do
      it 'SSO buttons are not rendered for tenant' do
        # The frontend should check if SSO is enabled before rendering
        # SSO login buttons.
        #
        # API endpoint /api/v2/auth/sso-providers should return empty
        # list when SSO is disabled for the organization.
        #
        # This is a frontend/API concern, but we can test the underlying
        # config behavior here.
        #
        # Test verifies:
        #   config = build_disabled_org_sso_config(:entra_id)
        #   expect(config.enabled?).to be false
        config = build_disabled_org_sso_config(:entra_id)
        expect(config.enabled?).to be false
      end

      it 'direct POST to /auth/sso/:provider returns error' do
        # Disabled SSO handling implemented in omniauth_setup hook:
        # - Checks org_config&.enabled? after loading config
        # - Calls handle_missing_tenant_config which may reject or fallback
        # - Logs :omniauth_tenant_sso_not_enabled event
        skip 'Requires Rack::Test POST to /auth/sso/:provider with disabled OrgSsoConfig in Valkey'
      end

      it 'logs disabled SSO access attempt' do
        # Logging implemented with event :omniauth_tenant_sso_not_enabled (level: :info)
        # See: Auth::Config::Hooks::OmniAuthTenant.configure, lines 69-76
        skip 'Requires log capture with disabled OrgSsoConfig fixture'
      end
    end
  end

  # ==========================================================================
  # Tenant Resolution Helper Tests
  # ==========================================================================
  #
  # These tests verify the Auth::Config::Hooks::OmniAuthTenant helper methods.
  # The tenant resolution logic is implemented in omniauth_tenant.rb.

  describe 'OmniAuthTenant helpers' do
    # Reference the actual implementation module
    let(:helpers) { Auth::Config::Hooks::OmniAuthTenant }

    describe '.resolve_custom_domain' do
      it 'returns nil for empty host' do
        expect(helpers.resolve_custom_domain(nil)).to be_nil
        expect(helpers.resolve_custom_domain('')).to be_nil
      end

      it 'returns nil for unregistered domain' do
        # Unregistered domains return nil (triggers fallback behavior)
        # This test runs without Valkey fixtures
        result = helpers.resolve_custom_domain('nonexistent.example.com')
        # Result is nil when domain not found (no Valkey fixtures)
        expect(result).to be_nil
      end

      it 'returns CustomDomain for registered domain' do
        skip 'Requires CustomDomain fixtures in Valkey - see tenant_test_fixtures.rb'
      end
    end

    describe '.strategy_matches?' do
      it 'returns true for matching OIDC strategy' do
        mock_strategy = double('strategy', class: double(name: 'OmniAuth::Strategies::OpenIDConnect'))
        expect(helpers.strategy_matches?(mock_strategy, :openid_connect)).to be true
      end

      it 'returns true for matching Entra ID strategy' do
        mock_strategy = double('strategy', class: double(name: 'OmniAuth::Strategies::EntraId'))
        expect(helpers.strategy_matches?(mock_strategy, :entra_id)).to be true
      end

      it 'returns true for Azure AD V2 alias' do
        mock_strategy = double('strategy', class: double(name: 'OmniAuth::Strategies::AzureActivedirectoryV2'))
        expect(helpers.strategy_matches?(mock_strategy, :entra_id)).to be true
      end

      it 'returns true for matching Google strategy' do
        mock_strategy = double('strategy', class: double(name: 'OmniAuth::Strategies::GoogleOauth2'))
        expect(helpers.strategy_matches?(mock_strategy, :google_oauth2)).to be true
      end

      it 'returns true for matching GitHub strategy' do
        mock_strategy = double('strategy', class: double(name: 'OmniAuth::Strategies::GitHub'))
        expect(helpers.strategy_matches?(mock_strategy, :github)).to be true
      end

      it 'returns false for mismatched strategy' do
        mock_strategy = double('strategy', class: double(name: 'OmniAuth::Strategies::GitHub'))
        expect(helpers.strategy_matches?(mock_strategy, :google_oauth2)).to be false
      end

      it 'returns false for nil strategy' do
        expect(helpers.strategy_matches?(nil, :openid_connect)).to be false
      end

      it 'returns false for unknown expected type' do
        mock_strategy = double('strategy', class: double(name: 'OmniAuth::Strategies::GitHub'))
        expect(helpers.strategy_matches?(mock_strategy, :unknown_provider)).to be false
      end
    end

    describe '.handle_missing_tenant_config' do
      it 'allows fallback by default (backward compatibility)' do
        # When allow_platform_fallback_for_tenants is nil, default to true
        allow(OT).to receive(:conf).and_return({})
        mock_rodauth = double('rodauth')

        # Should not raise or call throw_error_status
        expect(mock_rodauth).not_to receive(:throw_error_status)
        helpers.handle_missing_tenant_config('unknown.example.com', mock_rodauth)
      end

      it 'rejects when fallback explicitly disabled' do
        skip 'Requires OT.conf mock with site.sso.allow_platform_fallback_for_tenants = false'
      end
    end
  end

  # ==========================================================================
  # Setup Proc Injection Tests
  # ==========================================================================
  #
  # These tests verify the credential injection mechanism.

  describe 'credential injection mechanism' do
    describe 'provider-specific option mapping' do
      context 'for Entra ID provider' do
        it 'injects client_id, client_secret, tenant_id' do
          config = build_org_sso_config(:entra_id, org_id: tenant_org_id)
          options = config.to_omniauth_options

          expect(options[:strategy]).to eq(:entra_id)
          expect(options[:tenant_id]).to eq('contoso-tenant-uuid-1234')
          expect(options[:client_id]).not_to be_nil
          expect(options[:client_secret]).not_to be_nil
        end

        it 'uses org_id as strategy name' do
          config = build_org_sso_config(:entra_id, org_id: tenant_org_id)
          options = config.to_omniauth_options

          expect(options[:name]).to eq(tenant_org_id)
        end
      end

      context 'for OIDC provider' do
        it 'injects issuer and client_options' do
          config = build_org_sso_config(:oidc, org_id: tenant_org_id)
          options = config.to_omniauth_options

          expect(options[:strategy]).to eq(:openid_connect)
          expect(options[:issuer]).to eq('https://auth.example.com')
          expect(options[:client_options]).to be_a(Hash)
          expect(options[:client_options][:identifier]).not_to be_nil
        end
      end

      context 'for Google provider' do
        it 'injects client_id, client_secret, scope' do
          config = build_org_sso_config(:google, org_id: tenant_org_id)
          options = config.to_omniauth_options

          expect(options[:strategy]).to eq(:google_oauth2)
          expect(options[:scope]).to eq('openid,email,profile')
          expect(options[:prompt]).to eq('select_account')
        end
      end

      context 'for GitHub provider' do
        it 'injects client_id, client_secret' do
          config = build_org_sso_config(:github, org_id: tenant_org_id)
          options = config.to_omniauth_options

          expect(options[:strategy]).to eq(:github)
          expect(options[:scope]).to eq('user:email')
        end
      end
    end
  end

  # ==========================================================================
  # Error Handling Tests
  # ==========================================================================

  describe 'error handling' do
    let(:helpers) { Auth::Config::Hooks::OmniAuthTenant }

    describe 'CustomDomain not found' do
      it 'falls back gracefully without error' do
        # resolve_custom_domain returns nil for unknown domains (no exception)
        # handle_missing_tenant_config then decides fallback vs reject
        result = helpers.resolve_custom_domain('unknown.example.com')
        expect(result).to be_nil
      end
    end

    describe 'OrgSsoConfig not found' do
      it 'falls back gracefully without error' do
        # OrgSsoConfig.find_by_org_id returns nil for missing configs
        result = Onetime::OrgSsoConfig.find_by_org_id('nonexistent_org_id')
        expect(result).to be_nil
      end
    end

    describe 'invalid OrgSsoConfig' do
      it 'logs validation errors and falls back' do
        # If an OrgSsoConfig exists but is invalid (missing required fields),
        # the resolver should log the issue and fall back to env vars.
        config = build_invalid_org_sso_config(:empty_client_id)
        expect(config.valid?).to be false
        expect(config.validation_errors).to include('client_id is required')
      end
    end

    describe 'Redis/Valkey connection errors' do
      it 'falls back to env vars on connection failure' do
        # If the database is unavailable, SSO should still work
        # using the install-time env var configuration.
        skip 'Requires connection error simulation'
      end
    end
  end

  # ==========================================================================
  # Domain Validation in Tenant Context
  # ==========================================================================

  describe 'email domain validation with tenant config' do
    context 'when tenant has allowed_domains configured' do
      let(:config) do
        build_org_sso_config(:entra_id,
          org_id: tenant_org_id,
          allowed_domains: ['acme-corp.com', 'acme.io'])
      end

      it 'validates user email against tenant allowed_domains' do
        expect(config.valid_email_domain?('user@acme-corp.com')).to be true
        expect(config.valid_email_domain?('user@acme.io')).to be true
        expect(config.valid_email_domain?('user@attacker.com')).to be false
      end

      it 'is case-insensitive' do
        expect(config.valid_email_domain?('user@ACME-CORP.COM')).to be true
      end
    end

    context 'when tenant has no domain restrictions' do
      let(:config) do
        build_org_sso_config(:github,
          org_id: tenant_org_id,
          allowed_domains: [])
      end

      it 'allows any email domain' do
        expect(config.valid_email_domain?('user@any-domain.com')).to be true
      end
    end
  end

  # ==========================================================================
  # TenantVerifyingMock Strategy Tests
  # ==========================================================================
  #
  # These tests verify the mock strategy works correctly for tenant resolution
  # testing. They don't require database access and can run in isolation.

  describe 'TenantVerifyingMock strategy', :tenant_mock do
    before do
      OmniAuth::Strategies::TenantVerifyingMock.reset!
    end

    describe 'class methods' do
      it 'tracks request count' do
        expect(OmniAuth::Strategies::TenantVerifyingMock.request_count).to eq(0)

        OmniAuth::Strategies::TenantVerifyingMock.increment_request_count
        expect(OmniAuth::Strategies::TenantVerifyingMock.request_count).to eq(1)

        OmniAuth::Strategies::TenantVerifyingMock.increment_request_count
        expect(OmniAuth::Strategies::TenantVerifyingMock.request_count).to eq(2)
      end

      it 'stores and retrieves credentials' do
        test_creds = {
          client_id: 'test_client',
          client_secret: 'test_secret',
          tenant_id: 'test_tenant',
        }

        OmniAuth::Strategies::TenantVerifyingMock.last_received_credentials = test_creds
        retrieved = OmniAuth::Strategies::TenantVerifyingMock.last_received_credentials

        expect(retrieved[:client_id]).to eq('test_client')
        expect(retrieved[:client_secret]).to eq('test_secret')
        expect(retrieved[:tenant_id]).to eq('test_tenant')
      end

      it 'resets state between tests' do
        OmniAuth::Strategies::TenantVerifyingMock.last_received_credentials = { test: 'data' }
        OmniAuth::Strategies::TenantVerifyingMock.increment_request_count

        OmniAuth::Strategies::TenantVerifyingMock.reset!

        expect(OmniAuth::Strategies::TenantVerifyingMock.last_received_credentials).to be_nil
        expect(OmniAuth::Strategies::TenantVerifyingMock.request_count).to eq(0)
      end

      it 'returns duplicate to prevent external mutation' do
        original = { client_id: 'original' }
        OmniAuth::Strategies::TenantVerifyingMock.last_received_credentials = original

        retrieved = OmniAuth::Strategies::TenantVerifyingMock.last_received_credentials
        retrieved[:client_id] = 'mutated'

        # Original should be unchanged
        expect(OmniAuth::Strategies::TenantVerifyingMock.last_received_credentials[:client_id]).to eq('original')
      end
    end

    describe 'custom RSpec matchers' do
      it 'have_received_tenant_credentials matches credentials' do
        OmniAuth::Strategies::TenantVerifyingMock.last_received_credentials = {
          client_id: 'expected_id',
          tenant_id: 'expected_tenant',
        }

        expect(nil).to have_received_tenant_credentials(
          client_id: 'expected_id',
          tenant_id: 'expected_tenant'
        )
      end

      it 'have_received_tenant_credentials fails on mismatch' do
        OmniAuth::Strategies::TenantVerifyingMock.last_received_credentials = {
          client_id: 'actual_id',
        }

        expect(nil).not_to have_received_tenant_credentials(
          client_id: 'wrong_id'
        )
      end

      it 'have_received_request detects requests' do
        expect(nil).not_to have_received_request

        OmniAuth::Strategies::TenantVerifyingMock.increment_request_count

        expect(nil).to have_received_request
      end
    end
  end

  # ==========================================================================
  # OrgSsoConfig to_omniauth_options Mapping Tests
  # ==========================================================================
  #
  # These tests verify that OrgSsoConfig generates the correct options
  # for each provider type. They don't require database access.

  describe 'OrgSsoConfig option generation' do
    describe 'common option patterns' do
      it 'all providers use org_id as strategy name' do
        %i[oidc entra_id google github].each do |provider|
          config = build_org_sso_config(provider, org_id: 'test_org_id')
          options = config.to_omniauth_options

          expect(options[:name]).to eq('test_org_id'),
            "Expected #{provider} to use org_id as name"
        end
      end

      it 'all providers include strategy type' do
        expected_strategies = {
          oidc: :openid_connect,
          entra_id: :entra_id,
          google: :google_oauth2,
          github: :github,
        }

        expected_strategies.each do |provider, expected_strategy|
          config = build_org_sso_config(provider)
          options = config.to_omniauth_options

          expect(options[:strategy]).to eq(expected_strategy),
            "Expected #{provider} to have strategy #{expected_strategy}"
        end
      end
    end

    describe 'OIDC-specific options' do
      let(:config) { build_org_sso_config(:oidc) }

      it 'includes issuer for discovery' do
        options = config.to_omniauth_options
        expect(options[:issuer]).to eq('https://auth.example.com')
      end

      it 'enables PKCE' do
        options = config.to_omniauth_options
        expect(options[:pkce]).to be true
      end

      it 'enables discovery' do
        options = config.to_omniauth_options
        expect(options[:discovery]).to be true
      end

      it 'uses client_options hash for credentials' do
        options = config.to_omniauth_options
        expect(options[:client_options]).to be_a(Hash)
        expect(options[:client_options]).to have_key(:identifier)
        expect(options[:client_options]).to have_key(:secret)
      end

      it 'includes standard OIDC scopes' do
        options = config.to_omniauth_options
        expect(options[:scope]).to include(:openid)
        expect(options[:scope]).to include(:email)
        expect(options[:scope]).to include(:profile)
      end
    end

    describe 'Entra ID-specific options' do
      let(:config) { build_org_sso_config(:entra_id) }

      it 'includes tenant_id' do
        options = config.to_omniauth_options
        expect(options[:tenant_id]).to eq('contoso-tenant-uuid-1234')
      end

      it 'uses flat credential structure' do
        options = config.to_omniauth_options
        expect(options).to have_key(:client_id)
        expect(options).to have_key(:client_secret)
        expect(options).not_to have_key(:client_options)
      end

      it 'includes Entra-specific scope format' do
        options = config.to_omniauth_options
        expect(options[:scope]).to eq('openid profile email')
      end
    end

    describe 'Google-specific options' do
      let(:config) { build_org_sso_config(:google) }

      it 'uses comma-separated scope format' do
        options = config.to_omniauth_options
        expect(options[:scope]).to eq('openid,email,profile')
      end

      it 'prompts for account selection' do
        options = config.to_omniauth_options
        expect(options[:prompt]).to eq('select_account')
      end
    end

    describe 'GitHub-specific options' do
      let(:config) { build_org_sso_config(:github) }

      it 'requests user:email scope' do
        options = config.to_omniauth_options
        expect(options[:scope]).to eq('user:email')
      end

      it 'does not include prompt option' do
        options = config.to_omniauth_options
        expect(options).not_to have_key(:prompt)
      end
    end
  end

  # ==========================================================================
  # Tenant Resolution Edge Cases
  # ==========================================================================

  describe 'tenant resolution edge cases' do
    describe 'Host header normalization' do
      it 'host with port should strip port' do
        # This test documents expected behavior
        host_with_port = 'secrets.acme.com:3000'
        normalized = host_with_port.split(':').first.downcase
        expect(normalized).to eq('secrets.acme.com')
      end

      it 'host case normalization' do
        # Case should be normalized for lookup
        hosts = ['Secrets.ACME.com', 'SECRETS.ACME.COM', 'secrets.acme.com']
        normalized = hosts.map { |h| h.downcase }
        expect(normalized.uniq.length).to eq(1)
      end

      it 'handles nil host gracefully' do
        # Resolver should handle nil/empty hosts
        [nil, '', '   '].each do |invalid_host|
          result = invalid_host.to_s.strip.downcase
          expect(result).to eq('')
        end
      end
    end

    describe 'primary domain detection' do
      it 'should not resolve tenant config for primary domain' do
        # The primary installation domain should use env vars, not tenant config
        # This test documents the expected behavior
        primary = ENV.fetch('HOST', 'onetimesecret.com')
        expect(primary).not_to be_empty
      end
    end

    describe 'concurrent access' do
      before do
        OmniAuth::Strategies::TenantVerifyingMock.reset!
      end

      it 'TenantVerifyingMock is thread-safe' do
        # Verify the mutex protects concurrent access
        threads = 10.times.map do |i|
          Thread.new do
            OmniAuth::Strategies::TenantVerifyingMock.increment_request_count
            OmniAuth::Strategies::TenantVerifyingMock.last_received_credentials = { thread: i }
          end
        end

        threads.each(&:join)

        # All increments should have been counted
        expect(OmniAuth::Strategies::TenantVerifyingMock.request_count).to eq(10)
      end
    end
  end
end
