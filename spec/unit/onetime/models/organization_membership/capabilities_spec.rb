# spec/unit/onetime/models/organization_membership/capabilities_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::OrganizationMembership, :aggregate_failures do # rubocop:disable RSpec/SpecFilePathFormat -- model specs are grouped by feature
  let(:membership) { described_class.new(role: 'admin') }

  before { membership.save }
  after { membership.destroy_with_index_cleanup! if described_class.load(membership.objid) }

  it 'materializes existing memberships without consulting organization entitlements' do
    existing_membership = described_class.load(membership.objid)
    expect(existing_membership.materialized_capabilities).to be_nil
    allow(existing_membership).to receive(:organization).and_call_original

    expect(existing_membership.has_capability?(:manage_members)).to be(true)
    expect(existing_membership.has_capability?(:manage_org)).to be(false)
    expect(described_class.load(membership.objid).materialized_capabilities).to eq(['manage_members'])
    expect(existing_membership).not_to have_received(:organization)
  end

  it 'resolves the latest stored role even from an instance loaded before a demotion' do
    stale_membership = described_class.load(membership.objid)
    expect(stale_membership.has_capability?(:manage_members)).to be(true)

    membership.role = 'member'
    membership.save

    expect(stale_membership.has_capability?(:manage_members)).to be(false)
    expect(described_class.load(membership.objid).materialized_capabilities).to eq([])
  end

  it 'uses member overrides for capability names and applies revokes last' do
    membership.grant_entitlement('manage_org')
    membership.grant_entitlement('custom_domains')
    membership.revoke_entitlement('manage_members')
    membership.entitlements_grants.add('manage_members')

    expect(membership.materialize_capabilities!).to eq(['manage_org'])
    expect(membership.has_capability?(:custom_domains)).to be(false)

    membership.clear_entitlement_overrides

    expect(membership.materialize_capabilities!).to eq(['manage_members'])
  end

  it 'does not grant capabilities to a pending invitation or a removed membership' do
    expect(membership.has_capability?(:manage_members)).to be(true)
    membership.status = 'pending'
    membership.save
    expect(membership.has_capability?(:manage_members)).to be(false)
    expect(described_class.load(membership.objid).materialized_capabilities).to eq([])

    membership.destroy_with_index_cleanup!
    expect(membership.has_capability?(:manage_members)).to be(false)
    expect(described_class.load(membership.objid)).to be_nil
  end
end
