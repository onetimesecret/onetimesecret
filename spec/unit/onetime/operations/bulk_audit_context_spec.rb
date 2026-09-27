# frozen_string_literal: true

require 'spec_helper'
require 'onetime/operations/bulk_audit_context'
require 'onetime/operations/org/delete'
require 'onetime/operations/memberships/remove'
require 'onetime/operations/sessions/revoke_all_for_customer'

RSpec.describe Onetime::Operations::BulkAuditContext do
  let(:actor) { 'cli' }
  let(:covered_verbs) do
    ['customer.purge', 'organization.delete', 'membership.remove', 'session.revoke_all']
  end
  let(:operations) do
    [
      { verb: 'customer.purge', target: 'ur_one' },
      { verb: 'session.revoke_all', target: 'ur_one' },
      { verb: 'organization.delete', target: 'on_owned' },
      { verb: 'membership.remove', target: 'ur_one', scope: 'on_shared' },
    ]
  end

  before do
    allow(Onetime::ColonelAuditEvent).to receive(:record).and_return('id' => 'receipt')
  end

  def start_context(candidate_targets: ['cust_one'])
    described_class.start!(
      actor: actor,
      verb: 'customer.purge.bulk',
      target: 'inactive-customers',
      covered_verbs: covered_verbs,
      candidate_targets: candidate_targets,
      detail: { candidates: candidate_targets.size },
    )
  end

  def verified?(authorization, verb:, target:, operation:, scope: nil)
    described_class.verified?(
      authorization,
      actor: actor,
      verb: verb,
      target: target,
      scope: scope,
      operation: operation,
    )
  end

  it 'does not expose a forgeable authorization constructor' do
    expect do
      described_class::CandidateAuthorization.new(
        context: double(active?: true),
        actor: actor,
        covered_verbs: covered_verbs,
        operations: operations,
      )
    end.to raise_error(NoMethodError, /private method/)
  end

  it 'invalidates outstanding authorization after completion' do
    context = start_context
    authorization = context.authorize_candidate(customer_target: 'cust_one', operations: operations)
    operation = Object.new

    expect(verified?(authorization, verb: 'customer.purge', target: 'ur_one', operation: operation)).to be(true)

    context.complete!(result: :success, detail: { destroyed: 1 })

    expect(verified?(authorization, verb: 'customer.purge', target: 'ur_one', operation: operation)).to be(false)
    expect(context.authorize_candidate(customer_target: 'cust_one', operations: operations)).to be_nil
  end

  it 'invalidates outstanding authorization after abort' do
    context = start_context
    authorization = context.authorize_candidate(customer_target: 'cust_one', operations: operations)

    context.abort!(detail: { processed: 0 })

    expect(verified?(authorization, verb: 'customer.purge', target: 'ur_one', operation: Object.new)).to be(false)
  end

  it 'fails closed for an unregistered customer target' do
    context = start_context

    expect(context.authorize_candidate(customer_target: 'cust_other', operations: operations)).to be_nil
  end

  it 'consumes each registered customer target once' do
    context = start_context

    expect(context.authorize_candidate(customer_target: 'cust_one', operations: operations))
      .to be_a(described_class::CandidateAuthorization)
    expect(context.authorize_candidate(customer_target: 'cust_one', operations: operations)).to be_nil
  end

  it 'binds production child operations to the authorized customer and organization scopes' do
    context = start_context
    authorization = context.authorize_candidate(customer_target: 'cust_one', operations: operations)
    customer = double('Customer', extid: 'ur_one')
    owned_org = double('OwnedOrg', objid: 'org_owned', extid: 'on_owned', display_name: 'Owned')
    shared_org = double('SharedOrg', extid: 'on_shared')

    org_delete = Onetime::Operations::Org::Delete.new(
      org: owned_org,
      actor: actor,
      dry_run: false,
      bulk_audit_context: authorization,
    )
    membership_remove = Onetime::Operations::Memberships::Remove.new(
      org: shared_org,
      customer: customer,
      actor: actor,
      bulk_audit_context: authorization,
    )
    session_revoke = Onetime::Operations::Sessions::RevokeAllForCustomer.new(
      customer: customer,
      actor: actor,
      bulk_audit_context: authorization,
    )

    expect(org_delete.send(:audit_enabled?)).to be(false)
    expect(membership_remove.send(:audit_enabled?)).to be(false)
    expect(session_revoke.send(:audit_enabled?)).to be(false)

    wrong_org_remove = Onetime::Operations::Memberships::Remove.new(
      org: double('OtherOrg', extid: 'on_other'),
      customer: customer,
      actor: actor,
      bulk_audit_context: authorization,
    )
    expect(wrong_org_remove.send(:audit_enabled?)).to be(true)
  end

  it 'binds child suppression to known targets, scopes, and one operation instance' do
    context = start_context
    authorization = context.authorize_candidate(customer_target: 'cust_one', operations: operations)
    org_delete = Object.new
    membership_remove = Object.new

    expect(verified?(authorization,
      verb: 'organization.delete', target: 'on_owned', operation: org_delete)).to be(true)
    expect(verified?(authorization,
      verb: 'organization.delete', target: 'on_other', operation: Object.new)).to be(false)
    expect(verified?(authorization,
      verb: 'organization.delete', target: 'on_owned', operation: Object.new)).to be(false)

    expect(verified?(authorization,
      verb: 'membership.remove', target: 'ur_one', scope: 'on_shared', operation: membership_remove)).to be(true)
    expect(verified?(authorization,
      verb: 'membership.remove', target: 'ur_one', scope: 'on_other', operation: Object.new)).to be(false)
    expect(verified?(authorization,
      verb: 'membership.remove', target: 'ur_other', scope: 'on_shared', operation: Object.new)).to be(false)
  end
end
