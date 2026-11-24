# spec/unit/onetime/models/organization_membership/capabilities_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::OrganizationMembership, :aggregate_failures do # rubocop:disable RSpec/SpecFilePathFormat -- model specs are grouped by feature
  let(:membership) { described_class.new(role: 'admin') }

  before { membership.save }
  after { membership.destroy_with_index_cleanup! if described_class.load(membership.objid) }

  {
    'member' => [],
    'admin' => %w[manage_domains manage_members],
    'owner' => %w[manage_domains manage_members manage_org manage_sso manage_billing],
  }.each do |role, capabilities|
    it "materializes the default capabilities for an active #{role}" do
      membership.role = role
      membership.save

      expect(membership.materialize_capabilities!).to match_array(capabilities)
    end
  end

  it 'materializes existing memberships without consulting organization entitlements' do
    existing_membership = described_class.load(membership.objid)
    expect(existing_membership.materialized_capabilities).to be_nil
    allow(existing_membership).to receive(:organization).and_call_original

    expect(existing_membership.has_capability?(:manage_members)).to be(true)
    expect(existing_membership.has_capability?(:manage_org)).to be(false)
    expect(described_class.load(membership.objid).materialized_capabilities).to contain_exactly('manage_domains', 'manage_members')
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

    expect(membership.materialize_capabilities!).to contain_exactly('manage_domains', 'manage_org')
    expect(membership.has_capability?(:custom_domains)).to be(false)

    membership.clear_entitlement_overrides

    expect(membership.materialize_capabilities!).to contain_exactly('manage_domains', 'manage_members')
  end

  it 'mirrors established capability overrides for older readers and observes an older writer clearing them' do
    membership.grant_capability(:manage_org)
    expect(membership.entitlements_grants.to_a).to include('manage_org')
    expect(membership.materialized_entitlements.to_a).to include('manage_org')
    membership.entitlements_grants.clear
    expect(membership.role_capabilities).not_to include('manage_org')

    membership.entitlements_revokes.add('manage_members')
    expect(membership.has_capability?(:manage_members)).to be(false)
    expect(membership.revoke_capability(:manage_members)).to be(false)
  end

  it 'keeps a new capability separate from identically named historical and member feature overrides' do
    membership.role = 'member'
    membership.save
    membership.grant_entitlement('manage_domains')
    membership.grant_entitlement('custom_domains')
    expect(membership.has_capability?(:manage_domains)).to be(false)
    expect(membership.grant_capability(:manage_domains)).to be(true)
    stale = described_class.load(membership.objid)
    expect(stale.role_capabilities).to eq(['manage_domains'])
    membership.capability_state(action: 'clear')
    stale.save
    expect(membership.has_capability?(:manage_domains)).to be(false)
    expect(membership.entitlements_grants.to_a).to include('custom_domains', 'manage_domains')
    expect { membership.grant_capability('custom_domains') }.to raise_error(ArgumentError)
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
