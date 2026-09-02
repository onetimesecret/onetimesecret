# spec/unit/onetime/operations/memberships/add_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::Operations::Memberships::Add (#3731).
#
# Covers: fresh add (+ exactly one audit, via ensure_membership), already-member
# idempotent :no_change (role untouched, attempt STILL audited with
# outcome: 'no_change' — #4337), invalid role, and role convergence when
# ensure_membership activates a pending invitation whose stored role differs
# from the operator's request.
#
# Run: pnpm run test:rspec spec/unit/onetime/operations/memberships/add_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'onetime/operations/memberships/add'

RSpec.describe Onetime::Operations::Memberships::Add do
  let(:actor) { 'ur_col_public_extid' }

  let(:org) do
    double('Organization', objid: 'org-obj-1', extid: 'on_org_ext')
  end

  let(:customer) do
    double('Customer', objid: 'cust-obj-1', extid: 'ur_member')
  end

  before do
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Onetime::ColonelAuditEvent).to receive(:record_access)
  end

  context 'when the customer is not yet a member (fresh add)' do
    let(:membership) { double('OrganizationMembership', role: 'member') }

    before do
      allow(org).to receive(:member?).with(customer).and_return(false)
      allow(Onetime::OrganizationMembership)
        .to receive(:ensure_membership).with(org, customer, role: 'member').and_return(membership)
    end

    it 'adds via ensure_membership and returns :success with the landed role' do
      result = described_class.new(org: org, customer: customer, role: 'member', actor: actor).call

      expect(result.status).to eq(:success)
      expect(result.role).to eq('member')
      expect(Onetime::OrganizationMembership)
        .to have_received(:ensure_membership).with(org, customer, role: 'member')
    end

    it 'records EXACTLY ONE audit event (verb membership.add, public ids, org_id in detail)' do
      described_class.new(org: org, customer: customer, role: 'member', actor: actor).call

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'membership.add',
        target: 'ur_member',
        result: :success,
        detail: { role: 'member', org_id: 'on_org_ext' },
      )
    end
  end

  context 'when ensure_membership activates a pending invite with a different role' do
    # The invitation carried role 'member'; the operator asked for 'admin'.
    # ensure_membership returns the activated (member) membership; the op must
    # converge it to the requested role via change_role!.
    let(:membership) do
      double('OrganizationMembership').tap do |m|
        # role reads: first the != check ('member'), then audit + result ('admin')
        allow(m).to receive(:role).and_return('member', 'admin')
        allow(m).to receive(:change_role!).and_return(true)
      end
    end

    before do
      allow(org).to receive(:member?).with(customer).and_return(false)
      allow(Onetime::OrganizationMembership)
        .to receive(:ensure_membership).with(org, customer, role: 'admin').and_return(membership)
    end

    it 'converges the activated role to the requested role' do
      result = described_class.new(org: org, customer: customer, role: 'admin', actor: actor).call

      expect(membership).to have_received(:change_role!).with('admin')
      expect(result.status).to eq(:success)
      expect(result.role).to eq('admin')
    end
  end

  context 'when the customer is already a member' do
    let(:existing) { double('OrganizationMembership', role: 'admin') }

    before do
      allow(org).to receive(:member?).with(customer).and_return(true)
      allow(Onetime::OrganizationMembership)
        .to receive(:find_by_org_customer).with('org-obj-1', 'cust-obj-1').and_return(existing)
    end

    it 'is a :no_change reporting the current role, without touching it' do
      result = described_class.new(org: org, customer: customer, role: 'member', actor: actor).call

      expect(result.status).to eq(:no_change)
      expect(result.role).to eq('admin') # current role, NOT the requested 'member'
    end

    # The mutation is skipped, the attempt is not (#4337). Same verb and target
    # as the applied event; detail mirrors its shape (the member's CURRENT
    # role, org_id) plus the outcome marker. The op has no dry_run, so the
    # record is unconditional — and it never touches the observation trail.
    it 'records ONE outcome: no_change attempt and does not call ensure_membership (#4337)' do
      allow(Onetime::OrganizationMembership).to receive(:ensure_membership)

      described_class.new(org: org, customer: customer, role: 'member', actor: actor).call

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'membership.add',
        target: 'ur_member',
        result: :success,
        detail: { outcome: 'no_change', role: 'admin', org_id: 'on_org_ext' },
      )
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access)
      expect(Onetime::OrganizationMembership).not_to have_received(:ensure_membership)
    end
  end

  # A refusal is an ATTEMPTED privileged mutation, so it lands in the trail with
  # the same verb/target as a success — differing only in result:/detail.
  it 'returns :invalid_role (no mutation) and records ONE result: :failure event' do
    allow(org).to receive(:member?).and_return(false)

    result = described_class.new(org: org, customer: customer, role: 'wizard', actor: actor).call

    expect(result.status).to eq(:invalid_role)
    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      actor: actor,
      verb: 'membership.add',
      target: 'ur_member',
      result: :failure,
      detail: { reason: 'invalid_role', role: 'wizard', org_id: 'on_org_ext' },
    )
  end

  context 'when ensure_membership returns nil (data-integrity failure)' do
    before do
      allow(org).to receive(:member?).with(customer).and_return(false)
      allow(Onetime::OrganizationMembership)
        .to receive(:ensure_membership).with(org, customer, role: 'member').and_return(nil)
    end

    # The Onetime::AuditedFailure mechanism. This raise happens BEFORE the
    # success-path record call, so it is the only thing that puts a failed add
    # in the trail. Message expectation, not a store read: ColonelAuditEvent.record
    # swallows its own errors.
    it 'raises Onetime::Problem and records ONE result: :failure event' do
      expect do
        described_class.new(org: org, customer: customer, role: 'member', actor: actor).call
      end.to raise_error(Onetime::Problem, /Failed to create membership record/)

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(
          actor: actor,
          verb: 'membership.add',
          target: 'ur_member', # literal: a broken target lambda silently lands as 'unknown'
          result: :failure,
          detail: hash_including(
            error: 'Onetime::Problem',
            message: 'Failed to create membership record',
          ),
        ),
      )
    end
  end

  context 'when an already-member record has a blank role (corruption)' do
    let(:existing) { double('OrganizationMembership', role: '') }

    before do
      allow(org).to receive(:member?).with(customer).and_return(true)
      allow(Onetime::OrganizationMembership)
        .to receive(:find_by_org_customer).with('org-obj-1', 'cust-obj-1').and_return(existing)
      allow(OT).to receive(:le)
    end

    it 'is :no_change, logs the anomaly, and echoes the requested role as a fallback' do
      result = described_class.new(org: org, customer: customer, role: 'member', actor: actor).call

      expect(result.status).to eq(:no_change)
      expect(result.role).to eq('member') # fallback: blank current role
      expect(OT).to have_received(:le).with(/active membership has blank role/)
      # The no-change record (#4337) carries the same fallback the Result does.
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(detail: { outcome: 'no_change', role: 'member', org_id: 'on_org_ext' }),
      )
    end
  end
end
