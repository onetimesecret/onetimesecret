# spec/unit/onetime/session/recent_reauth_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::RecentReauth — the recent-full-re-authentication
# marker and gate (#4410). Every acceptance criterion from the issue lands
# here: account/session/surface binding, explicit max age, refusal of
# expired/replayed/partial/account-mismatched/surface-mismatched proof.
# Callers (login hooks, Connect entry points) are covered by their own
# specs; this file covers the module in isolation.

require 'spec_helper'
require 'onetime/session/recent_reauth'
require 'onetime/session/codec'

RSpec.describe Onetime::RecentReauth do
  def env_for(strategy:, display_domain: nil, custom_domain_id: nil)
    {
      'onetime.domain_strategy' => strategy,
      'onetime.display_domain' => display_domain,
      'onetime.custom_domain_id' => custom_domain_id,
    }
  end

  let(:canonical_env) { env_for(strategy: :canonical) }
  let(:tenant_a_env)  { env_for(strategy: :custom, custom_domain_id: 'tenant-a') }
  let(:tenant_b_env)  { env_for(strategy: :custom, custom_domain_id: 'tenant-b') }

  describe '.record' do
    it 'stamps account_id, at, surface, and methods when the surface resolves' do
      session = {}
      now     = Time.utc(2026, 9, 12, 23, 30, 0)

      payload = described_class.record(
        session,
        canonical_env,
        account_id: 42,
        methods: %w[password otp],
        now: now,
      )

      expect(payload).to eq(
        'account_id' => 42,
        'at' => now.to_i,
        'surface' => { 'kind' => 'canonical' },
        'methods' => %w[password otp],
      )
      expect(session[described_class::KEY]).to eq(payload)
    end

    it 'freezes the payload so callers cannot mutate the marker' do
      session = {}
      described_class.record(session, canonical_env, account_id: 1, methods: ['password'])

      expect(session[described_class::KEY]).to be_frozen
      expect(session[described_class::KEY]['methods']).to be_frozen
    end

    it 'records nothing and returns nil when the request surface is unresolved (:invalid)' do
      session = {}
      result  = described_class.record(session, env_for(strategy: :invalid), account_id: 1, methods: ['password'])

      expect(result).to be_nil
      expect(session).not_to have_key(described_class::KEY)
    end

    it 'records nothing when a :custom surface has no resolved id (blip)' do
      session = {}
      env     = env_for(strategy: :custom, display_domain: 'secrets.acme.com', custom_domain_id: nil)
      result  = described_class.record(session, env, account_id: 1, methods: ['password'])

      expect(result).to be_nil
      expect(session).not_to have_key(described_class::KEY)
    end

    it 'coerces string account_id to Integer for symmetric comparison in .satisfied?' do
      session = {}
      described_class.record(session, canonical_env, account_id: '42', methods: ['password'])

      expect(session[described_class::KEY]['account_id']).to eq(42)
    end

    it 'refuses proofs without an explicit local primary' do
      [nil, 'remember', 'email_auth', 'omniauth'].each do |primary|
        session = {}
        methods = [primary, 'otp'].compact

        expect(
          described_class.record(session, canonical_env, account_id: 42, methods: methods),
        ).to be_nil
        expect(session).not_to have_key(described_class::KEY)
      end
    end

    it 'accepts password and webauthn as local primaries' do
      described_class::LOCAL_PRIMARIES.each do |primary|
        session = {}
        expect(
          described_class.record(session, canonical_env, account_id: 42, methods: [primary]),
        ).not_to be_nil
      end
    end
  end

  describe '.satisfied?' do
    let(:now)     { Time.utc(2026, 9, 12, 23, 30, 0) }
    let(:session) do
      s = {}
      described_class.record(s, canonical_env, account_id: 42, methods: %w[password otp], now: now)
      s
    end

    it 'accepts a fresh proof for the same account on the same surface' do
      expect(described_class.satisfied?(session, canonical_env, account_id: 42, max_age: 600, now: now))
        .to be true
    end

    it 'survives the encrypted JSON session round trip' do
      codec    = Onetime::SessionCodec.new('recent-reauth-round-trip-test-secret')
      restored = codec.decode(codec.encode(session))

      expect(restored).to eq(
        'recent_reauth' => {
          'account_id' => 42,
          'at' => now.to_i,
          'surface' => { 'kind' => 'canonical' },
          'methods' => %w[password otp],
        },
      )
      expect(described_class.recorded(restored)).to eq(restored['recent_reauth'])
      expect(described_class.satisfied?(restored, canonical_env, account_id: 42, max_age: 600, now: now))
        .to be true

      described_class.clear(restored)
      expect(restored).not_to have_key('recent_reauth')
    end

    it 'accepts a proof exactly at the max_age boundary' do
      later = now + 600
      expect(described_class.satisfied?(session, canonical_env, account_id: 42, max_age: 600, now: later))
        .to be true
    end

    it 'refuses a proof one second past max_age (expiry)' do
      later = now + 601
      expect(described_class.satisfied?(session, canonical_env, account_id: 42, max_age: 600, now: later))
        .to be false
    end

    it 'refuses when no proof was ever recorded (missing marker)' do
      expect(described_class.satisfied?({}, canonical_env, account_id: 42, max_age: 600, now: now))
        .to be false
    end

    it 'refuses a proof for a different account (account mismatch)' do
      expect(described_class.satisfied?(session, canonical_env, account_id: 99, max_age: 600, now: now))
        .to be false
    end

    it 'refuses when session is nil (defensive; the caller has no session at all)' do
      expect(described_class.satisfied?(nil, canonical_env, account_id: 42, max_age: 600, now: now))
        .to be false
    end

    it 'refuses when env is nil' do
      expect(described_class.satisfied?(session, nil, account_id: 42, max_age: 600, now: now))
        .to be false
    end

    it 'refuses a platform proof on a tenant surface (surface mismatch)' do
      expect(described_class.satisfied?(session, tenant_a_env, account_id: 42, max_age: 600, now: now))
        .to be false
    end

    it 'refuses a tenant proof on a different tenant (tenant A → tenant B)' do
      tenant_session = {}
      described_class.record(tenant_session, tenant_a_env, account_id: 42, methods: ['password'], now: now)

      expect(described_class.satisfied?(tenant_session, tenant_b_env, account_id: 42, max_age: 600, now: now))
        .to be false
    end

    it 'refuses when the current request surface is unresolved (:invalid)' do
      expect(described_class.satisfied?(session, env_for(strategy: :invalid), account_id: 42, max_age: 600, now: now))
        .to be false
    end

    it 'refuses a future-dated proof (clock skew or forged marker)' do
      session[described_class::KEY] = session[described_class::KEY].merge('at' => now.to_i + 5).freeze

      expect(described_class.satisfied?(session, canonical_env, account_id: 42, max_age: 600, now: now))
        .to be false
    end

    it 'refuses when the stored payload is not a Hash (session was corrupted)' do
      expect(
        described_class.satisfied?(
          { described_class::KEY => 'garbage' },
          canonical_env,
          account_id: 42,
          max_age: 600,
          now: now,
        ),
      )
        .to be false
    end

    it 'refuses a persisted proof whose methods do not contain a local primary' do
      remembered = session[described_class::KEY].merge('methods' => %w[remember otp])
      session[described_class::KEY] = remembered

      expect(described_class.satisfied?(session, canonical_env, account_id: 42, max_age: 600, now: now))
        .to be false
    end

    it 'refuses when the stored at is missing or non-integer' do
      broken = {
        described_class::KEY => {
          'account_id' => 42,
          'at' => nil,
          'surface' => { 'kind' => 'canonical' },
          'methods' => %w[password],
        },
      }
      expect(described_class.satisfied?(broken, canonical_env, account_id: 42, max_age: 600, now: now))
        .to be false
    end
  end

  describe '.recorded' do
    it 'returns the payload without applying the gate' do
      session = {}
      payload = described_class.record(session, canonical_env, account_id: 42, methods: ['password'])
      expect(described_class.recorded(session)).to eq(payload)
    end
  end

  describe '.clear' do
    it 'removes the marker' do
      session = {}
      described_class.record(session, canonical_env, account_id: 42, methods: ['password'])
      described_class.clear(session)

      expect(session).not_to have_key(described_class::KEY)
    end
  end

  describe 'LOCAL_PRIMARIES constant' do
    it 'contains only reviewed local primary methods' do
      expect(described_class::LOCAL_PRIMARIES).to contain_exactly('password', 'webauthn')
    end
  end
end
