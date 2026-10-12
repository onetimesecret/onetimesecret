# apps/web/core/spec/views/serializers/organization_serializer_membership_spec.rb
#
# frozen_string_literal: true

# The bootstrap payload's is_current_user_default and current_user_role
# answer from the request's Onetime::MembershipSnapshot, which the
# organization loader filled during auth: the membership list and the
# ownership of each organization are read once per request, not again by
# the serializer.
#
# Run: tests/lanes/run unit --only apps/web/core/spec/views/serializers/organization_serializer_membership_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../views/serializers'
require 'onetime/application/organization_loader'

RSpec.describe Core::Views::OrganizationSerializer do
  let(:org) do
    instance_double(
      Onetime::Organization,
      objid: 'org_obj_123',
      extid: 'onabc123',
      display_name: 'Acme Workspace',
      is_default: true,
      archived?: false,
      planid: 'free_v1',
      entitlements: %w[create_secrets],
    )
  end
  let(:default_org_id) { '' }
  let(:cust) do
    double(
      'customer',
      objid: 'cust_obj_123',
      anonymous?: false,
      default_org_id: default_org_id,
      organization_instances: [org],
    )
  end
  let(:view_vars) { { 'authenticated' => true, 'organization' => org, 'cust' => cust } }

  before do
    allow(org).to receive(:limit_for).and_return(1)
    Onetime::MembershipSnapshot.open
  end

  after { Onetime::MembershipSnapshot.close }

  def serialized_org
    described_class.serialize(view_vars)['organization']
  end

  it 'marks the owned default workspace from one read of ownership' do
    expect(cust).to receive(:organization_instances).once.and_return([org])
    expect(org).to receive(:owner?).with(cust).once.and_return(true)

    payload = serialized_org

    expect(payload['is_current_user_default']).to be(true)
    expect(payload['current_user_role']).to eq('owner')
  end

  it 'reuses what the loader read during auth' do
    expect(cust).to receive(:organization_instances).once.and_return([org])
    expect(org).to receive(:owner?).with(cust).once.and_return(true)

    Onetime::Application::OrganizationLoader.load_organization_context(cust, {}, {})

    expect(serialized_org['is_current_user_default']).to be(true)
  end

  context 'for a member of someone else\'s workspace' do
    let(:membership) { instance_double(Onetime::OrganizationMembership, role: 'admin') }

    before do
      allow(org).to receive(:owner?).with(cust).and_return(false)
      allow(org).to receive(:member?).with(cust).and_return(true)
    end

    it 'reads the membership record once for the role' do
      expect(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
        .with(org.objid, cust.objid).once.and_return(membership)

      expect(serialized_org['current_user_role']).to eq('admin')
      expect(serialized_org['is_current_user_default']).to be(false)
    end

    context 'when the preference names it' do
      let(:default_org_id) { org.objid }

      it 'is the user default without a membership-record read' do
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer).and_return(membership)

        expect(serialized_org['is_current_user_default']).to be(true)
      end
    end
  end

  it 'reads again once the request changed the preference' do
    expect(cust).to receive(:organization_instances).twice.and_return([org])
    allow(org).to receive(:owner?).with(cust).and_return(true)

    serialized_org
    Onetime::MembershipSnapshot.forget(cust)
    serialized_org
  end
end
