# apps/web/auth/spec/operations/bind_sso_identity_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::BindSsoIdentity (#3840 Phase 4).
#
# The shared bind primitive: an idempotent, issuer-scoped insert of an SSO
# identity row for an already-PROVEN account. Covers every branch of the safe
# insert:
#   - fresh insert -> :ok
#   - pre-existing row, SAME account -> :ok (idempotent)
#   - pre-existing row, DIFFERENT account -> :conflict
#   - concurrent insert (UniqueConstraintViolation) re-read -> :ok / :conflict
#   - nil issuer coerced to the '' sentinel (issuer-scoped unique index, #3838)
#   - string/int account_id ownership comparison is coercion-safe
#
# The db is a Sequel-shaped double: db[:account_identities] exposes .where(...)
# (-> filtered dataset responding to #first) and #insert(...). No real DB — the
# end-to-end conflict path is already covered by
# spec/integration/full/omniauth_signin_interstitial_spec.rb.
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/bind_sso_identity_spec.rb

require 'spec_helper'
require 'auth/operations/bind_sso_identity'

RSpec.describe Auth::Operations::BindSsoIdentity do
  let(:account_id) { 5 }
  let(:provider)   { 'google' }
  let(:issuer)     { 'https://accounts.google.com' }
  let(:uid)        { 'sub-123' }
  let(:criteria)   { { provider: provider, issuer: issuer, uid: uid } }

  let(:identities) { double('identities_dataset') }
  let(:filtered)   { double('filtered_dataset') }
  let(:db)         { double('db') }

  before do
    allow(db).to receive(:[]).with(:account_identities).and_return(identities)
    allow(identities).to receive(:where).and_return(filtered)
    allow(identities).to receive(:insert)
  end

  # Invoke via the public class method with per-example overrides.
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
    before { allow(filtered).to receive(:first).and_return(nil) }

    it 'inserts the identity row and returns :ok' do
      expect(bind).to eq(:ok)

      expect(identities).to have_received(:insert)
        .with(hash_including(account_id: account_id, provider: provider, issuer: issuer, uid: uid))
    end

    it 'selects on the (provider, issuer, uid) criteria' do
      bind
      expect(identities).to have_received(:where).with(criteria)
    end
  end

  describe 'pre-existing row (idempotency guard)' do
    it 'returns :ok without inserting when the row belongs to the SAME account' do
      allow(filtered).to receive(:first).and_return({ account_id: account_id })

      expect(bind).to eq(:ok)
      expect(identities).not_to have_received(:insert)
    end

    it 'returns :conflict without inserting when the row belongs to a DIFFERENT account' do
      allow(filtered).to receive(:first).and_return({ account_id: 999 })

      expect(bind).to eq(:conflict)
      expect(identities).not_to have_received(:insert)
    end

    it 'compares account_id as strings (int row vs string caller)' do
      allow(filtered).to receive(:first).and_return({ account_id: 5 })

      expect(bind(account_id: '5')).to eq(:ok)
    end

    it 'compares account_id as strings (string row vs int caller)' do
      allow(filtered).to receive(:first).and_return({ account_id: '5' })

      expect(bind(account_id: 5)).to eq(:ok)
    end
  end

  describe 'concurrent insert (Sequel::UniqueConstraintViolation)' do
    before do
      # Pre-SELECT sees nothing; the insert loses the race; re-read finds the winner.
      allow(identities).to receive(:insert).and_raise(Sequel::UniqueConstraintViolation)
    end

    it 'returns :ok when the winning row belongs to the SAME account' do
      allow(filtered).to receive(:first).and_return(nil, { account_id: account_id })

      expect(bind).to eq(:ok)
    end

    it 'returns :conflict when the winning row belongs to a DIFFERENT account' do
      allow(filtered).to receive(:first).and_return(nil, { account_id: 999 })

      expect(bind).to eq(:conflict)
    end

    it 'returns :conflict when the winning row vanished before re-read' do
      allow(filtered).to receive(:first).and_return(nil, nil)

      expect(bind).to eq(:conflict)
    end
  end

  describe 'issuer sentinel coercion (#3838 issuer-scoped index)' do
    before { allow(filtered).to receive(:first).and_return(nil) }

    it 'coerces a nil issuer to the empty-string sentinel in both the SELECT and the INSERT' do
      bind(issuer: nil)

      expect(identities).to have_received(:where).with(hash_including(issuer: ''))
      expect(identities).to have_received(:insert).with(hash_including(issuer: ''))
    end
  end

  describe '.call parity' do
    before { allow(filtered).to receive(:first).and_return(nil) }

    it 'the class method returns the same result as an instance #call' do
      op = described_class.new(
        db: db, account_id: account_id, provider: provider, issuer: issuer, uid: uid,
      )
      expect(op.call).to eq(:ok)
    end
  end
end
