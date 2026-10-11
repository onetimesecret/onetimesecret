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
# the live-status constraint, AccountNotFound/AccountClosed, the unlinked-row
# email fallback, partial-index semantics (#3916) — is covered against a migrated
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
      verified_by: nil,
      mailbox_verified?: false,
      :verified= => nil,
      :verified_by= => nil,
      save: true,
    )
  end

  # The deferred federation re-claim (#4735) reaches into EnsureDefaultWorkspace;
  # its own gate is covered in ensure_default_workspace_federation_spec.rb, so
  # here it is a seam: was it invoked, and only when the resulting stamp
  # carries mailbox proof? (Every such call, not just the first: a repeat
  # verification is the operator's retry for a claim that failed.)
  let(:workspace_op) { class_double('Auth::Operations::EnsureDefaultWorkspace', claim_pending_federation_for: true) }

  let(:db) { double('db', transaction: nil) }

  let(:auth_config) { double('AuthConfig', mode: 'simple') }

  before do
    allow(Onetime).to receive(:auth_config).and_return(auth_config)
    stub_const('Auth::Operations::EnsureDefaultWorkspace', workspace_op)
  end

  describe 'idempotency' do
    it 'returns :no_change and writes nothing when already verified' do
      allow(customer).to receive_messages(verified?: true, verified_by: 'cli_provision')

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
      allow(customer).to receive_messages(verified?: true, verified_by: 'cli_provision')

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
      allow(customer).to receive_messages(verified?: true, verified_by: 'email')

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

  # #4735: an account verified on an IdP's say-so (verified_by: 'sso') is
  # Verified in Rodauth, so verify_account never runs for it. Rewriting the
  # provenance through this op is the ONLY way it acquires mailbox proof, which
  # is what has_system_role? and the federation claim gate on.
  describe 'provenance-only change (verified stays true)' do
    before do
      allow(customer).to receive_messages(verified?: true, verified_by: 'sso', mailbox_verified?: false)
    end

    it 'is not a no-op: rewrites verified_by and saves' do
      op = described_class.new(customer: customer, verified: true, verified_by: 'cli_provision', db: db)

      expect(op.call).to eq(:success)
      expect(customer).to have_received(:verified_by=).with('cli_provision')
      expect(customer).to have_received(:save)
    end

    # The accounts row is EXPECTED to be Verified already, but it is reconciled
    # rather than assumed: an earlier unverify can have committed SQL and then
    # failed the Redis save, leaving Redis reading verified/'sso' while the row
    # is Unverified. A provenance-only verify that skipped SQL would then report
    # :success with Rodauth still refusing the login (#4735 review).
    it 'reconciles the SQL row in full mode rather than assuming it is Verified' do
      allow(auth_config).to receive(:mode).and_return('full')
      allow(db).to receive(:transaction).and_return(1)

      op = described_class.new(customer: customer, verified: true, verified_by: 'cli_provision', db: db)

      expect(op.call).to eq(:success)
      expect(db).to have_received(:transaction)
      expect(customer).to have_received(:save)
    end

    it 'skips SQL only on the explicit rodauth_already_synced guarantee' do
      allow(auth_config).to receive(:mode).and_return('full')

      op = described_class.new(
        customer: customer, verified: true, verified_by: 'cli_provision', rodauth_already_synced: true, db: db,
      )

      expect(op.call).to eq(:success)
      expect(db).not_to have_received(:transaction)
    end

    it 'treats the same provenance as a no-op' do
      op = described_class.new(customer: customer, verified: true, verified_by: 'sso', db: db)

      expect(op.call).to eq(:no_change)
      expect(customer).not_to have_received(:save)
    end
  end

  describe 'deferred federation re-claim' do
    it 'claims once the stamp gains mailbox proof (unverified -> email)' do
      # mailbox_verified? is read after the write, so it answers for the new stamp.
      allow(customer).to receive(:mailbox_verified?).and_return(true)

      described_class.new(customer: customer, verified: true, verified_by: 'email', db: db).call

      expect(workspace_op).to have_received(:claim_pending_federation_for).with(customer)
    end

    it 'claims when an operator upgrades an IdP-asserted stamp (sso -> cli_provision)' do
      allow(customer).to receive_messages(verified?: true, verified_by: 'sso')
      allow(customer).to receive(:mailbox_verified?).and_return(true)

      described_class.new(customer: customer, verified: true, verified_by: 'cli_provision', db: db).call

      expect(workspace_op).to have_received(:claim_pending_federation_for).with(customer)
    end

    it 'does not claim when the new provenance carries no mailbox proof (sso)' do
      allow(customer).to receive(:mailbox_verified?).and_return(false)

      described_class.new(customer: customer, verified: true, verified_by: 'sso', db: db).call

      expect(workspace_op).not_to have_received(:claim_pending_federation_for)
    end

    it 'retries the claim when one mailbox-proof stamp replaces another (colonel_admin -> cli_provision)' do
      allow(customer).to receive_messages(verified?: true, verified_by: 'colonel_admin', mailbox_verified?: true)

      described_class.new(customer: customer, verified: true, verified_by: 'cli_provision', db: db).call

      expect(workspace_op).to have_received(:claim_pending_federation_for).with(customer)
    end

    it 'retries the claim on a :no_change verification that already carries mailbox proof' do
      # The claim is swallowed on failure (never undoes the verification), so a
      # transient Redis/billing error would otherwise strand the benefit: the
      # Rodauth hook fires once and the workspace already exists. Repeating
      # `customers verify` is the retry, and it writes nothing.
      allow(customer).to receive_messages(verified?: true, verified_by: 'cli_provision', mailbox_verified?: true)

      op = described_class.new(customer: customer, verified: true, verified_by: 'cli_provision', db: db)

      expect(op.call).to eq(:no_change)
      expect(customer).not_to have_received(:save)
      expect(workspace_op).to have_received(:claim_pending_federation_for).with(customer)
    end

    it 'does not claim on a :no_change verification without mailbox proof (sso -> sso)' do
      allow(customer).to receive_messages(verified?: true, verified_by: 'sso', mailbox_verified?: false)

      op = described_class.new(customer: customer, verified: true, verified_by: 'sso', db: db)

      expect(op.call).to eq(:no_change)
      expect(workspace_op).not_to have_received(:claim_pending_federation_for)
    end

    it 'does not claim on unverify' do
      allow(customer).to receive_messages(verified?: true, verified_by: 'email', mailbox_verified?: true)

      described_class.new(customer: customer, verified: false, verified_by: nil, db: db).call

      expect(workspace_op).not_to have_received(:claim_pending_federation_for)
    end

    it 'never lets a claim failure undo the verification' do
      allow(customer).to receive(:mailbox_verified?).and_return(true)
      allow(workspace_op).to receive(:claim_pending_federation_for).and_raise(RuntimeError, 'boom')
      allow(Onetime::ErrorHandler).to receive(:safe_execute).and_call_original

      op = described_class.new(customer: customer, verified: true, verified_by: 'email', db: db)

      expect(op.call).to eq(:success)
      expect(customer).to have_received(:save)
    end
  end
end
