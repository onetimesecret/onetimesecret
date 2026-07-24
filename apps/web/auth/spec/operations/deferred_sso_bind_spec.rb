# apps/web/auth/spec/operations/deferred_sso_bind_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::DeferredSsoBind (#3877 / #3840 Phase 4.A,
# storage moved to SessionSidecar in #3858).
#
# The MFA hand-off for the interstitial's identity bind: `.defer` stashes an
# ALREADY-AUTHORIZED (password-proven) bind as a short-TTL, sid-bound
# SessionSidecar key, and `.complete` — called from
# after_two_factor_authentication — consumes it (atomic GETDEL at the store)
# and performs the bind via the shared BindSsoIdentity primitive.
#
# Like bind_sso_identity_spec.rb, these run against a REAL in-memory SQLite
# account_identities table carrying the REAL (provider, issuer, uid) unique
# index (RodauthTestHelper.create_test_database), because the decisions under
# test — did a row land, on WHOSE account, exactly once — are DB facts. The
# Redis side is a minimal in-memory stand-in implementing exactly the commands
# SessionSidecar issues (SET+EX / GET / GETDEL / DEL / TTL), paired with a
# REAL SessionCodec so the encrypted, sid/field-bound envelope is genuine —
# the GETDEL-vs-concurrency guarantee itself is locked in by the sidecar's
# own tryouts against real Valkey (try/unit/session/sidecar_try.rb).
#
# What this file locks in:
#   - the storage contract: the stash is an ENCRYPTED sidecar envelope under
#     sidecar:<sid>:link_sso_pending_bind, sid/field-bound, string-keyed
#     payload, TTL clamped to the registered 900s MFA window;
#   - SINGLE-USE: the stash is consumed up front, on EVERY outcome — including
#     when the underlying insert raises — so no path leaves a retryable
#     pending bind behind;
#   - ACCOUNT-BOUND: a stash snapshotted for one account never binds onto a
#     different authenticated account (:mismatch, audit-and-skip);
#   - SID-BOUND: a stash value replayed under another sid decodes as absent
#     (:none) — one session's pending bind can never complete under another;
#   - BEST-EFFORT defer: a storage failure returns false instead of raising,
#     so it can never abort a login whose password already verified;
#   - :conflict passthrough: a (provider, issuer, uid) row owned by another
#     account is never bound over and never reported as success.
#
# The end-to-end MFA path (interstitial -> mfa_required -> OTP -> bound row)
# is covered by integration/full_mfa/omniauth_signin_interstitial_mfa_spec.rb.
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/deferred_sso_bind_spec.rb

require 'json'
require 'securerandom'
require_relative '../spec_helper'
require 'onetime/session/sidecar'
require 'auth/operations/deferred_sso_bind'

RSpec.describe Auth::Operations::DeferredSsoBind do
  # Minimal in-memory stand-in for the sidecar's Redis surface. Implements
  # only what SessionSidecar issues: SET+EX, GET, GETDEL (the atomic consume),
  # DEL, TTL. TTLs are recorded, not enforced — expiry semantics live in the
  # sidecar tryouts against real Valkey.
  class FakeSidecarRedis
    def initialize
      @data = {}
      @ttls = {}
    end

    def set(key, value, ex: nil)
      @data[key] = value
      @ttls[key] = ex
      'OK'
    end

    def get(key)
      @data[key]
    end

    def getdel(key)
      @ttls.delete(key)
      @data.delete(key)
    end

    def del(*keys)
      keys.count { |key| !@data.delete(key).nil? }
    end

    def ttl(key)
      return -2 unless @data.key?(key)

      @ttls[key] || -1
    end

    def exists(*keys)
      keys.count { |key| @data.key?(key) }
    end
  end

  # Fresh real DB per example (in-memory SQLite) -> perfect isolation, no cleanup.
  let(:db)         { create_test_database }
  let(:identities) { db[:account_identities] }

  let(:redis) { FakeSidecarRedis.new }
  let(:codec) { Onetime::SessionCodec.new('deferred-sso-bind-spec-secret') }
  let(:sid)   { SecureRandom.hex(32) } # 64 hex chars, matches the sidecar SID_FORMAT
  let(:key)   { Onetime::SessionSidecar.key_for(sid, described_class::FIELD) }

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

  before do
    # A live session blob for the sid: the sidecar clamps every write against
    # the blob's remaining TTL so a stash can never outlive the session.
    redis.set("session:#{sid}", 'blob', ex: 86_400)
  end

  # Stash a pending bind the same way the interstitial's rodauth.login block does.
  def defer(for_account: account_id, for_sid: sid, issuer_value: issuer)
    described_class.defer(
      sid: for_sid, account_id: for_account, provider: provider, issuer: issuer_value, uid: uid,
      dbclient: redis, codec: codec, logger: logger,
    )
  end

  def complete(as_account: account_id, for_sid: sid)
    described_class.complete(
      db: db, sid: for_sid, account_id: as_account,
      dbclient: redis, codec: codec, logger: logger,
    )
  end

  describe '.defer' do
    it 'stores an encrypted, sid/field-bound envelope around the STRING-keyed bind tuple' do
      expect(defer).to be(true)

      raw = redis.get(key)
      expect(raw).not_to be_nil

      envelope = codec.decode(raw)
      expect(envelope['sid']).to eq(sid)
      expect(envelope['f']).to eq(described_class::FIELD)
      expect(envelope['v']).to eq(
        'account_id' => account_id.to_s,
        'provider'   => provider,
        'issuer'     => issuer,
        'uid'        => uid,
      )
    end

    it 'clamps the key TTL to the registered 900s MFA completion window' do
      defer

      expect(redis.ttl(key)).to be_between(1, 900)
    end

    it 'coerces a nil issuer to the empty-string sentinel expected by the unique index' do
      defer(issuer_value: nil)

      expect(codec.decode(redis.get(key))['v']['issuer']).to eq('')
    end

    it 'returns false (and writes nothing) when no usable sid is available' do
      expect(defer(for_sid: nil)).to be(false)
      expect(logger).to have_received(:warn)
    end

    it 'is BEST-EFFORT: a storage failure returns false instead of raising' do
      # The defer runs inside the rodauth.login block of a login whose password
      # already verified — a Redis outage must not abort that login. Fail-closed:
      # no stash simply means no bind.
      allow(redis).to receive(:set).and_raise(StandardError, 'redis connection refused')

      expect(defer).to be(false)
      expect(logger).to have_received(:warn)
    end
  end

  describe '.complete on the happy path' do
    it 'binds the identity onto the stashed account, consumes the stash, and returns :ok' do
      defer

      expect(complete).to eq(:ok)

      rows = identities.where(criteria).all
      expect(rows.size).to eq(1)
      expect(rows.first[:account_id]).to eq(account_id)

      # SINGLE-USE: the sidecar key is gone — a second completion is a no-op.
      expect(redis.get(key)).to be_nil
      expect(complete).to eq(:none)
      expect(identities.where(criteria).count).to eq(1)
    end

    it 'returns :ok idempotently when the row already belongs to the same account' do
      identities.insert(criteria.merge(account_id: account_id))
      defer

      expect(complete).to eq(:ok)
      expect(identities.where(criteria).count).to eq(1)
    end
  end

  describe '.complete with no stash (every non-interstitial login)' do
    it 'returns :none and touches the database not at all' do
      expect(complete).to eq(:none)
      expect(identities.count).to eq(0)
    end

    it 'returns :none when no usable sid is available' do
      expect(complete(for_sid: nil)).to eq(:none)
      expect(identities.count).to eq(0)
    end
  end

  describe '.complete with a mismatched account (:mismatch, audit-and-skip)' do
    it 'refuses to bind when the authenticated account differs from the stash snapshot' do
      other = seed_account(999)
      defer # stash snapshots account_id (5)

      expect(complete(as_account: other)).to eq(:mismatch)

      # Nothing bound onto EITHER account, and the stash is still consumed —
      # a mismatch must not leave a retryable pending bind behind.
      expect(identities.count).to eq(0)
      expect(redis.get(key)).to be_nil
    end
  end

  describe '.complete when the identity belongs to another account (:conflict, audit-and-skip)' do
    it 'binds nothing over the existing owner and consumes the stash' do
      other = seed_account(999)
      identities.insert(criteria.merge(account_id: other))
      defer

      expect(complete).to eq(:conflict)

      rows = identities.where(criteria).all
      expect(rows.size).to eq(1)
      expect(rows.first[:account_id]).to eq(other)
      expect(redis.get(key)).to be_nil
    end
  end

  describe '.complete is SID-BOUND (the envelope binding, not just the key name)' do
    it 'refuses a stash value replayed under another sid, and still spends the planted key' do
      other_sid = SecureRandom.hex(32)
      redis.set("session:#{other_sid}", 'blob', ex: 86_400)
      defer

      # A Redis-writing attacker copies one session's pending bind under
      # another sid. The envelope's sid binding makes it decode as absent.
      planted = Onetime::SessionSidecar.key_for(other_sid, described_class::FIELD)
      redis.set(planted, redis.get(key), ex: 900)

      expect(complete(for_sid: other_sid)).to eq(:none)
      expect(identities.count).to eq(0)
      expect(redis.get(planted)).to be_nil # spent either way
    end
  end

  describe '.complete with a malformed stash' do
    it 'discards a non-hash payload (:none) and still consumes the key' do
      Onetime::SessionSidecar.write(
        sid, described_class::FIELD, 'not-a-hash', dbclient: redis, codec: codec,
      )

      expect(complete).to eq(:none)
      expect(redis.get(key)).to be_nil
      expect(identities.count).to eq(0)
    end

    it 'discards a payload missing part of the bind tuple (:none)' do
      Onetime::SessionSidecar.write(
        sid, described_class::FIELD,
        { 'account_id' => account_id.to_s, 'provider' => provider, 'issuer' => issuer },
        dbclient: redis, codec: codec,
      )

      expect(complete).to eq(:none)
      expect(identities.count).to eq(0)
    end
  end

  describe 'single-use holds even when the bind raises' do
    it 'consumes the stash BEFORE attempting the insert, so an error cannot leave a retry behind' do
      defer
      allow(Auth::Operations::BindSsoIdentity).to receive(:call)
        .and_raise(Sequel::DatabaseError, 'boom')

      # The error propagates (the hook wraps completion in ErrorHandler.safe_execute),
      # but the stash is already gone — GETDEL consumed it at the store.
      expect { complete }.to raise_error(Sequel::DatabaseError)
      expect(redis.get(key)).to be_nil
    end
  end
end
