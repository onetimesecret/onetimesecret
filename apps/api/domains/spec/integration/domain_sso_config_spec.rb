# apps/api/domains/spec/integration/domain_sso_config_spec.rb
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
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec apps/api/domains/spec/integration/domain_sso_config_spec.rb
#
# =============================================================================

require_relative File.join(Onetime::HOME, 'spec', 'integration', 'integration_spec_helper')

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

    # Configure encryption for DomainSsoConfig
    key_v1 = 'test_encryption_key_32bytes_ok!!'
    key_v2 = 'another_test_key_for_testing_!!'

    Familia.configure do |config|
      config.encryption_keys = {
        v1: Base64.strict_encode64(key_v1),
        v2: Base64.strict_encode64(key_v2),
      }
      config.current_key_version = :v1
      config.encryption_personalization = 'DomainSsoConfigIntegrationTest'
    end
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
    Onetime::CustomDomain.display_domains.put(tenant_domain, domain.domainid)
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
      allowed_domains: ['test.local'],
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
    Onetime::DomainSsoConfig.delete_for_domain!(test_custom_domain.identifier) rescue nil
    Onetime::CustomDomain.display_domains.remove(tenant_domain) rescue nil
    test_custom_domain&.destroy! rescue nil
    test_organization&.destroy! rescue nil
    test_owner&.destroy! rescue nil
    test_non_owner&.destroy! rescue nil
  end

  # ==========================================================================
  # Helper Methods
  # ==========================================================================

  def enable_sso_feature_flag
    allow(OT).to receive(:conf).and_return({
      'features' => { 'organizations' => { 'sso_enabled' => true } },
    })
  end

  def disable_sso_feature_flag
    allow(OT).to receive(:conf).and_return({
      'features' => { 'organizations' => { 'sso_enabled' => false } },
    })
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
          Onetime::DomainSsoConfig.create!(
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
      end

      context 'validation errors' do
        it 'returns 400 for missing provider_type' do
          params = valid_entra_params.dup
          params.delete(:provider_type)

          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(400)
          body = json_body
          expect(body['message']).to include('Provider type')
        end

        it 'returns 400 for invalid provider_type' do
          params = valid_entra_params.merge(provider_type: 'invalid_provider')

          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(400)
          body = json_body
          expect(body['message']).to include('Invalid provider type')
        end

        it 'returns 400 for missing client_id' do
          params = valid_entra_params.dup
          params.delete(:client_id)

          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(400)
          body = json_body
          expect(body['message']).to include('Client ID')
        end

        it 'returns 400 for missing client_secret on PUT' do
          params = valid_entra_params.dup
          params.delete(:client_secret)

          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(400)
          body = json_body
          expect(body['message']).to include('Client secret')
        end

        it 'returns 400 for missing tenant_id on Entra ID provider' do
          params = valid_entra_params.dup
          params.delete(:tenant_id)

          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(400)
          body = json_body
          expect(body['message']).to include('Tenant ID')
        end

        it 'returns 400 for missing issuer on OIDC provider' do
          params = valid_oidc_params.dup
          params.delete(:issuer)

          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(400)
          body = json_body
          expect(body['message']).to include('Issuer URL')
        end

        it 'returns 400 for non-HTTPS issuer URL' do
          params = valid_oidc_params.merge(issuer: 'http://insecure.example.com')

          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(400)
          body = json_body
          expect(body['message']).to include('Issuer URL')
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

      it 'returns 403 when SSO feature flag is disabled' do
        disable_sso_feature_flag
        login_as(test_owner)

        csrf_put api_path(test_custom_domain.extid), valid_entra_params

        expect(last_response.status).to eq(403)
        body = json_body
        expect(body['message']).to include('SSO is not enabled')
      end

      it 'returns 403 for non-owner of organization' do
        login_as(test_non_owner)

        csrf_put api_path(test_custom_domain.extid), valid_entra_params

        expect(last_response.status).to eq(403)
        body = json_body
        expect(body['message']).to include('owner')
      end

      it 'returns 403 when organization lacks manage_sso entitlement' do
        # In integration tests with billing disabled, all orgs get STANDALONE_ENTITLEMENTS.
        # We stub can? on the specific org instance to test this code path.
        # Note: This requires finding the org that will be loaded by the request.
        allow_any_instance_of(Onetime::Organization).to receive(:can?).with('manage_sso').and_return(false)

        login_as(test_owner)
        csrf_put api_path(test_custom_domain.extid), valid_entra_params

        expect(last_response.status).to eq(403)
        body = json_body
        expect(body['message']).to include('manage_sso')
      end

      it 'returns 404 for non-existent domain' do
        login_as(test_owner)
        csrf_put api_path('nonexistent-domain-extid'), valid_entra_params

        expect(last_response.status).to eq(404)
        body = json_body
        expect(body['message']).to include('Domain not found')
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
        Onetime::DomainSsoConfig.create!(
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
        expect(body['message']).to include('SSO configuration not found')
      end
    end

    context 'authorization checks' do
      before do
        Onetime::DomainSsoConfig.create!(
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
      Onetime::DomainSsoConfig.create!(
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
    end

    context 'when no existing config' do
      before do
        # Remove the existing config
        Onetime::DomainSsoConfig.delete_for_domain!(test_custom_domain.identifier)
        login_as(test_owner)
      end

      it 'creates new config when providing all required fields' do
        csrf_patch api_path(test_custom_domain.extid), valid_entra_params

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']
        expect(record['provider_type']).to eq('entra_id')
      end

      it 'returns 400 when required fields missing for creation' do
        csrf_patch api_path(test_custom_domain.extid), {
          display_name: 'Incomplete Config',
        }

        expect(last_response.status).to eq(400)
        body = json_body
        expect(body['message']).to include('required')
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
        Onetime::DomainSsoConfig.create!(
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
        config = Onetime::DomainSsoConfig.find_by_domain_id(test_custom_domain.identifier)
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
        expect(body['message']).to include('SSO configuration not found')
      end
    end

    context 'authorization checks' do
      before do
        Onetime::DomainSsoConfig.create!(
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
      login_as(test_owner)
    end

    context 'with valid Entra ID config' do
      let(:entra_test_params) do
        {
          provider_type: 'entra_id',
          client_id: 'test-client-id',
          tenant_id: '12345678-1234-1234-1234-123456789abc',
        }
      end

      it 'attempts connection test and returns result' do
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

    context 'with valid Google config' do
      let(:google_test_params) do
        {
          provider_type: 'google',
          client_id: 'test-client.apps.googleusercontent.com',
        }
      end

      it 'tests Google connection' do
        csrf_post test_connection_path(test_custom_domain.extid), google_test_params

        expect(last_response.status).to eq(200)

        body = json_body
        expect(body['provider_type']).to eq('google')
      end
    end

    context 'with valid GitHub config' do
      let(:github_test_params) do
        {
          provider_type: 'github',
          client_id: 'Iv1.1234567890abcdef',
        }
      end

      it 'validates GitHub config format (no network test)' do
        csrf_post test_connection_path(test_custom_domain.extid), github_test_params

        expect(last_response.status).to eq(200)

        body = json_body
        expect(body['provider_type']).to eq('github')
        expect(body['success']).to be true
        expect(body['message']).to include('format validated')
      end
    end

    context 'validation errors' do
      it 'returns 400 for missing provider_type' do
        csrf_post test_connection_path(test_custom_domain.extid), {
          client_id: 'some-client-id',
        }

        expect(last_response.status).to eq(400)
        body = json_body
        expect(body['message']).to include('Provider type')
      end

      it 'returns 400 for missing client_id' do
        csrf_post test_connection_path(test_custom_domain.extid), {
          provider_type: 'entra_id',
          tenant_id: 'some-tenant',
        }

        expect(last_response.status).to eq(400)
        body = json_body
        expect(body['message']).to include('Client ID')
      end

      it 'returns 400 for missing tenant_id on Entra ID' do
        csrf_post test_connection_path(test_custom_domain.extid), {
          provider_type: 'entra_id',
          client_id: 'some-client-id',
        }

        expect(last_response.status).to eq(400)
        body = json_body
        expect(body['message']).to include('Tenant ID')
      end

      it 'returns 400 for invalid tenant_id format on Entra ID' do
        csrf_post test_connection_path(test_custom_domain.extid), {
          provider_type: 'entra_id',
          client_id: 'some-client-id',
          tenant_id: 'not-a-uuid',
        }

        expect(last_response.status).to eq(400)
        body = json_body
        expect(body['message']).to include('UUID')
      end

      it 'returns 400 for missing issuer on OIDC' do
        csrf_post test_connection_path(test_custom_domain.extid), {
          provider_type: 'oidc',
          client_id: 'some-client-id',
        }

        expect(last_response.status).to eq(400)
        body = json_body
        expect(body['message']).to include('Issuer URL')
      end

      it 'returns 400 for invalid Google client_id format' do
        csrf_post test_connection_path(test_custom_domain.extid), {
          provider_type: 'google',
          client_id: 'invalid-google-client',
        }

        expect(last_response.status).to eq(400)
        body = json_body
        expect(body['message']).to include('googleusercontent.com')
      end

      it 'returns 400 for invalid GitHub client_id format' do
        csrf_post test_connection_path(test_custom_domain.extid), {
          provider_type: 'github',
          client_id: 'invalid-github-client',
        }

        expect(last_response.status).to eq(400)
        body = json_body
        expect(body['message']).to include('Iv1')
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

      it 'returns 403 for non-owner' do
        login_as(test_non_owner)

        csrf_post test_connection_path(test_custom_domain.extid), {
          provider_type: 'entra_id',
          client_id: 'client',
          tenant_id: '12345678-1234-1234-1234-123456789abc',
        }

        expect(last_response.status).to eq(403)
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
      Onetime::DomainSsoConfig.create!(
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
        client_id
        client_secret_masked
        tenant_id
        issuer
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
end
