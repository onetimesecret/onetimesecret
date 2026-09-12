# spec/unit/onetime/operations/memberships/remove_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::Operations::Memberships::Remove (#3731).
#
# Covers: successful removal (destroy_with_index_cleanup! + exactly one audit),
# not-found and the sole-owner guardrail (no destroy, one result: :failure audit
# event each), and a raising teardown (AuditedFailure records + re-raises).
#
# Run: pnpm run test:rspec spec/unit/onetime/operations/memberships/remove_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'onetime/operations/memberships/remove'

RSpec.describe Onetime::Operations::Memberships::Remove do
  let(:actor) { 'ur_col_public_extid' }

  let(:org) do
    double('Organization', objid: 'org-obj-1', extid: 'on_org_ext')
  end

  let(:customer) do
    double('Customer', objid: 'cust-obj-1', extid: 'ur_member')
  end

  before { allow(Onetime::ColonelAuditEvent).to receive(:record) }

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

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'membership.remove',
        target: 'ur_member',
        result: :success,
        detail: { org_id: 'on_org_ext' },
        # #4333: the membership row is destroyed, so the write is fail-closed.
        # #record_refusal (below) deliberately stays fail-open.
        fail_closed: true,
      )
    end
  end

  # A refusal is an ATTEMPTED privileged mutation, so it lands in the trail with
  # the same verb/target as a success — differing only in result:/detail.
  it 'returns :not_found and records ONE result: :failure event' do
    allow(Onetime::OrganizationMembership)
      .to receive(:find_by_org_customer).with('org-obj-1', 'cust-obj-1').and_return(nil)

    result = described_class.new(org: org, customer: customer, actor: actor).call

    expect(result.status).to eq(:not_found)
    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      actor: actor,
      verb: 'membership.remove',
      target: 'ur_member',
      result: :failure,
      detail: { reason: 'not_found', role: nil, org_id: 'on_org_ext' },
    )
  end

  context 'sole-owner guardrail' do
    let(:owner_membership) do
      double('OrganizationMembership', role: 'owner', owner?: true, destroy_with_index_cleanup!: true)
    end

    before do
      allow(Onetime::OrganizationMembership)
        .to receive(:find_by_org_customer).with('org-obj-1', 'cust-obj-1').and_return(owner_membership)
    end

    it 'refuses to remove the last remaining owner (:last_owner, no destroy, ONE failure audit)' do
      allow(Onetime::OrganizationMembership).to receive(:active_for_org).with(org).and_return([owner_membership])

      result = described_class.new(org: org, customer: customer, actor: actor).call

      expect(result.status).to eq(:last_owner)
      expect(owner_membership).not_to have_received(:destroy_with_index_cleanup!)
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'membership.remove',
        target: 'ur_member',
        result: :failure,
        detail: { reason: 'last_owner', role: 'owner', org_id: 'on_org_ext' },
      )
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

  # The Onetime::AuditedFailure mechanism. destroy_with_index_cleanup! runs
  # BEFORE the success-path record call, so a teardown that blows up partway
  # leaves the org in an unknown state with no trail unless the macro fires.
  # Message expectation, not a store read: ColonelAuditEvent.record swallows its
  # own errors, so a store read could pass or fail for unrelated reasons.
  it 'records ONE result: :failure event when the teardown raises, and re-raises' do
    membership = double('OrganizationMembership', role: 'admin', owner?: false)
    allow(membership).to receive(:destroy_with_index_cleanup!).and_raise(Onetime::Problem, 'redis down')
    allow(Onetime::OrganizationMembership)
      .to receive(:find_by_org_customer).with('org-obj-1', 'cust-obj-1').and_return(membership)

    expect do
      described_class.new(org: org, customer: customer, actor: actor).call
    end.to raise_error(Onetime::Problem, /redis down/)

    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      hash_including(
        actor: actor,
        verb: 'membership.remove',
        target: 'ur_member', # literal: a broken target lambda silently lands as 'unknown'
        result: :failure,
        detail: hash_including(error: 'Onetime::Problem', message: 'redis down'),
      ),
    )
  end
end
