# apps/api/domains/spec/integration/simple/domain_sso_config_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration Tests for Domain SSO Config API Endpoints
# =============================================================================
#
# Issue: #2786 - Per-domain SSO configuration
#
# Tests the Domain SSO Config REST API endpoints:
#   GET    /api/domains/:extid/sso
#   PUT    /api/domains/:extid/sso
#   PATCH  /api/domains/:extid/sso
#   DELETE /api/domains/:extid/sso
#   POST   /api/domains/:extid/sso/test
#
# These endpoints require:
#   1. Authenticated user (session auth)
#   2. ORGS_SSO_ENABLED feature flag
#   3. User must be organization owner
#   4. Organization must have manage_sso entitlement
#
# REQUIREMENTS:
# - Valkey running on port 2163: pnpm run test:database:start
# - AUTHENTICATION_MODE=simple (login_as creates a Valkey-backed Customer
#   with a passphrase; full mode routes /auth/login through Rodauth, which
#   has no matching account row, so every login 401s)
#
# RUN:
#   RACK_ENV=test AUTHENTICATION_MODE=simple bundle exec rspec apps/api/domains/spec/integration/simple/domain_sso_config_spec.rb
#
# =============================================================================

require_relative File.join(Onetime::HOME, 'spec', 'integration', 'integration_spec_helper')
# SAML certificate fixtures (#4450): generated at runtime, nothing checked in.
require_relative File.join(Onetime::HOME, 'apps', 'web', 'auth', 'spec', 'support', 'domain_sso_test_fixtures')

RSpec.describe 'Domain SSO Config API', type: :integration do
  include Rack::Test::Methods
  include CsrfTestHelpers

  # Use the full Rack::URLMap so requests traverse the complete middleware
  # stack (including CSRF bypass for /api/* paths) exactly as in production.
  def app
    @rack_app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

  # ==========================================================================
  # Test Fixture Setup
  # ==========================================================================

  before(:all) do
    Onetime.boot! :test

    # Configure encryption for CustomDomain::SsoConfig
    key_v1 = 'test_encryption_key_32bytes_ok!!'
    key_v2 = 'another_test_key_for_testing_!!'

    Familia.configure do |config|
      config.encryption_keys = {
        v1: Base64.strict_encode64(key_v1),
        v2: Base64.strict_encode64(key_v2),
      }
      config.current_key_version = :v1
      config.encryption_personalization = 'SsoConfigIntgTst'
    end
  end

  # Issuer save-time validation (SsrfProtection#valid_issuer_host?) resolves
  # the issuer host and fails closed on empty resolution, so the fixture
  # issuers below (auth.example.com, pkce-issuer.example.com — all NXDOMAIN)
  # would be rejected with 422 on a machine with working DNS. Resolve them to
  # a documentation-range public address instead: these tests are about the
  # SSO config API's own semantics, and the SSRF rules themselves are covered
  # in apps/api/domains/spec/logic/sso_config/ssrf_protection_spec.rb.
  before do
    allow(Resolv).to receive(:getaddresses).and_return(['203.0.113.10'])
  end

  let(:test_run_id) { SecureRandom.hex(8) }
  let(:test_email) { "owner-#{test_run_id}@test.local" }
  let(:test_password) { 'Test123!@#' }
  let(:tenant_domain) { "secrets-#{test_run_id}.acme-corp.example.com" }

  # Create owner customer
  let!(:test_owner) do
    customer = Onetime::Customer.new(email: test_email)
    customer.update_passphrase(test_password)
    customer.verified = 'true'
    customer.role = 'customer'
    customer.save
    customer
  end

  # Create non-owner customer (for authorization tests)
  let!(:test_non_owner) do
    email = "nonowner-#{test_run_id}@test.local"
    customer = Onetime::Customer.new(email: email)
    customer.update_passphrase(test_password)
    customer.verified = 'true'
    customer.role = 'customer'
    customer.save
    customer
  end

  # Create organization owned by test_owner
  # Note: In standalone/test mode (billing disabled), all orgs get
  # STANDALONE_ENTITLEMENTS which includes manage_sso automatically.
  # The entitlement denial test stubs org.can? to test that code path.
  let!(:test_organization) do
    Onetime::Organization.create!(
      "Test Org #{test_run_id}",
      test_owner,
      "contact-#{test_run_id}@test.local",
    )
  end

  # Create custom domain associated with organization
  let!(:test_custom_domain) do
    domain = Onetime::CustomDomain.new(
      display_domain: tenant_domain,
      org_id: test_organization.org_id,
    )
    domain.save
    Onetime::CustomDomain.display_domain_index.put(tenant_domain, domain.domainid)
    domain
  end

  # Valid Entra ID config params
  let(:valid_entra_params) do
    {
      provider_type: 'entra_id',
      display_name: 'Test Entra ID',
      client_id: 'test-client-id-12345',
      client_secret: 'test-client-secret-abcdef',
      tenant_id: '12345678-1234-1234-1234-123456789abc',
      allowed_domains: ['acme-corp.example.com'],
      enabled: true,
    }
  end

  # Valid OIDC config params
  let(:valid_oidc_params) do
    {
      provider_type: 'oidc',
      display_name: 'Test OIDC Provider',
      client_id: 'oidc-client-id',
      client_secret: 'oidc-client-secret',
      issuer: 'https://auth.example.com',
      allowed_domains: ['example.com'],
      enabled: true,
    }
  end

  # Clean up after each test
  after do
    Onetime::CustomDomain::SsoConfig.delete_for_domain!(test_custom_domain.identifier) rescue nil
    Onetime::CustomDomain.display_domain_index.remove(tenant_domain) rescue nil
    test_custom_domain&.destroy! rescue nil
    test_organization&.destroy! rescue nil
    test_owner&.destroy! rescue nil
    test_non_owner&.destroy! rescue nil
  end

  # ==========================================================================
  # Helper Methods
  # ==========================================================================

  def enable_sso_feature_flag
    real_conf = OT.conf.dup
    real_conf['features'] = (real_conf['features'] || {}).merge(
      'organizations' => ((real_conf.dig('features', 'organizations') || {}).merge(
        'sso_enabled' => true
      ))
    )
    allow(OT).to receive(:conf).and_return(real_conf)
  end

  def disable_sso_feature_flag
    real_conf = OT.conf.dup
    real_conf['features'] = (real_conf['features'] || {}).merge(
      'organizations' => ((real_conf.dig('features', 'organizations') || {}).merge(
        'sso_enabled' => false
      ))
    )
    allow(OT).to receive(:conf).and_return(real_conf)
  end

  def api_path(domain_extid)
    "/api/domains/#{domain_extid}/sso"
  end

  def test_connection_path(domain_extid)
    "/api/domains/#{domain_extid}/sso/test"
  end

  def login_as(customer)
    # Establish session by logging in via auth route
    reset_csrf_token
    csrf_post '/auth/login', {
      login: customer.email,
      password: test_password,
    }

    # Refresh CSRF token after login (session regeneration)
    reset_csrf_token
  end

  def json_get(path)
    header 'Accept', 'application/json'
    header 'Content-Type', nil
    get path
  end

  def json_body
    JSON.parse(last_response.body)
  end

  def csrf_patch(path, params = {})
    csrf_token = ensure_csrf_token

    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', csrf_token if csrf_token

    patch path, JSON.generate(params.merge(shrimp: csrf_token))
  end

  # ==========================================================================
  # PUT /api/domains/:extid/sso - Create/Replace SSO Config
  # ==========================================================================

  describe 'PUT /api/domains/:extid/sso' do
    before do
      enable_sso_feature_flag
    end

    context 'when authenticated as organization owner with entitlement' do
      before do
        login_as(test_owner)
      end

      context 'creating new SSO config' do
        it 'creates Entra ID config and returns masked secret' do
          csrf_put api_path(test_custom_domain.extid), valid_entra_params

          expect(last_response.status).to eq(200)

          body = json_body
          expect(body).to have_key('record')
          record = body['record']

          expect(record['provider_type']).to eq('entra_id')
          expect(record['display_name']).to eq('Test Entra ID')
          expect(record['client_id']).to eq('test-client-id-12345')
          expect(record['tenant_id']).to eq('12345678-1234-1234-1234-123456789abc')
          expect(record['enabled']).to be true

          # Secret should be masked
          expect(record['client_secret_masked']).to match(/^••••••••.{4}$/)
          expect(record).not_to have_key('client_secret')
        end

        it 'creates OIDC config with issuer' do
          csrf_put api_path(test_custom_domain.extid), valid_oidc_params

          expect(last_response.status).to eq(200)

          body = json_body
          record = body['record']
          expect(record['provider_type']).to eq('oidc')
          expect(record['issuer']).to eq('https://auth.example.com')
        end

        it 'returns user_id in response' do
          csrf_put api_path(test_custom_domain.extid), valid_entra_params

          body = json_body
          expect(body['user_id']).to eq(test_owner.extid)
        end
      end

      context 'replacing existing SSO config' do
        before do
          # Create initial config
          Onetime::CustomDomain::SsoConfig.create!(
            domain_id: test_custom_domain.identifier,
            provider_type: 'oidc',
            client_id: 'old-client-id',
            client_secret: 'old-secret',
            issuer: 'https://old-issuer.com',
            enabled: false,
          )
        end

        it 'replaces all fields with PUT semantics' do
          csrf_put api_path(test_custom_domain.extid), valid_entra_params

          expect(last_response.status).to eq(200)

          body = json_body
          record = body['record']

          # Provider should be replaced
          expect(record['provider_type']).to eq('entra_id')
          expect(record['tenant_id']).to eq('12345678-1234-1234-1234-123456789abc')

          # Old OIDC-specific fields should be cleared
          expect(record['issuer']).to be_empty.or be_nil
        end

        it 'clears a stored client_secret when an OIDC PUT omits it' do
          params = valid_oidc_params.dup
          params.delete(:client_secret)

          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(200)

          # PUT is full replacement: an omitted client_secret is CLEARED, not
          # preserved — legal only for OIDC (public client/PKCE); entra_id gets
          # 422 (see 'returns 422 for missing client_secret on PUT'). PATCH is
          # the secret-preserving verb; the frontend routes secretless saves
          # there (sso.service.ts#saveConfigForDomain).
          record = json_body['record']
          expect(record['client_secret_masked']).to be_nil

          # Persisted state agrees with the response
          json_get api_path(test_custom_domain.extid)
          expect(json_body['record']['client_secret_masked']).to be_nil
        end
      end

      context 'validation errors' do
        it 'returns 422 for missing provider_type' do
          params = valid_entra_params.dup
          params.delete(:provider_type)

          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(422)
          body = json_body
          expect(body['error']).to include('Provider type')
        end

        it 'returns 422 for invalid provider_type' do
          params = valid_entra_params.merge(provider_type: 'invalid_provider')

          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(422)
          body = json_body
          expect(body['error']).to include('Invalid provider type')
        end

        it 'returns 422 for missing client_id' do
          params = valid_entra_params.dup
          params.delete(:client_id)

          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(422)
          body = json_body
          expect(body['error']).to include('Client ID')
        end

        it 'returns 422 for missing client_secret on PUT' do
          params = valid_entra_params.dup
          params.delete(:client_secret)

          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(422)
          body = json_body
          expect(body['error']).to include('Client secret')
        end

        it 'returns 422 for missing tenant_id on Entra ID provider' do
          params = valid_entra_params.dup
          params.delete(:tenant_id)

          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(422)
          body = json_body
          expect(body['error']).to include('Tenant ID')
        end

        it 'returns 422 for missing issuer on OIDC provider' do
          params = valid_oidc_params.dup
          params.delete(:issuer)

          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(422)
          body = json_body
          expect(body['error']).to include('Issuer URL')
        end

        it 'returns 422 for non-HTTPS issuer URL' do
          params = valid_oidc_params.merge(issuer: 'http://insecure.example.com')

          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(422)
          body = json_body
          expect(body['error']).to include('Issuer URL')
        end
      end
    end

    context 'authorization checks' do
      it 'returns 401 for unauthenticated requests' do
        # No login
        header 'Accept', 'application/json'
        header 'Content-Type', 'application/json'
        put api_path(test_custom_domain.extid), JSON.generate(valid_entra_params)

        expect(last_response.status).to eq(401)
      end

      it 'returns 422 when SSO feature flag is disabled' do
        disable_sso_feature_flag
        login_as(test_owner)

        csrf_put api_path(test_custom_domain.extid), valid_entra_params

        # Feature flag check uses raise_form_error → FormError → 422
        expect(last_response.status).to eq(422)
        body = json_body
        expect(body['error']).to include('SSO is not enabled')
      end

      it 'returns 403 for non-member of organization' do
        login_as(test_non_owner)

        csrf_put api_path(test_custom_domain.extid), valid_entra_params

        # Non-member check uses require_entitlement_in! → Onetime::Forbidden → 403
        expect(last_response.status).to eq(403)
        body = json_body
        expect(body['error']).to include('member')
      end

      it 'returns 422 when organization lacks manage_sso entitlement' do
        # In integration tests with billing disabled, all orgs get STANDALONE_ENTITLEMENTS.
        # We stub can? on the specific org instance to test this code path.
        # Note: This requires finding the org that will be loaded by the request.
        allow_any_instance_of(Onetime::Organization).to receive(:can?).with('manage_sso').and_return(false)

        login_as(test_owner)
        csrf_put api_path(test_custom_domain.extid), valid_entra_params

        # Entitlement check uses raise_form_error → FormError → 422
        expect(last_response.status).to eq(422)
        body = json_body
        expect(body['error']).to include('manage_sso')
      end

      it 'returns 404 for non-existent domain' do
        login_as(test_owner)
        csrf_put api_path('nonexistent-domain-extid'), valid_entra_params

        expect(last_response.status).to eq(404)
        body = json_body
        expect(body['error']).to include('Domain not found')
      end
    end
  end

  # ==========================================================================
  # GET /api/domains/:extid/sso - Retrieve SSO Config
  # ==========================================================================

  describe 'GET /api/domains/:extid/sso' do
    before do
      enable_sso_feature_flag
    end

    context 'when SSO config exists' do
      let!(:existing_config) do
        Onetime::CustomDomain::SsoConfig.create!(
          domain_id: test_custom_domain.identifier,
          provider_type: 'entra_id',
          display_name: 'Existing Config',
          client_id: 'existing-client-id',
          client_secret: 'existing-secret-value',
          tenant_id: 'existing-tenant-id',
          allowed_domains: ['acme.com'],
          enabled: true,
        )
      end

      before do
        login_as(test_owner)
      end

      it 'returns the SSO config with masked secret' do
        json_get api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(200)

        body = json_body
        expect(body).to have_key('record')
        record = body['record']

        expect(record['provider_type']).to eq('entra_id')
        expect(record['display_name']).to eq('Existing Config')
        expect(record['client_id']).to eq('existing-client-id')
        expect(record['tenant_id']).to eq('existing-tenant-id')
        expect(record['enabled']).to be true
        expect(record['allowed_domains']).to eq(['acme.com'])

        # Secret should be masked
        expect(record['client_secret_masked']).to match(/^••••••••/)
        expect(record).not_to have_key('client_secret')
      end

      it 'returns timestamps as integers' do
        json_get api_path(test_custom_domain.extid)

        body = json_body
        record = body['record']

        expect(record['created_at']).to be_a(Integer)
        expect(record['updated_at']).to be_a(Integer)
      end

      it 'returns provider metadata flags' do
        json_get api_path(test_custom_domain.extid)

        body = json_body
        record = body['record']

        expect(record).to have_key('requires_domain_filter')
        expect(record).to have_key('idp_controls_access')
      end
    end

    context 'when SSO config does not exist' do
      before do
        login_as(test_owner)
      end

      it 'returns 404' do
        json_get api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(404)
        body = json_body
        expect(body['error']).to include('SSO configuration not found')
      end
    end

    context 'authorization checks' do
      before do
        Onetime::CustomDomain::SsoConfig.create!(
          domain_id: test_custom_domain.identifier,
          provider_type: 'entra_id',
          client_id: 'client-id',
          client_secret: 'secret',
          tenant_id: 'tenant-id',
          enabled: true,
        )
      end

      it 'returns 401 for unauthenticated requests' do
        json_get api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(401)
      end

      it 'returns 403 for non-owner' do
        login_as(test_non_owner)
        json_get api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(403)
      end
    end
  end

  # ==========================================================================
  # PATCH /api/domains/:extid/sso - Partial Update SSO Config
  # ==========================================================================

  describe 'PATCH /api/domains/:extid/sso' do
    before do
      enable_sso_feature_flag
    end

    let!(:existing_config) do
      Onetime::CustomDomain::SsoConfig.create!(
        domain_id: test_custom_domain.identifier,
        provider_type: 'entra_id',
        display_name: 'Original Name',
        client_id: 'original-client-id',
        client_secret: 'original-secret',
        tenant_id: 'original-tenant-id',
        allowed_domains: ['original.com'],
        enabled: false,
      )
    end

    context 'when authenticated as organization owner' do
      before do
        login_as(test_owner)
      end

      it 'updates only provided fields (PATCH semantics)' do
        csrf_patch api_path(test_custom_domain.extid), {
          display_name: 'Updated Name',
          enabled: true,
        }

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']

        # Updated fields
        expect(record['display_name']).to eq('Updated Name')
        expect(record['enabled']).to be true

        # Preserved fields
        expect(record['provider_type']).to eq('entra_id')
        expect(record['client_id']).to eq('original-client-id')
        expect(record['tenant_id']).to eq('original-tenant-id')
      end

      it 'preserves client_secret when not provided' do
        csrf_patch api_path(test_custom_domain.extid), {
          display_name: 'Updated Again',
        }

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']

        # Secret should still be masked (meaning it was preserved)
        expect(record['client_secret_masked']).to match(/^••••••••/)
      end

      it 'updates client_secret when provided' do
        csrf_patch api_path(test_custom_domain.extid), {
          client_secret: 'new-secret-value',
        }

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']

        # Secret should show new masked value
        expect(record['client_secret_masked']).to eq('••••••••alue')
      end

      it 'clears allowed_domains when empty array provided' do
        csrf_patch api_path(test_custom_domain.extid), {
          allowed_domains: [],
        }

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']
        expect(record['allowed_domains']).to eq([])
      end

      it 'preserves allowed_domains when not provided' do
        csrf_patch api_path(test_custom_domain.extid), {
          display_name: 'Name Only Update',
        }

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']
        expect(record['allowed_domains']).to eq(['original.com'])
      end

      it 'clears tenant_id when switching to oidc' do
        csrf_patch api_path(test_custom_domain.extid), {
          provider_type: 'oidc',
          issuer: 'https://auth.example.com',
        }

        expect(last_response.status).to eq(200)
        record = json_body['record']
        expect(record['provider_type']).to eq('oidc')
        expect(record['issuer']).to eq('https://auth.example.com')

        # Provider switch clears the outgoing provider's field — an oidc
        # record must not carry the entra fixture's stale tenant_id.
        expect(record['tenant_id'].to_s).to eq('')
      end
    end

    context 'switching provider from a secretless OIDC config' do
      before do
        # Replace the entra_id fixture with an OIDC public-client config
        # (PKCE) that has no stored client_secret to fall back to.
        Onetime::CustomDomain::SsoConfig.delete_for_domain!(test_custom_domain.identifier)
        Onetime::CustomDomain::SsoConfig.create!(
          domain_id: test_custom_domain.identifier,
          provider_type: 'oidc',
          client_id: 'pkce-client-id',
          issuer: 'https://pkce-issuer.example.com',
          enabled: false,
        )
        login_as(test_owner)
      end

      # The public-client exemption: an ABSENT stored secret (as opposed to
      # one that will not decrypt, below) stays optional on update.
      it 'accepts a PATCH that omits the secret and keeps the record secretless' do
        csrf_patch api_path(test_custom_domain.extid), { display_name: 'Renamed PKCE' }

        expect(last_response.status).to eq(200), last_response.body
        expect(json_body['record']).to include(
          'display_name' => 'Renamed PKCE', 'client_secret_masked' => nil, 'unreadable_fields' => [],
        )
      end

      it 'returns 422 when switching to entra_id without a client_secret' do
        # Neither the request nor the stored record has a secret — allowing
        # this through would produce an entra_id config whose token exchange
        # fails at the IdP.
        csrf_patch api_path(test_custom_domain.extid), {
          provider_type: 'entra_id',
          tenant_id: '12345678-1234-1234-1234-123456789abc',
        }

        expect(last_response.status).to eq(422)
        expect(json_body['error']).to include('Client secret')

        # Stored config is untouched
        config = Onetime::CustomDomain::SsoConfig.find_by_domain_id(test_custom_domain.identifier)
        expect(config.provider_type).to eq('oidc')
      end

      it 'switches to entra_id when a client_secret is provided' do
        csrf_patch api_path(test_custom_domain.extid), {
          provider_type: 'entra_id',
          tenant_id: '12345678-1234-1234-1234-123456789abc',
          client_secret: 'switch-secret-value',
        }

        expect(last_response.status).to eq(200)
        record = json_body['record']
        expect(record['provider_type']).to eq('entra_id')
        expect(record['client_secret_masked']).to eq('••••••••alue')

        # Provider switch clears the outgoing provider's field — an entra_id
        # record must not carry the oidc fixture's stale issuer.
        expect(record['issuer'].to_s).to eq('')
      end

      it 'switches to entra_id without a request secret when one is stored' do
        config = Onetime::CustomDomain::SsoConfig.find_by_domain_id(test_custom_domain.identifier)
        config.client_secret = 'stored-oidc-secret'
        config.commit_fields

        csrf_patch api_path(test_custom_domain.extid), {
          provider_type: 'entra_id',
          tenant_id: '12345678-1234-1234-1234-123456789abc',
        }

        expect(last_response.status).to eq(200)
        expect(json_body['record']['provider_type']).to eq('entra_id')
      end
    end

    # A stored credential that will not decrypt (GET names it in
    # unreadable_fields) is corrupt ciphertext, not "unset". PATCH preserves
    # an omitted client_secret, so the OIDC public-client exemption must
    # cover an ABSENT secret only — otherwise a blank save reports success
    # on a record whose strategy can never be built.
    context 'with a stored client_secret that cannot be decrypted' do
      def current_config
        Onetime::CustomDomain::SsoConfig.find_by_domain_id(test_custom_domain.identifier)
      end

      # Ciphertext bound (AAD) to another domain: present, undecryptable here.
      def swap_in_foreign(field, value)
        other = Onetime::CustomDomain::SsoConfig.new(domain_id: "other-#{test_run_id}")
        other.public_send(:"#{field}=", value)
        Familia.dbclient.hset(current_config.dbkey, field.to_s, other.public_send(field).encrypted_value)
      end

      before { login_as(test_owner) }

      context 'with an oidc record' do
        before do
          Onetime::CustomDomain::SsoConfig.delete_for_domain!(test_custom_domain.identifier)
          Onetime::CustomDomain::SsoConfig.create!(
            domain_id: test_custom_domain.identifier,
            provider_type: 'oidc',
            display_name: 'Original OIDC',
            client_id: 'oidc-client-id',
            client_secret: 'oidc-stored-secret',
            issuer: 'https://auth.example.com',
            enabled: true,
          )
          swap_in_foreign(:client_secret, 'foreign-secret')
        end

        it 'is reported by GET as unreadable (the precondition)' do
          json_get api_path(test_custom_domain.extid)

          expect(last_response.status).to eq(200)
          expect(json_body['record']).to include('unreadable_fields' => ['client_secret'], 'client_secret_masked' => nil)
        end

        it 'refuses a PATCH that omits the secret, although oidc allows public clients' do
          csrf_patch api_path(test_custom_domain.extid), { display_name: 'Renamed' }

          expect(last_response.status).to eq(422)
          expect(json_body).to include('error_type' => 'missing', 'field' => 'client_secret')
          expect(json_body['error']).to include('Client secret is required')
          # Fail closed: nothing was written
          expect(current_config.display_name).to eq('Original OIDC')
        end

        it 'refuses a bare disable too (DELETE and PUT remain the escape hatches)' do
          csrf_patch api_path(test_custom_domain.extid), { enabled: false }

          expect(last_response.status).to eq(422)
          expect(json_body['field']).to eq('client_secret')
          expect(current_config.enabled?).to be true
        end

        it 'accepts a PATCH that supplies a replacement secret, which then decrypts' do
          csrf_patch api_path(test_custom_domain.extid), { client_secret: 'replacement-secret-value' }

          expect(last_response.status).to eq(200), last_response.body
          expect(json_body['record']).to include('unreadable_fields' => [], 'client_secret_masked' => '••••••••alue')
          expect(current_config.client_secret.reveal { it }).to eq('replacement-secret-value')
        end
      end

      context 'with an entra_id record' do
        before { swap_in_foreign(:client_secret, 'foreign-secret') }

        it 'refuses a PATCH that omits the secret' do
          csrf_patch api_path(test_custom_domain.extid), { display_name: 'Renamed' }

          expect(last_response.status).to eq(422)
          expect(json_body).to include('error_type' => 'missing', 'field' => 'client_secret')
          expect(current_config.display_name).to eq('Original Name')
        end
      end
    end

    context 'with a legacy stored provider type (pre-#3902)' do
      before do
        # Pre-#3902 records (google/github) predate model validation and
        # cannot be created through any current API path — seed one by
        # writing the field directly.
        existing_config.provider_type = 'google'
        existing_config.commit_fields
        login_as(test_owner)
      end

      it 'returns 422 naming the stored legacy type, even for a bare disable' do
        # The request never sent provider_type — the error must blame the
        # stored record and point at the escape hatches, not claim the
        # caller supplied an invalid field.
        csrf_patch api_path(test_custom_domain.extid), { enabled: false }

        expect(last_response.status).to eq(422)
        expect(json_body['error']).to include("'google'")
        expect(json_body['error']).to include('no longer supported')

        # Fail closed: the stored record is untouched
        config = Onetime::CustomDomain::SsoConfig.find_by_domain_id(test_custom_domain.identifier)
        expect(config.provider_type).to eq('google')
      end

      it 'can still be deleted (the escape hatch)' do
        csrf_delete api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(200)
        expect(Onetime::CustomDomain::SsoConfig.find_by_domain_id(test_custom_domain.identifier)).to be_nil
      end

      it 'can be replaced with a full PUT' do
        csrf_put api_path(test_custom_domain.extid), {
          provider_type: 'entra_id',
          client_id: 'replacement-client-id',
          client_secret: 'replacement-secret',
          tenant_id: '12345678-1234-1234-1234-123456789abc',
          enabled: false,
        }

        expect(last_response.status).to eq(200)
        expect(json_body['record']['provider_type']).to eq('entra_id')
      end
    end

    context 'when no existing config' do
      before do
        # Remove the existing config
        Onetime::CustomDomain::SsoConfig.delete_for_domain!(test_custom_domain.identifier)
        login_as(test_owner)
      end

      it 'creates new config when providing all required fields' do
        csrf_patch api_path(test_custom_domain.extid), valid_entra_params

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']
        expect(record['provider_type']).to eq('entra_id')
      end

      it 'returns 422 when required fields missing for creation' do
        csrf_patch api_path(test_custom_domain.extid), {
          display_name: 'Incomplete Config',
        }

        expect(last_response.status).to eq(422)
        body = json_body
        expect(body['error']).to include('required')
      end
    end
  end

  # ==========================================================================
  # DELETE /api/domains/:extid/sso - Delete SSO Config
  # ==========================================================================

  describe 'DELETE /api/domains/:extid/sso' do
    before do
      enable_sso_feature_flag
    end

    context 'when SSO config exists' do
      before do
        Onetime::CustomDomain::SsoConfig.create!(
          domain_id: test_custom_domain.identifier,
          provider_type: 'entra_id',
          client_id: 'delete-test-client',
          client_secret: 'delete-test-secret',
          tenant_id: 'delete-test-tenant',
          enabled: true,
        )
        login_as(test_owner)
      end

      it 'deletes the SSO config and returns confirmation' do
        csrf_delete api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(200)

        body = json_body
        expect(body['success']).to be true
        expect(body['message']).to include('deleted')

        # Verify deletion
        config = Onetime::CustomDomain::SsoConfig.find_by_domain_id(test_custom_domain.identifier)
        expect(config).to be_nil
      end
    end

    context 'when SSO config does not exist' do
      before do
        login_as(test_owner)
      end

      it 'returns 404' do
        csrf_delete api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(404)
        body = json_body
        expect(body['error']).to include('SSO configuration not found')
      end
    end

    context 'authorization checks' do
      before do
        Onetime::CustomDomain::SsoConfig.create!(
          domain_id: test_custom_domain.identifier,
          provider_type: 'entra_id',
          client_id: 'auth-test-client',
          client_secret: 'auth-test-secret',
          tenant_id: 'auth-test-tenant',
          enabled: true,
        )
      end

      it 'returns 403 for non-owner' do
        login_as(test_non_owner)
        csrf_delete api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(403)
      end
    end
  end

  # ==========================================================================
  # POST /api/domains/:extid/sso/test - Test SSO Connection
  # ==========================================================================

  describe 'POST /api/domains/:extid/sso/test' do
    before do
      enable_sso_feature_flag
    end

    context 'with valid Entra ID config' do
      before { login_as(test_owner) }

      let(:entra_test_params) do
        {
          provider_type: 'entra_id',
          client_id: 'test-client-id',
          tenant_id: '12345678-1234-1234-1234-123456789abc',
        }
      end

      it 'attempts connection test and returns result' do
        stub_request(:get, "https://login.microsoftonline.com/12345678-1234-1234-1234-123456789abc/v2.0/.well-known/openid-configuration").to_return(status: 200, body: %Q({"issuer":"https://login.microsoftonline.com"}), headers: {"Content-Type" => "application/json"})

        csrf_post test_connection_path(test_custom_domain.extid), entra_test_params

        expect(last_response.status).to eq(200)

        body = json_body
        expect(body).to have_key('provider_type')
        expect(body['provider_type']).to eq('entra_id')

        # Result will include success/failure based on network connectivity
        expect(body).to have_key('success')
        expect(body).to have_key('message')
      end
    end

    # Tenant SSO is OIDC/Entra-only (#3902): issuerless providers (google,
    # github) resolve to the shared '' issuer sentinel and cannot satisfy
    # (provider, issuer, uid) identity partitioning, so they are rejected
    # at the provider_type gate.
    context 'with removed issuerless provider types (#3902)' do
      before { login_as(test_owner) }

      it 'rejects google as an invalid provider type' do
        csrf_post test_connection_path(test_custom_domain.extid), {
          provider_type: 'google',
          client_id: 'test-client.apps.googleusercontent.com',
        }

        expect(last_response.status).to eq(422)
        body = json_body
        expect(body['error']).to include('Invalid provider type')
        expect(body['error']).to include('oidc, entra_id')
      end

      it 'rejects github as an invalid provider type' do
        csrf_post test_connection_path(test_custom_domain.extid), {
          provider_type: 'github',
          client_id: 'Iv1.1234567890abcdef',
        }

        expect(last_response.status).to eq(422)
        body = json_body
        expect(body['error']).to include('Invalid provider type')
        expect(body['error']).to include('oidc, entra_id')
      end
    end

    context 'validation errors' do
      before { login_as(test_owner) }

      it 'returns 422 for missing provider_type' do
        csrf_post test_connection_path(test_custom_domain.extid), {
          client_id: 'some-client-id',
        }

        expect(last_response.status).to eq(422)
        body = json_body
        expect(body['error']).to include('Provider type')
      end

      it 'returns 422 for missing client_id' do
        csrf_post test_connection_path(test_custom_domain.extid), {
          provider_type: 'entra_id',
          tenant_id: 'some-tenant',
        }

        expect(last_response.status).to eq(422)
        body = json_body
        expect(body['error']).to include('Client ID')
      end

      it 'returns 422 for missing tenant_id on Entra ID' do
        csrf_post test_connection_path(test_custom_domain.extid), {
          provider_type: 'entra_id',
          client_id: 'some-client-id',
        }

        expect(last_response.status).to eq(422)
        body = json_body
        expect(body['error']).to include('Tenant ID')
      end

      it 'returns 422 for invalid tenant_id format on Entra ID' do
        csrf_post test_connection_path(test_custom_domain.extid), {
          provider_type: 'entra_id',
          client_id: 'some-client-id',
          tenant_id: 'not-a-uuid',
        }

        expect(last_response.status).to eq(422)
        body = json_body
        expect(body['error']).to include('UUID')
      end

      it 'returns 422 for missing issuer on OIDC' do
        csrf_post test_connection_path(test_custom_domain.extid), {
          provider_type: 'oidc',
          client_id: 'some-client-id',
        }

        expect(last_response.status).to eq(422)
        body = json_body
        expect(body['error']).to include('Issuer URL')
      end

    end

    context 'authorization checks' do
      it 'returns 401 for unauthenticated requests' do
        header 'Accept', 'application/json'
        header 'Content-Type', 'application/json'
        post test_connection_path(test_custom_domain.extid), JSON.generate({
          provider_type: 'entra_id',
          client_id: 'client',
          tenant_id: '12345678-1234-1234-1234-123456789abc',
        })

        expect(last_response.status).to eq(401)
      end

      it 'returns 403 for non-member' do
        login_as(test_non_owner)

        csrf_post test_connection_path(test_custom_domain.extid), {
          provider_type: 'entra_id',
          client_id: 'client',
          tenant_id: '12345678-1234-1234-1234-123456789abc',
        }

        # Non-member check uses require_entitlement_in! -> Onetime::Forbidden -> 403
        expect(last_response.status).to eq(403)
        body = json_body
        expect(body['error']).to include('member')
      end
    end
  end

  # ==========================================================================
  # enforce_sso_only Field Tests (Issue #3057)
  # ==========================================================================

  describe 'enforce_sso_only field' do
    before do
      enable_sso_feature_flag
      login_as(test_owner)
    end

    describe 'PUT /api/domains/:extid/sso' do
      it 'accepts enforce_sso_only in request and returns it in response' do
        params = valid_entra_params.merge(enforce_sso_only: true)
        csrf_put api_path(test_custom_domain.extid), params

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']
        expect(record['enforce_sso_only']).to be true
      end

      it 'defaults enforce_sso_only to false when not provided' do
        csrf_put api_path(test_custom_domain.extid), valid_entra_params

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']
        expect(record['enforce_sso_only']).to be false
      end
    end

    describe 'PATCH /api/domains/:extid/sso' do
      let!(:existing_config) do
        Onetime::CustomDomain::SsoConfig.create!(
          domain_id: test_custom_domain.identifier,
          provider_type: 'entra_id',
          display_name: 'Original Config',
          client_id: 'original-client-id',
          client_secret: 'original-secret',
          tenant_id: 'original-tenant-id',
          enabled: true,
        )
      end

      it 'updates enforce_sso_only when provided' do
        csrf_patch api_path(test_custom_domain.extid), {
          enforce_sso_only: true,
        }

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']
        expect(record['enforce_sso_only']).to be true
      end

      it 'preserves enforce_sso_only when not provided in PATCH' do
        # First set enforce_sso_only to true
        existing_config.enforce_sso_only = 'true'
        existing_config.save

        # PATCH without enforce_sso_only
        csrf_patch api_path(test_custom_domain.extid), {
          display_name: 'Updated Name Only',
        }

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']
        expect(record['enforce_sso_only']).to be true
        expect(record['display_name']).to eq('Updated Name Only')
      end

      it 'can disable enforce_sso_only via PATCH' do
        # First set enforce_sso_only to true
        existing_config.enforce_sso_only = 'true'
        existing_config.save

        # PATCH to disable it
        csrf_patch api_path(test_custom_domain.extid), {
          enforce_sso_only: false,
        }

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']
        expect(record['enforce_sso_only']).to be false
      end
    end

    describe 'GET /api/domains/:extid/sso' do
      it 'returns enforce_sso_only in response' do
        Onetime::CustomDomain::SsoConfig.create!(
          domain_id: test_custom_domain.identifier,
          provider_type: 'entra_id',
          display_name: 'Test Config',
          client_id: 'test-client-id',
          client_secret: 'test-secret',
          tenant_id: 'test-tenant-id',
          enforce_sso_only: true,
          enabled: true,
        )

        json_get api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']
        expect(record).to have_key('enforce_sso_only')
        expect(record['enforce_sso_only']).to be true
      end
    end
  end

  # ==========================================================================
  # SAML provider type (#4450)
  # ==========================================================================
  #
  # The JSON contract the frontend builds against:
  #   request : provider_type 'saml' + idp_sso_service_url, idp_entity_id,
  #             idp_cert (all required); no client_id / client_secret
  #   response: the trio in plaintext, read-only sp_entity_id / acs_url,
  #             unreadable_fields ([] when healthy), client_id null
  #   errors  : 422 { error, error_type: 'missing'|'invalid', field }

  describe 'SAML provider type' do
    include DomainSsoTestFixtures

    let(:saml_cert) { DomainSsoTestFixtures.saml_cert_pem }

    let(:valid_saml_params) do
      {
        provider_type: 'saml',
        display_name: 'Corp SAML',
        idp_sso_service_url: 'https://idp.example.com/saml/sso',
        idp_entity_id: 'https://idp.example.com/saml/metadata',
        idp_cert: saml_cert,
        allowed_domains: ['example.com'],
        enabled: true,
      }
    end

    def stored_config
      Onetime::CustomDomain::SsoConfig.find_by_domain_id(test_custom_domain.identifier)
    end

    # The install's session cookie, as the save path reads it. The test
    # config ships the default (same_site: lax), under which a saml config
    # can never complete a sign-in and the API refuses to save one
    # (SamlFields#reject_incompatible_session_cookie!). Stubbed to the
    # compatible pair here so the contract below is exercised; the refusal
    # itself is pinned in 'under an incompatible session cookie'.
    def stub_session_cookie(same_site:, secure:)
      allow(Onetime).to receive(:session_config).and_wrap_original do |original|
        original.call.merge('same_site' => same_site, 'secure' => secure)
      end
    end

    before do
      enable_sso_feature_flag
      login_as(test_owner)
      stub_session_cookie(same_site: 'none', secure: true)
    end

    describe 'under an incompatible session cookie' do
      before { stub_session_cookie(same_site: 'lax', secure: true) }

      it 'refuses to create a saml config via PUT, on provider_type, naming the settings' do
        csrf_put api_path(test_custom_domain.extid), valid_saml_params

        expect(last_response.status).to eq(422)
        expect(json_body).to include('error_type' => 'invalid', 'field' => 'provider_type')
        expect(json_body['error']).to include("same_site is 'lax'", 'same_site: none with secure: true', 'site.session')
        expect(stored_config).to be_nil
      end

      it 'refuses SameSite=None without Secure too' do
        stub_session_cookie(same_site: 'none', secure: false)

        csrf_put api_path(test_custom_domain.extid), valid_saml_params

        expect(last_response.status).to eq(422)
        expect(json_body['field']).to eq('provider_type')
      end

      it 'refuses a PATCH that switches an oidc config to saml' do
        stub_session_cookie(same_site: 'none', secure: true)
        csrf_put api_path(test_custom_domain.extid), valid_oidc_params
        expect(last_response.status).to eq(200), last_response.body
        stub_session_cookie(same_site: 'lax', secure: true)

        csrf_patch api_path(test_custom_domain.extid), valid_saml_params

        expect(last_response.status).to eq(422)
        expect(json_body['field']).to eq('provider_type')
        expect(stored_config.provider_type).to eq('oidc')
      end

      it 'still accepts an oidc config (the rule is saml-only)' do
        csrf_put api_path(test_custom_domain.extid), valid_oidc_params

        expect(last_response.status).to eq(200), last_response.body
      end

      context 'with a saml config saved while the cookie was compatible' do
        before do
          stub_session_cookie(same_site: 'none', secure: true)
          csrf_put api_path(test_custom_domain.extid), valid_saml_params
          expect(last_response.status).to eq(200), last_response.body
          stub_session_cookie(same_site: 'lax', secure: true)
        end

        # An existing record must stay editable: the admin can disable it,
        # rotate a field, or switch provider — never be stuck with it.
        it 'can still be disabled via PATCH' do
          csrf_patch api_path(test_custom_domain.extid), { enabled: false }

          expect(last_response.status).to eq(200), last_response.body
          expect(stored_config.enabled?).to be false
        end

        it 'can still rotate a trio field via PATCH' do
          csrf_patch api_path(test_custom_domain.extid), { idp_entity_id: 'urn:example:rotated' }

          expect(last_response.status).to eq(200), last_response.body
          expect(stored_config.reveal_saml_field(:idp_entity_id)).to eq('urn:example:rotated')
        end

        it 'is refused on a full PUT replace (PUT re-introduces the config)' do
          csrf_put api_path(test_custom_domain.extid), valid_saml_params.merge(display_name: 'Replaced')

          expect(last_response.status).to eq(422)
          expect(json_body['field']).to eq('provider_type')
        end
      end
    end

    describe 'PUT' do
      it 'creates a saml config without any client credential' do
        csrf_put api_path(test_custom_domain.extid), valid_saml_params

        expect(last_response.status).to eq(200), last_response.body
        record = json_body['record']

        expect(record).to include(
          'provider_type' => 'saml',
          'idp_sso_service_url' => 'https://idp.example.com/saml/sso',
          'idp_entity_id' => 'https://idp.example.com/saml/metadata',
          'idp_cert' => saml_cert.strip,
          'client_id' => nil,
          'client_secret_masked' => nil,
          'unreadable_fields' => [],
          'requires_domain_filter' => true,
          'idp_controls_access' => false,
        )
      end

      it 'returns the SP identifiers the tenant hook will use at login' do
        csrf_put api_path(test_custom_domain.extid), valid_saml_params

        base = "https://#{tenant_domain}/auth/sso/saml"
        expect(json_body['record']).to include('sp_entity_id' => "#{base}/metadata", 'acs_url' => "#{base}/callback")
      end

      it 'stores the trio encrypted, and revealable after a fresh load' do
        csrf_put api_path(test_custom_domain.extid), valid_saml_params

        config = stored_config
        raw    = Familia.dbclient.hget(config.dbkey, 'idp_entity_id').to_s

        expect(raw).not_to include('idp.example.com')
        expect(config.saml_trio).to eq(
          idp_sso_service_url: 'https://idp.example.com/saml/sso',
          idp_entity_id: 'https://idp.example.com/saml/metadata',
          idp_cert: saml_cert.strip,
        )
      end

      it 'strips surrounding whitespace from the EntityID before it is stored' do
        csrf_put api_path(test_custom_domain.extid),
          valid_saml_params.merge(idp_entity_id: "  urn:example:idp\n")

        expect(last_response.status).to eq(200), last_response.body
        expect(stored_config.reveal_saml_field(:idp_entity_id)).to eq('urn:example:idp')
      end

      it 'normalizes a certificate sent with CRLF line endings' do
        csrf_put api_path(test_custom_domain.extid),
          valid_saml_params.merge(idp_cert: saml_cert.gsub("\n", "\r\n"))

        expect(last_response.status).to eq(200), last_response.body
        expect(stored_config.reveal_saml_field(:idp_cert)).to eq(saml_cert.strip)
      end

      it 'discards a client credential sent with a saml config' do
        csrf_put api_path(test_custom_domain.extid),
          valid_saml_params.merge(client_id: 'stray-client', client_secret: 'stray-secret', issuer: 'https://auth.example.com')

        expect(last_response.status).to eq(200), last_response.body
        config = stored_config
        expect([config.client_id, config.client_secret, config.issuer.to_s]).to eq([nil, nil, ''])
      end

      {
        'idp_sso_service_url' => 'IdP SSO service URL is required',
        'idp_entity_id' => 'IdP EntityID is required',
        'idp_cert' => 'IdP certificate is required',
      }.each do |field, message|
        it "returns 422 (missing) without #{field}" do
          csrf_put api_path(test_custom_domain.extid), valid_saml_params.except(field.to_sym)

          expect(last_response.status).to eq(422)
          expect(json_body).to include('error_type' => 'missing', 'field' => field)
          expect(json_body['error']).to include(message)
        end
      end

      it 'returns 422 (invalid) for an http SSO service URL' do
        csrf_put api_path(test_custom_domain.extid),
          valid_saml_params.merge(idp_sso_service_url: 'http://idp.example.com/saml/sso')

        expect(last_response.status).to eq(422)
        expect(json_body).to include('error_type' => 'invalid', 'field' => 'idp_sso_service_url')
      end

      # The server never fetches the SSO URL (the browser is redirected to
      # it), so the OIDC issuer's SSRF host check does not apply: an IdP that
      # only the user's browser can reach is a legitimate configuration.
      it 'accepts an SSO service URL that resolves to a private address' do
        allow(Resolv).to receive(:getaddresses).and_return(['10.0.0.5'])

        csrf_put api_path(test_custom_domain.extid), valid_saml_params

        expect(last_response.status).to eq(200), last_response.body
        expect(stored_config.reveal_saml_field(:idp_sso_service_url)).to eq('https://idp.example.com/saml/sso')
      end

      it 'accepts an SSO service URL on a private hostname' do
        csrf_put api_path(test_custom_domain.extid),
          valid_saml_params.merge(idp_sso_service_url: 'https://sso.corp.internal/saml/sso')

        expect(last_response.status).to eq(200), last_response.body
      end

      # What the URL's origin IS admitted into is the domain's CSP form-action
      # and HttpOrigin allowances (AuthConfig#origin_from_url is the funnel),
      # so a host that would break the CSP directive is refused at save time.
      {
        'a trailing semicolon on the host' => 'https://idp.example.com;/saml/sso',
        'a quote in the host' => %(https://idp.example.com'/saml/sso),
        'userinfo' => 'https://user:secret@idp.example.com/saml/sso',
        # Derives fine — but as 'https://idp.example.com' (otto strips one
        # trailing dot), an origin the dotted-host IdP never POSTs from, so
        # every callback would be refused by HttpOrigin. Refused at save.
        'a trailing dot on the host' => 'https://idp.example.com./saml/sso',
      }.each do |label, url|
        it "returns 422 (invalid) for an SSO service URL with #{label}" do
          csrf_put api_path(test_custom_domain.extid), valid_saml_params.merge(idp_sso_service_url: url)

          expect(last_response.status).to eq(422)
          expect(json_body).to include('error_type' => 'invalid', 'field' => 'idp_sso_service_url')
          expect(last_response.body).not_to include('secret')
        end
      end

      it 'stores only a URL whose derived origin the CSP layer will carry' do
        csrf_put api_path(test_custom_domain.extid), valid_saml_params

        expect(last_response.status).to eq(200), last_response.body
        expect(Onetime.auth_config.tenant_idp_origin(stored_config)).to eq('https://idp.example.com')
      end

      it 'returns 422 (invalid) for a fingerprint in place of the certificate' do
        csrf_put api_path(test_custom_domain.extid), valid_saml_params.merge(idp_cert: 'AB:CD:EF:01:23:45')

        expect(last_response.status).to eq(422)
        expect(json_body).to include('error_type' => 'invalid', 'field' => 'idp_cert')
      end

      it 'returns 422 (invalid) for an expired certificate' do
        csrf_put api_path(test_custom_domain.extid), valid_saml_params.merge(idp_cert: expired_saml_cert_pem)

        expect(last_response.status).to eq(422)
        expect(json_body).to include('error_type' => 'invalid', 'field' => 'idp_cert')
        expect(json_body['error']).to match(/expired on/)
      end

      # Fingerprint-only trust accepts whatever certificate the response
      # embeds. Refused loudly, for every provider type, even alongside a
      # valid certificate.
      %w[idp_cert_fingerprint idp_cert_fingerprint_algorithm idp_cert_multi].each do |param|
        it "refuses #{param} outright" do
          csrf_put api_path(test_custom_domain.extid), valid_saml_params.merge(param => 'AB:CD:EF')

          expect(last_response.status).to eq(422)
          expect(json_body).to include('error_type' => 'invalid', 'field' => param)
          expect(stored_config).to be_nil
        end
      end

      it 'refuses a fingerprint param on a non-saml config too' do
        csrf_put api_path(test_custom_domain.extid), valid_oidc_params.merge(idp_cert_fingerprint: 'AB:CD')

        expect(last_response.status).to eq(422)
        expect(json_body['field']).to eq('idp_cert_fingerprint')
      end

      it 'replacing oidc with saml drops the client credential and issuer' do
        csrf_put api_path(test_custom_domain.extid), valid_oidc_params
        csrf_put api_path(test_custom_domain.extid), valid_saml_params

        expect(last_response.status).to eq(200), last_response.body
        config = stored_config
        expect(config.provider_type).to eq('saml')
        expect([config.client_id, config.client_secret, config.issuer.to_s]).to eq([nil, nil, ''])
      end

      it 'replacing saml with oidc drops the SAML trust anchor' do
        csrf_put api_path(test_custom_domain.extid), valid_saml_params
        csrf_put api_path(test_custom_domain.extid), valid_oidc_params

        expect(last_response.status).to eq(200), last_response.body
        config = stored_config
        expect(config.provider_type).to eq('oidc')
        expect(Onetime::CustomDomain::SsoConfig::SAML_FIELDS.map { |name| config.public_send(name) }).to all(be_nil)
      end

      it 'never stores an unvalidated trio on a non-saml config' do
        csrf_put api_path(test_custom_domain.extid),
          valid_oidc_params.merge(idp_entity_id: 'urn:planted', idp_cert: 'not a cert', idp_sso_service_url: 'http://x')

        expect(last_response.status).to eq(200), last_response.body
        expect(Onetime::CustomDomain::SsoConfig::SAML_FIELDS.map { |name| stored_config.public_send(name) }).to all(be_nil)
      end
    end

    describe 'PATCH' do
      context 'with an existing saml config' do
        before { csrf_put api_path(test_custom_domain.extid), valid_saml_params }

        it 'preserves the trio on a partial update' do
          csrf_patch api_path(test_custom_domain.extid), { display_name: 'Renamed' }

          expect(last_response.status).to eq(200), last_response.body
          expect(json_body['record']).to include(
            'display_name' => 'Renamed',
            'idp_entity_id' => 'https://idp.example.com/saml/metadata',
            'idp_cert' => saml_cert.strip,
          )
        end

        it 'replaces a single trio field' do
          csrf_patch api_path(test_custom_domain.extid), { idp_entity_id: 'urn:example:rotated' }

          expect(last_response.status).to eq(200), last_response.body
          expect(stored_config.saml_trio).to include(
            idp_entity_id: 'urn:example:rotated',
            idp_sso_service_url: 'https://idp.example.com/saml/sso',
          )
        end

        it 'validates a newly supplied field (expired certificate refused)' do
          csrf_patch api_path(test_custom_domain.extid), { idp_cert: expired_saml_cert_pem }

          expect(last_response.status).to eq(422)
          expect(json_body).to include('error_type' => 'invalid', 'field' => 'idp_cert')
          expect(stored_config.reveal_saml_field(:idp_cert)).to eq(saml_cert.strip)
        end

        # The reason expiry is not a MODEL invariant: an operator must be
        # able to switch off a config whose certificate has since expired.
        it 'can still disable a config whose stored certificate has expired' do
          config          = stored_config
          config.idp_cert = expired_saml_cert_pem
          config.commit_fields

          csrf_patch api_path(test_custom_domain.extid), { enabled: false }

          expect(last_response.status).to eq(200), last_response.body
          expect(stored_config.enabled?).to be false
        end

        it 'requires a client_id when switching away to oidc' do
          csrf_patch api_path(test_custom_domain.extid), { provider_type: 'oidc', issuer: 'https://auth.example.com' }

          expect(last_response.status).to eq(422)
          expect(json_body).to include('error_type' => 'missing', 'field' => 'client_id')
        end

        it 'drops the trio when switching away to oidc' do
          csrf_patch api_path(test_custom_domain.extid),
            { provider_type: 'oidc', issuer: 'https://auth.example.com', client_id: 'oidc-client' }

          expect(last_response.status).to eq(200), last_response.body
          config = stored_config
          expect(config.provider_type).to eq('oidc')
          expect(Onetime::CustomDomain::SsoConfig::SAML_FIELDS.map { |name| config.public_send(name) }).to all(be_nil)
        end

        # A saml record stores no issuer, so a switch to oidc has nothing to
        # fall back on: the issuer must arrive with the request.
        it 'rejects a switch to oidc that omits the issuer' do
          csrf_patch api_path(test_custom_domain.extid), { provider_type: 'oidc', client_id: 'oidc-client' }

          expect(last_response.status).to eq(422)
          expect(json_body).to include('error_type' => 'missing', 'field' => 'issuer')
        end

        it 'rejects a switch to oidc with an internal issuer host' do
          csrf_patch api_path(test_custom_domain.extid),
            { provider_type: 'oidc', client_id: 'oidc-client', issuer: 'https://sso.corp.internal/oidc' }

          expect(last_response.status).to eq(422)
          expect(json_body).to include('error_type' => 'invalid', 'field' => 'issuer')
          expect(stored_config.provider_type).to eq('saml')
        end

        # Records created before the create path cleared the OAuth-family
        # fields can carry an issuer that no validator ever saw. Switching
        # such a record to oidc must validate the stored value, not adopt it.
        it 'validates a dormant stored issuer when switching to oidc without one' do
          config        = stored_config
          config.issuer = 'https://sso.corp.internal/oidc'
          config.commit_fields

          csrf_patch api_path(test_custom_domain.extid), { provider_type: 'oidc', client_id: 'oidc-client' }

          expect(last_response.status).to eq(422)
          expect(json_body).to include('error_type' => 'invalid', 'field' => 'issuer')
          expect(stored_config.provider_type).to eq('saml')
        end

        it 'refuses a fingerprint param' do
          csrf_patch api_path(test_custom_domain.extid), { idp_cert_fingerprint: 'AB:CD' }

          expect(last_response.status).to eq(422)
          expect(json_body['field']).to eq('idp_cert_fingerprint')
        end

        # SamlFields#stored_saml_value?: a stored value that will not decrypt
        # (swapped in from another domain, corrupted, foreign key) counts as
        # ABSENT, so a partial update cannot quietly preserve a trust anchor
        # nobody can read; the admin must re-enter it. Fail closed — a
        # rescue that answered true would leave every login refusing
        # sso_not_configured with nothing on the form to say why.
        context 'when a stored trio field cannot be decrypted' do
          before do
            other          = Onetime::CustomDomain::SsoConfig.new(domain_id: "other-#{test_run_id}")
            other.idp_cert = saml_cert
            Familia.dbclient.hset(stored_config.dbkey, 'idp_cert', other.idp_cert.encrypted_value)
            allow(OT).to receive(:lw)
          end

          it 'refuses a partial update that would preserve it, naming the field' do
            csrf_patch api_path(test_custom_domain.extid), { display_name: 'Renamed' }

            expect(last_response.status).to eq(422)
            expect(json_body).to include('error_type' => 'missing', 'field' => 'idp_cert')
            expect(stored_config.display_name).to eq('Corp SAML')
          end

          it 'accepts the update once the field is re-entered' do
            csrf_patch api_path(test_custom_domain.extid), { display_name: 'Renamed', idp_cert: saml_cert }

            expect(last_response.status).to eq(200), last_response.body
            expect(stored_config.display_name).to eq('Renamed')
            expect(stored_config.reveal_saml_field(:idp_cert)).to eq(saml_cert.strip)
          end
        end
      end

      context 'with an existing oidc config' do
        before { csrf_put api_path(test_custom_domain.extid), valid_oidc_params }

        it 'requires the whole trio when switching to saml' do
          csrf_patch api_path(test_custom_domain.extid),
            { provider_type: 'saml', idp_entity_id: 'urn:example:idp', idp_cert: saml_cert }

          expect(last_response.status).to eq(422)
          expect(json_body).to include('error_type' => 'missing', 'field' => 'idp_sso_service_url')
        end

        it 'switches to saml and drops the client credential and issuer' do
          csrf_patch api_path(test_custom_domain.extid), valid_saml_params.slice(
            :provider_type, :idp_sso_service_url, :idp_entity_id, :idp_cert
          )

          expect(last_response.status).to eq(200), last_response.body
          config = stored_config
          expect(config.provider_type).to eq('saml')
          expect([config.client_id, config.client_secret, config.issuer.to_s]).to eq([nil, nil, ''])
        end
      end

      it 'creates a saml config when none exists' do
        csrf_patch api_path(test_custom_domain.extid), valid_saml_params

        expect(last_response.status).to eq(200), last_response.body
        expect(json_body['record']['provider_type']).to eq('saml')
      end

      # Same end state as PUT: a saml record keeps none of the OAuth-family
      # fields, so a stray issuer / tenant_id cannot lie dormant on it.
      it 'stores no issuer or tenant_id on a PATCH-created saml config even when supplied' do
        csrf_patch api_path(test_custom_domain.extid), valid_saml_params.merge(
          client_id: 'stray-client', client_secret: 'stray-secret',
          issuer: 'https://auth.example.com', tenant_id: 'stray-tenant'
        )

        expect(last_response.status).to eq(200), last_response.body
        config = stored_config
        expect(config.provider_type).to eq('saml')
        expect([config.client_id, config.client_secret]).to eq([nil, nil])
        expect([config.issuer.to_s, config.tenant_id.to_s]).to eq(['', ''])
      end
    end

    describe 'GET' do
      before { csrf_put api_path(test_custom_domain.extid), valid_saml_params }

      # A swapped or corrupted AAD-bound trust anchor must surface as an
      # error state, never as a quiet null that reads like "unset".
      it 'names a field that cannot be decrypted in unreadable_fields' do
        other = Onetime::CustomDomain::SsoConfig.new(domain_id: "other-#{test_run_id}")
        other.idp_entity_id = 'https://evil-idp.example.net/metadata'
        Familia.dbclient.hset(stored_config.dbkey, 'idp_entity_id', other.idp_entity_id.encrypted_value)
        allow(OT).to receive(:lw)

        json_get api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(200)
        record = json_body['record']
        expect(record['unreadable_fields']).to eq(['idp_entity_id'])
        expect(record['idp_entity_id']).to be_nil
        expect(record['idp_cert']).to eq(saml_cert.strip)
        expect(OT).to have_received(:lw).with(/Failed to reveal encrypted field idp_entity_id for domain/)
      end

      it 'returns null SP identifiers for a non-saml config' do
        csrf_put api_path(test_custom_domain.extid), valid_oidc_params

        json_get api_path(test_custom_domain.extid)

        expect(json_body['record']).to include('sp_entity_id' => nil, 'acs_url' => nil, 'unreadable_fields' => [])
      end

      # The credential fields go through the same error-state contract: a
      # client_secret that will not decrypt must be reported, not served as
      # a null the form reads as "unset" (and PATCH would then preserve).
      context 'with an entra_id record whose credential ciphertext was swapped' do
        before do
          csrf_put api_path(test_custom_domain.extid), valid_entra_params
          allow(OT).to receive(:lw)
        end

        def swap_in_foreign(field, value)
          other = Onetime::CustomDomain::SsoConfig.new(domain_id: "other-#{test_run_id}")
          other.public_send(:"#{field}=", value)
          Familia.dbclient.hset(stored_config.dbkey, field.to_s, other.public_send(field).encrypted_value)
        end

        it 'names client_secret in unreadable_fields with a null mask' do
          swap_in_foreign(:client_secret, 'foreign-secret')

          json_get api_path(test_custom_domain.extid)

          expect(last_response.status).to eq(200)
          expect(json_body['record']).to include('unreadable_fields' => ['client_secret'], 'client_secret_masked' => nil)
          expect(json_body['record']['client_id']).to eq('test-client-id-12345')
        end

        it 'names client_id in unreadable_fields with a null value' do
          swap_in_foreign(:client_id, 'foreign-client')

          json_get api_path(test_custom_domain.extid)

          expect(last_response.status).to eq(200)
          expect(json_body['record']).to include('unreadable_fields' => ['client_id'], 'client_id' => nil)
          expect(json_body['record']['client_secret_masked']).to end_with('cdef')
        end
      end
    end

    describe 'POST /sso/test' do
      it 'validates locally and reports the certificate expiry, without a client_id' do
        allow(Net::HTTP).to receive(:new).and_call_original

        csrf_post test_connection_path(test_custom_domain.extid), valid_saml_params

        expect(last_response.status).to eq(200), last_response.body
        expect(json_body).to include('success' => true, 'provider_type' => 'saml')
        expect(json_body['details']).to include('idp_entity_id', 'certificate_not_after', 'certificate_expires_in_days')
        expect(Net::HTTP).not_to have_received(:new)
      end

      it 'reports an expired certificate as a failed test, not a form error' do
        csrf_post test_connection_path(test_custom_domain.extid), valid_saml_params.merge(idp_cert: expired_saml_cert_pem)

        expect(last_response.status).to eq(200), last_response.body
        expect(json_body['success']).to be false
        expect(json_body['details']).to include('error_code' => 'certificate_expired', 'field' => 'idp_cert')
      end

      it 'returns 422 (missing) when a trio field is absent' do
        csrf_post test_connection_path(test_custom_domain.extid), valid_saml_params.except(:idp_cert)

        expect(last_response.status).to eq(422)
        expect(json_body).to include('error_type' => 'missing', 'field' => 'idp_cert')
      end

      it 'refuses a fingerprint param' do
        csrf_post test_connection_path(test_custom_domain.extid), valid_saml_params.merge(idp_cert_fingerprint: 'AB:CD')

        expect(last_response.status).to eq(422)
        expect(json_body['field']).to eq('idp_cert_fingerprint')
      end
    end
  end

  # ==========================================================================
  # Response Serialization Tests
  # ==========================================================================

  describe 'response serialization' do
    before do
      enable_sso_feature_flag
      login_as(test_owner)
    end

    let!(:config_with_all_fields) do
      Onetime::CustomDomain::SsoConfig.create!(
        domain_id: test_custom_domain.identifier,
        provider_type: 'entra_id',
        display_name: 'Full Config Test',
        client_id: 'full-client-id',
        client_secret: 'full-secret-value-here',
        tenant_id: 'full-tenant-id',
        allowed_domains: ['domain1.com', 'domain2.com'],
        enabled: true,
      )
    end

    it 'serializes all expected fields' do
      json_get api_path(test_custom_domain.extid)

      expect(last_response.status).to eq(200)

      body = json_body
      record = body['record']

      expected_keys = %w[
        domain_id
        provider_type
        display_name
        enabled
        enforce_sso_only
        client_id
        client_secret_masked
        tenant_id
        issuer
        idp_sso_service_url
        idp_entity_id
        idp_cert
        sp_entity_id
        acs_url
        unreadable_fields
        allowed_domains
        requires_domain_filter
        idp_controls_access
        created_at
        updated_at
      ]

      expected_keys.each do |key|
        expect(record).to have_key(key), "Expected record to have key '#{key}'"
      end
    end

    it 'masks secrets correctly for various lengths' do
      # Test short secret
      config_with_all_fields.client_secret = 'ab'
      config_with_all_fields.save

      json_get api_path(test_custom_domain.extid)
      body = json_body
      record = body['record']

      # Short secrets should still be masked
      expect(record['client_secret_masked']).to eq('••••••••')
    end

    it 'returns JSON content type' do
      json_get api_path(test_custom_domain.extid)

      expect(last_response.content_type).to include('application/json')
    end
  end

  # ==========================================================================
  # Model-level Validation (SsoConfig.create!)
  # ==========================================================================

  describe 'SsoConfig.create! validation' do
    it 'raises Onetime::Problem when required provider fields are missing' do
      expect do
        Onetime::CustomDomain::SsoConfig.create!(
          domain_id: test_custom_domain.identifier,
          enabled: true,
        )
      end.to raise_error(Onetime::Problem, /client_id is required.*issuer is required/)
    end

    it 'raises Onetime::Problem for entra_id without a client_secret' do
      expect do
        Onetime::CustomDomain::SsoConfig.create!(
          domain_id: test_custom_domain.identifier,
          provider_type: 'entra_id',
          client_id: 'entra-client-id',
          tenant_id: 'entra-tenant-id',
        )
      end.to raise_error(Onetime::Problem, /client_secret is required/)
    end

    it 'allows OIDC public clients without a client_secret' do
      config = Onetime::CustomDomain::SsoConfig.create!(
        domain_id: test_custom_domain.identifier,
        provider_type: 'oidc',
        client_id: 'pkce-client-id',
        issuer: 'https://pkce-issuer.example.com',
      )
      expect(config.valid?).to be true
    end
  end
end
