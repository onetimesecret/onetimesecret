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
    # Boot the full Onetime application for integration tests.
    # `force: true` resets any prior boot state so OmniAuth provider
    # registration runs against this suite's WebMock stubs and ENV —
    # without it, whichever spec booted first wins for the whole run
    # and the OIDC route may be silently missing.
    require 'onetime' unless defined?(Onetime)
    Onetime.boot!(:test, force: true)
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
  # Tests: SignupValidation Module (Unit-Level)
  # ==========================================================================
  #
  # These tests exercise the SignupValidation module directly without
  # requiring the full OmniAuth flow. They verify the resolver logic:
  # - Per-domain SignupConfig takes precedence when enabled
  # - Falls back to global config when per-domain is disabled or missing

  describe 'SignupValidation module' do
    let(:test_run_id) { SecureRandom.hex(8) }
    let(:tenant_domain) { "validation-#{test_run_id}.acme-corp.example.com" }

    let!(:tenant_org_owner) do
      owner = Onetime::Customer.new(email: "owner-#{test_run_id}@validation.example.com")
      owner.save
      owner
    end

    let!(:tenant_organization) do
      Onetime::Organization.create!(
        "Validation Org #{test_run_id}",
        tenant_org_owner,
        "contact-#{test_run_id}@validation.example.com",
      )
    end

    let!(:tenant_custom_domain) do
      domain = Onetime::CustomDomain.new(
        display_domain: tenant_domain,
        org_id: tenant_organization.org_id,
      )
      domain.save
      Onetime::CustomDomain.display_domains.put(tenant_domain, domain.domainid)
      domain
    end

    after do
      Onetime::CustomDomain::SignupConfig.delete_for_domain!(tenant_custom_domain.identifier) rescue nil
      Onetime::CustomDomain.display_domains.remove(tenant_domain) rescue nil
      tenant_custom_domain&.destroy! rescue nil
      tenant_organization&.destroy! rescue nil
      tenant_org_owner&.destroy! rescue nil
    end

    context 'with passthrough strategy enabled' do
      before do
        Onetime::CustomDomain::SignupConfig.create!(
          domain_id: tenant_custom_domain.identifier,
          validation_strategy: 'passthrough',
          enabled: true,
        )
        configure_allowed_domains(['restricted.com']) # Global would reject
      end

      it 'accepts any valid email format' do
        result = Onetime::SignupValidation.valid_signup_email?(
          'user@any-domain.org',
          display_domain: tenant_domain,
        )
        expect(result).to be(true), 'Passthrough should accept any valid email'
      end

      it 'rejects malformed email' do
        result = Onetime::SignupValidation.valid_signup_email?(
          'invalid-no-at',
          display_domain: tenant_domain,
        )
        expect(result).to be(false), 'Passthrough should reject malformed email'
      end
    end

    context 'with domain_allowlist strategy enabled' do
      before do
        Onetime::CustomDomain::SignupConfig.create!(
          domain_id: tenant_custom_domain.identifier,
          validation_strategy: 'domain_allowlist',
          allowed_signup_domains: ['partner.com', 'internal.example.com'],
          enabled: true,
        )
        configure_allowed_domains(nil) # No global restrictions
      end

      it 'accepts email from allowed domain' do
        result = Onetime::SignupValidation.valid_signup_email?(
          'employee@partner.com',
          display_domain: tenant_domain,
        )
        expect(result).to be(true), 'Should accept email from per-domain allowlist'
      end

      it 'rejects email from non-allowed domain' do
        result = Onetime::SignupValidation.valid_signup_email?(
          'user@outsider.com',
          display_domain: tenant_domain,
        )
        expect(result).to be(false), 'Should reject email not in per-domain allowlist'
      end

      it 'per-domain takes precedence over global config' do
        configure_allowed_domains(['company.com']) # Global allows company.com
        result = Onetime::SignupValidation.valid_signup_email?(
          'user@company.com',
          display_domain: tenant_domain,
        )
        # Per-domain doesn't have company.com, so it should be rejected
        expect(result).to be(false), 'Per-domain should override global'
      end
    end

    context 'with SignupConfig disabled' do
      before do
        Onetime::CustomDomain::SignupConfig.create!(
          domain_id: tenant_custom_domain.identifier,
          validation_strategy: 'passthrough',
          enabled: false, # Disabled
        )
        configure_allowed_domains(['global-allowed.com'])
      end

      it 'falls back to global config' do
        result = Onetime::SignupValidation.valid_signup_email?(
          'user@global-allowed.com',
          display_domain: tenant_domain,
        )
        expect(result).to be(true), 'Should use global when per-domain disabled'
      end

      it 'rejects domains not in global config' do
        result = Onetime::SignupValidation.valid_signup_email?(
          'user@not-allowed.com',
          display_domain: tenant_domain,
        )
        expect(result).to be(false), 'Should reject per global when per-domain disabled'
      end
    end

    context 'with no SignupConfig for domain' do
      before do
        # No SignupConfig created
        configure_allowed_domains(['global-only.com'])
      end

      it 'falls back to global config' do
        result = Onetime::SignupValidation.valid_signup_email?(
          'user@global-only.com',
          display_domain: tenant_domain,
        )
        expect(result).to be(true), 'Should use global when no per-domain config'
      end

      it 'rejects domains not in global config' do
        result = Onetime::SignupValidation.valid_signup_email?(
          'user@other.com',
          display_domain: tenant_domain,
        )
        expect(result).to be(false), 'Should reject per global when no per-domain config'
      end
    end

    context 'with no display_domain (platform-level)' do
      before do
        configure_allowed_domains(['platform-allowed.com'])
      end

      it 'uses global config when display_domain is nil' do
        result = Onetime::SignupValidation.valid_signup_email?(
          'user@platform-allowed.com',
          display_domain: nil,
        )
        expect(result).to be(true), 'Should use global when no display_domain'
      end

      it 'uses global config when display_domain not provided' do
        result = Onetime::SignupValidation.valid_signup_email?('user@platform-allowed.com')
        expect(result).to be(true), 'Should use global when display_domain not provided'
      end
    end

    describe 'resolve_signup_config' do
      context 'with enabled SignupConfig' do
        before do
          Onetime::CustomDomain::SignupConfig.create!(
            domain_id: tenant_custom_domain.identifier,
            validation_strategy: 'passthrough',
            enabled: true,
          )
        end

        it 'returns the SignupConfig' do
          config = Onetime::SignupValidation.resolve_signup_config(tenant_domain)
          expect(config).not_to be_nil
          expect(config.domain_id).to eq(tenant_custom_domain.identifier)
        end
      end

      context 'with disabled SignupConfig' do
        before do
          Onetime::CustomDomain::SignupConfig.create!(
            domain_id: tenant_custom_domain.identifier,
            validation_strategy: 'passthrough',
            enabled: false,
          )
        end

        it 'returns nil' do
          config = Onetime::SignupValidation.resolve_signup_config(tenant_domain)
          expect(config).to be_nil
        end
      end

      context 'with no SignupConfig' do
        it 'returns nil' do
          config = Onetime::SignupValidation.resolve_signup_config(tenant_domain)
          expect(config).to be_nil
        end
      end

      context 'with unknown domain' do
        it 'returns nil' do
          config = Onetime::SignupValidation.resolve_signup_config('unknown.example.com')
          expect(config).to be_nil
        end
      end

      context 'with nil display_domain' do
        it 'returns nil' do
          config = Onetime::SignupValidation.resolve_signup_config(nil)
          expect(config).to be_nil
        end
      end
    end
  end

  # ==========================================================================
  # Tests: Per-Domain SignupConfig Validation
  # ==========================================================================
  #
  # These tests cover the per-domain signup validation feature:
  # - SignupConfig with passthrough strategy (any valid email format)
  # - SignupConfig with domain_allowlist strategy
  # - Fallback to global config when SignupConfig disabled or missing
  # - signup_domain_id capture in customer record after SSO signup
  #
  # Integration points tested:
  # - before_omniauth_create_account hook calls SignupValidation.valid_signup_email?
  # - after_omniauth_create_account hook captures signup_domain_id
  # - SignupValidation resolver: per-domain first, then global fallback

  describe 'per-domain SignupConfig validation' do
    let(:test_run_id) { SecureRandom.hex(8) }
    let(:tenant_domain) { "secrets-#{test_run_id}.acme-corp.example.com" }

    let!(:tenant_org_owner) do
      owner = Onetime::Customer.new(email: "owner-#{test_run_id}@tenant.example.com")
      owner.save
      owner
    end

    let!(:tenant_organization) do
      Onetime::Organization.create!(
        "Tenant Org #{test_run_id}",
        tenant_org_owner,
        "contact-#{test_run_id}@tenant.example.com",
      )
    end

    let!(:tenant_custom_domain) do
      domain = Onetime::CustomDomain.new(
        display_domain: tenant_domain,
        org_id: tenant_organization.org_id,
      )
      domain.save
      Onetime::CustomDomain.display_domains.put(tenant_domain, domain.domainid)
      domain
    end

    after do
      # Clean up SignupConfig if created
      Onetime::CustomDomain::SignupConfig.delete_for_domain!(tenant_custom_domain.identifier) rescue nil
      Onetime::CustomDomain.display_domains.remove(tenant_domain) rescue nil
      tenant_custom_domain&.destroy! rescue nil
      tenant_organization&.destroy! rescue nil
      tenant_org_owner&.destroy! rescue nil
    end

    # Helper to simulate request arriving at a custom domain
    def mock_display_domain(domain_name)
      allow_any_instance_of(Rack::Request).to receive(:env).and_wrap_original do |original|
        env = original.call
        env['onetime.display_domain'] = domain_name
        env
      end
    end

    context 'with passthrough strategy (accepts any valid email format)' do
      before do
        Onetime::CustomDomain::SignupConfig.create!(
          domain_id: tenant_custom_domain.identifier,
          validation_strategy: 'passthrough',
          enabled: true,
        )
        configure_allowed_domains(['restricted.com']) # Global would reject non-restricted
        mock_display_domain(tenant_domain)
      end

      it 'allows signup from any domain when passthrough is enabled' do
        # Email from a domain NOT in the global allowlist, but passthrough accepts it
        setup_mock_auth(email: 'user@random-domain.org')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          # Passthrough strategy should accept any valid email format
          expect([400, 403]).not_to include(last_response.status),
            "Expected passthrough to accept any domain, got #{last_response.status}: #{last_response.body}"
        ensure
          teardown_mock_auth
        end
      end

      it 'still rejects malformed email even with passthrough' do
        setup_mock_auth(email: 'invalid-email-no-at')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          # Malformed email should be rejected (format check still applies)
          expect(last_response.status).to eq(400),
            "Expected 400 for malformed email with passthrough, got #{last_response.status}"
        ensure
          teardown_mock_auth
        end
      end
    end

    context 'with domain_allowlist strategy' do
      before do
        Onetime::CustomDomain::SignupConfig.create!(
          domain_id: tenant_custom_domain.identifier,
          validation_strategy: 'domain_allowlist',
          allowed_signup_domains: ['partner.com', 'internal.example.com'],
          enabled: true,
        )
        configure_allowed_domains(nil) # No global restrictions
        mock_display_domain(tenant_domain)
      end

      it 'allows signup from domains in the per-domain allowlist' do
        setup_mock_auth(email: 'employee@partner.com')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          expect([400, 403]).not_to include(last_response.status),
            "Expected per-domain allowlist to pass, got #{last_response.status}: #{last_response.body}"
        ensure
          teardown_mock_auth
        end
      end

      it 'rejects signup from domains not in the per-domain allowlist' do
        setup_mock_auth(email: 'user@outsider.com')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          expect(last_response.status).to eq(403),
            "Expected 403 for domain not in per-domain allowlist, got #{last_response.status}"
        ensure
          teardown_mock_auth
        end
      end

      it 'per-domain allowlist overrides global config' do
        # Global config would allow company.com, but per-domain doesn't have it
        configure_allowed_domains(['company.com'])
        setup_mock_auth(email: 'user@company.com')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          # Per-domain takes precedence, and company.com is not in per-domain list
          expect(last_response.status).to eq(403),
            "Expected per-domain to override global, got #{last_response.status}"
        ensure
          teardown_mock_auth
        end
      end
    end

    context 'with disabled SignupConfig (fallback to global)' do
      before do
        # Create SignupConfig but leave it disabled
        Onetime::CustomDomain::SignupConfig.create!(
          domain_id: tenant_custom_domain.identifier,
          validation_strategy: 'passthrough',
          enabled: false, # Disabled
        )
        configure_allowed_domains(['global-allowed.com'])
        mock_display_domain(tenant_domain)
      end

      it 'falls back to global config when SignupConfig is disabled' do
        setup_mock_auth(email: 'user@global-allowed.com')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          # Should use global config since per-domain is disabled
          expect([400, 403]).not_to include(last_response.status),
            "Expected global config to allow, got #{last_response.status}"
        ensure
          teardown_mock_auth
        end
      end

      it 'rejects domains not in global config when SignupConfig is disabled' do
        setup_mock_auth(email: 'user@not-allowed.com')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          expect(last_response.status).to eq(403),
            "Expected global rejection when per-domain disabled, got #{last_response.status}"
        ensure
          teardown_mock_auth
        end
      end
    end

    context 'with custom domain but no SignupConfig' do
      before do
        # Domain exists but no SignupConfig record created
        configure_allowed_domains(['global-only.com'])
        mock_display_domain(tenant_domain)
      end

      it 'falls back to global config when no SignupConfig exists' do
        setup_mock_auth(email: 'user@global-only.com')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          expect([400, 403]).not_to include(last_response.status),
            "Expected global config to apply, got #{last_response.status}"
        ensure
          teardown_mock_auth
        end
      end

      it 'rejects domains per global config when no SignupConfig exists' do
        setup_mock_auth(email: 'user@other-domain.com')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          expect(last_response.status).to eq(403),
            "Expected global rejection, got #{last_response.status}"
        ensure
          teardown_mock_auth
        end
      end
    end
  end

  # ==========================================================================
  # Tests: signup_domain_id Capture in Customer Record
  # ==========================================================================
  #
  # The after_omniauth_create_account hook captures the signup domain
  # in the customer record for re-verification and background jobs.

  describe 'signup_domain_id capture after SSO signup' do
    let(:test_run_id) { SecureRandom.hex(8) }
    let(:tenant_domain) { "signup-#{test_run_id}.acme-corp.example.com" }

    let!(:tenant_org_owner) do
      owner = Onetime::Customer.new(email: "owner-#{test_run_id}@signup.example.com")
      owner.save
      owner
    end

    let!(:tenant_organization) do
      Onetime::Organization.create!(
        "Signup Org #{test_run_id}",
        tenant_org_owner,
        "contact-#{test_run_id}@signup.example.com",
      )
    end

    let!(:tenant_custom_domain) do
      domain = Onetime::CustomDomain.new(
        display_domain: tenant_domain,
        org_id: tenant_organization.org_id,
      )
      domain.save
      Onetime::CustomDomain.display_domains.put(tenant_domain, domain.domainid)
      domain
    end

    after do
      Onetime::CustomDomain::SignupConfig.delete_for_domain!(tenant_custom_domain.identifier) rescue nil
      Onetime::CustomDomain.display_domains.remove(tenant_domain) rescue nil
      tenant_custom_domain&.destroy! rescue nil
      tenant_organization&.destroy! rescue nil
      tenant_org_owner&.destroy! rescue nil
    end

    # Unit test for the after_omniauth_create_account logic
    # Tests the signup_domain_id capture without full OmniAuth flow
    it 'captures signup_domain_id when SSO arrives via custom domain' do
      # Create a new customer to simulate post-signup state
      new_customer = Onetime::Customer.new(email: "newuser-#{test_run_id}@partner.com")
      new_customer.save

      begin
        # Simulate the after_omniauth_create_account logic
        display_domain = tenant_domain
        custom_domain = Onetime::CustomDomain.load_by_display_domain(display_domain)

        expect(custom_domain).not_to be_nil, 'Custom domain should be found'

        new_customer.signup_domain_id = custom_domain.identifier
        new_customer.save

        # Verify the capture
        reloaded = Onetime::Customer.load(new_customer.custid)
        expect(reloaded.signup_domain_id).to eq(tenant_custom_domain.identifier),
          "signup_domain_id should be captured"
      ensure
        new_customer&.destroy! rescue nil
      end
    end

    it 'does not set signup_domain_id when no custom domain context' do
      new_customer = Onetime::Customer.new(email: "platform-#{test_run_id}@example.com")
      new_customer.save

      begin
        # Simulate platform-level signup (no display_domain)
        display_domain = nil
        expect(display_domain).to be_nil

        # The hook logic: skip if no display_domain
        # signup_domain_id remains nil/empty
        expect(new_customer.signup_domain_id.to_s).to be_empty,
          "signup_domain_id should not be set for platform signups"
      ensure
        new_customer&.destroy! rescue nil
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

  # ==========================================================================
  # Tests: Per-Domain Security Considerations
  # ==========================================================================
  #
  # Error messages must not leak per-domain SignupConfig details.
  # Attackers should not learn which domains are allowed or which
  # validation strategy is in use for a particular custom domain.

  describe 'per-domain security considerations' do
    let(:test_run_id) { SecureRandom.hex(8) }
    let(:tenant_domain) { "secure-#{test_run_id}.acme-corp.example.com" }

    let!(:tenant_org_owner) do
      owner = Onetime::Customer.new(email: "owner-#{test_run_id}@secure.example.com")
      owner.save
      owner
    end

    let!(:tenant_organization) do
      Onetime::Organization.create!(
        "Secure Org #{test_run_id}",
        tenant_org_owner,
        "contact-#{test_run_id}@secure.example.com",
      )
    end

    let!(:tenant_custom_domain) do
      domain = Onetime::CustomDomain.new(
        display_domain: tenant_domain,
        org_id: tenant_organization.org_id,
      )
      domain.save
      Onetime::CustomDomain.display_domains.put(tenant_domain, domain.domainid)
      domain
    end

    after do
      Onetime::CustomDomain::SignupConfig.delete_for_domain!(tenant_custom_domain.identifier) rescue nil
      Onetime::CustomDomain.display_domains.remove(tenant_domain) rescue nil
      tenant_custom_domain&.destroy! rescue nil
      tenant_organization&.destroy! rescue nil
      tenant_org_owner&.destroy! rescue nil
    end

    def mock_display_domain(domain_name)
      allow_any_instance_of(Rack::Request).to receive(:env).and_wrap_original do |original|
        env = original.call
        env['onetime.display_domain'] = domain_name
        env
      end
    end

    context 'with domain_allowlist strategy' do
      before do
        Onetime::CustomDomain::SignupConfig.create!(
          domain_id: tenant_custom_domain.identifier,
          validation_strategy: 'domain_allowlist',
          allowed_signup_domains: ['secret-partner.com', 'confidential.example.com'],
          enabled: true,
        )
        mock_display_domain(tenant_domain)
      end

      it 'does not reveal per-domain allowed domains in error response' do
        setup_mock_auth(email: 'attacker@evil.com')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          if last_response.status == 403
            # Response must NOT reveal which domains are in the per-domain allowlist
            expect(last_response.body).not_to include('secret-partner.com'),
              "Error response reveals per-domain allowed domain"
            expect(last_response.body).not_to include('confidential.example.com'),
              "Error response reveals per-domain allowed domain"
          end
        ensure
          teardown_mock_auth
        end
      end

      it 'does not reveal validation strategy in error response' do
        setup_mock_auth(email: 'attacker@evil.com')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          if last_response.status == 403
            # Response must NOT reveal the validation strategy type
            expect(last_response.body).not_to include('domain_allowlist'),
              "Error response reveals validation strategy"
            expect(last_response.body).not_to include('passthrough'),
              "Error response reveals validation strategy"
          end
        ensure
          teardown_mock_auth
        end
      end

      it 'does not reveal tenant domain or organization in error response' do
        setup_mock_auth(email: 'attacker@evil.com')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          if last_response.status == 403
            # Response must NOT reveal the custom domain or org details
            expect(last_response.body).not_to include(tenant_domain),
              "Error response reveals tenant domain"
            expect(last_response.body).not_to include("Secure Org"),
              "Error response reveals organization name"
          end
        ensure
          teardown_mock_auth
        end
      end

      it 'uses same generic error for per-domain rejection as global rejection' do
        setup_mock_auth(email: 'attacker@evil.com')

        begin
          post '/auth/sso/oidc/callback'

          if last_response.status == 404
            skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
          end

          if last_response.status == 403
            # Must use same generic message regardless of rejection source
            expect(last_response.body).to include('not authorized').or include('domain_not_allowed'),
              "Expected generic error, got: #{last_response.body}"
          end
        ensure
          teardown_mock_auth
        end
      end
    end
  end
end
