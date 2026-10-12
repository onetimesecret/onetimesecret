# spec/unit/onetime/middleware/membership_snapshot_context_spec.rb
#
# frozen_string_literal: true

# Run: tests/lanes/run unit --only spec/unit/onetime/middleware/membership_snapshot_context_spec.rb
require 'spec_helper'
require 'onetime/middleware/membership_snapshot_context'

RSpec.describe Onetime::Middleware::MembershipSnapshotContext do
  let(:customer) { double('customer', objid: 'cust-1') }

  after { Onetime::MembershipSnapshot.close }

  it 'keeps the store open for the request and clears it after' do
    seen = []
    app  = ->(_env) do
      seen << Onetime::MembershipSnapshot.open?
      seen << (Onetime::MembershipSnapshot.for(customer).equal?(Onetime::MembershipSnapshot.for(customer)))
      [200, {}, ['ok']]
    end

    status, = described_class.new(app).call({})

    expect(status).to eq(200)
    expect(seen).to eq([true, true])
    expect(Onetime::MembershipSnapshot.open?).to be(false)
  end

  it 'clears the store when the app raises' do
    app = ->(_env) { raise 'boom' }

    expect { described_class.new(app).call({}) }.to raise_error('boom')
    expect(Onetime::MembershipSnapshot.open?).to be(false)
  end

  it 'does not carry a snapshot left by an earlier request on this fiber' do
    Onetime::MembershipSnapshot.open
    stale = Onetime::MembershipSnapshot.for(customer)
    app   = ->(_env) do
      expect(Onetime::MembershipSnapshot.for(customer)).not_to be(stale)
      [200, {}, []]
    end

    described_class.new(app).call({})
  end
end
