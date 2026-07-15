# apps/web/auth/spec/operations/customers/purge_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::Customers::Purge.
#
# Covers: it reuses DeleteCustomer, returns :success + audits once on a
# successful destroy (target = pre-destroy extid), and returns :not_found
# without auditing when nothing was deleted.
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/customers/purge_spec.rb

require 'spec_helper'
require 'onetime/models/admin_audit_event'
require 'auth/operations/customers/purge'

RSpec.describe Auth::Operations::Customers::Purge do
  let(:customer) do
    double('Customer', extid: 'ur_p', custid: 'cust_p', obscure_email: 'p***@e***.com')
  end
  let(:deleter) { instance_double(Auth::Operations::DeleteCustomer) }

  before do
    allow(Onetime::AdminAuditEvent).to receive(:record)
    allow(Auth::Operations::DeleteCustomer).to receive(:new).and_return(deleter)
  end

  it 'destroys via DeleteCustomer, returns :success, and audits once at the extid' do
    allow(deleter).to receive(:call).and_return(true)

    result = described_class.new(customer: customer, actor: 'ur_col').call

    expect(result.status).to eq(:success)
    expect(result.extid).to eq('ur_p')
    expect(Auth::Operations::DeleteCustomer).to have_received(:new).with(customer: customer)
    expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
      actor: 'ur_col',
      verb: 'customer.purge',
      target: 'ur_p',
      result: :success,
      detail: { email: 'p***@e***.com' },
    )
  end

  it 'returns :not_found and does not audit when nothing was deleted' do
    allow(deleter).to receive(:call).and_return(false)

    result = described_class.new(customer: customer, actor: 'x').call

    expect(result.status).to eq(:not_found)
    expect(Onetime::AdminAuditEvent).not_to have_received(:record)
  end
end
