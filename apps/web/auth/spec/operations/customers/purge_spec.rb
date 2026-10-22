# apps/web/auth/spec/operations/customers/purge_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::Customers::Purge.
#
# Covers: it reuses TeardownAccount, returns :success + audits once on a
# successful destroy (target = pre-destroy extid), returns :not_found
# without auditing when nothing was deleted, and — since #4333 — writes that
# audit event FAIL-CLOSED: an unwritable event surfaces as a raised
# Onetime::AuditWriteFailure instead of a clean :success for a purge with no
# trail. Also pins the kwarg shape handed to RevokeAllForCustomer: the resolved
# `customer:` record, never a `custid:` the op would re-resolve through the
# extid index (#4205/#4217 drift) — the live-datastore proof of that gap is in
# try/unit/auth/operations/customers_ops_try.rb.
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/customers/purge_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'auth/operations/customers/purge'
require 'auth/operations/customers/doctor'

RSpec.describe Auth::Operations::Customers::Purge do
  let(:customer) do
    double('Customer', objid: 'cust-obj-p', extid: 'ur_p', custid: 'cust_p',
      email: 'p@example.com', obscure_email: 'p***@e***.com')
  end
  let(:deletion_result) do
    instance_double(
      Auth::Operations::TeardownAccount::Result,
      status: :success,
      completed_stages: [],
      blocked_stage: nil,
    )
  end
  let(:deleter) { instance_double(Auth::Operations::TeardownAccount, call: deletion_result) }
  let(:empty_plan) do
    Auth::Operations::Customers::PurgePreflight::Plan.new(actions: [], blockers: [])
  end
  let(:preflight) do
    instance_double(Auth::Operations::Customers::PurgePreflight,
      call: empty_plan, pending_organization_checks: [])
  end

  before do
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Auth::Operations::TeardownAccount).to receive(:new).and_return(deleter)
    allow(Auth::Operations::Customers::PurgePreflight).to receive(:new).and_return(preflight)
  end

  it 'does not expose audit suppression booleans on destructive operations' do
    org = double('Organization', objid: 'org-obj', extid: 'on_org', display_name: 'Workspace')

    expect { described_class.new(customer: customer, audit: false) }
      .to raise_error(ArgumentError, /unknown keyword: :audit/)
    expect { Onetime::Operations::Org::Delete.new(org: org, actor: 'cli', audit: false) }
      .to raise_error(ArgumentError, /unknown keyword: :audit/)
    expect do
      Onetime::Operations::Memberships::Remove.new(
        org: org,
        customer: customer,
        actor: 'cli',
        audit: false,
      )
    end.to raise_error(ArgumentError, /unknown keyword: :audit/)
    expect do
      Onetime::Operations::Sessions::RevokeAllForCustomer.new(
        customer: customer,
        actor: 'cli',
        audit: false,
      )
    end.to raise_error(ArgumentError, /unknown keyword: :audit/)
  end

  it 'destroys via TeardownAccount, returns :success, and audits once at the extid' do
    result = described_class.new(customer: customer, actor: 'ur_col').call

    expect(result.status).to eq(:success)
    expect(result.extid).to eq('ur_p')
    expect(Auth::Operations::TeardownAccount).to have_received(:new).with(
      customer: customer,
      actor: 'ur_col',
      reason: nil,
      before_mutation: kind_of(Method),
      on_mutation: kind_of(Method),
      bulk_audit_context: nil,
      sweep_untracked_sessions: true,
      self_service: false,
      retain_auth_account: false,
    )
    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      actor: 'ur_col',
      verb: 'customer.purge',
      target: 'ur_p',
      result: :success,
      detail: { email: 'p***@e***.com' },
      # #4333: the account is destroyed before this line runs, so an
      # unwritable event cannot be recovered from anywhere else.
      fail_closed: true,
    )
  end

  it 'hands the bulk membership snapshot to every preflight and declines the session sweep' do
    snapshot = Auth::Operations::Customers::MembershipSnapshot.new({})

    result = described_class.new(
      customer: customer,
      actor: 'cli',
      membership_snapshot: snapshot,
      sweep_untracked_sessions: false,
    ).call

    expect(result.status).to eq(:success)
    expect(Auth::Operations::Customers::PurgePreflight).to have_received(:new)
      .with(customer: customer, deep: false, membership_snapshot: snapshot, registry_sweep: nil).at_least(:twice)
    expect(Auth::Operations::Customers::PurgePreflight).not_to have_received(:new)
      .with(hash_including(membership_snapshot: nil))
    expect(Auth::Operations::TeardownAccount).to have_received(:new).with(
      hash_including(sweep_untracked_sessions: false),
    )
  end

  it 'runs the deep sweep at the plan and again after teardown, never in between' do
    sweep = instance_double(Auth::Operations::Customers::RegistrySweep)
    deep  = instance_double(Auth::Operations::Customers::PurgePreflight,
      call: empty_plan, pending_organization_checks: [], registry_sweep: sweep)
    allow(Auth::Operations::Customers::PurgePreflight).to receive(:new)
      .with(hash_including(deep: true)).and_return(deep)

    result = described_class.new(customer: customer, actor: 'cli', deep: true).call

    expect(result.status).to eq(:success)
    # Each deep preflight captures its own sweep (registry_sweep: nil): the
    # plan's sweep is reused only by the capability recheck on that plan, and
    # the post-teardown check must see writes made during the purge. The
    # revalidations in between stay shallow and carry no sweep.
    expect(Auth::Operations::Customers::PurgePreflight).to have_received(:new)
      .with(customer: customer, deep: true, membership_snapshot: nil, registry_sweep: nil).twice
    expect(Auth::Operations::Customers::PurgePreflight).to have_received(:new)
      .with(hash_including(deep: false, registry_sweep: nil)).at_least(:once)
    expect(Auth::Operations::Customers::PurgePreflight).not_to have_received(:new)
      .with(hash_including(registry_sweep: sweep))
  end

  it 'passes the administrative context to the unified deletion operation' do
    described_class.new(customer: customer, actor: 'ur_col', reason: 'takeover').call

    expect(Auth::Operations::TeardownAccount).to have_received(:new).with(
      customer: customer,
      actor: 'ur_col',
      reason: 'takeover',
      before_mutation: kind_of(Method),
      on_mutation: kind_of(Method),
      bulk_audit_context: nil,
      sweep_untracked_sessions: true,
      self_service: false,
      retain_auth_account: false,
    )
  end

  # A user-triggered close-account (auth close_account hook, simple-mode
  # /destroyaccount) must not be able to flush the count-capped operator
  # audit trail via the nested Org::Delete / Memberships::Remove /
  # RevokeAllForCustomer writes. Purge threads self_service: through so those
  # ops route to the security trail (fail-open).
  it 'threads self_service: through to TeardownAccount' do
    described_class.new(customer: customer, self_service: true).call

    expect(Auth::Operations::TeardownAccount).to have_received(:new)
      .with(hash_including(self_service: true))
  end

  # The reason the op takes `customer:` at all: a revoke keyed by extid
  # re-resolves through the extid index, and a miss there degrades to a silent
  # zero-count revoke followed by a destroy that leaves live blobs behind a
  # deleted customer. Purge holds the record, so it hands over the record —
  # and does not itself go back to the index for it.
  it 'hands the resolved record to TeardownAccount without re-resolving it' do
    allow(Onetime::Customer).to receive(:find_by_extid)

    described_class.new(customer: customer, actor: 'ur_col').call

    expect(Auth::Operations::TeardownAccount).to have_received(:new)
      .with(hash_including(customer: customer))
    expect(Onetime::Customer).not_to have_received(:find_by_extid)
  end

  it 'returns :not_found and does not audit when nothing was deleted' do
    allow(deletion_result).to receive(:status).and_return(:not_found)

    result = described_class.new(customer: customer, actor: 'x').call

    expect(result.status).to eq(:not_found)
    expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
  end

  it 'refuses before account teardown when preflight has blockers' do
    blocked = Auth::Operations::Customers::PurgePreflight::Plan.new(
      actions: [], blockers: [{ code: :has_domains, org_id: 'on_blocked' }],
    )
    allow(preflight).to receive(:call).and_return(blocked)

    result = described_class.new(customer: customer, actor: 'ur_col').call

    expect(result.status).to eq(:refused)
    expect(result.blockers).to eq([{ code: :has_domains, org_id: 'on_blocked' }])
    expect(result.stage).to eq(:preflight)
    expect(Auth::Operations::TeardownAccount).not_to have_received(:new)
    expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
      hash_including(verb: 'customer.purge', result: :failure,
        detail: hash_including(status: 'refused', blocker_codes: ['has_domains']))
    )
  end

  it 'refuses when the revalidated plan changes before mutation' do
    changed = Auth::Operations::Customers::PurgePreflight::Plan.new(
      actions: [], blockers: [{ code: :pending_invitations, org_id: 'on_changed' }],
    )
    allow(preflight).to receive(:call).and_return(empty_plan, changed)

    result = described_class.new(customer: customer, actor: 'ur_col').call

    expect(result.status).to eq(:refused)
    expect(result.blockers.map { |blocker| blocker[:code] })
      .to include(:pending_invitations, :preflight_changed)
    expect(Auth::Operations::TeardownAccount).not_to have_received(:new)
  end

  it 'refuses a stale plan signature and records the refusal without a bulk context' do
    result = described_class.new(
      customer: customer,
      actor: 'ur_col',
      expected_plan_signature: 'stale-signature',
    ).call

    expect(result.status).to eq(:refused)
    expect(result.blockers).to eq([{ code: :preflight_changed }])
    expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
      hash_including(
        verb: 'customer.purge',
        result: :failure,
        detail: hash_including(status: 'refused', blocker_codes: ['preflight_changed']),
      ),
    )
  end

  # A bulk run registers every candidate before mutation and its completion
  # receipt carries the refused count, so a refused candidate must be covered
  # by the receipt rather than writing its own operator-trail event: an
  # inactivity sweep with thousands of blocked candidates would otherwise trim
  # the capped trail by the size of the run.
  describe 'a refused candidate under a receipt-backed bulk context' do
    def start_bulk_context
      allow(Onetime::ColonelAuditEvent).to receive(:record).and_return('id' => 'start-receipt')
      Onetime::Operations::BulkAuditContext.start!(
        actor: 'cli',
        verb: 'customer.purge.bulk',
        target: 'inactive-customers',
        covered_verbs: ['customer.purge', 'session.revoke_all'],
        candidate_targets: [customer.objid],
        detail: { candidates: 1 },
      )
    end

    def block_preflight
      blocked = Auth::Operations::Customers::PurgePreflight::Plan.new(
        actions: [], blockers: [{ code: :has_domains, org_id: 'on_blocked' }],
      )
      allow(preflight).to receive(:call).and_return(blocked)
    end

    it 'writes only the bulk start receipt when preflight has blockers' do
      block_preflight
      bulk_context = start_bulk_context

      result = described_class.new(customer: customer, actor: 'cli', bulk_audit_context: bulk_context).call

      expect(result.status).to eq(:refused)
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
        .with(hash_including(verb: 'customer.purge'))
    end

    it 'writes only the bulk start receipt when the plan signature is stale' do
      bulk_context = start_bulk_context

      result = described_class.new(
        customer: customer,
        actor: 'cli',
        bulk_audit_context: bulk_context,
        expected_plan_signature: 'stale-signature',
      ).call

      expect(result.blockers).to eq([{ code: :preflight_changed }])
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
        .with(hash_including(verb: 'customer.purge'))
    end

    it 'consumes the candidate slot so a retry in the same run audits normally' do
      block_preflight
      bulk_context = start_bulk_context

      described_class.new(customer: customer, actor: 'cli', bulk_audit_context: bulk_context).call
      described_class.new(customer: customer, actor: 'cli', bulk_audit_context: bulk_context).call

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once
        .with(hash_including(verb: 'customer.purge', result: :failure))
    end
  end

  it 'deletes an approved personal workspace canonically before account teardown' do
    org = double('Organization', objid: 'org-obj')
    action = Auth::Operations::Customers::PurgePreflight::Action.new(
      type: :delete_organization, organization: org, org_id: 'on_personal', role: 'owner',
    )
    ready = Auth::Operations::Customers::PurgePreflight::Plan.new(actions: [action], blockers: [])
    planners = [ready, ready, empty_plan].map do |plan|
      instance_double(Auth::Operations::Customers::PurgePreflight, call: plan, pending_organization_checks: [])
    end
    allow(Auth::Operations::Customers::PurgePreflight).to receive(:new).and_return(*planners)

    delete_result = double('OrgDeleteResult', status: :success)
    delete_op = instance_double(Onetime::Operations::Org::Delete, call: delete_result)
    allow(Onetime::Operations::Org::Delete).to receive(:new).and_return(delete_op)

    result = described_class.new(customer: customer, actor: 'ur_col', reason: 'erasure').call

    expect(result.status).to eq(:success)
    expect(result.actions).to eq([
      { type: :delete_organization, org_id: 'on_personal', role: 'owner', status: :success },
    ])
    expect(result.completed_stages)
      .to contain_exactly(:delete_organization, :organization_cleanup, :account_teardown,
        :reference_cleanup, :customer_audit)
    expect(Onetime::Operations::Org::Delete).to have_received(:new).with(
      org: org,
      actor: 'ur_col',
      dry_run: false,
      account_purge_context: nil,
      reason: 'erasure',
      bulk_audit_context: nil,
      self_service: false,
    )
    expect(Auth::Operations::TeardownAccount).to have_received(:new).with(
      customer: customer,
      actor: 'ur_col',
      reason: 'erasure',
      before_mutation: kind_of(Method),
      on_mutation: kind_of(Method),
      bulk_audit_context: nil,
      sweep_untracked_sessions: true,
      self_service: false,
      retain_auth_account: false,
    )
  end

  it 'suppresses nested operator events only with a receipt-backed bulk context' do
    org = double('Organization', objid: 'org-bulk')
    action = Auth::Operations::Customers::PurgePreflight::Action.new(
      type: :delete_organization, organization: org, org_id: 'on_bulk', role: 'owner',
    )
    ready = Auth::Operations::Customers::PurgePreflight::Plan.new(actions: [action], blockers: [])
    allow(preflight).to receive(:call).and_return(ready, ready, empty_plan, empty_plan)
    delete_op = instance_double(
      Onetime::Operations::Org::Delete,
      call: double('OrgDeleteResult', status: :success),
    )
    allow(Onetime::Operations::Org::Delete).to receive(:new).and_return(delete_op)

    allow(Onetime::ColonelAuditEvent).to receive(:record).and_return('id' => 'start-receipt')
    bulk_context = Onetime::Operations::BulkAuditContext.start!(
      actor: 'cli',
      verb: 'customer.purge.bulk',
      target: 'inactive-customers',
      covered_verbs: [
        'customer.purge',
        'organization.delete',
        'membership.remove',
        'session.revoke_all',
      ],
      candidate_targets: [customer.objid],
      detail: { candidates: 1 },
    )
    result = described_class.new(
      customer: customer,
      actor: 'cli',
      bulk_audit_context: bulk_context,
    ).call

    expect(result.status).to eq(:success)
    expect(Onetime::Operations::Org::Delete).to have_received(:new).with(
      org: org,
      actor: 'cli',
      dry_run: false,
      account_purge_context: nil,
      reason: nil,
      bulk_audit_context: kind_of(Onetime::Operations::BulkAuditContext::CandidateAuthorization),
      self_service: false,
    )
    expect(Auth::Operations::TeardownAccount).to have_received(:new).with(
      customer: customer,
      actor: 'cli',
      reason: nil,
      before_mutation: kind_of(Method),
      on_mutation: kind_of(Method),
      bulk_audit_context: kind_of(Onetime::Operations::BulkAuditContext::CandidateAuthorization),
      sweep_untracked_sessions: true,
      self_service: false,
      retain_auth_account: false,
    )
    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      hash_including(verb: 'customer.purge.bulk', result: :started)
    )
  end

  it 'uses normal per-customer audit for an unregistered bulk target' do
    allow(Onetime::ColonelAuditEvent).to receive(:record).and_return('id' => 'receipt')
    context = Onetime::Operations::BulkAuditContext.start!(
      actor: 'cli',
      verb: 'customer.purge.bulk',
      target: 'inactive-customers',
      covered_verbs: ['customer.purge', 'session.revoke_all'],
      candidate_targets: ['different-customer'],
      detail: { candidates: 1 },
    )

    described_class.new(customer: customer, actor: 'cli', bulk_audit_context: context).call

    expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
      hash_including(verb: 'customer.purge', target: 'ur_p', result: :success)
    )
  end

  it 'uses normal per-customer audit when a completed bulk context is reused' do
    allow(Onetime::ColonelAuditEvent).to receive(:record).and_return('id' => 'receipt')
    context = Onetime::Operations::BulkAuditContext.start!(
      actor: 'cli',
      verb: 'customer.purge.bulk',
      target: 'inactive-customers',
      covered_verbs: ['customer.purge', 'session.revoke_all'],
      candidate_targets: [customer.objid],
      detail: { candidates: 1 },
    )
    context.complete!(result: :success, detail: { destroyed: 0 })

    described_class.new(customer: customer, actor: 'cli', bulk_audit_context: context).call

    expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
      hash_including(verb: 'customer.purge', target: 'ur_p', result: :success)
    )
  end

  it 'uses normal per-customer audit when the same candidate authorization is requested twice' do
    allow(Onetime::ColonelAuditEvent).to receive(:record).and_return('id' => 'receipt')
    context = Onetime::Operations::BulkAuditContext.start!(
      actor: 'cli',
      verb: 'customer.purge.bulk',
      target: 'inactive-customers',
      covered_verbs: ['customer.purge', 'session.revoke_all'],
      candidate_targets: [customer.objid],
      detail: { candidates: 1 },
    )

    described_class.new(customer: customer, actor: 'cli', bulk_audit_context: context).call
    described_class.new(customer: customer, actor: 'cli', bulk_audit_context: context).call

    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      hash_including(verb: 'customer.purge', target: 'ur_p', result: :success)
    )
  end

  it 'removes an approved non-owner membership through the semantic operation' do
    org = double('Organization', objid: 'org-shared')
    action = Auth::Operations::Customers::PurgePreflight::Action.new(
      type: :remove_membership, organization: org, org_id: 'on_shared', role: 'member',
    )
    ready = Auth::Operations::Customers::PurgePreflight::Plan.new(actions: [action], blockers: [])
    planners = [ready, ready, empty_plan].map do |plan|
      instance_double(Auth::Operations::Customers::PurgePreflight, call: plan, pending_organization_checks: [])
    end
    allow(Auth::Operations::Customers::PurgePreflight).to receive(:new).and_return(*planners)

    remove_result = double('MembershipRemoveResult', status: :success)
    remove_op = instance_double(Onetime::Operations::Memberships::Remove, call: remove_result)
    allow(Onetime::Operations::Memberships::Remove).to receive(:new).and_return(remove_op)

    result = described_class.new(customer: customer, actor: 'ur_col').call

    expect(result.status).to eq(:success)
    expect(Onetime::Operations::Memberships::Remove).to have_received(:new).with(
      org: org, customer: customer, actor: 'ur_col', reason: nil, bulk_audit_context: nil,
      self_service: false,
    )
  end

  it 'threads self_service: through to a nested Org::Delete on the applied action' do
    org      = double('Organization', objid: 'org-personal', extid: 'on_personal')
    delete_a = Auth::Operations::Customers::PurgePreflight::Action.new(
      type: :delete_organization, organization: org, org_id: 'on_personal', role: 'owner',
    )
    ready = Auth::Operations::Customers::PurgePreflight::Plan.new(
      actions: [delete_a], blockers: [],
    )
    planners = [ready, ready, empty_plan, empty_plan].map do |plan|
      instance_double(Auth::Operations::Customers::PurgePreflight, call: plan, pending_organization_checks: [])
    end
    allow(Auth::Operations::Customers::PurgePreflight).to receive(:new).and_return(*planners)

    delete_op = instance_double(Onetime::Operations::Org::Delete,
      call: double('OrgDeleteResult', status: :success))
    allow(Onetime::Operations::Org::Delete).to receive(:new).and_return(delete_op)

    described_class.new(customer: customer, self_service: true).call

    expect(Onetime::Operations::Org::Delete).to have_received(:new)
      .with(hash_including(self_service: true))
  end

  it 'threads self_service: through to a nested Memberships::Remove on the applied action' do
    org      = double('Organization', objid: 'org-shared', extid: 'on_shared')
    remove_a = Auth::Operations::Customers::PurgePreflight::Action.new(
      type: :remove_membership, organization: org, org_id: 'on_shared', role: 'member',
    )
    ready = Auth::Operations::Customers::PurgePreflight::Plan.new(
      actions: [remove_a], blockers: [],
    )
    planners = [ready, ready, empty_plan, empty_plan].map do |plan|
      instance_double(Auth::Operations::Customers::PurgePreflight, call: plan, pending_organization_checks: [])
    end
    allow(Auth::Operations::Customers::PurgePreflight).to receive(:new).and_return(*planners)

    remove_op = instance_double(Onetime::Operations::Memberships::Remove,
      call: double('MembershipRemoveResult', status: :success))
    allow(Onetime::Operations::Memberships::Remove).to receive(:new).and_return(remove_op)

    described_class.new(customer: customer, self_service: true).call

    expect(Onetime::Operations::Memberships::Remove).to have_received(:new)
      .with(hash_including(self_service: true))
  end

  it 'returns :partial and does not tear down the account when references remain after cleanup' do
    org = double('Organization', objid: 'org-shared')
    action = Auth::Operations::Customers::PurgePreflight::Action.new(
      type: :remove_membership, organization: org, org_id: 'on_shared', role: 'member',
    )
    ready = Auth::Operations::Customers::PurgePreflight::Plan.new(actions: [action], blockers: [])
    residual = Auth::Operations::Customers::PurgePreflight::Plan.new(
      actions: [action], blockers: [{ code: :target_participation_drift, org_id: 'on_shared' }],
    )
    planners = [ready, ready, residual].map do |plan|
      instance_double(Auth::Operations::Customers::PurgePreflight, call: plan, pending_organization_checks: [])
    end
    allow(Auth::Operations::Customers::PurgePreflight).to receive(:new).and_return(*planners)
    allow(Onetime::Operations::Memberships::Remove).to receive(:new).and_return(
      instance_double(Onetime::Operations::Memberships::Remove,
        call: double('MembershipRemoveResult', status: :success)),
    )

    result = described_class.new(customer: customer, actor: 'ur_col').call

    expect(result.status).to eq(:partial)
    expect(result.stage).to eq(:post_cleanup_revalidation)
    expect(result.blockers.map { |blocker| blocker[:code] })
      .to include(:target_participation_drift, :preflight_changed, :references_remain)
    expect(Auth::Operations::TeardownAccount).not_to have_received(:new)
  end

  describe 'automatic stale participation cleanup' do
    let(:reference) { 'organization:org-gone:members' }
    let(:stale_action) do
      Auth::Operations::Customers::PurgePreflight::Action.new(
        type: :remove_stale_participation,
        organization: double('Deleted organization', objid: 'org-gone'),
        org_id: 'org-gone', role: '', reference: reference,
      )
    end
    let(:stale_plan) do
      Auth::Operations::Customers::PurgePreflight::Plan.new(actions: [stale_action], blockers: [])
    end
    let(:participations) { double('Participations') }
    let(:pending_checks) { double('Pending organization checks') }
    let(:completed_action) { stale_action.public_detail(status: :success) }
    let(:dependency_blockers) do
      [{ code: :orphan_organization_dependencies_remain, org_id: 'org-gone' }]
    end

    before do
      @references = [reference]
      @pending_references = []
      allow(customer).to receive(:purge_pending_organization_checks).and_return(pending_checks)
      allow(pending_checks).to receive(:to_a) { @pending_references.dup }
      allow(pending_checks).to receive(:add).with(reference) do
        @pending_references |= [reference]
        1
      end
      allow(customer).to receive(:participations).and_return(participations)
      allow(participations).to receive(:to_a) { @references.dup }
      allow(customer).to receive(:untrack_participation_in).with(reference) do
        @references.delete(reference) ? 1 : 0
      end
      allow(preflight).to receive(:call).and_return(stale_plan, stale_plan, empty_plan)
      allow(preflight).to receive(:stale_participation_blockers).with(stale_action).and_return([])
    end

    it 'records verified cleanup in the result and the fail-closed success audit' do
      operation = described_class.new(customer: customer, actor: 'ur_col')
      allow(customer).to receive(:untrack_participation_in).with(reference) do
        expect(operation.mutation_started?).to be(true)
        expect(@pending_references).to eq([reference])
        @references.clear
        1
      end

      result = operation.call

      expect(result.status).to eq(:success)
      expect(result.actions).to eq([completed_action])
      expect(result.completed_stages).to include(:remove_stale_participation)
      expect(customer).to have_received(:untrack_participation_in).with(reference).once
      expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
        hash_including(verb: 'customer.purge', result: :success, fail_closed: true,
          detail: hash_including(completed_actions: [completed_action])),
      )
    end

    it 'returns partial without claiming completion when untracking silently does nothing' do
      allow(customer).to receive(:untrack_participation_in).and_return(0)
      operation = described_class.new(customer: customer, actor: 'ur_col')

      result = operation.call

      expect(result.status).to eq(:partial)
      expect(result.blockers).to include(hash_including(code: :stale_participation_cleanup_failed))
      expect(result.actions).to be_empty
      expect(result.completed_stages).not_to include(:remove_stale_participation)
      expect(@pending_references).to eq([reference])
      expect(operation.mutation_started?).to be(true)
      expect(@references).to eq([reference])
      expect(Auth::Operations::TeardownAccount).not_to have_received(:new)
      expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
        hash_including(result: :failure, fail_closed: true,
          detail: hash_including(status: 'partial', completed_actions: [])),
      )
    end

    it 'retains the marker when untracking raises after removing the reverse index' do
      failure = IOError.new('untrack response lost')
      allow(customer).to receive(:untrack_participation_in).with(reference) do
        expect(@pending_references).to eq([reference])
        @references.clear
        raise failure
      end
      operation = described_class.new(customer: customer, actor: 'ur_col')

      expect { operation.call }.to raise_error { |error| expect(error).to be(failure) }
      expect(@pending_references).to eq([reference])
      expect(@references).to be_empty
      expect(operation.mutation_started?).to be(true)
      expect(operation.outcome_context[:actions]).to be_empty
      expect(Auth::Operations::TeardownAccount).not_to have_received(:new)
    end

    it 'propagates a partial-audit failure without claiming that cleanup completed' do
      allow(customer).to receive(:untrack_participation_in).and_return(0)
      failure = Onetime::AuditWriteFailure.new(verb: 'customer.purge', target: 'ur_p')
      allow(Onetime::ColonelAuditEvent).to receive(:record)
        .with(hash_including(verb: 'customer.purge', fail_closed: true)).and_raise(failure)
      operation = described_class.new(customer: customer, actor: 'ur_col')

      expect { operation.call }.to raise_error { |error| expect(error).to be(failure) }
      expect(operation.mutation_started?).to be(true)
      expect(operation.outcome_context[:actions]).to be_empty
      expect(Auth::Operations::TeardownAccount).not_to have_received(:new)
      expect(@references).to eq([reference])
    end

    it 'uses verified absence rather than the removal count for idempotent cleanup' do
      allow(customer).to receive(:untrack_participation_in).with(reference) do
        @references.clear
        0
      end

      result = described_class.new(customer: customer, actor: 'ur_col').call

      expect(result.status).to eq(:success)
      expect(result.actions).to eq([completed_action])
    end

    it 'refuses dependency drift before removing the reference' do
      blocked = Auth::Operations::Customers::PurgePreflight::Plan.new(
        actions: [], blockers: dependency_blockers,
      )
      allow(preflight).to receive(:call).and_return(stale_plan, blocked)

      result = described_class.new(customer: customer, actor: 'ur_col').call

      expect(result.status).to eq(:refused)
      expect(result.blockers).to include(*dependency_blockers)
      expect(customer).not_to have_received(:untrack_participation_in)
      expect(Auth::Operations::TeardownAccount).not_to have_received(:new)
    end

    it 'retains the cleaned action for dependency checks after its reverse index is gone' do
      allow(preflight).to receive(:stale_participation_blockers).with(stale_action) do
        @references.empty? ? dependency_blockers : []
      end

      result = described_class.new(customer: customer, actor: 'ur_col').call

      expect(result.status).to eq(:partial)
      expect(result.stage).to eq(:post_cleanup_revalidation)
      expect(result.actions).to eq([completed_action])
      expect(result.blockers).to include(*dependency_blockers)
      expect(@references).to be_empty
      expect(Auth::Operations::TeardownAccount).not_to have_received(:new)
    end

    it 'rechecks a cleaned orphan before the next organization mutation' do
      later_action = Auth::Operations::Customers::PurgePreflight::Action.new(
        type: :remove_membership,
        organization: double('Later organization', objid: 'org-later'),
        org_id: 'on_later', role: 'member',
      )
      initial = Auth::Operations::Customers::PurgePreflight::Plan.new(
        actions: [stale_action, later_action], blockers: [],
      )
      remaining = Auth::Operations::Customers::PurgePreflight::Plan.new(
        actions: [later_action], blockers: [],
      )
      allow(preflight).to receive(:call).and_return(initial, initial, remaining)
      allow(preflight).to receive(:stale_participation_blockers).with(stale_action) do
        @references.empty? ? dependency_blockers : []
      end
      allow(Onetime::Operations::Memberships::Remove).to receive(:new)

      result = described_class.new(customer: customer, actor: 'ur_col').call

      expect(result.status).to eq(:partial)
      expect(result.stage).to eq(:cleanup_revalidation)
      expect(result.actions).to eq([completed_action])
      expect(result.blockers).to include(*dependency_blockers)
      expect(Onetime::Operations::Memberships::Remove).not_to have_received(:new)
      expect(Auth::Operations::TeardownAccount).not_to have_received(:new)
    end

    it 'rechecks cleaned dependencies at each account mutation boundary' do
      checks = []
      dependency_present = false
      allow(preflight).to receive(:stale_participation_blockers).with(stale_action) do
        dependency_present ? dependency_blockers : []
      end
      allow(Auth::Operations::TeardownAccount).to receive(:new) do |**options|
        allow(deleter).to receive(:call) do
          checks << options.fetch(:before_mutation).call(:sessions)
          dependency_present = true
          checks << options.fetch(:before_mutation).call(:customer)
          instance_double(Auth::Operations::TeardownAccount::Result,
            status: :refused, completed_stages: [], blocked_stage: :customer)
        end
        deleter
      end

      result = described_class.new(customer: customer, actor: 'ur_col').call

      expect(checks).to eq([true, false])
      expect(result.status).to eq(:partial)
      expect(result.blockers).to include(*dependency_blockers)
      expect(result.actions).to eq([completed_action])
    end

    it 'detects dependencies appearing after account teardown despite an empty reverse index' do
      dependency_present = false
      allow(preflight).to receive(:stale_participation_blockers).with(stale_action) do
        dependency_present ? dependency_blockers : []
      end
      allow(deleter).to receive(:call) do
        dependency_present = true
        deletion_result
      end

      result = described_class.new(customer: customer, actor: 'ur_col').call

      expect(result.status).to eq(:partial)
      expect(result.stage).to eq(:post_teardown_revalidation)
      expect(result.blockers).to include(*dependency_blockers)
      expect(result.actions).to eq([completed_action])
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
        .with(hash_including(result: :success))
    end

    it 'retains marker-only reader actions after teardown clears the persistent markers' do
      @references.clear
      @pending_references = [reference]
      allow(preflight).to receive(:call).and_return(empty_plan)
      allow(preflight).to receive(:pending_organization_checks) do
        @pending_references.empty? ? [] : [stale_action]
      end
      dependency_present = false
      allow(preflight).to receive(:stale_participation_blockers).with(stale_action) do
        dependency_present ? dependency_blockers : []
      end
      allow(deleter).to receive(:call) do
        @pending_references.clear
        dependency_present = true
        deletion_result
      end

      result = described_class.new(customer: customer, actor: 'ur_col').call

      expect(result.status).to eq(:partial)
      expect(result.stage).to eq(:post_teardown_revalidation)
      expect(result.blockers).to include(*dependency_blockers)
      expect(result.actions).to be_empty
      expect(result.planned_actions).to be_empty
      expect(@pending_references).to be_empty
      expect(customer).not_to have_received(:untrack_participation_in)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
        .with(hash_including(result: :success))
    end

    it 'preserves the completed cleanup when teardown refuses and permits a fresh retry' do
      allow(deletion_result).to receive(:status).and_return(:refused)
      first = described_class.new(customer: customer, actor: 'ur_col').call

      expect(first.status).to eq(:partial)
      expect(first.actions).to eq([completed_action])
      expect(@references).to be_empty

      allow(preflight).to receive(:call).and_return(empty_plan)
      allow(deletion_result).to receive(:status).and_return(:success)
      retried = described_class.new(customer: customer, actor: 'ur_col').call

      expect(retried.status).to eq(:success)
      expect(retried.actions).to be_empty
      expect(customer).to have_received(:untrack_participation_in).once
    end

    it 'propagates a success-audit failure after recording the completed cleanup payload' do
      failure = Onetime::AuditWriteFailure.new(verb: 'customer.purge', target: 'ur_p')
      allow(Onetime::ColonelAuditEvent).to receive(:record)
        .with(hash_including(verb: 'customer.purge', result: :success)).and_raise(failure)

      expect { described_class.new(customer: customer, actor: 'ur_col').call }
        .to raise_error { |error| expect(error).to be(failure) }
      expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
        hash_including(verb: 'customer.purge', result: :success,
          detail: hash_including(completed_actions: [completed_action])),
      )
      expect(@references).to be_empty
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
        .with(hash_including(verb: 'customer.purge', result: :failure))
    end

    [:success, :partial].each do |status|
      it "routes self-service stale cleanup #{status} to the security audit only" do
        allow(Onetime::ColonelAuditEvent).to receive(:record_security)
        allow(customer).to receive(:untrack_participation_in).and_return(0) if status == :partial

        result = described_class.new(customer: customer, self_service: true).call

        expect(result.status).to eq(status)
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
        expect(Onetime::ColonelAuditEvent).to have_received(:record_security).with(
          hash_including(verb: 'customer.purge',
            result: status == :success ? :success : :failure,
            detail: hash_including(completed_actions: status == :success ? [completed_action] : [])),
        )
      end
    end
  end

  describe 'real datastore lifecycle', :datastore do
    let(:suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }
    let(:email) { "purge_4440_#{suffix}@onetimesecret.com" }

    before do
      allow(Auth::Operations::Customers::PurgePreflight).to receive(:new).and_call_original
      allow(Auth::Operations::TeardownAccount).to receive(:new).and_call_original
      allow(Onetime.auth_config).to receive(:full_enabled?).and_return(false)
      allow(Onetime::Operations::Sessions::RevokeAllForCustomer).to receive(:new)
        .and_return(instance_double(Onetime::Operations::Sessions::RevokeAllForCustomer, call: nil))
      allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(true)

      @real_customer = Onetime::Customer.create!(email: email)
      @real_org      = Onetime::Organization.create!(
        "Purge workspace #{suffix}",
        @real_customer,
        email,
        is_default: true,
      )
      @real_customer.default_org_id = @real_org.objid
      @real_customer.save
    end

    after do
      if @real_org&.exists?
        Onetime::Organization.instances.remove(@real_org.objid)
        @real_org.destroy!
      end
      @real_customer&.destroy! if @real_customer&.exists?
      Onetime::Organization.contact_email_index.remove(email)
    rescue StandardError => ex
      warn "[customer purge spec] cleanup failed: #{ex.class}: #{ex.message}"
    end

    def seed_previous_partial(shape, prefix: 'organization')
      plan = Auth::Operations::Customers::PurgePreflight.new(customer: @real_customer).call
      action = plan.actions.find { |entry| entry.type == :delete_organization }
      deleted = Onetime::Operations::Org::Delete.new(
        org: @real_org, actor: 'ur_col', dry_run: false,
        account_purge_context: action.account_purge_context,
      ).call
      expect(deleted.status).to eq(:success)
      expect(@real_org.exists?).to be(false)
      expect(@real_customer.exists?).to be(true)

      reference = "#{prefix}:#{@real_org.objid}:members"
      set = @real_customer.participations
      encoded = set.serialize_value(reference)
      values = case shape
               when :raw then [reference]
               when :canonical then [encoded]
               when :mixed then [reference, encoded]
               end
      set.dbclient.sadd(set.dbkey, values)
      reference
    end

    [:raw, :canonical, :mixed].each do |shape|
      it "retries a previous partial purge with #{shape} dangling bytes and audits the cleanup" do
        reference = seed_previous_partial(shape)
        allow(Auth::Operations::Customers::Doctor).to receive(:new).and_call_original
        before = @real_customer.participations.membersraw.sort
        plan = Auth::Operations::Customers::PurgePreflight.new(customer: @real_customer).call

        expect(plan).to be_executable
        expect(plan.actions.map(&:reference)).to eq([reference])
        expect(@real_customer.participations.membersraw.sort).to eq(before)

        result = described_class.new(customer: @real_customer, actor: 'ur_col').call

        expect(result.status).to eq(:success), result.blockers.inspect
        expect(result.actions).to eq(plan.action_details(status: :success))
        expect(@real_customer.exists?).to be(false)
        expect(@real_customer.participations.membersraw).to be_empty
        expect(Auth::Operations::Customers::Doctor).not_to have_received(:new)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
          hash_including(verb: 'customer.purge', result: :success, fail_closed: true,
            detail: hash_including(completed_actions: result.actions)),
        )
      end
    end

    it 'cleans both organization prefix aliases without leaving physical encodings behind' do
      reference = seed_previous_partial(:mixed)
      legacy = reference.sub('organization:', 'org:')
      set = @real_customer.participations
      set.dbclient.sadd(set.dbkey, [legacy, set.serialize_value(legacy)])

      result = described_class.new(customer: @real_customer, actor: 'ur_col').call

      expect(result.status).to eq(:success), result.blockers.inspect
      expect(result.actions.map { |action| action[:type] })
        .to eq([:remove_stale_participation, :remove_stale_participation])
      expect(set.membersraw).to be_empty
      expect(@real_customer.exists?).to be(false)
    end

    %w[organization org].each do |prefix|
      [:raw, :canonical, :mixed].each do |shape|
        it "refuses #{shape} malformed #{prefix} participation before mutation on initial and subsequent purges" do
          seed_previous_partial(:mixed)
          set = @real_customer.participations
          set.clear
          invalid = "#{prefix}:org.gone:members"
          encoded = set.serialize_value(invalid)
          values = case shape
                   when :raw then [invalid]
                   when :canonical then [encoded]
                   when :mixed then [invalid, encoded]
                   end
          set.dbclient.sadd(set.dbkey, values)
          before = set.membersraw.sort
          markers = @real_customer.purge_pending_organization_checks

          2.times do
            operation = described_class.new(customer: @real_customer, actor: 'ur_col')
            result = operation.call

            expect(result.status).to eq(:refused)
            expect(result.stage).to eq(:preflight)
            expect(result.blockers).to include(code: :dangling_customer_participation, reference: invalid)
            expect(result.actions).to be_empty
            expect(result.planned_actions).to be_empty
            expect(operation.mutation_started?).to be(false)
            expect(set.membersraw.sort).to eq(before)
            expect(markers.membersraw).to be_empty
            expect(@real_customer.exists?).to be(true)
          end
          expect(Auth::Operations::TeardownAccount).not_to have_received(:new)
        end
      end
    end

    it 'shares dependency scans within each checker but checks again across cleanup and teardown' do
      reference = seed_previous_partial(:mixed)
      legacy = reference.sub('organization:', 'org:')
      @real_customer.participations.add(legacy)
      checkers = []
      allow(Auth::Operations::Customers::PurgePreflight).to receive(:new).and_wrap_original do |original, **options|
        checker = original.call(**options)
        allow(checker).to receive(:orphan_dependencies?).and_call_original
        checkers << checker
        checker
      end

      result = described_class.new(customer: @real_customer, actor: 'ur_col').call

      expect(result.status).to eq(:success), result.blockers.inspect
      expect(result.actions.map { |action| action[:reference] }).to eq([reference, legacy].sort)
      expect(checkers.size).to be > 4
      checkers.each do |checker|
        expect(checker).to have_received(:orphan_dependencies?).once
      end
      expect(@real_customer.exists?).to be(false)
      expect(@real_customer.purge_pending_organization_checks.membersraw).to be_empty
    end

    it 'refuses a fresh purge after late receipt data appears until that dependency is removed' do
      reference = seed_previous_partial(:mixed)
      markers = @real_customer.purge_pending_organization_checks
      receipt_key = @real_org.receipts.dbkey
      redis = Onetime::Organization.dbclient
      allow(@real_customer).to receive(:untrack_participation_in).and_wrap_original do |original, key|
        expect(markers.to_a).to eq([reference])
        removed = original.call(key)
        redis.zadd(receipt_key, 1, 'late-receipt')
        removed
      end

      begin
        first = described_class.new(customer: @real_customer, actor: 'ur_col').call

        expect(first.status).to eq(:partial)
        expect(first.stage).to eq(:post_cleanup_revalidation)
        expect(first.actions).to include(hash_including(type: :remove_stale_participation))
        expect(@real_customer.participations.to_a).to be_empty
        expect(markers.to_a).to eq([reference])
        expect(@real_customer.exists?).to be(true)

        reloaded = Onetime::Customer.load(@real_customer.objid)
        second = described_class.new(customer: reloaded, actor: 'ur_col').call

        expect(second.status).to eq(:refused)
        expect(second.stage).to eq(:preflight)
        expect(second.actions).to be_empty
        expect(second.blockers).to include(hash_including(code: :orphan_organization_dependencies_remain))
        expect(reloaded.exists?).to be(true)
        expect(reloaded.participations.to_a).to be_empty
        expect(reloaded.purge_pending_organization_checks.to_a).to eq([reference])
        expect(redis.zrange(receipt_key, 0, -1)).to eq(['late-receipt'])
        expect(Auth::Operations::TeardownAccount).not_to have_received(:new)

        redis.del(receipt_key)
        ready = Auth::Operations::Customers::PurgePreflight.new(customer: reloaded).call
        expect(ready).to be_executable
        expect(ready.actions).to be_empty
        expect(reloaded.purge_pending_organization_checks.to_a).to eq([reference])

        third = described_class.new(customer: reloaded, actor: 'ur_col').call

        expect(third.status).to eq(:success), third.blockers.inspect
        expect(third.actions).to be_empty
        expect(reloaded.exists?).to be(false)
        expect(markers.dbclient.exists?(markers.dbkey)).to be(false)
      ensure
        redis.del(receipt_key)
      end
    end

    it 'returns partial for a marker-only retry when receipt data appears after successful teardown' do
      reference = seed_previous_partial(:mixed)
      @real_customer.purge_pending_organization_checks.add(reference)
      @real_customer.untrack_participation_in(reference)
      reloaded = Onetime::Customer.load(@real_customer.objid)
      markers = reloaded.purge_pending_organization_checks
      receipt_key = @real_org.receipts.dbkey
      redis = Onetime::Organization.dbclient
      checker = Auth::Operations::Customers::PurgePreflight.new(customer: reloaded)
      plan = checker.call
      expect(plan).to be_executable
      expect(plan.actions).to be_empty
      expect(checker.pending_organization_checks.map(&:reference)).to eq([reference])

      allow(Auth::Operations::TeardownAccount).to receive(:new).and_wrap_original do |original, **options|
        operation = original.call(**options)
        allow(operation).to receive(:call).and_wrap_original do |call|
          deletion = call.call
          expect(deletion.status).to eq(:success)
          expect(reloaded.exists?).to be(false)
          expect(markers.dbclient.exists?(markers.dbkey)).to be(false)
          redis.zadd(receipt_key, 1, 'post-teardown-receipt')
          deletion
        end
        operation
      end

      begin
        result = described_class.new(customer: reloaded, actor: 'ur_col').call

        expect(result.status).to eq(:partial)
        expect(result.stage).to eq(:post_teardown_revalidation)
        expect(result.actions).to be_empty
        expect(result.planned_actions).to be_empty
        expect(result.blockers).to include(hash_including(code: :orphan_organization_dependencies_remain))
        expect(reloaded.exists?).to be(false)
        expect(markers.dbclient.exists?(markers.dbkey)).to be(false)
        expect(redis.zrange(receipt_key, 0, -1)).to eq(['post-teardown-receipt'])
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
          .with(hash_including(verb: 'customer.purge', result: :success))
        expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
          hash_including(verb: 'customer.purge', result: :failure, fail_closed: true,
            detail: hash_including(status: 'partial', stage: 'post_teardown_revalidation')),
        )
      ensure
        redis.del(receipt_key)
      end
    end

    it 'retries account teardown after stale cleanup completed without requiring doctor' do
      seed_previous_partial(:mixed)
      refused = instance_double(Auth::Operations::TeardownAccount::Result,
        status: :refused, completed_stages: [], blocked_stage: :customer)
      allow(Auth::Operations::TeardownAccount).to receive(:new)
        .and_return(instance_double(Auth::Operations::TeardownAccount, call: refused))

      first = described_class.new(customer: @real_customer, actor: 'ur_col').call

      expect(first.status).to eq(:partial)
      expect(first.actions).to include(hash_including(type: :remove_stale_participation, status: :success))
      expect(@real_customer.exists?).to be(true)
      expect(@real_customer.participations.membersraw).to be_empty
      expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
        hash_including(verb: 'customer.purge', result: :failure,
          detail: hash_including(status: 'partial', completed_actions: first.actions)),
      )

      allow(Auth::Operations::TeardownAccount).to receive(:new).and_call_original
      retried = described_class.new(customer: @real_customer, actor: 'ur_col').call

      expect(retried.status).to eq(:success), retried.blockers.inspect
      expect(retried.actions).to be_empty
      expect(@real_customer.exists?).to be(false)
    end

    it 'removes the eligible default workspace, customer, and email reservation' do
      customer_objid = @real_customer.objid
      org_objid      = @real_org.objid

      result = described_class.new(
        customer: @real_customer,
        actor: 'ur_col',
        reason: 'erasure',
      ).call

      expect(result.status).to eq(:success), result.blockers.inspect
      expect(Onetime::Customer.load(customer_objid)).to be_nil
      expect(Onetime::Organization.load(org_objid)).to be_nil
      expect(Onetime::Organization.contact_email_index.get(email)).to be_nil
      expect(result.actions.map { |action| action[:type] }).to eq([:delete_organization])
    end
  end

  # The point of fail-closed (#4333): the op must NOT convert an unrecorded
  # purge into a successful-looking Result. Message expectation rather than a
  # store read — the model swallows its own errors on the fail-open path, so a
  # store read here could pass or fail for unrelated reasons.
  it 'propagates Onetime::AuditWriteFailure instead of returning :success' do
    allow(Onetime::ColonelAuditEvent).to receive(:record)
      .and_raise(Onetime::AuditWriteFailure.new(verb: 'customer.purge', target: 'ur_p'))

    expect { described_class.new(customer: customer, actor: 'ur_col').call }
      .to raise_error(Onetime::AuditWriteFailure, /customer\.purge/)
  end

  # #4324: AuditedFailure wraps #call, so the raise above is itself audited —
  # but NOT as `customer.purge / result: :failure`. The account is already
  # destroyed by the time the write fails, and this follow-up write is
  # fail-open and lands a tick later, so a transient blip would let it succeed
  # and leave the trail affirmatively claiming the purge FAILED. It goes under
  # audit.write_failure instead, naming the verb whose event is missing.
  it 'records the missing trail under audit.write_failure, not as a failed purge' do
    allow(Onetime::ColonelAuditEvent).to receive(:record)
      .and_raise(Onetime::AuditWriteFailure.new(verb: 'customer.purge', target: 'ur_p'))

    expect { described_class.new(customer: customer, actor: 'ur_col').call }
      .to raise_error(Onetime::AuditWriteFailure)

    expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      .with(hash_including(verb: 'customer.purge', result: :failure))
    expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
      actor: 'ur_col',
      verb: 'audit.write_failure',
      target: 'ur_p', # the purged account, so the gap is attributable
      result: :failure,
      detail: hash_including(failed_verb: 'customer.purge', error: 'Onetime::AuditWriteFailure'),
    )
  end

  # The wrapper is best-effort and on the fail-open path; it must not replace
  # the original exception.
  it 'still re-raises the original error after the failure wrapper runs' do
    write_failure = Onetime::AuditWriteFailure.new(verb: 'customer.purge', target: 'ur_p')
    allow(Onetime::ColonelAuditEvent).to receive(:record).and_raise(write_failure)

    raised = nil
    begin
      described_class.new(customer: customer, actor: 'ur_col').call
    rescue Onetime::AuditWriteFailure => ex
      raised = ex
    end

    expect(raised).to be(write_failure)
  end
end
