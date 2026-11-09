# apps/web/auth/spec/operations/customers/change_email_forced_clear_record_spec.rb
#
# frozen_string_literal: true

# ChangeEmail's forced verification clear against a STORED Customer.
#
# change_email_spec.rb stubs every collaborator, including the persisted
# `verified` field, so it cannot see the bytes Familia writes: every string
# is JSON-encoded, and a Customer saved verified holds "\"true\"". A guard
# that compared the raw field with 'true' read such a record as already
# unverified, skipped the clear, and the op still reported :reset. In simple
# mode, where Redis is the login authority, the account then stayed verified
# on an address nobody had proven. These examples use a real record.
#
# Run: tests/lanes/run unit --only apps/web/auth/spec/operations/customers/change_email_forced_clear_record_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'auth/database'
require 'auth/operations/customers/change_email'

RSpec.describe Auth::Operations::Customers::ChangeEmail, 'forced clear on a stored Customer', :datastore do
  let(:suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }

  before do
    # Real loggers here: create! and load log under other names.
    allow(Onetime).to receive(:get_logger).and_call_original
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    # Simple mode: no accounts row, so the Customer is the only store.
    allow(Auth::Database).to receive(:connection).and_return(nil)

    @record             = Onetime::Customer.create!(email: "forced_clear_#{suffix}@onetimesecret.com")
    @record.verified    = true
    @record.verified_by = 'email'
    @record.save
  end

  after { @record&.destroy! }

  def op
    described_class.new(customer: @record, new_email: "new_#{suffix}@onetimesecret.com",
      actor: 'cli', dry_run: false)
  end

  def stored
    Onetime::Customer.load(@record.identifier)
  end

  it 'clears a Customer the datastore holds as verified' do
    expect(op.send(:clear_customer_verification!)).to eq(:cleared)
    expect(stored.verified?).to be(false)
    expect(stored.verified_by.to_s).to be_empty
  end

  it 'reports the forced clear only after it reached the datastore (simple mode)' do
    change = op

    expect(change.send(:force_clear_verification!)).to eq(:reset)
    expect(stored.verified?).to be(false)
    expect(change.instance_variable_get(:@warnings)).to include(:verification_force_cleared)
  end

  it 'leaves a Customer the datastore holds as unverified alone' do
    @record.verified    = false
    @record.verified_by = nil
    @record.save

    expect(op.send(:clear_customer_verification!)).to eq(:unchanged)
  end

  # Without the op's own rescue the error reaches the outer rescue in
  # clear_customer_verification! and the result is :failed.
  it 'runs the clear when the stored read raises (fails closed)' do
    allow(@record).to receive(:stored_verified?).and_raise(StandardError, 'read failed')

    expect(op.send(:clear_customer_verification!)).to eq(:cleared)
    expect(stored.verified?).to be(false)
  end
end
