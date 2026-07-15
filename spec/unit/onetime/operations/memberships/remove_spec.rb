# spec/unit/onetime/operations/memberships/remove_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::Operations::Memberships::Remove (#3731).
#
# Covers: successful removal (destroy_with_index_cleanup! + exactly one audit),
# not-found (no destroy, no audit), and the sole-owner guardrail (blocks the
# destroy + audits nothing).
#
# Run: pnpm run test:rspec spec/unit/onetime/operations/memberships/remove_spec.rb

require 'spec_helper'
require 'onetime/models/admin_audit_event'
require 'onetime/operations/memberships/remove'

RSpec.describe Onetime::Operations::Memberships::Remove do
  let(:actor) { 'ur_col_public_extid' }

  let(:org) do
    double('Organization', objid: 'org-obj-1', extid: 'on_org_ext')
  end

  let(:customer) do
    double('Customer', objid: 'cust-obj-1', extid: 'ur_member')
  end

  before { allow(Onetime::AdminAuditEvent).to receive(:record) }

  context 'when an active member is removed' do
    let(:membership) do
      double('OrganizationMembership', role: 'admin', owner?: false, destroy_with_index_cleanup!: true)
    end

    before do
      allow(Onetime::OrganizationMembership)
        .to receive(:find_by_org_customer).with('org-obj-1', 'cust-obj-1').and_return(membership)
    end

    it 'tears down the membership and returns :success with the removed role' do
      result = described_class.new(org: org, customer: customer, actor: actor).call

      expect(result.status).to eq(:success)
      expect(result.role).to eq('admin')
      expect(membership).to have_received(:destroy_with_index_cleanup!)
    end

    it 'records EXACTLY ONE audit event (verb membership.remove, public ids, org_id in detail)' do
      described_class.new(org: org, customer: customer, actor: actor).call

      expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'membership.remove',
        target: 'ur_member',
        result: :success,
        detail: { org_id: 'on_org_ext' },
      )
    end
  end

  it 'returns :not_found (no audit) when the membership does not exist' do
    allow(Onetime::OrganizationMembership)
      .to receive(:find_by_org_customer).with('org-obj-1', 'cust-obj-1').and_return(nil)

    result = described_class.new(org: org, customer: customer, actor: actor).call

    expect(result.status).to eq(:not_found)
    expect(Onetime::AdminAuditEvent).not_to have_received(:record)
  end

  context 'sole-owner guardrail' do
    let(:owner_membership) do
      double('OrganizationMembership', role: 'owner', owner?: true, destroy_with_index_cleanup!: true)
    end

    before do
      allow(Onetime::OrganizationMembership)
        .to receive(:find_by_org_customer).with('org-obj-1', 'cust-obj-1').and_return(owner_membership)
    end

    it 'refuses to remove the last remaining owner (:last_owner, no destroy, no audit)' do
      allow(Onetime::OrganizationMembership).to receive(:active_for_org).with(org).and_return([owner_membership])

      result = described_class.new(org: org, customer: customer, actor: actor).call

      expect(result.status).to eq(:last_owner)
      expect(owner_membership).not_to have_received(:destroy_with_index_cleanup!)
      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end

    it 'allows removing an owner when another owner remains' do
      other_owner = double('OrganizationMembership', owner?: true)
      allow(Onetime::OrganizationMembership)
        .to receive(:active_for_org).with(org).and_return([owner_membership, other_owner])

      result = described_class.new(org: org, customer: customer, actor: actor).call

      expect(result.status).to eq(:success)
      expect(owner_membership).to have_received(:destroy_with_index_cleanup!)
    end
  end
end
