# apps/api/account/spec/logic/account/update_default_organization_spec.rb
#
# frozen_string_literal: true

# Unit tests for setting the user's default organization. The membership,
# archived and domain-scope decisions are made by the real
# Onetime::Application::OrganizationLoader; only datastore reads and the
# customer write are stubbed.
#
# Run with:
#   tests/lanes/run unit --only apps/api/account/spec/logic/account/update_default_organization_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'account/logic'

RSpec.describe AccountAPI::Logic::Account::UpdateDefaultOrganization do
  subject(:logic) { described_class.new(strategy_result, params) }

  # The user's own default workspace, the default before the change.
  let(:personal_org) do
    instance_double(Onetime::Organization, objid: 'org-personal-111', archived?: false, is_default: true)
  end

  # Another customer's default workspace the user is a member of.
  let(:target_org) do
    instance_double(Onetime::Organization, objid: 'org-target-222', archived?: false, is_default: true)
  end

  let(:customer) do
    instance_double(
      Onetime::Customer,
      objid: 'test-cust-123',
      extid: 'urtest-cust-123',
      custid: 'test-cust-123',
      anonymous?: false,
      default_org_id: '',
      organization_instances: [personal_org, target_org],
    )
  end

  let(:session) { { 'csrf' => 'test-csrf-token' } }
  let(:scope_domains) { [] }
  let(:organization_context) { { organization: personal_org, scope_domains: scope_domains } }

  let(:strategy_result) do
    double(
      'StrategyResult',
      session: session,
      user: customer,
      authenticated?: true,
      metadata: { organization_context: organization_context },
    )
  end

  let(:params) { { 'organization_id' => target_org.objid } }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(Onetime::Organization).to receive(:load).and_return(nil)
    allow(Onetime::Organization).to receive(:load).with(target_org.objid).and_return(target_org)
    allow(target_org).to receive(:member?).with(customer).and_return(true)
    allow(personal_org).to receive(:owner?).with(customer).and_return(true)
    allow(target_org).to receive(:owner?).with(customer).and_return(false)
    allow(customer).to receive(:default_org_id!)
  end

  describe '#raise_concerns' do
    it 'accepts an organization the user may select' do
      expect { logic.raise_concerns }.not_to raise_error
    end

    it 'requires an organization id' do
      params['organization_id'] = '  '
      expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Organization is required/)
    end

    it 'does not turn a malformed id into a different one' do
      params['organization_id'] = "../#{target_org.objid}"
      expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Organization is required/)
    end

    # Not a member and archived are refused alike, without saying which.
    it 'refuses an organization the user is not a member of' do
      allow(target_org).to receive(:member?).with(customer).and_return(false)
      expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /\AInvalid organization\z/)
    end

    it 'refuses an archived organization' do
      allow(target_org).to receive(:archived?).and_return(true)
      expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /\AInvalid organization\z/)
    end

    it 'refuses when the domain scope cannot be checked' do
      allow(strategy_result).to receive(:metadata).and_return({})
      expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /\AInvalid organization\z/)
    end

    it 'refuses anonymous users' do
      allow(customer).to receive(:anonymous?).and_return(true)
      expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Authentication required/)
    end
  end

  describe '#process' do
    before { logic.raise_concerns }

    it 'writes the default organization' do
      logic.process
      expect(customer).to have_received(:default_org_id!).with(target_org.objid)
    end

    # An older selection in the session would otherwise keep winning over
    # the new default in this browser.
    it 'selects the organization for the session' do
      session['organization_id'] = personal_org.objid
      logic.process
      expect(session['organization_id']).to eq(target_org.objid)
      expect(session['organization_selected_at']).to be_a(Integer)
    end

    it 'reports the new and the previous default' do
      expect(logic.process).to eq(
        organization_id: target_org.objid,
        previous_default_organization_id: personal_org.objid,
      )
    end

    context 'when the membership is revoked between the checks' do
      before { allow(target_org).to receive(:member?).with(customer).and_return(false) }

      it 'refuses and writes nothing' do
        expect { logic.process }.to raise_error(Onetime::FormError, /\AInvalid organization\z/)
        expect(customer).not_to have_received(:default_org_id!)
        expect(session).not_to include('organization_id')
      end
    end
  end

  describe 'route declaration' do
    let(:route_line) do
      File.readlines(File.join(Onetime::HOME, 'apps/api/account/routes.txt'))
        .find { |line| line.include?('/update-default-organization') }
    end

    it 'is a POST to this logic class with session auth only' do
      expect(route_line).to match(%r{\APOST\s+/update-default-organization\s+#{described_class.name}\s})
      expect(route_line).to include('response=json', 'auth=sessionauth')
      expect(route_line).not_to include('basicauth')
    end
  end
end
