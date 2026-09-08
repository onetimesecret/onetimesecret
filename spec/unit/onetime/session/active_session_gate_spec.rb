# spec/unit/onetime/session/active_session_gate_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::ActiveSessionGate — per-request enforcement of
# Rodauth's account_active_session_keys table in full auth mode.
#
# Terms (Rack session, active-session row, join key, revoke, refuse) are
# defined in the gate's module doc. `session` below is the Rack session; the
# rows inserted into the table are active-session rows.
#
# The table is real (in-memory SQLite with the production column shape) so
# the join, the touch throttle and the revoked/active split are exercised
# against SQL, not doubles. Mode, feature flag and connection are stubbed at
# the seams the module reads them from.

require 'spec_helper'
require 'sequel'
require 'onetime/session/active_session_gate'

RSpec.describe Onetime::ActiveSessionGate do
  let(:db) do
    Sequel.sqlite.tap do |sqlite|
      sqlite.create_table(:account_active_session_keys) do
        Integer :account_id
        String :session_id
        Time :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
        Time :last_use, null: false, default: Sequel::CURRENT_TIMESTAMP
        primary_key [:account_id, :session_id]
      end
    end
  end

  let(:hmac) { 'a' * 64 }
  let(:session) { { 'authenticated' => true, 'account_id' => 42, 'active_session_id_hmac' => hmac } }

  # The constant only exists once the auth application has booted; the unit
  # lane (simple mode) has not loaded it, so define a stand-in that carries
  # the one method the gate calls — partial-double verification refuses to
  # stub a method the constant does not implement.
  before do
    stub_const('Auth::Database', Class.new { def self.connection = nil }) unless defined?(Auth::Database)
    allow(Auth::Database).to receive(:connection).and_return(db)
    allow(Onetime.auth_config).to receive_messages(full_enabled?: true, active_sessions_enabled?: true)
    allow(OT).to receive(:le)
    allow(OT).to receive(:ld)
  end

  def insert_row(last_use: Time.now)
    db[:account_active_session_keys].insert(account_id: 42, session_id: hmac, last_use: last_use, created_at: last_use)
  end

  describe '.verdict' do
    it 'is :active while the active-session row exists' do
      insert_row
      expect(described_class.verdict(session)).to eq(:active)
    end

    it 'is :revoked once the active-session row has been revoked' do
      expect(described_class.verdict(session)).to eq(:revoked)
    end

    it 'joins on BOTH halves of the key: another account holding the same digest does not count' do
      db[:account_active_session_keys].insert(account_id: 7, session_id: hmac)
      expect(described_class.verdict(session)).to eq(:revoked)
    end

    it 'is :skipped outside full mode, even for a Rack session with a join key' do
      allow(Onetime.auth_config).to receive(:full_enabled?).and_return(false)
      expect(described_class.verdict(session)).to eq(:skipped)
    end

    it 'is :skipped when the active_sessions feature is off' do
      allow(Onetime.auth_config).to receive(:active_sessions_enabled?).and_return(false)
      expect(described_class.verdict(session)).to eq(:skipped)
    end

    it 'is :skipped for a Rack session that carries no join key (pre-stamp login) — never a mass logout' do
      session.delete('active_session_id_hmac')
      expect(described_class.verdict(session)).to eq(:skipped)
    end

    it 'is :skipped for a Rack session with no account id' do
      session.delete('account_id')
      expect(described_class.verdict(session)).to eq(:skipped)
    end

    it 'is :skipped for a nil Rack session' do
      expect(described_class.verdict(nil)).to eq(:skipped)
    end

    it 'is :unavailable, with an error log, when the authdb has no connection' do
      allow(Auth::Database).to receive(:connection).and_return(nil)

      expect(described_class.verdict(session)).to eq(:unavailable)
      expect(OT).to have_received(:le).with(/fail closed/)
    end

    it 'is :unavailable, with an error log, when the active-session row query raises' do
      allow(Auth::Database).to receive(:connection).and_raise(Sequel::DatabaseConnectionError, 'down')

      expect(described_class.verdict(session)).to eq(:unavailable)
      expect(OT).to have_received(:le).with(/DatabaseConnectionError/)
    end
  end

  describe '.revoked?' do
    it 'is true once the active-session row has been revoked' do
      expect(described_class.revoked?(session)).to be(true)
    end

    it 'is false while the active-session row exists' do
      insert_row
      expect(described_class.revoked?(session)).to be(false)
    end

    it 'is true when the active-session row cannot be checked (fail closed)' do
      allow(Auth::Database).to receive(:connection).and_return(nil)
      expect(described_class.revoked?(session)).to be(true)
    end

    it 'is false when the gate does not apply (no join key)' do
      session.delete('active_session_id_hmac')
      expect(described_class.revoked?(session)).to be(false)
    end
  end

  describe 'per-request memo' do
    it 'computes once per env and serves the memo afterwards' do
      insert_row
      env = {}

      expect(described_class.verdict(session, env: env)).to eq(:active)
      db[:account_active_session_keys].delete
      expect(described_class.verdict(session, env: env)).to eq(:active)
      expect(env[described_class::ENV_KEY]).to eq(:active)
    end

    it 'does not share a memo across envs' do
      insert_row
      expect(described_class.verdict(session, env: {})).to eq(:active)
      db[:account_active_session_keys].delete
      expect(described_class.verdict(session, env: {})).to eq(:revoked)
    end
  end

  describe 'last_use touch' do
    it 'refreshes a stale last_use so the sessions-page inactivity sweep sees real activity' do
      insert_row(last_use: Time.now - (described_class::TOUCH_INTERVAL + 60))

      described_class.verdict(session)

      last_use = db[:account_active_session_keys].first[:last_use]
      expect(Time.now - last_use).to be < 5
    end

    it 'leaves a recent last_use alone (throttled)' do
      recent = Time.now - 30
      insert_row(last_use: recent)

      described_class.verdict(session)

      expect(db[:account_active_session_keys].first[:last_use].to_i).to eq(recent.to_i)
    end

    it 'never turns a failed touch into a non-active verdict' do
      insert_row(last_use: Time.now - (described_class::TOUCH_INTERVAL + 60))
      dataset = instance_double(Sequel::Dataset)
      allow(db).to receive(:[]).with(described_class::TABLE).and_return(dataset)
      allow(dataset).to receive(:where).and_return(dataset)
      allow(dataset).to receive(:select).and_return(dataset)
      allow(dataset).to receive(:first).and_return({ last_use: Time.now - 1000 })
      allow(dataset).to receive(:update).and_raise(Sequel::DatabaseError, 'read-only replica')

      expect(described_class.verdict(session)).to eq(:active)
    end
  end
end
