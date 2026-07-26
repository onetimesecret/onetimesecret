# apps/web/auth/spec/operations/set_customer_verification_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::SetCustomerVerification.
#
# Covers:
# - Idempotency when already in target state
# - Simple-mode verify/unverify (Redis only)
# - Full-mode verify/unverify (SQL update + Redis save)
# - Failure modes: no auth DB, no account row, closed account, SQL exception
# - SQL update keys on external_id, constrained to live statuses; legacy
#   NULL-external_id rows fall back to email + live statuses — never bare
#   email (#3916). Partial-index semantics are exercised for real in
#   set_customer_verification_sql_spec.rb.
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/set_customer_verification_spec.rb

require 'spec_helper'
require 'auth/database'
require 'auth/operations/set_customer_verification'

RSpec.describe Auth::Operations::SetCustomerVerification do
  # The op only touches scalar fields and the SQL accounts table; the
  # double exposes just those plus the predicates the op consults.
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

  # Sequel-shaped doubles, one per WHERE filter: the op resolves the row by
  # external_id, then updates by id constrained to live statuses (1, 2);
  # legacy rows (NULL external_id) go through the email fallback scope.
  let(:by_external_id) { double('by_external_id', get: 42) }
  let(:live_scope)     { double('live_scope', update: 1) }
  let(:by_id)          { double('by_id', where: live_scope) }
  let(:legacy_scope)   { double('legacy_scope', empty?: false, where: live_scope) }
  let(:accounts_dataset) do
    ds = double('accounts_dataset')
    allow(ds).to receive(:where) do |cond|
      if cond.key?(:id)       then by_id
      elsif cond.key?(:email) then legacy_scope
      else                         by_external_id
      end
    end
    ds
  end
  let(:db) do
    db_dbl = double('db', :[] => accounts_dataset)
    # Explicit block implementation: yields AND returns the block's value,
    # matching Sequel's transaction semantics (the op reads the returned
    # rowcount) without leaning on and_yield's return-value behavior.
    allow(db_dbl).to receive(:transaction) { |&blk| blk.call }
    db_dbl
  end

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

    it 'verifies: updates SQL status_id=2 then saves Redis' do
      op = described_class.new(
        customer: customer,
        verified: true,
        verified_by: 'cli_provision',
        db: db,
      )

      expect(op.call).to eq(:success)
      expect(db).to have_received(:transaction)
      expect(accounts_dataset).to have_received(:where).with(external_id: 'ur_test_123')
      expect(accounts_dataset).to have_received(:where).with(id: 42)
      expect(live_scope).to have_received(:update)
        .with(hash_including(status_id: 2))
      expect(customer).to have_received(:save)
    end

    it 'unverifies: updates SQL status_id=1 then saves Redis' do
      allow(customer).to receive(:verified?).and_return(true)

      op = described_class.new(
        customer: customer,
        verified: false,
        verified_by: nil,
        db: db,
      )

      expect(op.call).to eq(:success)
      expect(live_scope).to have_received(:update)
        .with(hash_including(status_id: 1))
    end

    it 'constrains the UPDATE to live statuses so a Closed row is never touched' do
      op = described_class.new(
        customer: customer,
        verified: true,
        verified_by: 'cli_provision',
        db: db,
      )

      op.call
      expect(by_id).to have_received(:where)
        .with(status_id: described_class::LIVE_STATUS_IDS)
    end

    it 'falls back to Auth::Database.connection when db: not injected' do
      allow(Auth::Database).to receive(:connection).and_return(db)

      op = described_class.new(
        customer: customer,
        verified: true,
        verified_by: 'cli_provision',
      )

      expect(op.call).to eq(:success)
      expect(Auth::Database).to have_received(:connection)
    end

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

    it 'raises AccountNotFound when no row matches by external_id or legacy email; Redis untouched' do
      allow(by_external_id).to receive(:get).and_return(nil)
      allow(legacy_scope).to receive(:empty?).and_return(true)

      op = described_class.new(
        customer: customer,
        verified: true,
        verified_by: 'cli_provision',
        db: db,
      )

      expect { op.call }.to raise_error(
        described_class::AccountNotFound,
        /ur_test_123/,
      )
      expect(customer).not_to have_received(:save)
    end

    it 'raises AccountClosed when the row exists but the live-status UPDATE hits 0 rows; Redis untouched' do
      allow(live_scope).to receive(:update).and_return(0)

      op = described_class.new(
        customer: customer,
        verified: true,
        verified_by: 'cli_provision',
        db: db,
      )

      expect { op.call }.to raise_error(
        described_class::AccountClosed,
        /ur_test_123/,
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

    it 'keys the SQL WHERE on external_id, never bare email (#3916)' do
      # A bare-email WHERE would sweep Closed rows sharing the address:
      # resurrection in the one-row case, a partial-unique-index violation
      # in the two-row case.
      op = described_class.new(
        customer: customer,
        verified: true,
        verified_by: 'cli_provision',
        db: db,
      )

      op.call
      expect(accounts_dataset).to have_received(:where).with(external_id: 'ur_test_123')
      expect(accounts_dataset).not_to have_received(:where).with(hash_including(:email))
    end

    it 'falls back to email + NULL external_id for legacy rows, never bare email' do
      allow(by_external_id).to receive(:get).and_return(nil)

      op = described_class.new(
        customer: customer,
        verified: true,
        verified_by: 'cli_provision',
        db: db,
      )

      expect(op.call).to eq(:success)
      expect(accounts_dataset).to have_received(:where)
        .with(email: 'user@example.com', external_id: nil)
      expect(legacy_scope).to have_received(:where)
        .with(status_id: described_class::LIVE_STATUS_IDS)
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
