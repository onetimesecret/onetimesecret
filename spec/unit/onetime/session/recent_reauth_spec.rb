# frozen_string_literal: true

require 'spec_helper'
require 'onetime/session/recent_reauth'

RSpec.describe Onetime::RecentReauth do
  def env_for(strategy:, custom_domain_id: nil)
    {
      'onetime.domain_strategy' => strategy,
      'onetime.custom_domain_id' => custom_domain_id,
    }
  end

  let(:canonical_env) { env_for(strategy: :canonical) }
  let(:tenant_a_env) { env_for(strategy: :custom, custom_domain_id: 'tenant-a') }
  let(:tenant_b_env) { env_for(strategy: :custom, custom_domain_id: 'tenant-b') }
  let(:sid) { 'session-public-id' }
  let(:session_data) { {} }
  let(:session_id) { double('SessionId', public_id: sid) }
  let(:session) do
    double('RackSession', id: session_id).tap do |value|
      allow(value).to receive(:delete) { |key| session_data.delete(key) }
    end
  end
  let(:sidecar) { {} }
  let(:now) { Time.utc(2026, 9, 12, 23, 30, 0) }

  before do
    allow(Onetime::SessionSidecar).to receive(:write) do |received_sid, field, value|
      next nil unless received_sid == sid

      sidecar[field] = value
      900
    end
    allow(Onetime::SessionSidecar).to receive(:read) do |received_sid, field|
      received_sid == sid ? sidecar[field] : nil
    end
    allow(Onetime::SessionSidecar).to receive(:consume) do |received_sid, field|
      received_sid == sid ? sidecar.delete(field) : nil
    end
    allow(Onetime::SessionSidecar).to receive(:delete) do |received_sid, field|
      received_sid == sid && sidecar.delete(field) ? 1 : 0
    end
  end

  describe '.record' do
    it 'stores a session-bound proof in the explicit-use sidecar' do
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
      expect(Onetime::SessionSidecar).to have_received(:write)
        .with(sid, described_class::KEY, payload)
      expect(session_data).not_to have_key(described_class::KEY)
    end

    it 'refuses an unresolved surface, missing account, or non-local primary' do
      expect(described_class.record(session, env_for(strategy: :invalid), account_id: 42, methods: ['password'])).to be_nil
      expect(described_class.record(session, canonical_env, account_id: nil, methods: ['password'])).to be_nil
      expect(described_class.record(session, canonical_env, account_id: 42, methods: ['email_auth'])).to be_nil

      expect(Onetime::SessionSidecar).not_to have_received(:write)
    end

    it 'fails closed when the session has no usable public id' do
      allow(session).to receive(:id).and_return(nil)
      allow(Onetime::SessionSidecar).to receive(:write).and_return(nil)

      expect(described_class.record(session, canonical_env, account_id: 42, methods: ['password'])).to be_nil
    end

    it 'fails closed when sidecar persistence raises' do
      allow(Onetime::SessionSidecar).to receive(:write).and_raise(StandardError, 'redis unavailable')

      expect(described_class.record(session, canonical_env, account_id: 42, methods: ['password'])).to be_nil
    end
  end

  describe '.satisfied?' do
    def record_proof(env: canonical_env, account_id: 42, methods: %w[password otp], at: now)
      described_class.record(session, env, account_id: account_id, methods: methods, now: at)
    end

    it 'accepts a fresh matching proof exactly once' do
      record_proof

      expect(described_class.satisfied?(session, canonical_env, account_id: 42, max_age: 600, now: now)).to be true
      expect(described_class.satisfied?(session, canonical_env, account_id: 42, max_age: 600, now: now)).to be false
    end

    it 'allows only one winner when two calls present the same proof' do
      record_proof

      outcomes = 2.times.map do
        described_class.satisfied?(session, canonical_env, account_id: 42, max_age: 600, now: now)
      end
      expect(outcomes).to contain_exactly(true, false)
    end

    it 'accepts a proof exactly at the max-age boundary' do
      record_proof

      expect(described_class.satisfied?(session, canonical_env, account_id: 42, max_age: 600, now: now + 600)).to be true
    end

    it 'refuses and consumes expired or future-dated proof' do
      record_proof
      expect(described_class.satisfied?(session, canonical_env, account_id: 42, max_age: 600, now: now + 601)).to be false
      expect(sidecar).not_to have_key(described_class::KEY)

      record_proof(at: now + 1)
      expect(described_class.satisfied?(session, canonical_env, account_id: 42, max_age: 600, now: now)).to be false
      expect(sidecar).not_to have_key(described_class::KEY)
    end

    it 'refuses account, surface, and primary-method mismatches' do
      record_proof
      expect(described_class.satisfied?(session, canonical_env, account_id: 99, max_age: 600, now: now)).to be false

      record_proof(env: tenant_a_env)
      expect(described_class.satisfied?(session, tenant_b_env, account_id: 42, max_age: 600, now: now)).to be false

      sidecar[described_class::KEY] = {
        'account_id' => 42,
        'at' => now.to_i,
        'surface' => { 'kind' => 'canonical' },
        'methods' => %w[remember otp],
      }
      expect(described_class.satisfied?(session, canonical_env, account_id: 42, max_age: 600, now: now)).to be false
    end

    it 'refuses missing or malformed proof and datastore failures' do
      expect(described_class.satisfied?(session, canonical_env, account_id: 42, max_age: 600, now: now)).to be false

      sidecar[described_class::KEY] = 'garbage'
      expect(described_class.satisfied?(session, canonical_env, account_id: 42, max_age: 600, now: now)).to be false

      allow(Onetime::SessionSidecar).to receive(:consume).and_raise(StandardError, 'redis unavailable')
      expect(described_class.satisfied?(session, canonical_env, account_id: 42, max_age: 600, now: now)).to be false
    end
  end

  describe '.recorded and .clear' do
    it 'reads without consuming and explicitly deletes the sidecar proof' do
      payload = described_class.record(session, canonical_env, account_id: 42, methods: ['password'], now: now)

      expect(described_class.recorded(session)).to eq(payload)
      expect(described_class.recorded(session)).to eq(payload)
      expect(described_class.clear(session)).to eq(1)
      expect(described_class.recorded(session)).to be_nil
    end
  end
end
