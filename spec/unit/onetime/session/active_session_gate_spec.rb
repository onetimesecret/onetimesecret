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
      # Auth::Database loads the same extension on the authdb connection; the
      # gate's throttle predicate (Sequel.date_sub) needs it.
      sqlite.extension :date_arithmetic
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
    allow(OT).to receive(:lw)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:info)
  end

  def insert_row(last_use: Time.now, created_at: last_use)
    db[:account_active_session_keys].insert(account_id: 42, session_id: hmac, last_use: last_use, created_at: created_at)
  end

  def rows
    db[:account_active_session_keys]
  end

  describe '.verdict' do
    it 'is :active while the active-session row exists' do
      insert_row
      expect(described_class.verdict(session)).to eq(:active)
    end

    it 'is :revoked once the active-session row has been revoked, naming the join in the log' do
      expect(described_class.verdict(session)).to eq(:revoked)
      expect(OT).to have_received(:info).with(/no active-session row.*account_id=42 join_key=aaaaaaaaaaaa…/)
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

  # Rodauth's two deadlines are decided in the gate's own SELECT. They have
  # to be: the gate keeps last_use fresh on every request, so a deadline
  # applied anywhere later (the sessions page, a wired-up check_active_session)
  # would never find a stale row, and an expired row would be revived by the
  # request that should have ended it.
  describe 'deadlines' do
    let(:now) { Time.now }

    it 'refuses a row past the inactivity deadline and removes it, as the sweep would' do
      insert_row(last_use: now - (described_class::INACTIVITY_DEADLINE + 60), created_at: now)

      expect(described_class.verdict(session)).to eq(:revoked)
      expect(rows.count).to eq(0)
      expect(OT).to have_received(:info).with(/past its inactivity deadline/)
    end

    it 'refuses a row past the lifetime deadline however recent its last_use, and removes it' do
      insert_row(last_use: now, created_at: now - (described_class::LIFETIME_DEADLINE + 60))

      expect(described_class.verdict(session)).to eq(:revoked)
      expect(rows.count).to eq(0)
      expect(OT).to have_received(:info).with(/past its lifetime deadline/)
    end

    it 'keeps a row inside both deadlines active' do
      insert_row(
        last_use: now - (described_class::INACTIVITY_DEADLINE - 3600),
        created_at: now - (described_class::LIFETIME_DEADLINE - 3600),
      )

      expect(described_class.verdict(session)).to eq(:active)
      expect(rows.count).to eq(1)
    end

    # The failure mode that makes the deadlines the gate's job: the request
    # that finds an expired row must not refresh last_use on it first.
    it 'never revives an expired row by touching last_use' do
      stale = now - (described_class::INACTIVITY_DEADLINE + 60)
      insert_row(last_use: stale, created_at: now)

      described_class.verdict(session)

      expect(rows.count).to eq(0)
    end

    it 'still refuses when the expired row cannot be removed, and warns' do
      insert_row(last_use: now - (described_class::INACTIVITY_DEADLINE + 60), created_at: now)
      dataset = instance_double(Sequel::Dataset)
      allow(db).to receive(:[]).with(described_class::TABLE).and_return(dataset)
      allow(dataset).to receive_messages(where: dataset, select: dataset, first: { inactive: 1, outlived: 0, touch_due: 1 })
      allow(dataset).to receive(:delete).and_raise(Sequel::DatabaseError, 'read-only replica')

      expect(described_class.verdict(session)).to eq(:revoked)
      expect(OT).to have_received(:lw).with(/sweep will collect it.*read-only replica/)
    end

    it 'is refused on the /auth surface and by the strategies like any revoked row' do
      insert_row(last_use: now - (described_class::INACTIVITY_DEADLINE + 60), created_at: now)
      expect(described_class.revoked?(session)).to be(true)
    end

    # Same clock discipline as the touch: the database decides. A process
    # running five hours ahead of the database must not expire a row that
    # the database still considers inside its deadline.
    it 'decides in the database clock, not Ruby\'s' do
      insert_row(last_use: now - (described_class::INACTIVITY_DEADLINE - 3600), created_at: now)
      allow(Time).to receive(:now).and_return(now + (5 * 3600))

      expect(described_class.verdict(session)).to eq(:active)
      expect(rows.count).to eq(1)
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

    # The throttle and the refreshed value both live in the database's clock,
    # the one Rodauth wrote `last_use` with. Ruby's Time.now is not consulted:
    # a process whose TZ differs from the database session's would otherwise
    # either never refresh (west of the DB: the inactivity sweep then signs
    # out an active user) or refresh on every request (east of it). The two
    # examples below skew Ruby's clock by five hours each way; the DB's
    # verdict must not move.
    context 'when the process clock is skewed from the database clock' do
      let(:real_now) { Time.now }
      let(:skew) { 5 * 3600 }

      def last_use_in_db
        db[:account_active_session_keys].first[:last_use]
      end

      it 'still refreshes a stale row when Ruby thinks it is five hours EARLIER than the DB' do
        stale = real_now - (described_class::TOUCH_INTERVAL + 60)
        insert_row(last_use: stale)
        allow(Time).to receive(:now).and_return(real_now - skew)

        described_class.verdict(session)

        expect(real_now - last_use_in_db).to be < 5
      end

      it 'still leaves a fresh row alone when Ruby thinks it is five hours LATER than the DB' do
        recent = real_now - 30
        insert_row(last_use: recent)
        allow(Time).to receive(:now).and_return(real_now + skew)

        described_class.verdict(session)

        expect(last_use_in_db.to_i).to eq(recent.to_i)
      end
    end

    context 'when the refresh write fails' do
      let(:dataset) { instance_double(Sequel::Dataset) }

      before do
        insert_row(last_use: Time.now - (described_class::TOUCH_INTERVAL + 60))
        allow(db).to receive(:[]).with(described_class::TABLE).and_return(dataset)
        allow(dataset).to receive_messages(where: dataset, select: dataset, first: { touch_due: 1 })
        allow(dataset).to receive(:update).and_raise(Sequel::DatabaseError, 'read-only replica')
      end

      it 'never turns a failed touch into a non-active verdict' do
        expect(described_class.verdict(session)).to eq(:active)
      end

      # Warn, not debug: the row's last_use feeds Rodauth's inactivity sweep,
      # so a refresh that keeps failing ends in a live session being revoked.
      it 'warns, naming the consequence, so the eventual sign-out is traceable' do
        described_class.verdict(session)

        expect(OT).to have_received(:lw).with(/inactivity deadline will end a live session.*account_id=42.*read-only replica/)
      end
    end
  end
end
