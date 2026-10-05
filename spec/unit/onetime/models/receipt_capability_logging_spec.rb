# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Receipt capability logging' do
  let(:receipt) do
    Onetime::Receipt.new.tap do |record|
      record.state = 'new'
      record.secret_identifier = 'secret-bearer-value-not-for-logs'
      allow(record).to receive(:identifier).and_return('receipt-bearer-value-not-for-logs')
      allow(record).to receive(:save).and_return(true)
      allow(record).to receive(:compare_and_set_state!).and_return(true)
      allow(record).to receive(:record_org_secret_activity_event)
      allow(record).to receive(:secret_expired?).and_return(true)
      allow(record).to receive(:age).and_return(3600)
    end
  end
  let(:messages) { [] }

  before do
    logger = double('secret logger')
    [:info, :warn].each do |level|
      allow(logger).to receive(level) { |message, payload| messages << [message, payload] }
    end
    allow(receipt).to receive(:secret_logger).and_return(logger)
  end

  [:revealed!, :orphaned!, :burned!, :expired!].each do |transition|
    it "omits the full secret identifier on #{transition}" do
      receipt.public_send(transition)
      expect(messages.size).to eq(1)
      expect(messages.to_s).not_to include('secret-bearer-value-not-for-logs', 'receipt-bearer-value-not-for-logs')
      expect(messages.last.last).to include(receipt_id: 'receipt-', secret_id: 'secret-b')
    end
  end

  it 'omits the key and exception message when a customer receipt cannot be loaded' do
    customer = Onetime::Customer.new
    allow(customer).to receive(:extid).and_return('customer-extid')
    allow(customer).to receive(:receipts).and_return(double(revmembers: ['receipt-bearer-value-not-for-logs']))
    allow(Onetime::Receipt).to receive(:load).and_raise(Onetime::RecordNotFound, 'receipt-bearer-value-not-for-logs')
    allow(Onetime).to receive(:le)

    expect(customer.receipts_list).to eq([])
    expect(Onetime).to have_received(:le).with('[receipts_list] Onetime::RecordNotFound (receipt=receipt- / customer=customer-extid)')
  end
end
