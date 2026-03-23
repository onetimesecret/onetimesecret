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
        allow_any_instance_of(OrganizationAPI::Logic::SsoConfig::UpdateSsoConfig)
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
end
