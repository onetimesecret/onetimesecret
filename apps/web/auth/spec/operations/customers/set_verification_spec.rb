# apps/web/auth/spec/operations/customers/set_verification_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::Customers::SetVerification.
#
# Covers: it reuses (delegates to) the incumbent SetCustomerVerification op,
# passes through the result symbol + db, audits exactly once on :success,
# audits the ATTEMPT on :no_change too (#4337, marked outcome: no_change), and
# records one result: :failure (then re-raises) when the inner op raises one of
# its documented error classes.
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/customers/set_verification_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'auth/operations/customers/set_verification'

RSpec.describe Auth::Operations::Customers::SetVerification do
  let(:customer) { double('Customer', extid: 'ur_v') }
  let(:inner)    { instance_double(Auth::Operations::SetCustomerVerification) }

  before do
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Auth::Operations::SetCustomerVerification).to receive(:new).and_return(inner)
  end

  it 'delegates to SetCustomerVerification and audits once on :success' do
    allow(inner).to receive(:call).and_return(:success)

    result = described_class.new(
      customer: customer, verified: true, actor: 'ur_col', verified_by: 'colonel_admin'
    ).call

    expect(result).to eq(:success)
    expect(Auth::Operations::SetCustomerVerification).to have_received(:new).with(
      customer: customer, verified: true, verified_by: 'colonel_admin', db: nil
    )
    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      actor: 'ur_col',
      verb: 'customer.set_verification',
      target: 'ur_v',
      result: :success,
      detail: { verified: true },
    )
  end

  # #4337: a :no_change mutated nothing, but it is still a deliberate ADMIN
  # attempt to verify a named account — and this wrapper exists precisely so
  # admin verifications are distinguishable from the self-service Rodauth ones.
  # Dropping the no-op meant the trail could show nothing while an operator
  # repeatedly poked at an account's verification state.
  it 'audits the attempt on :no_change, marked outcome: no_change' do
    allow(inner).to receive(:call).and_return(:no_change)

    result = described_class.new(
      customer: customer, verified: true, actor: 'x', verified_by: 'colonel_admin'
    ).call

    expect(result).to eq(:no_change)
    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      actor: 'x',
      verb: 'customer.set_verification',
      target: 'ur_v',
      result: :success,
      detail: { outcome: 'no_change', verified: true },
    )
  end

  # Verification is reversible and destroys nothing, so neither path fails
  # closed.
  it 'does not fail closed on either path' do
    allow(inner).to receive(:call).and_return(:no_change)

    described_class.new(
      customer: customer, verified: true, actor: 'x', verified_by: 'colonel_admin'
    ).call

    expect(Onetime::ColonelAuditEvent).to have_received(:record).with(hash_excluding(:fail_closed))
  end

  it 'passes an injected db through to the underlying op' do
    allow(inner).to receive(:call).and_return(:no_change)
    db = double('db')

    described_class.new(
      customer: customer, verified: false, actor: 'x', verified_by: nil, db: db
    ).call

    expect(Auth::Operations::SetCustomerVerification).to have_received(:new).with(
      customer: customer, verified: false, verified_by: nil, db: db
    )
  end

  # The Onetime::AuditedFailure mechanism. This wrapper's ENTIRE job is the
  # audit event, and all three documented error classes are raised by the inner
  # op before it — so an operator repeatedly trying to verify a closed or
  # missing account previously left no trace whatsoever. Message expectation,
  # not a store read: ColonelAuditEvent.record swallows its own errors.
  it 'records ONE result: :failure event when the inner op raises, and re-raises' do
    error_class = Auth::Operations::SetCustomerVerification::AccountNotFound
    allow(inner).to receive(:call).and_raise(error_class, 'no auth row for ur_v')

    expect do
      described_class.new(
        customer: customer, verified: true, actor: 'ur_col', verified_by: 'colonel_admin'
      ).call
    end.to raise_error(error_class, /no auth row for ur_v/)

    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      hash_including(
        actor: 'ur_col',
        verb: 'customer.set_verification',
        target: 'ur_v', # literal: a broken target lambda silently lands as 'unknown'
        result: :failure,
        detail: hash_including(
          error: error_class.name, message: 'no auth row for ur_v', verified: true,
        ),
      ),
    )
  end
end
