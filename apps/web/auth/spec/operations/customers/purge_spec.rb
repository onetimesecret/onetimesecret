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
  let(:preflight) { instance_double(Auth::Operations::Customers::PurgePreflight, call: empty_plan) }

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
      authentication_closed: false,
      bulk_audit_context: nil,
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

  it 'passes the administrative context to the unified deletion operation' do
    described_class.new(customer: customer, actor: 'ur_col', reason: 'takeover').call

    expect(Auth::Operations::TeardownAccount).to have_received(:new).with(
      customer: customer,
      actor: 'ur_col',
      reason: 'takeover',
      before_mutation: kind_of(Method),
      on_mutation: kind_of(Method),
      authentication_closed: false,
      bulk_audit_context: nil,
    )
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

  it 'deletes an approved personal workspace canonically before account teardown' do
    org = double('Organization', objid: 'org-obj')
    action = Auth::Operations::Customers::PurgePreflight::Action.new(
      type: :delete_organization, organization: org, org_id: 'on_personal', role: 'owner',
    )
    ready = Auth::Operations::Customers::PurgePreflight::Plan.new(actions: [action], blockers: [])
    planners = [ready, ready, empty_plan].map do |plan|
      instance_double(Auth::Operations::Customers::PurgePreflight, call: plan)
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
    )
    expect(Auth::Operations::TeardownAccount).to have_received(:new).with(
      customer: customer,
      actor: 'ur_col',
      reason: 'erasure',
      before_mutation: kind_of(Method),
      on_mutation: kind_of(Method),
      authentication_closed: false,
      bulk_audit_context: nil,
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
    )
    expect(Auth::Operations::TeardownAccount).to have_received(:new).with(
      customer: customer,
      actor: 'cli',
      reason: nil,
      before_mutation: kind_of(Method),
      on_mutation: kind_of(Method),
      authentication_closed: false,
      bulk_audit_context: kind_of(Onetime::Operations::BulkAuditContext::CandidateAuthorization),
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
      instance_double(Auth::Operations::Customers::PurgePreflight, call: plan)
    end
    allow(Auth::Operations::Customers::PurgePreflight).to receive(:new).and_return(*planners)

    remove_result = double('MembershipRemoveResult', status: :success)
    remove_op = instance_double(Onetime::Operations::Memberships::Remove, call: remove_result)
    allow(Onetime::Operations::Memberships::Remove).to receive(:new).and_return(remove_op)

    result = described_class.new(customer: customer, actor: 'ur_col').call

    expect(result.status).to eq(:success)
    expect(Onetime::Operations::Memberships::Remove).to have_received(:new).with(
      org: org, customer: customer, actor: 'ur_col', reason: nil, bulk_audit_context: nil,
    )
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
      instance_double(Auth::Operations::Customers::PurgePreflight, call: plan)
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
