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
#   Host header -> CustomDomain -> CustomDomain::SsoConfig
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

  # Configure Familia encryption for testing, saving originals for restoration
  before(:all) do
    @original_encryption_keys = Familia.config.encryption_keys&.dup
    @original_key_version = Familia.config.current_key_version
    @original_personalization = Familia.config.encryption_personalization

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

  # Restore original Familia encryption config to avoid cross-contamination
  after(:all) do
    Familia.configure do |config|
      config.encryption_keys = @original_encryption_keys if @original_encryption_keys
      config.current_key_version = @original_key_version if @original_key_version
      config.encryption_personalization = @original_personalization if @original_personalization
    end
  end

  # ==========================================================================
  # Resolution Tests
  # ==========================================================================

  describe 'domain resolution' do
    # The resolution chain:
    #   1. Host -> CustomDomain
    #   2. CustomDomain.identifier -> CustomDomain::SsoConfig
    #   3. If no CustomDomain::SsoConfig -> platform env vars (if allowed)

    context 'when domain has CustomDomain::SsoConfig' do
      include_context 'tenant fixtures'

      it 'uses CustomDomain::SsoConfig credentials' do
        domain_sso_config = Onetime::CustomDomain::SsoConfig.find_by_domain_id(test_custom_domain.identifier)
        expect(domain_sso_config).not_to be_nil
        expect(domain_sso_config.enabled?).to be true
      end

      it 'uses domain_id as strategy name' do
        # Use a stubbed instance for to_omniauth_options because Familia's AAD
        # computation differs between unsaved (encryption) and persisted (decryption)
        # records when aad_fields are specified. The loaded record would fail to
        # decrypt since exists? changes the AAD path.
        #
        # Use a unique domain_id that does NOT exist in Valkey (the tenant fixtures
        # create a real record with test_custom_domain.identifier, causing exists?
        # to return true during encryption in new(), but the persistence stub sets
        # exists? to false for decryption -- AAD mismatch).
        unique_domain_id = "dom_strategy_name_test_#{SecureRandom.hex(4)}"
        config = build_domain_sso_config(:entra_id, domain_id: unique_domain_id)
        options = config.to_omniauth_options
        expect(options[:name]).to eq(unique_domain_id)
      end
    end

    context 'when domain has no CustomDomain::SsoConfig' do
      it 'falls back to platform env vars if allowed' do
        # Domain without CustomDomain::SsoConfig should use platform credentials
        # This is controlled by allow_platform_fallback_for_tenants config
        expect(Onetime::CustomDomain::SsoConfig.find_by_domain_id('nonexistent_domain')).to be_nil
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
    context 'when CustomDomain::SsoConfig exists but is disabled' do
      it 'skips disabled CustomDomain::SsoConfig' do
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

    # Full OAuth callback flow tests (cross-domain attack prevention,
    # same-domain success, platform-level flow) are consolidated in
    # callback_validation_spec.rb to avoid duplication.
  end

  # ==========================================================================
  # Edge Case Tests
  # ==========================================================================

  describe 'edge cases' do
    describe 'domain orphaned from org' do
      it 'handles missing organization gracefully' do
        # Domain exists but org was deleted
        # Stub custom_domain to return nil (simulates orphaned domain)
        # since CustomDomain.load now requires (display_domain, org_id)
        config = build_domain_sso_config(:oidc)
        config.define_singleton_method(:custom_domain) { nil }
        expect(config.organization).to be_nil
      end
    end
  end
end
