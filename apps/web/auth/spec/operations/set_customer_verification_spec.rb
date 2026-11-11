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
require 'auth/database' # defines Auth::Database so the connection stubs below resolve
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

  # The verified_by vocabulary is defined once, on the model
  # (Onetime::Customer::VERIFIED_BY_VALUES), and refused HERE, in the
  # initializer, before any store is touched, so an unknown tag can never
  # reach Redis or SQL through this op.
  describe 'verified_by vocabulary' do
    it 'raises ArgumentError for an unknown tag with verified: true, before any write', :aggregate_failures do
      expect do
        described_class.new(
          customer: customer,
          verified: true,
          verified_by: 'made_up',
          db: db,
        )
      end.to raise_error(ArgumentError, /made_up/)

      expect(customer).not_to have_received(:save)
      expect(db).not_to have_received(:transaction)
    end

    it 'accepts every documented tag' do
      Onetime::Customer::VERIFIED_BY_VALUES.each do |tag|
        expect do
          described_class.new(customer: customer, verified: true, verified_by: tag, db: db)
        end.not_to raise_error
      end
    end

    it 'aliases the doctor constant to the same list' do
      require 'auth/operations/customers/doctor'

      expect(Auth::Operations::Customers::Doctor::VALID_VERIFIED_BY)
        .to equal(Onetime::Customer::VERIFIED_BY_VALUES)
    end

    it 'does not police verified_by when clearing verification' do
      expect do
        described_class.new(customer: customer, verified: false, verified_by: 'made_up', db: db)
      end.not_to raise_error
    end

    it 'allows nil provenance on verify (the pre-tag record shape the doctor backfills)' do
      expect do
        described_class.new(customer: customer, verified: true, verified_by: nil, db: db)
      end.not_to raise_error
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

  # The self-service email change: the account holder redeemed a link sent to
  # their new address, so the stored stamp described the old one.
  describe 'new_address: true' do
    it 'replaces a stored mailbox-proof stamp instead of keeping it' do
      allow(customer).to receive_messages(verified?: true, verified_by: 'colonel_admin', mailbox_verified?: true)

      op = described_class.new(customer: customer, verified: true, verified_by: 'email', new_address: true)

      expect(op.call).to eq(:success)
      expect(customer).to have_received(:verified_by=).with('email')
      expect(customer).to have_received(:save)
    end

    it 'writes even when the stored stamp is already email: it proved the old address' do
      allow(customer).to receive_messages(verified?: true, verified_by: 'email', mailbox_verified?: true)

      op = described_class.new(customer: customer, verified: true, verified_by: 'email', new_address: true)

      expect(op.call).to eq(:success)
      expect(customer).to have_received(:save)
    end

    it 'without it, the same call keeps the stored stamp and writes nothing' do
      allow(customer).to receive_messages(verified?: true, verified_by: 'colonel_admin', mailbox_verified?: true)

      op = described_class.new(customer: customer, verified: true, verified_by: 'email')

      expect(op.call).to eq(:no_change)
      expect(customer).not_to have_received(:save)
    end
  end

  # The self-service email change's stamp: an account an operator unverified
  # after the caller's read stays unverified. The SQL predicate is pinned in
  # set_customer_verification_sql_spec.rb; this is the Customer CAS outcome.
  describe 'stamp_only: true' do
    def stamp
      described_class.new(customer: customer, verified: true, verified_by: 'email',
        new_address: true, stamp_only: true, confirmed_email: 'user@example.com')
    end

    let(:redis) { double('Redis', eval: 1) }

    before do
      allow(customer).to receive_messages(verified?: true, verified_by: 'sso', dbclient: redis, dbkey: 'customer:123:object')
      allow(customer).to receive(:serialize_value) { |value| JSON.generate(value) }
    end

    it 'stamps only provenance with serialized address and verified predicates' do
      expect(stamp.call).to eq(:success)
      expect(redis).to have_received(:eval).with(
        described_class::STAMP_CONFIRMED_EMAIL,
        keys: ['customer:123:object'],
        argv: ['"user@example.com"', '"true"', '"email"'],
      )
      expect(customer).not_to have_received(:save)
    end

    it 'returns :not_verified when the atomic predicate finds an unverified Customer' do
      allow(redis).to receive(:eval).and_return(0)

      expect(stamp.call).to eq(:not_verified)
      expect(customer).not_to have_received(:verified=)
      expect(customer).not_to have_received(:save)
      expect(workspace_op).not_to have_received(:claim_pending_federation_for)
    end

    it 'returns :stale when the atomic predicate finds a different address or a missing Customer' do
      allow(redis).to receive(:eval).and_return(-1)

      expect(stamp.call).to eq(:stale)
      expect(customer).not_to have_received(:verified_by=)
      expect(customer).not_to have_received(:save)
      expect(workspace_op).not_to have_received(:claim_pending_federation_for)
    end

    it 'requires the address proved by the link, not merely the mutable Customer' do
      expect do
        described_class.new(customer: customer, verified: true, verified_by: 'email', stamp_only: true)
      end.to raise_error(ArgumentError, /confirmed_email/)
    end

    it 'refuses verified: false' do
      expect do
        described_class.new(customer: customer, verified: false, verified_by: nil, stamp_only: true)
      end.to raise_error(ArgumentError, /stamp_only/)
    end

    # The double above cannot show what the stamp does to the caller's
    # object, or read the bytes Familia stores: a real record can.
    context 'with a stored Customer', :datastore do
      let(:suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }

      before do
        allow(Onetime).to receive(:get_logger).and_call_original
        @record             = Onetime::Customer.create!(email: "stamp_only_#{suffix}@onetimesecret.com")
        @record.verified    = true
        @record.verified_by = 'sso'
        @record.save
      end

      after { @record&.destroy! }

      def stamp_record
        described_class.new(customer: @record, verified: true, verified_by: 'email',
          new_address: true, stamp_only: true, confirmed_email: @record.email).call
      end

      it "keeps the caller's unsaved assignments" do
        @record.locale = 'fr'

        expect(stamp_record).to eq(:success)
        expect(@record.locale).to eq('fr')
        expect(Onetime::Customer.load(@record.identifier).verified_by).to eq('email')
      end

      it 'returns :not_verified for a record unverified after the caller loaded it' do
        other             = Onetime::Customer.load(@record.identifier)
        other.verified    = false
        other.verified_by = nil
        other.save

        expect(stamp_record).to eq(:not_verified)
        expect(Onetime::Customer.load(@record.identifier).verified?).to be(false)
      end
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

  # #4754 review, F2: `bin/ots customers verify` ('cli_provision') and the
  # colonel admin ('colonel_admin') are the documented retry for a stranded
  # federation claim. Run on an account the Rodauth hook stamped 'email', they
  # used to rewrite that provenance to the operator's tag, with no record of
  # the original anywhere. Both tags are mailbox proof, so the move records no
  # new fact: the stored stamp is kept, and only the claim retry runs.
  describe 'a verification retry on an account that already has mailbox proof' do
    before do
      allow(customer).to receive_messages(verified?: true, verified_by: 'email', mailbox_verified?: true)
    end

    %w[cli_provision colonel_admin].each do |operator_tag|
      it "keeps the 'email' stamp when the operator re-verifies with #{operator_tag}" do
        op = described_class.new(customer: customer, verified: true, verified_by: operator_tag, db: db)

        expect(op.call).to eq(:no_change)
        expect(customer).not_to have_received(:verified_by=)
        expect(customer).not_to have_received(:verified=)
        expect(customer).not_to have_received(:save)
      end

      it "still runs the claim retry when re-verified with #{operator_tag}" do
        op = described_class.new(customer: customer, verified: true, verified_by: operator_tag, db: db)

        op.call

        expect(workspace_op).to have_received(:claim_pending_federation_for).with(customer, own_address_only: false)
        expect(op.federation_claimed?).to be(true)
      end
    end

    it 'does not touch the SQL row in full mode, like a same-stamp repeat' do
      allow(auth_config).to receive(:mode).and_return('full')

      op = described_class.new(customer: customer, verified: true, verified_by: 'cli_provision', db: db)

      expect(op.call).to eq(:no_change)
      expect(db).not_to have_received(:transaction)
    end

    it 'keeps an operator stamp when the Rodauth hook would stamp email' do
      allow(customer).to receive_messages(verified_by: 'cli_provision')

      op = described_class.new(
        customer: customer, verified: true, verified_by: 'email', rodauth_already_synced: true,
      )

      expect(op.call).to eq(:no_change)
      expect(customer).not_to have_received(:verified_by=)
    end

    # The stored tag is mailbox proof only together with verified? true
    # (Customer#mailbox_verified?). An unverified record carrying a stale
    # 'cli_provision' (the pre-#4735 CLI stamped it regardless) is a state
    # change and writes as before.
    it 'still writes when the record is unverified despite a stale mailbox tag' do
      allow(customer).to receive_messages(verified?: false, verified_by: 'cli_provision', mailbox_verified?: false)

      op = described_class.new(customer: customer, verified: true, verified_by: 'cli_provision', db: db)

      expect(op.call).to eq(:success)
      expect(customer).to have_received(:verified=).with(true)
      expect(customer).to have_received(:save)
    end

    it 'still upgrades an IdP-asserted stamp (sso -> cli_provision)' do
      allow(customer).to receive_messages(verified_by: 'sso', mailbox_verified?: false)

      op = described_class.new(customer: customer, verified: true, verified_by: 'cli_provision', db: db)

      expect(op.call).to eq(:success)
      expect(customer).to have_received(:verified_by=).with('cli_provision')
      expect(customer).to have_received(:save)
    end

    it 'still unverifies, clearing the provenance' do
      op = described_class.new(customer: customer, verified: false, verified_by: nil, db: db)

      expect(op.call).to eq(:success)
      expect(customer).to have_received(:verified=).with(false)
      expect(customer).to have_received(:verified_by=).with(nil)
      expect(customer).to have_received(:save)
    end
  end

  # Built without claim_own_address_only, as the Rodauth hook and the operator
  # verifications build it, the op asks for a claim that is not held to the
  # customer's own address; only .record_mailbox_proof (below) sets it.
  describe 'deferred federation re-claim' do
    it 'claims once the stamp gains mailbox proof (unverified -> email)' do
      # mailbox_verified? is read after the write, so it answers for the new stamp.
      allow(customer).to receive(:mailbox_verified?).and_return(true)

      described_class.new(customer: customer, verified: true, verified_by: 'email', db: db).call

      expect(workspace_op).to have_received(:claim_pending_federation_for).with(customer, own_address_only: false)
    end

    it 'claims when an operator upgrades an IdP-asserted stamp (sso -> cli_provision)' do
      allow(customer).to receive_messages(verified?: true, verified_by: 'sso')
      allow(customer).to receive(:mailbox_verified?).and_return(true)

      described_class.new(customer: customer, verified: true, verified_by: 'cli_provision', db: db).call

      expect(workspace_op).to have_received(:claim_pending_federation_for).with(customer, own_address_only: false)
    end

    it 'does not claim when the new provenance carries no mailbox proof (sso)' do
      allow(customer).to receive(:mailbox_verified?).and_return(false)

      described_class.new(customer: customer, verified: true, verified_by: 'sso', db: db).call

      expect(workspace_op).not_to have_received(:claim_pending_federation_for)
    end

    it 'retries the claim when one mailbox-proof stamp replaces another (colonel_admin -> cli_provision)' do
      allow(customer).to receive_messages(verified?: true, verified_by: 'colonel_admin', mailbox_verified?: true)

      described_class.new(customer: customer, verified: true, verified_by: 'cli_provision', db: db).call

      expect(workspace_op).to have_received(:claim_pending_federation_for).with(customer, own_address_only: false)
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
      expect(workspace_op).to have_received(:claim_pending_federation_for).with(customer, own_address_only: false)
    end

    # The symbol says :no_change because the verification state did not move;
    # the grant is the one effect such a call can have, so it is exposed
    # separately for the adapters that print and audit the call.
    it 'reports an applied claim on #federation_claimed? even when the verification was a :no_change' do
      allow(customer).to receive_messages(verified?: true, verified_by: 'cli_provision', mailbox_verified?: true)

      op = described_class.new(customer: customer, verified: true, verified_by: 'cli_provision', db: db)

      expect(op.call).to eq(:no_change)
      expect(op.federation_claimed?).to be(true)
    end

    it 'reports no claim when nothing was pending' do
      allow(customer).to receive_messages(verified?: false, verified_by: nil, mailbox_verified?: true)
      allow(workspace_op).to receive(:claim_pending_federation_for).and_return(false)

      op = described_class.new(customer: customer, verified: true, verified_by: 'email', db: db)

      expect(op.call).to eq(:success)
      expect(op.federation_claimed?).to be(false)
    end

    it 'reports no claim before #call and when the claim was never attempted' do
      allow(customer).to receive_messages(verified?: true, verified_by: 'sso', mailbox_verified?: false)

      op = described_class.new(customer: customer, verified: true, verified_by: 'sso', db: db)

      expect(op.federation_claimed?).to be(false)
      op.call
      expect(op.federation_claimed?).to be(false)
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
      expect(op.federation_claimed?).to be(false)
    end

    # Only .record_mailbox_proof declines it, for a link not on record as
    # sent to the customer's current address (#4754 review, round 3). The
    # stamp is written as before; the claim is not run on either path.
    context 'when the caller declines the claim (claim_pending_federation: false)' do
      it 'writes the stamp and runs no claim' do
        allow(customer).to receive(:mailbox_verified?).and_return(true)

        op = described_class.new(customer: customer, verified: true, verified_by: 'email', db: db,
          claim_pending_federation: false)

        expect(op.call).to eq(:success)
        expect(customer).to have_received(:verified_by=).with('email')
        expect(customer).to have_received(:save)
        expect(workspace_op).not_to have_received(:claim_pending_federation_for)
        expect(op.federation_claimed?).to be(false)
      end

      it 'runs no claim on a :no_change repeat either' do
        allow(customer).to receive_messages(verified?: true, verified_by: 'email', mailbox_verified?: true)

        op = described_class.new(customer: customer, verified: true, verified_by: 'email', db: db,
          claim_pending_federation: false)

        expect(op.call).to eq(:no_change)
        expect(workspace_op).not_to have_received(:claim_pending_federation_for)
      end
    end
  end

  # #4754 review, round 3: the simple-mode mailbox proof. The v1 and v2 secret
  # reveal logic redeem the emailed verification secret through this entry
  # point instead of stamping the Customer directly, so the deferred federation
  # claim runs for them too. The verification secret is minted only by
  # simple-mode flows but redeemed through routes that serve every mode, so a
  # link minted before a switch to full mode can still be followed; Rodauth
  # owns verification there, and the link records nothing. Nothing is rescued.
  # The claim runs only for a link on record as sent to the customer's current
  # address (Secret#delivered_to?), and is held to that address
  # (own_address_only: true); both checks run against real records in
  # ensure_default_workspace_federation_spec.rb.
  describe '.record_mailbox_proof' do
    let(:auth_logger) { double('AuthLogger', info: nil) }

    # The welcome link, sent to the customer's current address.
    let(:link) { double('Secret', delivered_to?: true, delivery_digest: 'digest-of-current-address') }

    before do
      allow(described_class).to receive(:auth_logger).and_return(auth_logger)
      allow(described_class).to receive(:new).and_call_original
      # A spy, never consulted in simple mode (no SQL there).
      allow(Auth::Database).to receive(:connection).and_return(db)
    end

    it 'stamps verified with the email provenance and runs the own-address claim, touching no SQL' do
      allow(customer).to receive(:mailbox_verified?).and_return(true)

      expect(described_class.record_mailbox_proof(customer, link)).to eq(:success)
      expect(link).to have_received(:delivered_to?).with('user@example.com')
      expect(described_class).to have_received(:new).with(
        customer: customer, verified: true, verified_by: 'email',
        claim_pending_federation: true, claim_own_address_only: true
      )
      expect(customer).to have_received(:verified=).with(true)
      expect(customer).to have_received(:verified_by=).with('email')
      expect(customer).to have_received(:save)
      expect(workspace_op).to have_received(:claim_pending_federation_for).with(customer, own_address_only: true)
      expect(Auth::Database).not_to have_received(:connection)
      expect(db).not_to have_received(:transaction)
      expect(auth_logger).not_to have_received(:info)
    end

    it 'keeps a stored mailbox-proof stamp on a repeat and still retries the claim' do
      allow(customer).to receive_messages(verified?: true, verified_by: 'colonel_admin', mailbox_verified?: true)

      expect(described_class.record_mailbox_proof(customer, link)).to eq(:no_change)
      expect(customer).not_to have_received(:verified_by=)
      expect(customer).not_to have_received(:save)
      expect(workspace_op).to have_received(:claim_pending_federation_for).with(customer, own_address_only: true)
    end

    it 'upgrades a stamp that is not mailbox proof' do
      allow(customer).to receive_messages(verified?: true, verified_by: 'stripe_payment', mailbox_verified?: false)

      expect(described_class.record_mailbox_proof(customer, link)).to eq(:success)
      expect(customer).to have_received(:verified_by=).with('email')
      expect(customer).to have_received(:save)
    end

    # Simple mode has nothing for it to rescue, so an error that escapes #call
    # reaches the reveal, as one from the direct stamp did.
    it 'propagates an unexpected error from #call' do
      allow(customer).to receive(:save).and_raise(Redis::CannotConnectError, 'valkey unavailable')

      expect { described_class.record_mailbox_proof(customer, link) }
        .to raise_error(Redis::CannotConnectError, 'valkey unavailable')
      expect(workspace_op).not_to have_received(:claim_pending_federation_for)
      expect(auth_logger).not_to have_received(:info)
    end

    # A link is tied to the account, not to an address. After an operator
    # email change it still reveals, but it proves only the mailbox it was
    # sent to, while the change pointed the default workspace at the new
    # address. It stamps as the direct stamp did and runs no claim, so the
    # new address's pending record stays where it was.
    context 'when the link is not on record as sent to the current address' do
      let(:link) { double('Secret', delivered_to?: false, delivery_digest: 'digest-of-earlier-address') }

      it 'stamps as before and runs no claim' do
        allow(customer).to receive(:mailbox_verified?).and_return(true)

        expect(described_class.record_mailbox_proof(customer, link)).to eq(:success)
        expect(described_class).to have_received(:new).with(
          customer: customer, verified: true, verified_by: 'email',
          claim_pending_federation: false, claim_own_address_only: true
        )
        expect(customer).to have_received(:verified_by=).with('email')
        expect(customer).to have_received(:save)
        expect(workspace_op).not_to have_received(:claim_pending_federation_for)
      end

      it 'runs no claim on the repeat an owner with mailbox proof reaches either' do
        allow(customer).to receive_messages(verified?: true, verified_by: 'email', mailbox_verified?: true)

        expect(described_class.record_mailbox_proof(customer, link)).to eq(:no_change)
        expect(workspace_op).not_to have_received(:claim_pending_federation_for)
      end

      it 'logs at info that the claim was withheld, and that a delivery address was recorded' do
        described_class.record_mailbox_proof(customer, link)

        expect(auth_logger).to have_received(:info).with(
          /not on record as sent to the account's current address; stamping without the federation claim/,
          { customer: 'ur_test_123', delivery_recorded: true },
        )
      end

      # Minted before the delivery address was recorded: nothing says which
      # mailbox it proves, so it is treated the same way.
      it 'treats a link that recorded no delivery address the same way' do
        unrecorded = double('Secret', delivered_to?: false, delivery_digest: nil)
        allow(customer).to receive(:mailbox_verified?).and_return(true)

        expect(described_class.record_mailbox_proof(customer, unrecorded)).to eq(:success)
        expect(workspace_op).not_to have_received(:claim_pending_federation_for)
        expect(auth_logger).to have_received(:info).with(
          /not on record as sent to the account's current address/,
          { customer: 'ur_test_123', delivery_recorded: false },
        )
      end
    end

    # The link was minted in simple mode and followed after the install
    # switched to full mode. Reconciling the accounts row from a reveal would
    # let an Unverified account that Rodauth blocks sign in; the old direct
    # stamp wrote Redis alone and left the row Unverified. So nothing at all.
    context 'when the install runs full auth mode' do
      # Any message to it fails the example: nothing may reach the database.
      let(:db) { double('db') }

      before { allow(auth_config).to receive(:mode).and_return('full') }

      it 'records nothing, builds no operation and touches no SQL' do
        expect(described_class.record_mailbox_proof(customer, link)).to be_nil

        expect(described_class).not_to have_received(:new)
        expect(Auth::Database).not_to have_received(:connection)
        expect(customer).not_to have_received(:verified=)
        expect(customer).not_to have_received(:verified_by=)
        expect(customer).not_to have_received(:save)
        expect(workspace_op).not_to have_received(:claim_pending_federation_for)
      end

      it 'logs at info that Rodauth owns verification there' do
        described_class.record_mailbox_proof(customer, link)

        expect(auth_logger).to have_received(:info).with(
          /redeemed in full auth mode; Rodauth owns account verification there/,
          { customer: 'ur_test_123' },
        )
      end
    end
  end
end
