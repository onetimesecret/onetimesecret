# spec/unit/onetime/models/customer/stored_verified_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Customer#stored_verified?: the verified flag as the datastore holds it,
# read without changing the object's fields. Familia JSON-encodes every
# string, so a record saved by current code holds the bytes "\"true\"", and
# a raw comparison with 'true' matches only a legacy bare value.
#
# Run: tests/lanes/run unit --only spec/unit/onetime/models/customer/stored_verified_spec.rb
RSpec.describe Onetime::Customer, '#stored_verified?', :datastore do
  let(:suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }

  before do
    # Real loggers here: create! and load log under other names.
    allow(Onetime).to receive(:get_logger).and_call_original
    @customer = described_class.create!(email: "stored_verified_#{suffix}@onetimesecret.com")
  end

  after { @customer&.destroy! }

  def raw_verified
    Familia.dbclient.hget(@customer.dbkey, 'verified')
  end

  def save_verified(value)
    @customer.verified = value
    @customer.save
  end

  it 'is true for a record saved verified, whose stored bytes are JSON-quoted' do
    save_verified(true)

    expect(raw_verified).to eq('"true"')
    expect(@customer.stored_verified?).to be(true)
  end

  it 'is false for a record saved unverified' do
    save_verified(false)

    expect(@customer.stored_verified?).to be(false)
  end

  it 'is false when the field was never written' do
    Familia.dbclient.hdel(@customer.dbkey, 'verified')

    expect(@customer.stored_verified?).to be(false)
  end

  it 'is true for a legacy bare value, as a load reads it' do
    Familia.dbclient.hset(@customer.dbkey, 'verified', 'true')

    expect(@customer.stored_verified?).to be(true)
    expect(described_class.load(@customer.identifier).verified?).to be(true)
  end

  it 'reads the datastore and leaves the object as it was' do
    save_verified(true)
    @customer.verified = false
    @customer.locale   = 'fr'

    expect(@customer.stored_verified?).to be(true)
    expect(@customer.verified?).to be(false)
    expect(@customer.locale).to eq('fr')
  end

  it 'sees an unverify another process saved after this object was loaded' do
    save_verified(true)
    other          = described_class.load(@customer.identifier)
    other.verified = false
    other.save

    expect(@customer.verified?).to be(true)
    expect(@customer.stored_verified?).to be(false)
  end
end
