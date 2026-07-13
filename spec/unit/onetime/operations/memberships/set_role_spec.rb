# spec/unit/onetime/operations/memberships/set_role_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::Operations::Memberships::SetRole (#3731).
#
# Two layers:
#   1. Mocked contract — status routing, exactly-one-audit, no-op audits
#      nothing, invalid-role / not-found / last-owner guardrail. No datastore.
#   2. Real materialization — a member -> owner change flips
#      can?('manage_org') from false to true, proving the op re-materializes
#      entitlements via change_role! (the whole point of the issue).
#
# Run: pnpm run test:rspec spec/unit/onetime/operations/memberships/set_role_spec.rb

require 'spec_helper'
require 'onetime/models/admin_audit_event'
require 'onetime/operations/memberships/set_role'

RSpec.describe Onetime::Operations::Memberships::SetRole do
  let(:actor) { 'ur_col_public_extid' } # PUBLIC identity (extid/email)

  let(:org) do
    double('Organization', objid: 'org-obj-1', extid: 'on_org_ext')
  end

  let(:customer) do
    double('Customer', objid: 'cust-obj-1', extid: 'ur_member')
  end

  before { allow(Onetime::AdminAuditEvent).to receive(:record) }

  describe 'mocked contract' do
    let(:membership) do
      double(
        'OrganizationMembership',
        role: 'member',
        active?: true,
        owner?: false,
        :updated_at= => nil,
        save: true,
      )
    end

    before do
      allow(Onetime::OrganizationMembership)
        .to receive(:find_by_org_customer).with('org-obj-1', 'cust-obj-1').and_return(membership)
      allow(membership).to receive(:change_role!).and_return(true)
    end

    it 'changes the role and returns :success with from/to' do
      result = described_class.new(org: org, customer: customer, new_role: 'admin', actor: actor).call

      expect(result.status).to eq(:success)
      expect(result.from).to eq('member')
      expect(result.to).to eq('admin')
      expect(result.org_id).to eq('on_org_ext')
      expect(result.customer_id).to eq('ur_member')
      expect(membership).to have_received(:change_role!).with('admin')
      expect(membership).to have_received(:save)
    end

    it 'records EXACTLY ONE audit event (public actor, target = member extid, org_id in detail)' do
      described_class.new(org: org, customer: customer, new_role: 'admin', actor: actor).call

      expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'membership.set_role',
        target: 'ur_member',
        result: :success,
        detail: { from: 'member', to: 'admin', org_id: 'on_org_ext' },
      )
    end

    it 'is a :no_change (no change_role!, no audit) when already at the target role' do
      allow(membership).to receive(:role).and_return('admin')

      result = described_class.new(org: org, customer: customer, new_role: 'admin', actor: actor).call

      expect(result.status).to eq(:no_change)
      expect(membership).not_to have_received(:change_role!)
      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end

    it 'returns :invalid_role (no lookup, no audit) for an unknown role' do
      result = described_class.new(org: org, customer: customer, new_role: 'wizard', actor: actor).call

      expect(result.status).to eq(:invalid_role)
      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end

    it 'returns :not_found (no audit) when no active membership exists' do
      allow(Onetime::OrganizationMembership)
        .to receive(:find_by_org_customer).with('org-obj-1', 'cust-obj-1').and_return(nil)

      result = described_class.new(org: org, customer: customer, new_role: 'admin', actor: actor).call

      expect(result.status).to eq(:not_found)
      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end
  end

  describe 'sole-owner guardrail' do
    let(:owner_membership) do
      double(
        'OrganizationMembership',
        role: 'owner',
        active?: true,
        owner?: true,
        :updated_at= => nil,
        save: true,
      )
    end

    before do
      allow(Onetime::OrganizationMembership)
        .to receive(:find_by_org_customer).with('org-obj-1', 'cust-obj-1').and_return(owner_membership)
      allow(owner_membership).to receive(:change_role!).and_return(true)
    end

    it 'refuses to demote the last remaining owner (:last_owner, no change, no audit)' do
      allow(Onetime::OrganizationMembership).to receive(:active_for_org).with(org).and_return([owner_membership])

      result = described_class.new(org: org, customer: customer, new_role: 'admin', actor: actor).call

      expect(result.status).to eq(:last_owner)
      expect(owner_membership).not_to have_received(:change_role!)
      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end

    it 'allows demoting an owner when another owner remains' do
      other_owner = double('OrganizationMembership', owner?: true)
      allow(Onetime::OrganizationMembership)
        .to receive(:active_for_org).with(org).and_return([owner_membership, other_owner])

      result = described_class.new(org: org, customer: customer, new_role: 'admin', actor: actor).call

      expect(result.status).to eq(:success)
      expect(owner_membership).to have_received(:change_role!).with('admin')
    end
  end

  # --- Real materialization: proves can?('manage_org') flips via change_role! ---
  describe 'entitlement materialization (real membership)' do
    let(:org_objid) { 'org-setrole-mat-1' }

    # Stands in for the org side of materialize_for_role! — its entitlement set
    # includes manage_org, so an OWNER membership materializes it.
    let(:org_side) do
      instance_double(
        Onetime::Organization,
        objid: org_objid,
        extid: 'on_mat_ext',
        entitlements: %w[create_secrets api_access manage_members manage_org manage_billing],
      )
    end

    let(:real_membership) do
      m = Onetime::OrganizationMembership.new
      m.organization_objid = org_objid
      m.customer_objid = 'cust-obj-mat'
      m.role = 'member'
      m.save
      # Yield collection writes without a second scalar round-trip (matches the
      # model's own change_role_spec pattern for the unsaved-parent guard).
      allow(m).to receive(:save_with_collections).and_yield.and_return(true)
      m
    end

    before do
      allow(Onetime::Organization).to receive(:load).with(org_objid).and_return(org_side)
      allow(Onetime::OrganizationMembership)
        .to receive(:find_by_org_customer).with(org_objid, 'cust-obj-mat').and_return(real_membership)
    end

    it 'flips can?(manage_org) false -> true when promoting member -> owner' do
      expect(real_membership.can?('manage_org')).to be false

      result = described_class.new(
        org: org_side, customer: customer_for(org_objid), new_role: 'owner', actor: actor
      ).call

      expect(result.status).to eq(:success)
      expect(real_membership.can?('manage_org')).to be true
    end

    def customer_for(_org_objid)
      double('Customer', objid: 'cust-obj-mat', extid: 'ur_mat_member')
    end
  end
end
