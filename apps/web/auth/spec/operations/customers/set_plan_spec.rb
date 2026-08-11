# apps/web/auth/spec/operations/customers/set_plan_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::Customers::SetPlan.
#
# Covers: successful change (+ exactly one audit event), idempotent no_change
# (no save, no audit), and a raising save (Onetime::AuditedFailure records
# result: :failure and re-raises). Catalog validation is the adapter's job, so
# this op accepts any planid — there is no invalid-plan rejection here.
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/customers/set_plan_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'auth/operations/customers/set_plan'

RSpec.describe Auth::Operations::Customers::SetPlan do
  let(:customer) do
    double('Customer', planid: 'free_v1', extid: 'ur_test', :planid= => nil, save: true)
  end

  before { allow(Onetime::ColonelAuditEvent).to receive(:record) }

  it 'changes the plan, saves, and returns :success with from/to' do
    result = described_class.new(customer: customer, planid: 'pro_v1', actor: 'ur_col').call

    expect(result.status).to eq(:success)
    expect(result.from).to eq('free_v1')
    expect(result.to).to eq('pro_v1')
    expect(customer).to have_received(:planid=).with('pro_v1')
    expect(customer).to have_received(:save)
  end

  it 'records exactly one audit event on success (actor = public id, target = extid)' do
    described_class.new(customer: customer, planid: 'pro_v1', actor: 'ur_col').call

    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      actor: 'ur_col',
      verb: 'customer.set_plan',
      target: 'ur_test',
      result: :success,
      detail: { from: 'free_v1', to: 'pro_v1' },
    )
  end

  it 'is a no_change (no save, no audit) when already on the target plan' do
    allow(customer).to receive(:planid).and_return('pro_v1')

    result = described_class.new(customer: customer, planid: 'pro_v1', actor: 'x').call

    expect(result.status).to eq(:no_change)
    expect(customer).not_to have_received(:save)
    expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
  end

  # The Onetime::AuditedFailure mechanism. `save` runs BEFORE the success-path
  # record call, so without the macro a plan change that blew up mid-write left
  # the trail claiming nothing happened. Message expectation, not a store read:
  # ColonelAuditEvent.record swallows its own errors and returns nil.
  it 'records ONE result: :failure event when save raises, and re-raises' do
    allow(customer).to receive(:save).and_raise(Onetime::Problem, 'redis down')

    expect do
      described_class.new(customer: customer, planid: 'pro_v1', actor: 'ur_col').call
    end.to raise_error(Onetime::Problem, /redis down/)

    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      hash_including(
        actor: 'ur_col',
        verb: 'customer.set_plan',
        target: 'ur_test', # literal: a broken target lambda silently lands as 'unknown'
        result: :failure,
        detail: hash_including(
          error: 'Onetime::Problem', message: 'redis down', to: 'pro_v1',
        ),
      ),
    )
  end
end
