# apps/web/auth/spec/operations/deferred_sso_bind_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::DeferredSsoBind (#3877 / #3840 Phase 4.A).
#
# The MFA hand-off for the interstitial's identity bind: `.defer` stashes an
# ALREADY-AUTHORIZED (password-proven) bind into the partial MFA session, and
# `.complete` — called from after_two_factor_authentication — consumes it and
# performs the bind via the shared BindSsoIdentity primitive.
#
# Like bind_sso_identity_spec.rb, these run against a REAL in-memory SQLite
# account_identities table carrying the REAL (provider, issuer, uid) unique
# index (RodauthTestHelper.create_test_database), because the decisions under
# test — did a row land, on WHOSE account, exactly once — are DB facts.
#
# What this file locks in:
#   - the session contract: the stash round-trips the JSON serialization the
#     Redis session blob applies between the login request and the MFA-verify
#     request (lib/onetime/session.rb) — symbol keys would NOT survive that,
#     so the payload must be string-keyed;
#   - SINGLE-USE: the stash is consumed up front, on EVERY outcome — including
#     when the underlying insert raises — so no path leaves a retryable
#     pending bind behind;
#   - ACCOUNT-BOUND: a stash snapshotted for one account never binds onto a
#     different authenticated account (:mismatch, audit-and-skip);
#   - :conflict passthrough: a (provider, issuer, uid) row owned by another
#     account is never bound over and never reported as success.
#
# The end-to-end MFA path (interstitial -> mfa_required -> OTP -> bound row)
# needs an AUTH_MFA_ENABLED integration harness — tracked in #3877 alongside
# the pending example in integration/full/omniauth_signin_interstitial_spec.rb.
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/deferred_sso_bind_spec.rb

require 'json'
require_relative '../spec_helper'
require 'auth/operations/deferred_sso_bind'

RSpec.describe Auth::Operations::DeferredSsoBind do
  # Fresh real DB per example (in-memory SQLite) -> perfect isolation, no cleanup.
  let(:db)         { create_test_database }
  let(:identities) { db[:account_identities] }

  let(:provider) { 'oidc' }
  let(:issuer)   { 'https://issuer.example.com' }
  let(:uid)      { 'sub-123' }
  let(:criteria) { { provider: provider, issuer: issuer, uid: uid } }

  # Quiet logger accepting the (message, **fields) call shape of Onetime loggers
  # (stdlib Logger would reject the keyword fields).
  let(:logger) { double('logger', info: nil, warn: nil) }

  let(:account_id) { seed_account(5) }

  # account_identities.account_id is a NOT NULL foreign key -> accounts(id).
  def seed_account(id)
    db[:accounts].insert(
      id: id, email: "acct-#{id}@example.com", status_id: AuthTestConstants::STATUS_VERIFIED,
    )
    id
  end

  # A session as the interstitial leaves it: `.defer` writes the stash the same
  # way the rodauth.login block does.
  def deferred_session(for_account: account_id)
    session = {}
    described_class.defer(
      session: session, account_id: for_account, provider: provider, issuer: issuer, uid: uid,
    )
    session
  end

  def complete(session, as_account: account_id)
    described_class.complete(db: db, session: session, account_id: as_account, logger: logger)
  end

  describe '.defer' do
    it 'stashes a fully STRING-keyed, string-valued payload under SESSION_KEY' do
      session = deferred_session

      expect(session).to eq(
        described_class::SESSION_KEY => {
          'account_id' => account_id.to_s,
          'provider'   => provider,
          'issuer'     => issuer,
          'uid'        => uid,
        },
      )
    end

    it 'coerces a nil issuer to the empty-string sentinel expected by the unique index' do
      session = {}
      described_class.defer(
        session: session, account_id: account_id, provider: provider, issuer: nil, uid: uid,
      )
      expect(session[described_class::SESSION_KEY]['issuer']).to eq('')
    end
  end

  describe '.complete on the happy path' do
    it 'binds the identity onto the stashed account, consumes the stash, and returns :ok' do
      session = deferred_session

      expect(complete(session)).to eq(:ok)

      rows = identities.where(criteria).all
      expect(rows.size).to eq(1)
      expect(rows.first[:account_id]).to eq(account_id)

      # SINGLE-USE: the stash is gone — a second completion is a no-op.
      expect(session).not_to have_key(described_class::SESSION_KEY)
      expect(complete(session)).to eq(:none)
      expect(identities.where(criteria).count).to eq(1)
    end

    it 'survives the JSON round-trip the Redis session blob applies between requests' do
      # The stash is written during the login request but read during the LATER
      # MFA-verify request, after lib/onetime/session.rb has JSON-serialized the
      # session into Redis and parsed it back. Symbol keys would come back as
      # strings, so the contract is string keys throughout — locked in here.
      session = JSON.parse(JSON.generate(deferred_session))

      expect(complete(session)).to eq(:ok)
      expect(identities.where(criteria).first[:account_id]).to eq(account_id)
    end

    it 'returns :ok idempotently when the row already belongs to the same account' do
      identities.insert(criteria.merge(account_id: account_id))

      expect(complete(deferred_session)).to eq(:ok)
      expect(identities.where(criteria).count).to eq(1)
    end
  end

  describe '.complete with no stash (every non-interstitial login)' do
    it 'returns :none and touches neither the session nor the database' do
      session = { 'awaiting_mfa' => false, 'account_id' => account_id }

      expect(complete(session)).to eq(:none)
      expect(session).to eq('awaiting_mfa' => false, 'account_id' => account_id)
      expect(identities.count).to eq(0)
    end
  end

  describe '.complete with a mismatched account (:mismatch, audit-and-skip)' do
    it 'refuses to bind when the authenticated account differs from the stash snapshot' do
      other   = seed_account(999)
      session = deferred_session # stash snapshots account_id (5)

      expect(complete(session, as_account: other)).to eq(:mismatch)

      # Nothing bound onto EITHER account, and the stash is still consumed —
      # a mismatch must not leave a retryable pending bind behind.
      expect(identities.count).to eq(0)
      expect(session).not_to have_key(described_class::SESSION_KEY)
    end
  end

  describe '.complete when the identity belongs to another account (:conflict, audit-and-skip)' do
    it 'binds nothing over the existing owner and consumes the stash' do
      other = seed_account(999)
      identities.insert(criteria.merge(account_id: other))
      session = deferred_session

      expect(complete(session)).to eq(:conflict)

      rows = identities.where(criteria).all
      expect(rows.size).to eq(1)
      expect(rows.first[:account_id]).to eq(other)
      expect(session).not_to have_key(described_class::SESSION_KEY)
    end
  end

  describe '.complete with a malformed stash' do
    it 'discards a non-hash payload (:none) and still consumes the key' do
      session = { described_class::SESSION_KEY => 'not-a-hash' }

      expect(complete(session)).to eq(:none)
      expect(session).not_to have_key(described_class::SESSION_KEY)
      expect(identities.count).to eq(0)
    end

    it 'discards a payload missing part of the bind tuple (:none)' do
      session = deferred_session
      session[described_class::SESSION_KEY].delete('uid')

      expect(complete(session)).to eq(:none)
      expect(identities.count).to eq(0)
    end
  end

  describe 'single-use holds even when the bind raises' do
    it 'consumes the stash BEFORE attempting the insert, so an error cannot leave a retry behind' do
      session = deferred_session
      allow(Auth::Operations::BindSsoIdentity).to receive(:call)
        .and_raise(Sequel::DatabaseError, 'boom')

      # The error propagates (the hook wraps completion in ErrorHandler.safe_execute),
      # but the stash is already gone.
      expect { complete(session) }.to raise_error(Sequel::DatabaseError)
      expect(session).not_to have_key(described_class::SESSION_KEY)
    end
  end
end
