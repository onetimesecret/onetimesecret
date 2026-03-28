# apps/api/organizations/spec/logic/sso_config/get_sso_config_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'organizations/logic'

RSpec.describe OrganizationAPI::Logic::SsoConfig::GetSsoConfig do
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
      config.encryption_personalization = 'SsoConfigTest'
    end
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

  let(:session) { { 'csrf' => 'test-csrf-token' } }

  let(:strategy_result) do
    double('StrategyResult',
      session: session,
      user: customer,
      authenticated?: true,
      metadata: {},
    )
  end

  let(:params) do
    { 'extid' => 'ext-org-123' }
  end

  subject(:logic) { described_class.new(strategy_result, params) }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
  end

  describe '#process_params' do
    it 'extracts extid from params' do
      expect(logic.instance_variable_get(:@extid)).to eq('ext-org-123')
    end

    it 'sanitizes extid' do
      params['extid'] = 'ext-org-123<script>'
      expect(logic.instance_variable_get(:@extid)).to eq('ext-org-123script')
    end
  end

  describe '#raise_concerns' do
    context 'when customer is anonymous' do
      let(:customer) do
        instance_double(
          Onetime::Customer,
          objid: 'anon-123',
          anonymous?: true,
        )
      end

      it 'raises unauthorized error' do
        expect { logic.raise_concerns }.to raise_error(
          OT::FormError,
          'Authentication required',
        )
      end
    end

    context 'when extid is missing' do
      let(:params) { { 'extid' => '' } }

      it 'raises missing error' do
        expect { logic.raise_concerns }.to raise_error(
          OT::FormError,
          'Organization ID required',
        )
      end
    end

    context 'when organization does not exist' do
      before do
        allow(Onetime::Organization).to receive(:find_by_extid).with('ext-org-123').and_return(nil)
      end

      it 'raises not found error' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::RecordNotFound,
        )
      end
    end

    context 'when user is not organization owner' do
      before do
        allow(Onetime::Organization).to receive(:find_by_extid).with('ext-org-123').and_return(organization)
        allow(organization).to receive(:owner?).with(customer).and_return(false)
      end

      it 'raises forbidden error' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::Forbidden,
          'Only organization owner can perform this action',
        )
      end
    end

    context 'when SSO config does not exist' do
      before do
        allow(Onetime::Organization).to receive(:find_by_extid).with('ext-org-123').and_return(organization)
        allow(organization).to receive(:owner?).with(customer).and_return(true)
        allow(Onetime::OrgSsoConfig).to receive(:find_by_org_id).with('org-123').and_return(nil)
      end

      it 'raises not found error' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::RecordNotFound,
        )
      end
    end
  end

  describe '#process' do
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
      # Stub persistence
      config.define_singleton_method(:save) { true }
      config
    end

    before do
      allow(Onetime::Organization).to receive(:find_by_extid).with('ext-org-123').and_return(organization)
      allow(organization).to receive(:owner?).with(customer).and_return(true)
      allow(Onetime::OrgSsoConfig).to receive(:find_by_org_id).with('org-123').and_return(sso_config)
      # Call raise_concerns to set up instance variables before process
      logic.raise_concerns
    end

    it 'returns success_data with serialized config' do
      result = logic.process
      expect(result).to have_key(:user_id)
      expect(result).to have_key(:record)
    end

    it 'includes user_id in response' do
      result = logic.process
      expect(result[:user_id]).to eq('ext-cust-123')
    end

    it 'includes config fields in record' do
      result = logic.process
      record = result[:record]

      expect(record[:org_id]).to eq('org-123')
      expect(record[:provider_type]).to eq('entra_id')
      expect(record[:display_name]).to eq('Contoso SSO')
      expect(record[:tenant_id]).to eq('tenant-uuid-123')
      expect(record[:enabled]).to be true
      expect(record[:allowed_domains]).to eq(['contoso.com'])
    end

    it 'reveals client_id' do
      result = logic.process
      expect(result[:record][:client_id]).to eq('client-id-123')
    end

    it 'masks client_secret showing only last 4 chars' do
      result = logic.process
      # "super-secret-value" -> last 4 chars are "alue"
      expect(result[:record][:client_secret_masked]).to eq('••••••••alue')
    end

    it 'includes timestamps as Unix integers' do
      result = logic.process
      record = result[:record]

      expect(record[:created_at]).to be_a(Integer)
      expect(record[:updated_at]).to be_a(Integer)
    end

    it 'includes non-zero timestamps when config has timestamps set' do
      # Set timestamps on the config to simulate a properly created config
      sso_config.created = 1700000000
      sso_config.updated = 1700000000

      result = logic.process
      record = result[:record]

      expect(record[:created_at]).to be > 0
      expect(record[:updated_at]).to be > 0
    end
  end

  describe 'secret masking' do
    let(:sso_config) do
      config = Onetime::OrgSsoConfig.new(
        org_id: 'org-123',
        provider_type: 'oidc',
        enabled: 'true',
      )
      config.define_singleton_method(:save) { true }
      config
    end

    before do
      allow(Onetime::Organization).to receive(:find_by_extid).with('ext-org-123').and_return(organization)
      allow(organization).to receive(:owner?).with(customer).and_return(true)
      allow(Onetime::OrgSsoConfig).to receive(:find_by_org_id).with('org-123').and_return(sso_config)
      # Call raise_concerns to set up instance variables before process
      logic.raise_concerns
    end

    context 'when client_secret is short (<= 4 chars)' do
      before do
        sso_config.client_id = 'test'
        sso_config.client_secret = 'abc'
      end

      it 'returns only mask without revealing any characters' do
        result = logic.process
        expect(result[:record][:client_secret_masked]).to eq('••••••••')
      end
    end

    context 'when client_secret is nil' do
      it 'returns nil' do
        result = logic.process
        expect(result[:record][:client_secret_masked]).to be_nil
      end
    end
  end
end
