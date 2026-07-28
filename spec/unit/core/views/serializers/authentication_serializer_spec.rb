# spec/unit/core/views/serializers/authentication_serializer_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'sequel'

# Unit tests for AuthenticationSerializer.account_has_password? (#3926).
#
# The lookup is tri-state: true/false are definitive answers, nil means the
# query failed and the caller (frontend bootstrap store) should keep its last
# known value. A transient database error must never serialize as a confident
# has_password:false — that is the wire signal for an SSO-only account and
# hides the password/MFA settings UI. Programming errors must propagate.
RSpec.describe Core::Views::AuthenticationSerializer do
  describe '.account_has_password?' do
    subject(:result) { described_class.account_has_password?(sess) }

    let(:sess) { { 'account_id' => 42 } }
    let(:dataset) { instance_double(Sequel::Dataset) }
    let(:db) { double('Sequel::Database') }

    before do
      stub_const('Auth::Database', class_double('Auth::Database', connection: db))
      allow(db).to receive(:[]).with(:account_password_hashes).and_return(dataset)
      allow(dataset).to receive(:where).with(id: 42).and_return(dataset)
    end

    context 'without a session account' do
      let(:sess) { nil }

      it 'returns false for a nil session' do
        expect(result).to be(false)
      end

      it 'returns false when the session has no account_id' do
        expect(described_class.account_has_password?({})).to be(false)
      end
    end

    context 'when the auth app is not loaded' do
      before { hide_const('Auth::Database') }

      it 'returns false' do
        expect(result).to be(false)
      end
    end

    context 'without an auth database connection (simple mode)' do
      let(:db) { nil }

      it 'returns false' do
        expect(result).to be(false)
      end
    end

    context 'with a working database' do
      it 'returns true when a password hash row exists' do
        allow(dataset).to receive(:any?).and_return(true)

        expect(result).to be(true)
      end

      it 'returns false for an SSO-only account (no row)' do
        allow(dataset).to receive(:any?).and_return(false)

        expect(result).to be(false)
      end
    end

    context 'when the query raises a database error' do
      before do
        allow(dataset).to receive(:any?).and_raise(Sequel::DatabaseError, 'connection refused')
      end

      it 'returns nil (unknown), not false' do
        expect(result).to be_nil
      end

      it 'logs the failure with class and account context' do
        expect(OT).to receive(:le).with(
          '[AuthenticationSerializer] account_has_password? query failed: Sequel::DatabaseError account_id=42'
        )

        result
      end
    end

    context 'when the connection pool is exhausted' do
      before do
        allow(dataset).to receive(:any?).and_raise(Sequel::PoolTimeout, 'pool timeout')
      end

      it 'returns nil (unknown)' do
        expect(result).to be_nil
      end
    end

    context 'when the lookup hits a programming error' do
      before do
        allow(dataset).to receive(:any?).and_raise(NoMethodError, "undefined method `oops'")
      end

      it 'propagates instead of masking it as a serialized value' do
        expect { result }.to raise_error(NoMethodError)
      end
    end
  end
end
