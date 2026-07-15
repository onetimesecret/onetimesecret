# apps/web/auth/spec/operations/customers/set_verification_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::Customers::SetVerification.
#
# Covers: it reuses (delegates to) the incumbent SetCustomerVerification op,
# passes through the result symbol + db, audits exactly once on :success, and
# does not audit on :no_change.
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/customers/set_verification_spec.rb

require 'spec_helper'
require 'onetime/models/admin_audit_event'
require 'auth/operations/customers/set_verification'

RSpec.describe Auth::Operations::Customers::SetVerification do
  let(:customer) { double('Customer', extid: 'ur_v') }
  let(:inner)    { instance_double(Auth::Operations::SetCustomerVerification) }

  before do
    allow(Onetime::AdminAuditEvent).to receive(:record)
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
    expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
      actor: 'ur_col',
      verb: 'customer.set_verification',
      target: 'ur_v',
      result: :success,
      detail: { verified: true },
    )
  end

  it 'does not audit on :no_change' do
    allow(inner).to receive(:call).and_return(:no_change)

    result = described_class.new(
      customer: customer, verified: true, actor: 'x', verified_by: 'colonel_admin'
    ).call

    expect(result).to eq(:no_change)
    expect(Onetime::AdminAuditEvent).not_to have_received(:record)
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
end
