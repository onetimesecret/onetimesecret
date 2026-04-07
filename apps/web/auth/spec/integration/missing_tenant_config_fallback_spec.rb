# apps/web/auth/spec/integration/missing_tenant_config_fallback_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration Tests for handle_missing_tenant_config Fallback Policy
# =============================================================================
#
# Issue: #2786 - Per-domain SSO configuration
# Issue: #2918 - SSO platform fallback config moved to auth.defaults.yaml
#
# Tests the fallback policy when a custom domain has no CustomDomain::SsoConfig
# (or has a disabled one). The behavior is controlled by:
#   Onetime.auth_config.allow_platform_fallback_for_tenants?
#
# As of #2918, this setting lives in auth config (full.sso section) and
# defaults to false (deny fallback). Previously it lived in site config
# under site.sso and defaulted to true when absent.
#
# Gap covered:
#   - Custom domain, no CustomDomain::SsoConfig, fallback allowed -> proceeds
#   - Custom domain, no CustomDomain::SsoConfig, fallback denied -> 403
#   - Custom domain, disabled CustomDomain::SsoConfig, fallback allowed -> proceeds
#   - Custom domain, disabled CustomDomain::SsoConfig, fallback denied -> 403
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec apps/web/auth/spec/integration/missing_tenant_config_fallback_spec.rb
#
# =============================================================================

require_relative '../spec_helper'
require_relative '../support/tenant_test_fixtures'
require_relative '../support/domain_sso_test_fixtures'
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

RSpec.describe 'handle_missing_tenant_config Fallback Policy', type: :integration do
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
      config.encryption_personalization = 'MissingTenantConfigFallbackTest'
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

  let(:helpers) { Auth::Config::Hooks::OmniAuthTenant }

  # Mock Rodauth instance that captures throw_error_status calls
  # instead of actually halting the request.
  class MockRodauth
    attr_reader :error_status, :error_field, :error_message

    def throw_error_status(status, field, message)
      @error_status = status
      @error_field = field
      @error_message = message
      throw :error, { status: status, field: field, message: message }
    end

    def error_thrown?
      !@error_status.nil?
    end
  end

  # ==========================================================================
  # No CustomDomain::SsoConfig Scenarios
  # ==========================================================================

  describe 'custom domain with no CustomDomain::SsoConfig' do
    let(:host) { 'secrets.no-sso-config.example.com' }

    context 'when fallback is allowed (true)' do
      before do
        allow(Onetime.auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
      end

      it 'returns without raising (proceeds with platform defaults)' do
        mock_rodauth = MockRodauth.new

        # Should return normally, no error thrown
        result = catch(:error) do
          helpers.handle_missing_tenant_config(host, mock_rodauth)
          :no_error
        end

        expect(result).to eq(:no_error),
          "Expected handle_missing_tenant_config to return normally when fallback is allowed"
        expect(mock_rodauth.error_thrown?).to be(false)
      end
    end

    context 'when fallback is denied (false) — the default' do
      before do
        allow(Onetime.auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(false)
      end

      it 'raises 403 sso_not_configured' do
        mock_rodauth = MockRodauth.new

        result = catch(:error) do
          helpers.handle_missing_tenant_config(host, mock_rodauth)
          :no_error
        end

        expect(result).not_to eq(:no_error),
          "Expected handle_missing_tenant_config to throw an error when fallback is denied"
        expect(result[:status]).to eq(403)
        expect(result[:field]).to eq('sso_not_configured')
        expect(result[:message]).to eq('SSO not configured for this domain')
      end
    end

    context 'when auth_config returns default (no stub, exercises real accessor)' do
      # Since auth.defaults.yaml sets allow_platform_fallback_for_tenants to false
      # by default (ENV['SSO_ALLOW_PLATFORM_FALLBACK'] is not set in test), the
      # real accessor should return false, denying fallback.
      it 'denies fallback by default (secure default from #2918)' do
        mock_rodauth = MockRodauth.new

        result = catch(:error) do
          helpers.handle_missing_tenant_config(host, mock_rodauth)
          :no_error
        end

        expect(result).not_to eq(:no_error),
          "Default config should deny fallback (allow_platform_fallback_for_tenants defaults to false)"
        expect(result[:status]).to eq(403)
        expect(result[:field]).to eq('sso_not_configured')
      end
    end
  end

  # ==========================================================================
  # Disabled CustomDomain::SsoConfig Scenarios
  # ==========================================================================
  #
  # When a CustomDomain::SsoConfig exists but is disabled (enabled: false), the
  # omniauth_setup hook calls handle_missing_tenant_config. These tests
  # verify that the same fallback policy applies.
  #

  describe 'custom domain with disabled CustomDomain::SsoConfig' do
    include_context 'tenant fixtures'

    # Override the test_sso_config to be disabled
    let!(:test_sso_config) do
      Onetime::CustomDomain::SsoConfig.create!(
        domain_id: test_custom_domain.identifier,
        provider_type: 'entra_id',
        display_name: 'Disabled Entra ID',
        tenant_id: "tenant-#{test_run_id}",
        client_id: "client-#{test_run_id}",
        client_secret: "secret-#{test_run_id}",
        enabled: false
      )
    end

    it 'confirms the CustomDomain::SsoConfig is disabled' do
      config = Onetime::CustomDomain::SsoConfig.find_by_domain_id(test_custom_domain.identifier)
      expect(config).not_to be_nil
      expect(config.enabled?).to be(false),
        "Test precondition: CustomDomain::SsoConfig should be disabled"
    end

    context 'when fallback is allowed' do
      before do
        allow(Onetime.auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
      end

      it 'proceeds with platform defaults (does not raise)' do
        mock_rodauth = MockRodauth.new

        # The hook checks sso_config&.enabled? -> false, then calls
        # handle_missing_tenant_config, which should allow fallback
        result = catch(:error) do
          helpers.handle_missing_tenant_config(tenant_domain, mock_rodauth)
          :no_error
        end

        expect(result).to eq(:no_error),
          "Disabled config with fallback allowed should proceed with platform defaults"
      end
    end

    context 'when fallback is denied' do
      before do
        allow(Onetime.auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(false)
      end

      it 'raises 403 sso_not_configured' do
        mock_rodauth = MockRodauth.new

        result = catch(:error) do
          helpers.handle_missing_tenant_config(tenant_domain, mock_rodauth)
          :no_error
        end

        expect(result).not_to eq(:no_error),
          "Disabled config with fallback denied should raise 403"
        expect(result[:status]).to eq(403)
        expect(result[:field]).to eq('sso_not_configured')
      end
    end
  end

  # ==========================================================================
  # Edge Cases
  # ==========================================================================

  describe 'edge cases' do
    context 'when sso section is missing from auth config (legacy/broken config)' do
      it 'denies fallback (secure default)' do
        mock_rodauth = MockRodauth.new

        # When sso_config returns the legacy fallback hash (no full.sso section),
        # allow_platform_fallback_for_tenants won't be present, so the accessor
        # returns false. Stub to simulate this explicitly.
        allow(Onetime.auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(false)

        result = catch(:error) do
          helpers.handle_missing_tenant_config('orphan.example.com', mock_rodauth)
          :no_error
        end

        expect(result).not_to eq(:no_error),
          "Missing sso config section should deny fallback (secure default)"
        expect(result[:status]).to eq(403)
      end
    end

    context 'when allow_platform_fallback_for_tenants? accessor behavior with nil sso section' do
      it 'returns false when full.sso section is absent (legacy fallback hash)' do
        # Verify the accessor itself handles missing sso config gracefully.
        # When full['sso'] is nil, sso_config returns a legacy fallback hash
        # that does not contain allow_platform_fallback_for_tenants, so
        # the == true check returns false.
        auth_config = Onetime.auth_config
        original_full = auth_config.send(:full)

        # Temporarily remove the sso section to test accessor resilience
        allow(auth_config).to receive(:full).and_return(original_full.merge('sso' => nil))

        expect(auth_config.allow_platform_fallback_for_tenants?).to be(false)
      end
    end

    context 'when allow_platform_fallback_for_tenants is string "true" instead of boolean' do
      it 'returns false (strict boolean check)' do
        auth_config = Onetime.auth_config
        original_full = auth_config.send(:full)

        # Simulate a misconfiguration where the value is a string not a boolean
        allow(auth_config).to receive(:full).and_return(
          original_full.merge('sso' => { 'allow_platform_fallback_for_tenants' => 'true' })
        )

        expect(auth_config.allow_platform_fallback_for_tenants?).to be(false),
          "String 'true' should not satisfy == true check (strict boolean)"
      end
    end
  end
end
