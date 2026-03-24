# apps/api/organizations/spec/integration/sso_config_spec.rb
#
# frozen_string_literal: true

# Integration tests for SSO Config API endpoints
#
# These tests verify the full HTTP request/response cycle through
# the Organization API for SSO configuration CRUD operations.
#
# Run:
#   pnpm run test:rspec apps/api/organizations/spec/integration/sso_config_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'rack/test'
require 'organizations/application'
require 'organizations/logic'

RSpec.describe 'SSO Config API Integration', type: :request do
  include Rack::Test::Methods

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
      config.encryption_personalization = 'SsoConfigIntegrationTest'
    end
  end

  def app
    OrganizationAPI::Application.new
  end

  let(:customer) do
    instance_double(
      Onetime::Customer,
      objid: 'cust-123',
      custid: 'cust-123',
      extid: 'ext-cust-123',
      email: 'owner@example.com',
      anonymous?: false,
      role: 'customer',
    )
  end

  let(:organization) do
    instance_double(
      Onetime::Organization,
      objid: 'org-123',
      extid: 'ext-org-123',
      display_name: 'Test Organization',
    )
  end

  let(:sso_config) do
    config = Onetime::OrgSsoConfig.new(
      org_id: 'org-123',
      provider_type: 'entra_id',
      display_name: 'Contoso SSO',
      tenant_id: 'tenant-uuid-123',
      enabled: 'true',
    )
    config.client_id = 'client-id-123'
    config.client_secret = 'super-secret-value'
    config.allowed_domains = ['contoso.com']
    config.define_singleton_method(:save) { true }
    config
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
  end

  describe 'GET /:extid/sso' do
    context 'when authenticated as org owner with existing config' do
      before do
        # Mock authentication - this would normally be handled by auth middleware
        allow_any_instance_of(OrganizationAPI::Logic::SsoConfig::GetSsoConfig)
          .to receive(:cust).and_return(customer)
        allow(Onetime::Organization).to receive(:find_by_extid).with('ext-org-123').and_return(organization)
        allow(organization).to receive(:owner?).with(customer).and_return(true)
        allow(Onetime::OrgSsoConfig).to receive(:find_by_org_id).with('org-123').and_return(sso_config)
      end

      it 'returns 200 with masked config', skip: 'Integration tests require full app setup' do
        get '/ext-org-123/sso'
        expect(last_response.status).to eq(200)

        body = JSON.parse(last_response.body)
        expect(body['record']['provider_type']).to eq('entra_id')
        expect(body['record']['client_secret']).to match(/^••••••••/)
      end
    end

    context 'when config does not exist' do
      before do
        allow_any_instance_of(OrganizationAPI::Logic::SsoConfig::GetSsoConfig)
          .to receive(:cust).and_return(customer)
        allow(Onetime::Organization).to receive(:find_by_extid).with('ext-org-123').and_return(organization)
        allow(organization).to receive(:owner?).with(customer).and_return(true)
        allow(Onetime::OrgSsoConfig).to receive(:find_by_org_id).with('org-123').and_return(nil)
      end

      it 'returns 404', skip: 'Integration tests require full app setup' do
        get '/ext-org-123/sso'
        expect(last_response.status).to eq(404)
      end
    end
  end

  describe 'PUT /:extid/sso' do
    let(:valid_params) do
      {
        provider_type: 'entra_id',
        display_name: 'Contoso SSO',
        client_id: 'new-client-id',
        client_secret: 'new-client-secret',
        tenant_id: 'new-tenant-id',
        allowed_domains: ['contoso.com'],
        enabled: true,
      }
    end

    context 'when creating new config' do
      before do
        allow_any_instance_of(OrganizationAPI::Logic::SsoConfig::PutSsoConfig)
          .to receive(:cust).and_return(customer)
        allow(Onetime::Organization).to receive(:find_by_extid).with('ext-org-123').and_return(organization)
        allow(organization).to receive(:owner?).with(customer).and_return(true)
        allow(Onetime::OrgSsoConfig).to receive(:find_by_org_id).with('org-123').and_return(nil)
        allow(Onetime::OrgSsoConfig).to receive(:create!).and_return(sso_config)
      end

      it 'returns 200 with created config', skip: 'Integration tests require full app setup' do
        put '/ext-org-123/sso', valid_params.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)

        body = JSON.parse(last_response.body)
        expect(body['record']['provider_type']).to eq('entra_id')
      end
    end
  end

  describe 'DELETE /:extid/sso' do
    context 'when config exists' do
      before do
        allow_any_instance_of(OrganizationAPI::Logic::SsoConfig::DeleteSsoConfig)
          .to receive(:cust).and_return(customer)
        allow(Onetime::Organization).to receive(:find_by_extid).with('ext-org-123').and_return(organization)
        allow(organization).to receive(:owner?).with(customer).and_return(true)
        allow(Onetime::OrgSsoConfig).to receive(:exists_for_org?).with('org-123').and_return(true)
        allow(Onetime::OrgSsoConfig).to receive(:delete_for_org!).with('org-123').and_return(true)
      end

      it 'returns 200 with deleted confirmation', skip: 'Integration tests require full app setup' do
        delete '/ext-org-123/sso'
        expect(last_response.status).to eq(200)

        body = JSON.parse(last_response.body)
        expect(body['deleted']).to be true
      end
    end
  end

  # Integration test for PUT/PATCH lifecycle
  #
  # This test verifies that:
  # 1. PUT creates config with client_secret
  # 2. PATCH updates display_name without providing client_secret (preserves existing secret)
  # 3. The secret is still usable after PATCH (verifying preservation)
  #
  # This tests the real Logic layer classes in sequence, without HTTP routing,
  # to validate the PUT -> PATCH workflow for client_secret preservation.
  describe 'PUT/PATCH lifecycle: client_secret preservation' do
    let(:original_secret) { 'initial-super-secret-value' }
    let(:updated_display_name) { 'Updated SSO Display Name' }

    let(:put_params) do
      {
        'extid' => 'ext-org-123',
        'provider_type' => 'entra_id',
        'display_name' => 'Contoso SSO',
        'client_id' => 'client-id-123',
        'client_secret' => original_secret,
        'tenant_id' => 'tenant-uuid-789',
        'allowed_domains' => ['contoso.com'],
        'enabled' => true,
      }
    end

    let(:patch_params) do
      {
        'extid' => 'ext-org-123',
        'provider_type' => 'entra_id',
        'display_name' => updated_display_name,
        'client_id' => 'client-id-123',
        'client_secret' => '', # Empty - should preserve existing secret
        'tenant_id' => 'tenant-uuid-789',
        'allowed_domains' => ['contoso.com'],
        'enabled' => true,
      }
    end

    let(:session) { { 'csrf' => 'test-csrf-token' } }

    let(:strategy_result) do
      double('StrategyResult',
        session: session,
        user: customer,
        authenticated?: true,
        metadata: {},
      )
    end

    # Shared mutable config instance to track state across PUT -> PATCH
    let(:shared_config) do
      Onetime::OrgSsoConfig.new(
        org_id: 'org-123',
        provider_type: 'entra_id',
        display_name: 'Contoso SSO',
        tenant_id: 'tenant-uuid-789',
        enabled: 'true',
      )
    end

    before do
      allow(Onetime::Organization).to receive(:find_by_extid).with('ext-org-123').and_return(organization)
      allow(organization).to receive(:owner?).with(customer).and_return(true)
    end

    it 'preserves client_secret through PUT -> PATCH -> verification cycle' do
      # Phase 1: PUT creates config with client_secret
      allow(Onetime::OrgSsoConfig).to receive(:find_by_org_id).with('org-123').and_return(nil)

      put_logic = OrganizationAPI::Logic::SsoConfig::PutSsoConfig.new(strategy_result, put_params)

      # Stub create! to return shared_config and simulate creation
      allow(Onetime::OrgSsoConfig).to receive(:create!) do |params|
        shared_config.client_id = params[:client_id]
        shared_config.client_secret = params[:client_secret]
        shared_config.allowed_domains = params[:allowed_domains]
        shared_config.define_singleton_method(:save) { true }
        shared_config
      end

      put_logic.raise_concerns
      put_result = put_logic.process

      # Verify PUT created the secret
      expect(shared_config.client_secret.reveal { it }).to eq(original_secret)
      expect(shared_config.display_name).to eq('Contoso SSO')

      # Phase 2: PATCH updates display_name without client_secret
      allow(Onetime::OrgSsoConfig).to receive(:find_by_org_id).with('org-123').and_return(shared_config)
      allow(shared_config).to receive(:save).and_return(true)

      patch_logic = OrganizationAPI::Logic::SsoConfig::PatchSsoConfig.new(strategy_result, patch_params)
      patch_logic.raise_concerns
      patch_result = patch_logic.process

      # Verify PATCH updated display_name
      expect(shared_config.display_name).to eq(updated_display_name)

      # Phase 3: Verify client_secret was preserved (not overwritten)
      revealed_secret = shared_config.client_secret.reveal { it }
      expect(revealed_secret).to eq(original_secret)
      expect(revealed_secret).not_to be_empty
    end

    it 'allows updating client_secret when explicitly provided in PATCH' do
      new_secret = 'brand-new-rotated-secret'

      # Setup: config already exists with original secret
      shared_config.client_id = 'client-id-123'
      shared_config.client_secret = original_secret
      shared_config.allowed_domains = ['contoso.com']
      allow(shared_config).to receive(:save).and_return(true)

      allow(Onetime::OrgSsoConfig).to receive(:find_by_org_id).with('org-123').and_return(shared_config)

      patch_with_new_secret = patch_params.merge('client_secret' => new_secret)
      patch_logic = OrganizationAPI::Logic::SsoConfig::PatchSsoConfig.new(strategy_result, patch_with_new_secret)
      patch_logic.raise_concerns
      patch_logic.process

      # Verify secret was rotated
      expect(shared_config.client_secret.reveal { it }).to eq(new_secret)
    end
  end
end
