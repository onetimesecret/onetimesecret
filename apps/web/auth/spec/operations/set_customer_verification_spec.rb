# apps/web/auth/spec/operations/set_customer_verification_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::SetCustomerVerification CONTROL FLOW:
#
# - Idempotency when already in target state
# - Simple-mode verify/unverify (Redis only, SQL never touched)
# - rodauth_already_synced: caller owns the SQL side, op only mirrors Redis
# - NoAuthDatabase when full mode has no connection
# - SQL exceptions propagate with Redis untouched
#
# Everything that actually touches the accounts table — external_id keying,
# the live-status constraint, AccountNotFound/AccountClosed, the legacy email
# fallback, partial-index semantics (#3916) — is covered against a migrated
# schema in set_customer_verification_sql_spec.rb. Deliberately NO
# Sequel-shaped dataset doubles here: mocking the query chain only re-states
# the implementation, so the db double below answers exactly one question —
# "was a transaction opened?"
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/set_customer_verification_spec.rb

require 'spec_helper'
require 'auth/database'
require 'auth/operations/set_customer_verification'

RSpec.describe Auth::Operations::SetCustomerVerification do
  # The op only touches scalar fields; the double exposes just those plus
  # the predicates the op consults.
  let(:customer) do
    double(
      'Customer',
      extid: 'ur_test_123',
      email: 'user@example.com',
      verified?: false,
      :verified= => nil,
      :verified_by= => nil,
      save: true,
    )
  end

  let(:db) { double('db', transaction: nil) }

  let(:auth_config) { double('AuthConfig', mode: 'simple') }

  before do
    allow(Onetime).to receive(:auth_config).and_return(auth_config)
  end

  describe 'idempotency' do
    it 'returns :no_change and writes nothing when already verified' do
      allow(customer).to receive(:verified?).and_return(true)

      op = described_class.new(
        customer: customer,
        verified: true,
        verified_by: 'cli_provision',
      )

      expect(op.call).to eq(:no_change)
      expect(customer).not_to have_received(:save)
    end

    it 'returns :no_change when already unverified' do
      allow(customer).to receive(:verified?).and_return(false)

      op = described_class.new(
        customer: customer,
        verified: false,
        verified_by: nil,
      )

      expect(op.call).to eq(:no_change)
      expect(customer).not_to have_received(:save)
    end

    it 'does not touch the SQL database when no-op even in full mode' do
      allow(auth_config).to receive(:mode).and_return('full')
      allow(customer).to receive(:verified?).and_return(true)

      op = described_class.new(
        customer: customer,
        verified: true,
        verified_by: 'cli_provision',
        db: db,
      )

      expect(op.call).to eq(:no_change)
      expect(db).not_to have_received(:transaction)
    end
  end

  describe 'simple auth mode' do
    it 'verifies: sets fields and saves to Redis, no SQL' do
      op = described_class.new(
        customer: customer,
        verified: true,
        verified_by: 'cli_provision',
        db: db,
      )

      expect(op.call).to eq(:success)
      expect(customer).to have_received(:verified=).with(true)
      expect(customer).to have_received(:verified_by=).with('cli_provision')
      expect(customer).to have_received(:save)
      expect(db).not_to have_received(:transaction)
    end

    it 'unverifies: clears verified_by to nil, saves, no SQL' do
      allow(customer).to receive(:verified?).and_return(true)

      op = described_class.new(
        customer: customer,
        verified: false,
        verified_by: nil,
        db: db,
      )

      expect(op.call).to eq(:success)
      expect(customer).to have_received(:verified=).with(false)
      expect(customer).to have_received(:verified_by=).with(nil)
      expect(db).not_to have_received(:transaction)
    end
  end

  describe 'full auth mode' do
    before { allow(auth_config).to receive(:mode).and_return('full') }

    it 'raises NoAuthDatabase when connection is nil; Redis untouched' do
      allow(Auth::Database).to receive(:connection).and_return(nil)

      op = described_class.new(
        customer: customer,
        verified: true,
        verified_by: 'cli_provision',
      )

      expect { op.call }.to raise_error(
        described_class::NoAuthDatabase,
        /unreachable/,
      )
      expect(customer).not_to have_received(:save)
    end

    it 'propagates SQL exceptions without touching Redis' do
      allow(db).to receive(:transaction).and_raise(Sequel::DatabaseError, 'boom')

      op = described_class.new(
        customer: customer,
        verified: true,
        verified_by: 'cli_provision',
        db: db,
      )

      expect { op.call }.to raise_error(Sequel::DatabaseError, 'boom')
      expect(customer).not_to have_received(:save)
    end
  end

  # Contract: caller (e.g., Rodauth after_verify_account hook) asserts
  # that the Rodauth side is already correct, so the op must skip its
  # own SQL update. This keeps the hook sync-path free of redundant
  # writes and avoids transaction nesting inside Rodauth's transaction.
  describe 'rodauth_already_synced: true' do
    before { allow(auth_config).to receive(:mode).and_return('full') }

    it 'skips the SQL update in full mode and only writes Redis' do
      op = described_class.new(
        customer: customer,
        verified: true,
        verified_by: 'email',
        rodauth_already_synced: true,
        db: db,
      )

      expect(op.call).to eq(:success)
      expect(db).not_to have_received(:transaction)
      expect(customer).to have_received(:save)
    end

    it 'does not require a db connection at all' do
      allow(Auth::Database).to receive(:connection).and_return(nil)

      op = described_class.new(
        customer: customer,
        verified: true,
        verified_by: 'email',
        rodauth_already_synced: true,
      )

      expect { op.call }.not_to raise_error
      expect(Auth::Database).not_to have_received(:connection)
    end

    it 'still respects idempotency' do
      allow(customer).to receive(:verified?).and_return(true)

      op = described_class.new(
        customer: customer,
        verified: true,
        verified_by: 'email',
        rodauth_already_synced: true,
      )

      expect(op.call).to eq(:no_change)
      expect(customer).not_to have_received(:save)
    end
  end
end
