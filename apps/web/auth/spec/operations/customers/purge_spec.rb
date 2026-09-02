# apps/web/auth/spec/operations/customers/purge_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::Customers::Purge.
#
# Covers: it reuses DeleteCustomer, returns :success + audits once on a
# successful destroy (target = pre-destroy extid), returns :not_found
# without auditing when nothing was deleted, and — since #4333 — writes that
# audit event FAIL-CLOSED: an unwritable event surfaces as a raised
# Onetime::AuditWriteFailure instead of a clean :success for a purge with no
# trail.
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/customers/purge_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'auth/operations/customers/purge'

RSpec.describe Auth::Operations::Customers::Purge do
  let(:customer) do
    double('Customer', extid: 'ur_p', custid: 'cust_p', obscure_email: 'p***@e***.com')
  end
  let(:deleter) { instance_double(Auth::Operations::DeleteCustomer) }

  before do
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Auth::Operations::DeleteCustomer).to receive(:new).and_return(deleter)
  end

  it 'destroys via DeleteCustomer, returns :success, and audits once at the extid' do
    allow(deleter).to receive(:call).and_return(true)

    result = described_class.new(customer: customer, actor: 'ur_col').call

    expect(result.status).to eq(:success)
    expect(result.extid).to eq('ur_p')
    expect(Auth::Operations::DeleteCustomer).to have_received(:new).with(customer: customer)
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

  it 'returns :not_found and does not audit when nothing was deleted' do
    allow(deleter).to receive(:call).and_return(false)

    result = described_class.new(customer: customer, actor: 'x').call

    expect(result.status).to eq(:not_found)
    expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
  end

  # The point of fail-closed (#4333): the op must NOT convert an unrecorded
  # purge into a successful-looking Result. Message expectation rather than a
  # store read — the model swallows its own errors on the fail-open path, so a
  # store read here could pass or fail for unrelated reasons.
  it 'propagates Onetime::AuditWriteFailure instead of returning :success' do
    allow(deleter).to receive(:call).and_return(true)
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
    allow(deleter).to receive(:call).and_return(true)
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
    allow(deleter).to receive(:call).and_return(true)
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
