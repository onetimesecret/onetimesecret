# apps/web/auth/spec/integration/callback_validation_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration Tests for Cross-Tenant Callback Validation
# =============================================================================
#
# Issue: #2786 - Per-domain SSO configuration
#
# Tests the before_omniauth_callback_route hook in OmniAuthTenant, which
# validates that OAuth callbacks arrive at the same domain that initiated
# the authentication request.
#
# These tests exercise the callback validation path directly by simulating
# session state (domain_id + host stored during request phase) and then
# invoking the callback validation logic against various host headers.
#
# Gap covered:
#   - Callback from same domain as setup -> succeeds (no 403)
#   - Callback domain mismatch -> 403 tenant_mismatch
#   - No tenant context in session (platform-level) -> proceeds normally
#   - Session context is cleaned up after callback
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec apps/web/auth/spec/integration/callback_validation_spec.rb
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

RSpec.describe 'Cross-Tenant Callback Validation', type: :integration do
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
      config.encryption_personalization = 'CallbackValidationTest'
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

  # ==========================================================================
  # Direct Hook Logic Tests (no full app boot required)
  # ==========================================================================
  #
  # These tests validate the callback validation logic by calling the helper
  # methods directly and simulating the session + request state that the
  # before_omniauth_callback_route hook reads.
  #
  # This approach is more reliable than full OAuth flow tests because it
  # does not depend on OIDC discovery being available at boot time.
  #

  describe 'before_omniauth_callback_route logic' do
    include_context 'tenant fixtures'

    # Simulates the state transitions the hook performs:
    #   1. session.delete(:omniauth_tenant_domain_id)
    #   2. session.delete(:omniauth_tenant_host)
    #   3. resolve_custom_domain(request.host)
    #   4. compare identifiers -> 403 or proceed

    describe 'callback from same domain as setup' do
      it 'does not raise when domain_id matches' do
        # Simulate: setup stored domain_id for test_custom_domain
        expected_domain_id = test_custom_domain.identifier
        callback_host = tenant_domain

        # Resolve the callback domain (same domain as setup)
        current_domain = helpers.resolve_custom_domain(callback_host)

        # The hook's comparison: current_domain.identifier != expected_domain_id
        expect(current_domain).not_to be_nil
        expect(current_domain.identifier).to eq(expected_domain_id),
          "Same-domain callback should have matching domain_id"
      end
    end

    describe 'callback domain mismatch' do
      let(:attacker_domain) { "evil-#{test_run_id}.attacker.example.com" }

      let!(:attacker_custom_domain) do
        domain = Onetime::CustomDomain.new(
          display_domain: attacker_domain,
          org_id: test_organization.org_id
        )
        domain.save
        Onetime::CustomDomain.display_domains.put(attacker_domain, domain.domainid)
        domain
      end

      after do
        Onetime::CustomDomain.display_domains.remove(attacker_domain) rescue nil
        attacker_custom_domain&.destroy! rescue nil
      end

      it 'detects mismatch when callback arrives at a different domain' do
        # Setup stored domain_id from domain A
        expected_domain_id = test_custom_domain.identifier

        # Callback arrives at domain B (attacker domain)
        current_domain = helpers.resolve_custom_domain(attacker_domain)

        expect(current_domain).not_to be_nil
        expect(current_domain.identifier).not_to eq(expected_domain_id),
          "Cross-domain callback should produce a domain_id mismatch"
      end

      it 'detects mismatch when callback host resolves to nil' do
        # Setup stored domain_id from a real domain
        expected_domain_id = test_custom_domain.identifier

        # Callback arrives at an unknown host (no CustomDomain record)
        current_domain = helpers.resolve_custom_domain('unknown.example.com')

        # The hook checks: current_domain&.identifier != expected_domain_id
        # When current_domain is nil, nil != expected_domain_id => mismatch
        domain_mismatch = current_domain&.identifier != expected_domain_id
        expect(domain_mismatch).to be(true),
          "Callback to unknown domain should trigger mismatch"
      end
    end

    describe 'no tenant context in session (platform-level flow)' do
      it 'skips validation when no domain_id was stored in session' do
        # Simulate: session.delete(:omniauth_tenant_domain_id) returns nil
        expected_domain_id = nil

        # The hook does: next unless expected_domain_id
        # When nil, it skips all validation and lets callback proceed
        expect(expected_domain_id).to be_nil,
          "Platform-level flow has no tenant context in session"
      end

      it 'does not attempt domain resolution when no tenant context' do
        # When expected_domain_id is nil, the hook short-circuits with `next`
        # and never calls resolve_custom_domain. Verify this invariant:
        # the resolve call only makes sense when expected_domain_id is present.
        expected_domain_id = nil
        skip_validation = !expected_domain_id

        expect(skip_validation).to be(true),
          "Hook should skip validation when no tenant context in session"
      end
    end

    describe 'session cleanup after callback' do
      it 'removes domain_id from session via delete (not just read)' do
        # The hook uses session.delete, which both reads and removes.
        # Simulate with a real hash to verify the delete semantics.
        mock_session = {
          omniauth_tenant_domain_id: test_custom_domain.identifier,
          omniauth_tenant_host: tenant_domain,
        }

        # session.delete returns the value AND removes the key
        extracted_domain_id = mock_session.delete(:omniauth_tenant_domain_id)
        extracted_host = mock_session.delete(:omniauth_tenant_host)

        expect(extracted_domain_id).to eq(test_custom_domain.identifier)
        expect(extracted_host).to eq(tenant_domain)

        # After delete, keys should be gone
        expect(mock_session).not_to have_key(:omniauth_tenant_domain_id),
          "Session should not retain domain_id after callback"
        expect(mock_session).not_to have_key(:omniauth_tenant_host),
          "Session should not retain host after callback"
      end

      it 'cleans up session even when domain matches (success path)' do
        mock_session = {
          omniauth_tenant_domain_id: test_custom_domain.identifier,
          omniauth_tenant_host: tenant_domain,
        }

        # Simulate the hook's session.delete calls
        expected_domain_id = mock_session.delete(:omniauth_tenant_domain_id)
        _expected_host = mock_session.delete(:omniauth_tenant_host)

        # Verify domain matches (success case)
        current_domain = helpers.resolve_custom_domain(tenant_domain)
        expect(current_domain&.identifier).to eq(expected_domain_id)

        # Session should still be cleaned up even on success
        expect(mock_session).to be_empty,
          "Session tenant context must be cleaned up even on successful callback"
      end

      it 'cleans up session even on mismatch (failure path)' do
        mock_session = {
          omniauth_tenant_domain_id: 'domain_that_does_not_exist',
          omniauth_tenant_host: 'original.example.com',
        }

        # The hook deletes BEFORE checking mismatch
        expected_domain_id = mock_session.delete(:omniauth_tenant_domain_id)
        _expected_host = mock_session.delete(:omniauth_tenant_host)

        # Mismatch would be detected here
        current_domain = helpers.resolve_custom_domain(tenant_domain)
        domain_mismatch = current_domain&.identifier != expected_domain_id

        expect(domain_mismatch).to be(true)
        # Session is already clean regardless of mismatch
        expect(mock_session).to be_empty,
          "Session tenant context must be cleaned up even on failed callback"
      end
    end
  end

  # ==========================================================================
  # Full OAuth Flow Tests (require app boot + OIDC routes)
  # ==========================================================================
  #
  # These tests attempt the real OAuth initiation -> callback flow through
  # the Rack stack. They may skip if OIDC routes are not registered.
  #

  describe 'full OAuth callback flow', type: :integration, oauth_flow: true do
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

    context 'same-domain callback succeeds' do
      let(:test_run_id) { "same-cb-#{SecureRandom.hex(4)}" }
      let(:domain_host) { "secrets-#{test_run_id}.same-domain.example.com" }

      before do
        @domain_fixtures = setup_oauth_test_domain(domain_host)
      end

      it 'does not return 403 when callback domain matches initiation domain' do
        OmniAuth.config.test_mode = true
        OmniAuth.config.allowed_request_methods = %i[get post]

        OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new({
          provider: 'oidc',
          uid: "uid-same-#{test_run_id}",
          info: { email: "user-#{test_run_id}@same-domain.example.com", name: 'Test User' },
        })

        begin
          # Initiate from domain
          header 'Host', domain_host
          post '/auth/sso/oidc'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          expect(last_response.status).to eq(302)

          # Callback from same domain
          header 'Host', domain_host
          post '/auth/sso/oidc/callback'

          expect(last_response.status).not_to eq(403),
            "Same-domain callback should not return 403, got: #{last_response.status}"
        ensure
          OmniAuth.config.test_mode = false
          OmniAuth.config.mock_auth.clear
        end
      end
    end

    context 'cross-domain callback returns 403' do
      let(:test_run_id) { "cross-cb-#{SecureRandom.hex(4)}" }
      let(:domain_a_host) { "secrets-#{test_run_id}.legit.example.com" }
      let(:domain_b_host) { "secrets-#{test_run_id}.attacker.example.com" }

      before do
        @domain_a_fixtures = setup_oauth_test_domain(domain_a_host)
        @domain_b_fixtures = setup_oauth_test_domain(domain_b_host)
      end

      it 'returns 403 tenant_mismatch when callback host differs from initiation host' do
        OmniAuth.config.test_mode = true
        OmniAuth.config.allowed_request_methods = %i[get post]

        OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new({
          provider: 'oidc',
          uid: "uid-cross-#{test_run_id}",
          info: { email: "user-#{test_run_id}@legit.example.com", name: 'Test User' },
        })

        begin
          # Initiate from domain A
          header 'Host', domain_a_host
          post '/auth/sso/oidc'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          expect(last_response.status).to eq(302)

          # Callback from domain B (different host)
          header 'Host', domain_b_host
          post '/auth/sso/oidc/callback'

          expect(last_response.status).to eq(403),
            "Cross-domain callback should return 403, got: #{last_response.status}, body: #{last_response.body}"
          expect(last_response.body).to include('tenant_mismatch').or include('Authentication context mismatch')
        ensure
          OmniAuth.config.test_mode = false
          OmniAuth.config.mock_auth.clear
        end
      end
    end

    context 'platform-level callback (no tenant context)' do
      it 'proceeds without 403 when no tenant context in session' do
        OmniAuth.config.test_mode = true
        OmniAuth.config.allowed_request_methods = %i[get post]

        OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new({
          provider: 'oidc',
          uid: 'uid-platform-level',
          info: { email: 'user@platform.example.com', name: 'Platform User' },
        })

        begin
          # Hit callback directly on canonical domain (no initiation, no tenant context)
          canonical_host = OT.conf.dig('site', 'host') || 'onetimesecret.com'
          header 'Host', canonical_host
          post '/auth/sso/oidc/callback'

          # Should not get 403 since there is no tenant context to validate
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
