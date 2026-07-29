# apps/web/auth/spec/operations/bind_sso_identity_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::BindSsoIdentity (#3840 Phase 4).
#
# The shared bind primitive: an idempotent, issuer-scoped insert of an SSO
# identity row for an already-PROVEN account.
#
# These run against a REAL in-memory SQLite account_identities table carrying the
# REAL (provider, issuer, uid) unique index — RodauthTestHelper.create_test_database
# mirrors migration 008 (see apps/web/auth/spec/spec_helper.rb), the same schema
# the config-feature specs build on. That matters: the two guarantees this
# primitive exists to provide can only be shown against a real index, not a
# stubbed dataset —
#   - the '' issuer SENTINEL actually collapses `nil` and '' onto ONE index slot
#     (#3838 — a NULL vs '' split would silently defeat issuer-scoping), and
#   - ownership actually HOLDS: a duplicate (provider, issuer, uid) is rejected by
#     the index, so :conflict is a real decision about a real row, never a branch
#     that only fires because a double was told to return it.
# The one exception is the concurrent-insert rescue: the SELECT-then-INSERT race
# window can't be produced single-threaded, so ONLY the pre-SELECT "miss" is
# simulated — the UniqueConstraintViolation and the ownership re-read both hit the
# real DB.
#
# The end-to-end HTTP path (challenge -> password proof -> bind) lives in
# spec/integration/full/omniauth_signin_interstitial_spec.rb; this file locks the
# primitive's decision table in isolation.
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/bind_sso_identity_spec.rb

require_relative '../spec_helper'
require 'auth/operations/bind_sso_identity'

RSpec.describe Auth::Operations::BindSsoIdentity do
  # Fresh real DB per example (in-memory SQLite) -> perfect isolation, no cleanup.
  let(:db)         { create_test_database }
  let(:identities) { db[:account_identities] }

  let(:provider) { 'google' }
  let(:issuer)   { 'https://accounts.google.com' }
  let(:uid)      { 'sub-123' }
  let(:criteria) { { provider: provider, issuer: issuer, uid: uid } }

  # The account we authenticate as (seeded lazily the first time it's referenced).
  let(:account_id) { seed_account(5) }

  # account_identities.account_id is a NOT NULL foreign key -> accounts(id), and
  # Sequel enables SQLite foreign_keys by default, so every account referenced by
  # an inserted identity row must exist first.
  def seed_account(id)
    db[:accounts].insert(
      id: id, email: "acct-#{id}@example.com", status_id: AuthTestConstants::STATUS_VERIFIED,
    )
    id
  end

  def bind(**overrides)
    described_class.call(
      db: db,
      account_id: overrides.fetch(:account_id, account_id),
      provider: overrides.fetch(:provider, provider),
      issuer: overrides.fetch(:issuer, issuer),
      uid: overrides.fetch(:uid, uid),
    )
  end

  describe 'fresh insert' do
    it 'inserts the identity row on the proven account and returns :ok' do
      expect(bind).to eq(:ok)

      rows = identities.where(criteria).all
      expect(rows.size).to eq(1)
      expect(rows.first).to include(
        account_id: account_id, provider: provider, issuer: issuer, uid: uid,
      )
    end
  end

  describe 'idempotency guard' do
    it 'returns :ok without a duplicate when the row already belongs to the SAME account' do
      identities.insert(criteria.merge(account_id: account_id))

      expect(bind).to eq(:ok)
      expect(identities.where(criteria).count).to eq(1)
    end

    it 'returns :conflict and binds nothing when the row belongs to a DIFFERENT account' do
      other = seed_account(999)
      identities.insert(criteria.merge(account_id: other))

      expect(bind).to eq(:conflict)

      # The single existing row is untouched — nothing was bound onto our account.
      rows = identities.where(criteria).all
      expect(rows.size).to eq(1)
      expect(rows.first[:account_id]).to eq(other)
    end

    it 'matches a STRING caller account_id against the INTEGER DB row (:ok)' do
      # rodauth.account_id is an Integer, but the primitive was extracted for the
      # #3877 / 4.B callers that bind from OUTSIDE a Rodauth request with a
      # Redis-sourced STRING account_id. The column is Bignum, so the row always
      # reads back Integer -> the op coerces both sides to compare cleanly. The
      # reverse (a String-typed DB row) is not a shape a Bignum column can yield,
      # so it is intentionally not exercised here.
      identities.insert(criteria.merge(account_id: account_id)) # account_id == 5 (Integer)

      expect(bind(account_id: account_id.to_s)).to eq(:ok)
    end
  end

  describe 'issuer sentinel (#3838 issuer-scoped unique index)' do
    it 'persists a nil issuer as the empty-string sentinel (never NULL)' do
      expect(bind(issuer: nil)).to eq(:ok)

      row = identities.where(provider: provider, uid: uid).first
      expect(row[:issuer]).to eq('')
    end

    it 'collapses nil and "" onto the SAME index slot: a different account conflicts' do
      other = seed_account(999)
      # Another account already holds the row under the EXPLICIT '' sentinel...
      identities.insert(provider: provider, issuer: '', uid: uid, account_id: other)

      # ...so a nil-issuer bind for our account resolves to the SAME
      # (provider, '', uid) row and is refused. If nil did not coerce to '' this
      # would insert a second, index-splitting row instead — the #3838 regression.
      expect(bind(issuer: nil)).to eq(:conflict)
      expect(identities.where(provider: provider, uid: uid).count).to eq(1)
    end
  end

  describe 'the (provider, issuer, uid) unique index the op depends on' do
    it 'really rejects a duplicate insert with Sequel::UniqueConstraintViolation' do
      identities.insert(criteria.merge(account_id: account_id))
      other = seed_account(999)

      # This is the DB fact the concurrent-insert rescue below is built on; assert
      # it directly rather than fake it with allow(insert).to raise.
      expect { identities.insert(criteria.merge(account_id: other)) }
        .to raise_error(Sequel::UniqueConstraintViolation)
    end
  end

  describe 'concurrent insert loses the race (Sequel::UniqueConstraintViolation rescue)' do
    # Drive the op with only its pre-SELECT forced to miss — i.e. our SELECT ran
    # in the window before the winning insert committed. The insert then hits the
    # REAL index and raises a REAL UniqueConstraintViolation, and the rescue
    # re-reads the REAL winning row to decide ownership. `on_reread` lets a test
    # mutate the table just before the re-read (to model the winner vanishing).
    def bind_losing_the_preselect(account_id:, on_reread: nil)
      op    = described_class.new(
        db: db, account_id: account_id, provider: provider, issuer: issuer, uid: uid,
      )
      calls = 0
      allow(op).to receive(:dataset).and_wrap_original do |orig|
        calls += 1
        if calls == 1
          # pre-SELECT: the winner hasn't "committed" yet from our vantage point.
          instance_double(Sequel::Dataset, where: instance_double(Sequel::Dataset, first: nil))
        else
          on_reread.call if calls == 3 && on_reread # re-read is the 3rd dataset use
          orig.call # real dataset: insert (2nd) raises, re-read (3rd) reads the winner
        end
      end
      op.call
    end

    it 'returns :conflict when the winning row belongs to a DIFFERENT account' do
      other = seed_account(999)
      identities.insert(criteria.merge(account_id: other))

      expect(bind_losing_the_preselect(account_id: account_id)).to eq(:conflict)
    end

    it 'returns :ok when the winning row belongs to the SAME account (idempotent)' do
      identities.insert(criteria.merge(account_id: account_id))

      expect(bind_losing_the_preselect(account_id: account_id)).to eq(:ok)
    end

    it 'returns :conflict when the winner vanishes before the re-read (defensive nil guard)' do
      other = seed_account(999)
      identities.insert(criteria.merge(account_id: other))

      # Delete the winning row between the raise and the re-read -> re-read finds
      # nothing, which owned_or_conflict must treat as :conflict, never :ok.
      vanish = -> { identities.where(criteria).delete }
      expect(bind_losing_the_preselect(account_id: account_id, on_reread: vanish)).to eq(:conflict)
    end
  end

  describe '.call parity with #call' do
    it 'the class method delegates to an instance #call (same real bind, same result)' do
      op = described_class.new(
        db: db, account_id: account_id, provider: provider, issuer: issuer, uid: uid,
      )
      expect(op.call).to eq(:ok)

      # Class form over the SAME criteria now hits the row the instance just bound
      # -> idempotent :ok, still exactly one row.
      expect(bind).to eq(:ok)
      expect(identities.where(criteria).count).to eq(1)
    end
  end
end
