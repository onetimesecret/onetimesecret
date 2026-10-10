# spec/unit/onetime/models/customer/chores/reserialize_fields_spec.rb
#
# frozen_string_literal: true

# Unit tests for the reserialize_fields housekeeping chore.
#
# Tests the legacy bare-string detection and resave logic with a double
# that mirrors the interface the chore expects (hgetall, extid,
# save_fields). A full `save` is not stubbed, so calling it fails the
# example. The last group runs against the datastore to show the partial
# write keeps a concurrent edit (#4343).
#
# Five branches:
#   1. All values already JSON-encoded       -> silent no-op (nil)
#   2. Any value is a bare string            -> rewrite the bare fields (true)
#   3. Bare JSON literals (true/false/null)  -> treated as serialized (skip)
#   4. Nil or empty values                   -> ignored (don't trigger resave)
#   5. Mixed fields (some bare, some JSON)   -> rewrite the bare fields (true)
#
# Run: pnpm run test:rspec spec/unit/onetime/models/customer/chores/reserialize_fields_spec.rb

require 'spec_helper'

# Load the chore registration
require_relative '../../../../../../lib/onetime/models/customer/chores/reserialize_fields'

RSpec.describe 'Customer chore: reserialize_fields' do
  let(:chore) { Onetime::Customer.chores[:reserialize_fields] }

  let(:mock_logger) do
    double('SemanticLogger').tap do |logger|
      allow(logger).to receive(:info) { |_msg, _payload = {}| nil }
    end
  end

  # Build a customer double with hgetall returning `raw_hash`.
  # hgetall is defined on Familia::Horreum::DatabaseCommands,
  # which Customer inherits, so instance_double resolves it.
  let(:cust) do
    obj = instance_double(
      'Onetime::Customer',
      extid: 'cust_test456',
      hgetall: raw_hash,
    )
    allow(obj).to receive(:save_fields).and_return(obj)
    %i[email= role= planid= locale= custid=].each { |setter| allow(obj).to receive(setter) }
    obj
  end

  before do
    allow(Onetime).to receive(:get_logger).with('Chores').and_return(mock_logger)
  end

  describe 'chore registration' do
    let(:raw_hash) { {} }

    it 'is registered on Onetime::Customer' do
      expect(Onetime::Customer.chores).to have_key(:reserialize_fields)
    end

    it 'is a callable block' do
      expect(chore).to respond_to(:call)
    end
  end

  describe 'already-serialized fields (silent skip)' do
    context 'when all values are JSON-quoted strings' do
      let(:raw_hash) do
        {
          'email' => '"alice@example.com"',
          'custid' => '"cust_abc123"',
          'role' => '"customer"',
        }
      end

      it 'returns nil' do
        expect(chore.call(cust)).to be_nil
      end

      it 'does not save' do
        expect(cust).not_to receive(:save_fields)
        chore.call(cust)
      end

      it 'does not log' do
        expect(mock_logger).not_to receive(:info)
        chore.call(cust)
      end
    end

    context 'when values start with { (JSON object)' do
      let(:raw_hash) { { 'metadata' => '{"key":"value"}' } }

      it 'returns nil' do
        expect(chore.call(cust)).to be_nil
      end
    end

    context 'when values start with [ (JSON array)' do
      let(:raw_hash) { { 'tags' => '["a","b"]' } }

      it 'returns nil' do
        expect(chore.call(cust)).to be_nil
      end
    end
  end

  describe 'bare JSON literals (true/false/null) are treated as serialized' do
    %w[true false null].each do |literal|
      context "when a value is bare #{literal.inspect}" do
        let(:raw_hash) { { 'some_flag' => literal } }

        it 'returns nil (skips)' do
          expect(chore.call(cust)).to be_nil
        end

        it 'does not save' do
          expect(cust).not_to receive(:save_fields)
          chore.call(cust)
        end
      end
    end
  end

  describe 'nil and empty values are ignored' do
    context 'when all values are nil' do
      let(:raw_hash) { { 'email' => nil, 'role' => nil } }

      it 'returns nil (skips)' do
        expect(chore.call(cust)).to be_nil
      end

      it 'does not save' do
        expect(cust).not_to receive(:save_fields)
        chore.call(cust)
      end
    end

    context 'when all values are empty strings' do
      let(:raw_hash) { { 'email' => '', 'role' => '' } }

      it 'returns nil (skips)' do
        expect(chore.call(cust)).to be_nil
      end
    end

    context 'when hash is empty' do
      let(:raw_hash) { {} }

      it 'returns nil (skips)' do
        expect(chore.call(cust)).to be_nil
      end
    end
  end

  describe 'bare string fields trigger resave' do
    context 'when email is a bare string (not JSON-quoted)' do
      let(:raw_hash) do
        {
          'email' => 'alice@example.com',
          'custid' => '"cust_abc123"',
        }
      end

      it 'rewrites only the bare field, from the bytes just read' do
        expect(cust).to receive(:email=).with('alice@example.com').ordered
        expect(cust).to receive(:save_fields).with(:email).ordered
        chore.call(cust)
      end

      it 'returns true' do
        expect(chore.call(cust)).to be true
      end

      it 'logs with chore name and cust_extid' do
        expect(mock_logger).to receive(:info).with(
          'Reserializing legacy plain-string fields',
          hash_including(
            chore: :reserialize_fields,
            cust_extid: 'cust_test456',
          ),
        )
        chore.call(cust)
      end
    end

    context 'when role is a bare string' do
      let(:raw_hash) { { 'role' => 'customer' } }

      it 'rewrites the role field' do
        expect(cust).to receive(:save_fields).with(:role)
        chore.call(cust)
      end

      it 'returns true' do
        expect(chore.call(cust)).to be true
      end
    end

    context 'when a value is a bare number string (not JSON-quoted)' do
      # '1700000000' does not start with {, [, or " and is not in
      # %w[true false null], so the heuristic flags the record. But a bare
      # number is already v2's encoding: nothing to rewrite, and rewriting it
      # from the loaded copy could undo a concurrent write.
      let(:raw_hash) { { 'last_login' => '1700000000' } }

      it 'reports the record but rewrites nothing' do
        expect(cust).not_to receive(:save_fields)
        expect(chore.call(cust)).to be true
      end
    end

    context 'when the bare field is not a declared field' do
      # `save` only ever wrote declared fields, so it left these alone too;
      # the result (true) is unchanged.
      let(:raw_hash) { { 'some_count' => '123' } }

      it 'writes nothing and still reports the record' do
        expect(cust).not_to receive(:save_fields)
        expect(chore.call(cust)).to be true
      end
    end
  end

  describe 'mixed fields (some bare, some serialized)' do
    context 'when one field is bare among properly-serialized fields' do
      let(:raw_hash) do
        {
          'email' => '"alice@example.com"',
          'custid' => '"cust_abc123"',
          'role' => '"customer"',
          'planid' => 'basic',  # bare string
        }
      end

      it 'rewrites only the bare field, not the serialized ones' do
        expect(cust).to receive(:save_fields).with(:planid)
        chore.call(cust)
      end

      it 'returns true' do
        expect(chore.call(cust)).to be true
      end
    end

    context 'when nil/empty values coexist with a bare string' do
      let(:raw_hash) do
        {
          'email' => nil,
          'role' => '',
          'locale' => 'en',  # bare string
        }
      end

      it 'triggers resave due to the bare string' do
        expect(cust).to receive(:save_fields).with(:locale)
        chore.call(cust)
      end
    end
  end

  describe 'idempotency' do
    context 'when all fields are already serialized' do
      let(:raw_hash) do
        {
          'email' => '"alice@example.com"',
          'role' => '"customer"',
        }
      end

      it 'returns nil on first call' do
        expect(chore.call(cust)).to be_nil
      end

      it 'returns nil on second call (still a no-op)' do
        chore.call(cust)
        expect(chore.call(cust)).to be_nil
      end

      it 'never saves across multiple calls' do
        expect(cust).not_to receive(:save_fields)
        chore.call(cust)
        chore.call(cust)
      end
    end
  end

  describe 'logging details' do
    context 'when resave occurs' do
      let(:raw_hash) { { 'email' => 'alice@example.com' } }

      it 'includes chore name in payload' do
        expect(mock_logger).to receive(:info).with(
          'Reserializing legacy plain-string fields',
          hash_including(chore: :reserialize_fields),
        )
        chore.call(cust)
      end

      it 'includes cust_extid in payload' do
        expect(mock_logger).to receive(:info).with(
          'Reserializing legacy plain-string fields',
          hash_including(cust_extid: 'cust_test456'),
        )
        chore.call(cust)
      end
    end

    context 'when no resave needed' do
      let(:raw_hash) { { 'email' => '"alice@example.com"' } }

      it 'does not log' do
        expect(mock_logger).not_to receive(:info)
        chore.call(cust)
      end
    end
  end

  # The point of the partial write (#4343): HousekeepingJob loads customers
  # in batches, and an on-demand run can land while a customer is being
  # edited. A whole-record save from the stale copy would undo that edit.
  describe 'against the datastore', :datastore do
    let(:suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }

    before do
      # Real loggers here: create! and load log under other names.
      allow(Onetime).to receive(:get_logger).and_call_original
      @customer = Onetime::Customer.create!(email: "reserialize_#{suffix}@onetimesecret.com")
      @customer.planid = 'basic'
      @customer.save_fields(:planid)
      # A legacy, pre-v2 bare value.
      Familia.dbclient.hset(@customer.dbkey, 'locale', 'en')
    end

    after { @customer&.destroy! }

    it 'keeps fields edited after the batch load and re-encodes the legacy one' do
      stale = Onetime::Customer.load(@customer.identifier) # the batch load

      concurrent         = Onetime::Customer.load(@customer.identifier)
      concurrent.planid  = 'identity_plus_v1'
      concurrent.updated = Familia.now.to_f + 100 # bare number, as v2 writes it
      concurrent.save_fields(:planid, :updated)
      @concurrent_updated = Familia.dbclient.hget(@customer.dbkey, 'updated')

      expect(chore.call(stale)).to be true

      raw = Familia.dbclient.hgetall(@customer.dbkey)
      expect(raw['planid']).to eq('"identity_plus_v1"')
      expect(raw['locale']).to eq('"en"')
      expect(raw['updated']).to eq(@concurrent_updated)
    end
  end
end
