# spec/unit/onetime/models/customer/chores/reserialize_fields_spec.rb
#
# frozen_string_literal: true

# Unit tests for the reserialize_fields housekeeping chore.
#
# Tests the legacy bare-string detection and resave logic without
# requiring Redis or actual Customer instances. Uses a double that
# mirrors the interface the chore expects (hgetall, extid, save).
#
# Five branches:
#   1. All values already JSON-encoded       -> silent no-op (nil)
#   2. Any value is a bare string            -> resave (true)
#   3. Bare JSON literals (true/false/null)  -> treated as serialized (skip)
#   4. Nil or empty values                   -> ignored (don't trigger resave)
#   5. Mixed fields (some bare, some JSON)   -> resave (true)
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
    allow(obj).to receive(:save).and_return(true)
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
        expect(cust).not_to receive(:save)
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
          expect(cust).not_to receive(:save)
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
        expect(cust).not_to receive(:save)
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

      it 'saves the customer' do
        expect(cust).to receive(:save)
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

      it 'saves the customer' do
        expect(cust).to receive(:save)
        chore.call(cust)
      end

      it 'returns true' do
        expect(chore.call(cust)).to be true
      end
    end

    context 'when a value is a bare number string (not JSON-quoted)' do
      # '123' does not start with {, [, or " and is not in %w[true false null],
      # so the heuristic flags it for resave.
      let(:raw_hash) { { 'some_count' => '123' } }

      it 'triggers resave' do
        expect(cust).to receive(:save)
        chore.call(cust)
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

      it 'saves the customer' do
        expect(cust).to receive(:save)
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
        expect(cust).to receive(:save)
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
        expect(cust).not_to receive(:save)
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
end
