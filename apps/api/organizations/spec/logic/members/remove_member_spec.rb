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
      role: 'customer',
      mailbox_verified?: true,
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

  # The colonel override goes through has_system_role?, which requires
  # mailbox proof (#4735). A colonel-role account stamped only by an IdP
  # ('sso') gets no override and is treated like any other caller.
  describe 'colonel override' do
    let(:mailbox_verified) { true }

    let(:owner) do
      instance_double(
        Onetime::Customer,
        objid: 'cust-colonel-789',
        extid: 'ext-cust-colonel',
        email: 'colonel@example.com',
        anonymous?: false,
        role: 'colonel',
        mailbox_verified?: mailbox_verified,
      )
    end

    let(:target_membership) do
      instance_double(
        Onetime::OrganizationMembership,
        owner?: false,
        role: 'member',
        destroy_with_index_cleanup!: true,
        default_org_cleanup: :cleared,
      )
    end

    context 'with mailbox proof' do
      it 'needs no membership in the organization' do
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer).and_return(nil)

        expect(logic.send(:load_actor_membership, organization)).to be_nil
        expect(OT).to have_received(:info).with(a_string_including('action=colonel_membership_bypass'))
      end

      it 'may remove a member without an organization role' do
        expect { logic.send(:validate_removal!) }.not_to raise_error
      end

      it 'records colonel_override=true in the audit line' do
        logic.process

        expect(OT).to have_received(:info).with(a_string_including('action=member_removed', 'colonel_override=true'))
      end
    end

    context "without mailbox proof (verified_by: 'sso')" do
      let(:mailbox_verified) { false }

      it 'must be a member of the organization' do
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer).and_return(nil)

        expect { logic.send(:load_actor_membership, organization) }.to raise_error(OT::FormError) { |ex|
          expect(ex.error_key).to eq('api.organizations.members.errors.must_be_member')
        }
        expect(OT).not_to have_received(:info).with(a_string_including('colonel_membership_bypass'))
      end

      it 'is limited to what its organization role allows' do
        logic.instance_variable_set(
          :@actor_membership, instance_double(Onetime::OrganizationMembership, role: 'member')
        )

        expect { logic.send(:validate_removal!) }.to raise_error(OT::FormError) { |ex|
          expect(ex.error_key).to eq('api.organizations.members.errors.no_permission_to_remove')
        }
      end

      it 'records colonel_override=false in the audit line' do
        logic.process

        expect(OT).to have_received(:info).with(a_string_including('action=member_removed', 'colonel_override=false'))
      end
    end
  end
end
