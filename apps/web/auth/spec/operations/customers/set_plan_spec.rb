# apps/web/auth/spec/operations/customers/set_plan_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::Customers::SetPlan.
#
# Covers: successful change (+ exactly one audit event), and idempotent
# no_change (no save, no audit). Catalog validation is the adapter's job, so
# this op accepts any planid — there is no invalid-plan rejection here.
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/customers/set_plan_spec.rb

require 'spec_helper'
require 'onetime/models/admin_audit_event'
require 'auth/operations/customers/set_plan'

RSpec.describe Auth::Operations::Customers::SetPlan do
  let(:customer) do
    double('Customer', planid: 'free_v1', extid: 'ur_test', :planid= => nil, save: true)
  end

  before { allow(Onetime::AdminAuditEvent).to receive(:record) }

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

    expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
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
    expect(Onetime::AdminAuditEvent).not_to have_received(:record)
  end
end
