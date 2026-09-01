# apps/web/auth/spec/operations/customers/set_role_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::Customers::SetRole.
#
# Covers: successful change (+ exactly one audit event), idempotent no_change
# (no save, but STILL one audit event since #4337), the operator reason
# threaded through both (#4338), and invalid-role rejection.
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/customers/set_role_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'auth/operations/customers/set_role'

RSpec.describe Auth::Operations::Customers::SetRole do
  let(:customer) do
    double('Customer', role: 'customer', extid: 'ur_test', :role= => nil, save: true)
  end

  before { allow(Onetime::ColonelAuditEvent).to receive(:record) }

  it 'changes the role, saves, and returns :success with from/to' do
    result = described_class.new(customer: customer, role: 'colonel', actor: 'ur_col').call

    expect(result.status).to eq(:success)
    expect(result.from).to eq('customer')
    expect(result.to).to eq('colonel')
    expect(customer).to have_received(:role=).with('colonel')
    expect(customer).to have_received(:save)
  end

  it 'records exactly one audit event on success (actor = public id, target = extid)' do
    described_class.new(customer: customer, role: 'colonel', actor: 'ur_col').call

    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      actor: 'ur_col',
      verb: 'customer.set_role',
      target: 'ur_test',
      result: :success,
      detail: { from: 'customer', to: 'colonel' },
      # #4333: a privilege grant leaves no other durable evidence, so the
      # write is fail-closed — an unwritable event raises instead of
      # reporting :success.
      fail_closed: true,
    )
  end

  # #4337: idempotent in EFFECT, not in the trail. Nothing is saved, but
  # reaching for `colonel` on an account that already holds it is the same
  # reach for the same privilege, so the ATTEMPT is recorded under the same
  # verb, marked `outcome: 'no_change'`.
  it 'is a no_change (no save) but still records the attempt when already at the target role' do
    allow(customer).to receive(:role).and_return('colonel')

    result = described_class.new(customer: customer, role: 'colonel', actor: 'x').call

    expect(result.status).to eq(:no_change)
    expect(customer).not_to have_received(:save)
    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      actor: 'x',
      verb: 'customer.set_role',
      target: 'ur_test',
      result: :success,
      detail: { outcome: 'no_change', from: 'colonel', to: 'colonel' },
    )
  end

  # No privilege moved, so there is nothing untraceable for a hard failure to
  # surface — and turning an idempotent no-op into a 500 would be a
  # regression. This is the one place the no-change event differs from the
  # applied one above.
  it 'does not fail closed on a no_change, unlike the applied role change' do
    allow(customer).to receive(:role).and_return('colonel')

    described_class.new(customer: customer, role: 'colonel', actor: 'x').call

    expect(Onetime::ColonelAuditEvent).to have_received(:record).with(hash_excluding(:fail_closed))
  end

  # #4338: the operator reason threads through the no-change path too — a
  # refused-because-already-there attempt is exactly the one a reviewer wants
  # the WHY for.
  it 'carries an operator reason into the no_change detail' do
    allow(customer).to receive(:role).and_return('colonel')

    described_class.new(
      customer: customer, role: 'colonel', actor: 'x', reason: '  ticket OPS-42  ',
    ).call

    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      hash_including(detail: { outcome: 'no_change', from: 'colonel', to: 'colonel', reason: 'ticket OPS-42' }),
    )
  end

  # Blank is ABSENT, never `reason: ""` — an operator who tabs past the field
  # must not mint a row that reads as "they gave a reason".
  it 'leaves the no_change detail byte-identical when the reason is blank' do
    allow(customer).to receive(:role).and_return('colonel')

    described_class.new(customer: customer, role: 'colonel', actor: 'x', reason: '   ').call

    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      hash_including(detail: { outcome: 'no_change', from: 'colonel', to: 'colonel' }),
    )
  end

  it 'raises InvalidRole (no save) for an unknown role' do
    expect do
      described_class.new(customer: customer, role: 'wizard', actor: 'x').call
    end.to raise_error(described_class::InvalidRole)

    expect(customer).not_to have_received(:save)
  end

  # Onetime::AuditedFailure: the InvalidRole guard raises before the
  # success-path record call, so a rejected role change would otherwise be
  # invisible. A refused attempt to hand out a role is exactly what the trail
  # is for.
  it 'records one result: :failure event for a rejected role and re-raises' do
    expect do
      described_class.new(customer: customer, role: 'wizard', actor: 'x').call
    end.to raise_error(described_class::InvalidRole)

    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      hash_including(
        actor: 'x',
        verb: 'customer.set_role',
        result: :failure,
        detail: hash_including(error: 'Auth::Operations::Customers::SetRole::InvalidRole'),
      ),
    )
  end
end
