# apps/api/organizations/spec/logic/sso_config/delete_sso_config_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'organizations/logic'

RSpec.describe OrganizationAPI::Logic::SsoConfig::DeleteSsoConfig do
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
        allow(Onetime::OrgSsoConfig).to receive(:exists_for_org?).with('org-123').and_return(false)
      end

      it 'raises not found error' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::RecordNotFound,
        )
      end
    end
  end

  describe '#process' do
    before do
      allow(Onetime::Organization).to receive(:find_by_extid).with('ext-org-123').and_return(organization)
      allow(organization).to receive(:owner?).with(customer).and_return(true)
      allow(Onetime::OrgSsoConfig).to receive(:exists_for_org?).with('org-123').and_return(true)
      # Call raise_concerns to set up instance variables before process
      logic.raise_concerns
    end

    it 'calls delete_for_org!' do
      expect(Onetime::OrgSsoConfig).to receive(:delete_for_org!).with('org-123').and_return(true)
      logic.process
    end

    it 'logs the deletion' do
      allow(Onetime::OrgSsoConfig).to receive(:delete_for_org!).and_return(true)

      expect(OT).to receive(:info).with(
        '[DeleteSsoConfig] SSO config deleted for org ext-org-123',
        hash_including(org_extid: 'ext-org-123', user_extid: 'ext-cust-123'),
      )

      logic.process
    end
  end

  describe '#success_data' do
    before do
      allow(Onetime::Organization).to receive(:find_by_extid).with('ext-org-123').and_return(organization)
      allow(organization).to receive(:owner?).with(customer).and_return(true)
      allow(Onetime::OrgSsoConfig).to receive(:exists_for_org?).with('org-123').and_return(true)
      allow(Onetime::OrgSsoConfig).to receive(:delete_for_org!).with('org-123').and_return(true)
      # Call raise_concerns to set up instance variables before process
      logic.raise_concerns
    end

    it 'includes success flag' do
      result = logic.process
      expect(result[:success]).to be true
    end

    it 'includes message' do
      result = logic.process
      expect(result[:message]).to eq('SSO configuration deleted for organization ext-org-123')
    end
  end

  describe '#form_fields' do
    it 'includes extid' do
      # process_params is called in initialize
      expect(logic.form_fields).to eq({ extid: 'ext-org-123' })
    end
  end
end
