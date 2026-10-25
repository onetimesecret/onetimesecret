# apps/api/organizations/spec/logic/members/remove_member_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'organizations/logic'

# The removal records the member's default_org_id cleanup outcome in its
# audit line and warns when the pointer may have survived; the response is
# unchanged (#4860).
RSpec.describe OrganizationAPI::Logic::Members::RemoveMember do
  let(:owner) do
    instance_double(
      Onetime::Customer,
      objid: 'cust-owner-123',
      extid: 'ext-cust-owner',
      email: 'owner@example.com',
      anonymous?: false,
      'role?': false,
    )
  end

  let(:target_member) do
    instance_double(
      Onetime::Customer,
      objid: 'cust-target-456',
      extid: 'ext-cust-target',
      email: 'member@example.com',
      locale: 'en',
    )
  end

  let(:organization) do
    instance_double(
      Onetime::Organization,
      objid: 'org-123',
      extid: 'ext-org-123',
      display_name: 'Test Organization',
      clear_default_org_pointer: :cleared,
    )
  end

  let(:target_membership) do
    instance_double(Onetime::OrganizationMembership, destroy_with_index_cleanup!: true, default_org_cleanup: :cleared)
  end

  let(:logic) do
    strategy_result = double('StrategyResult', session: {}, user: owner, authenticated?: true, metadata: {})
    described_class.new(strategy_result, { 'extid' => 'ext-org-123', 'member_extid' => 'ext-cust-target' }).tap do |l|
      l.instance_variable_set(:@organization, organization)
      l.instance_variable_set(:@target_member, target_member)
      l.instance_variable_set(:@target_membership, target_membership)
    end
  end

  before do
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email)
    allow(OT).to receive(:info)
    allow(OT).to receive(:lw)
  end

  it "clears the caller's copy of the pointer after the teardown" do
    logic.process

    expect(target_membership).to have_received(:destroy_with_index_cleanup!).ordered
    expect(organization).to have_received(:clear_default_org_pointer).with(target_member, prior: :cleared).ordered
  end

  it 'records the cleanup outcome in the audit line and returns the usual response' do
    data = logic.process

    expect(OT).to have_received(:info).with(a_string_including('action=member_removed', 'default_org_cleanup=cleared'))
    expect(OT).not_to have_received(:lw)
    expect(data).to eq(deleted: true, member_extid: 'ext-cust-target')
  end

  it 'warns when the pointer may still name the org, and still reports the removal' do
    allow(organization).to receive(:clear_default_org_pointer).and_return(:failed)

    data = logic.process

    expect(OT).to have_received(:info).with(a_string_including('default_org_cleanup=failed'))
    expect(OT).to have_received(:lw).with(a_string_including('target=ext-cust-target', 'org=ext-org-123'))
    expect(data).to eq(deleted: true, member_extid: 'ext-cust-target')
  end
end
