# apps/web/auth/spec/integration/full/prune_closed_accounts_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# Issue: #4819. Closures before that change left a CLOSED `accounts` row and
# the account's whole authentication audit log behind, with no expiry.
# Auth::Operations::Customers::PruneClosedAccounts removes those rows; this
# file drives it against the REAL migrated schema (Auth::Database.connection)
# so the IN-subquery deletes are exercised on whichever engine the lane runs
# (`full-sqlite`, `full-pg-agnostic`).
#
# Fixtures are inserted directly: the rows under test are the ones an OLD
# closure produced, which no current code path writes.
# =============================================================================

require_relative '../../spec_helper'

RSpec.describe 'Closed account pruning (#4819)', type: :integration do
  before(:all) do
    require 'onetime' unless defined?(Onetime)
    Onetime.boot! :test unless Onetime.ready?
    # Lazily required by the CLI, not autoloaded; needs the app booted.
    require 'auth/operations/customers/prune_closed_accounts'
  end

  let(:db) { Auth::Database.connection }
  let(:accounts) { db[:accounts] }
  let(:audit_logs) { db[:account_authentication_audit_logs] }
  let(:run) { SecureRandom.hex(6) }

  # Belt-and-suspenders cleanup; the auth spec_helper clears the auth DB
  # around every :integration example, but the datastore is shared so every
  # fixture this file creates is also removed explicitly (see `after` below).
  let(:created_account_ids) { [] }

  # Two closed rows (one with history, one bare), a verified row and an
  # unverified row, each with audit rows of its own. The closed row with
  # history also keeps an active-session row and an SSO identity, the shape
  # an interrupted old closure could leave.
  let!(:closed_with_history) do
    id = insert_account('closed-a', status_id: AuthTestConstants::STATUS_CLOSED)
    insert_audit_rows(id, 3)
    db[:account_active_session_keys].insert(
      account_id: id,
      session_id: "sess-#{run}",
      created_at: Time.now,
      last_use: Time.now,
    )
    db[:account_identities].insert(
      account_id: id,
      provider: 'google',
      issuer: 'https://accounts.google.com',
      uid: "uid-#{run}",
    )
    id
  end
  let!(:closed_bare) { insert_account('closed-b', status_id: AuthTestConstants::STATUS_CLOSED) }
  let!(:verified) do
    id = insert_account('verified', status_id: AuthTestConstants::STATUS_VERIFIED)
    insert_audit_rows(id, 2)
    id
  end
  let!(:unverified) do
    id = insert_account('unverified', status_id: AuthTestConstants::STATUS_UNVERIFIED)
    insert_audit_rows(id, 1)
    id
  end

  after do
    created_account_ids.each do |id|
      Auth::Operations::RemoveAuthenticationData.delete_dependent_rows(db, id)
      accounts.where(id: id).delete
    end
  end

  def insert_account(label, status_id:)
    id = accounts.insert(
      email: "#{label}-#{run}@prune.example.com",
      status_id: status_id,
      external_id: "ur_#{label}_#{run}",
    )
    created_account_ids << id
    id
  end

  def insert_audit_rows(account_id, count)
    count.times do |index|
      audit_logs.insert(
        account_id: account_id,
        message: "Login successful #{index}",
        metadata: '{"ip":"10.0.0.1","user_agent":"spec"}',
      )
    end
  end

  def audit_count(account_id)
    audit_logs.where(account_id: account_id).count
  end

  def new_operation(dry_run: true)
    Auth::Operations::Customers::PruneClosedAccounts.new(dry_run: dry_run)
  end

  describe 'dry run (default)' do
    it 'counts the closed rows and their dependent rows and writes nothing' do
      result = new_operation.call

      expect(result.dry_run).to be(true)
      expect(result.accounts).to eq(2)
      # `include`, not `eq`: the active-session insert also fires the
      # account_activity_times trigger (migration 004), and the report lists
      # every referencing table with rows.
      expect(result.rows).to include(
        account_authentication_audit_logs: 3,
        account_active_session_keys: 1,
        account_identities: 1,
      )

      expect(accounts.where(id: [closed_with_history, closed_bare]).count).to eq(2)
      expect(audit_count(closed_with_history)).to eq(3)
      expect(db[:account_active_session_keys].where(account_id: closed_with_history).count).to eq(1)
      expect(db[:account_identities].where(account_id: closed_with_history).count).to eq(1)
    end

    it 'is the default mode' do
      expect(Auth::Operations::Customers::PruneClosedAccounts.new.call.dry_run).to be(true)
    end
  end

  describe 'live run' do
    it 'deletes the closed rows with every row that references them and reports the counts' do
      result = new_operation(dry_run: false).call

      expect(result.dry_run).to be(false)
      expect(result.accounts).to eq(2)
      expect(result.rows).to include(
        account_authentication_audit_logs: 3,
        account_active_session_keys: 1,
        account_identities: 1,
      )

      expect(accounts.where(id: [closed_with_history, closed_bare]).count).to eq(0)
      Auth::Operations::RemoveAuthenticationData::DEPENDENT_TABLES.each do |table|
        column = Auth::Operations::RemoveAuthenticationData.fk_column_for(table)
        expect(db[table].where(column => [closed_with_history, closed_bare]).count).to eq(0),
          "#{table} still references a pruned account"
      end
    end

    it 'leaves live accounts and their audit history alone' do
      new_operation(dry_run: false).call

      expect(accounts.where(id: verified).get(:status_id)).to eq(AuthTestConstants::STATUS_VERIFIED)
      expect(accounts.where(id: unverified).get(:status_id)).to eq(AuthTestConstants::STATUS_UNVERIFIED)
      expect(audit_count(verified)).to eq(2)
      expect(audit_count(unverified)).to eq(1)
    end

    it 'deletes the same rows when the closed ids go out one per statement' do
      stub_const('Auth::Operations::Customers::PruneClosedAccounts::DELETE_BATCH', 1)

      result = new_operation(dry_run: false).call

      expect(result.accounts).to eq(2)
      expect(result.rows).to include(account_authentication_audit_logs: 3, account_identities: 1)
      expect(accounts.where(id: [closed_with_history, closed_bare]).count).to eq(0)
      expect(audit_count(verified)).to eq(2)
    end

    # The deletes are keyed on the ids the lock read returned, not on a
    # status subquery evaluated again per statement: a row closed after the
    # lock was never locked, so it is left for the next run.
    it 'leaves a row closed after the lock read for the next run' do
      operation = new_operation(dry_run: false)
      allow(operation).to receive(:dependent_tables).and_wrap_original do |original|
        accounts.where(id: verified).update(status_id: AuthTestConstants::STATUS_CLOSED)
        original.call
      end

      result = operation.call

      expect(result.accounts).to eq(2)
      expect(accounts.where(id: verified).count).to eq(1)
      expect(audit_count(verified)).to eq(2)
      expect(new_operation(dry_run: false).call.accounts).to eq(1)
    end

    # A closure before #4819 that stopped after closing the row and before
    # deleting the Customer record left both behind. The closed row was the
    # only thing keeping `customers sync-auth-accounts` from giving that
    # record a live account again; the marker takes over before it goes.
    context 'when a closed row still names a customer record' do
      let(:closed_at) { Time.at(1_700_000_000).utc }
      let!(:leftover) { Onetime::Customer.create!(email: "leftover-#{run}@prune.example.com") }
      # Stored as the update trigger stores it: a naive UTC wall clock, not a
      # Time Sequel would write and read back in the same host zone.
      let!(:leftover_row) do
        id = accounts.insert(
          email: leftover.email,
          status_id: AuthTestConstants::STATUS_CLOSED,
          external_id: leftover.extid,
          updated_at: closed_at.strftime('%Y-%m-%d %H:%M:%S'),
        )
        created_account_ids << id
        id
      end

      it 'counts the record on a dry run without marking it' do
        result = new_operation.call

        expect(result.marked).to eq(1)
        expect(Onetime::Customer.load(leftover.objid).closing?).to be(false)
      end

      it 'marks the record as closing, dated when its row closed, before deleting the row' do
        result = new_operation(dry_run: false).call

        expect(result.marked).to eq(1)
        expect(accounts.where(id: leftover_row).count).to eq(0)
        expect(Onetime::Customer.load(leftover.objid).closure_started_at).to eq(closed_at.to_i)
      end

      # What Sequel returns for that column on a UTC-7 host with no database
      # timezone pinned: the UTC wall clock labelled with the host's offset.
      it 'reads the row time as the UTC wall clock it is, whatever zone Sequel labels it with' do
        host_read = Time.new(2023, 11, 14, 22, 13, 20, '-07:00')

        expect(new_operation.send(:closed_at_epoch, host_read)).to eq(closed_at.to_i)
      end

      # A marker dated ahead of the clock would read as a closure in progress
      # until the clock caught up. Inserted rather than updated: the update
      # trigger would overwrite updated_at with the current time.
      it 'never dates the marker later than now' do
        now    = Familia.now.to_i
        ahead  = Onetime::Customer.create!(email: "ahead-#{run}@prune.example.com")
        created_account_ids << accounts.insert(
          email: ahead.email,
          status_id: AuthTestConstants::STATUS_CLOSED,
          external_id: ahead.extid,
          updated_at: Time.at(now + 3600).utc.strftime('%Y-%m-%d %H:%M:%S'),
        )

        new_operation(dry_run: false).call

        expect(Onetime::Customer.load(ahead.objid).closure_started_at.to_i).to be_between(now, Familia.now.to_i)
      end

      it 'deletes nothing when the marker cannot be written' do
        allow_any_instance_of(Onetime::Customer).to receive(:mark_closure_started!)
          .and_raise(Redis::CannotConnectError, 'valkey unavailable')

        expect { new_operation(dry_run: false).call }.to raise_error(Redis::CannotConnectError)
        expect(accounts.where(id: [leftover_row, closed_with_history, closed_bare]).count).to eq(3)
      end
    end

    it 'is a no-op the second time' do
      new_operation(dry_run: false).call
      result = new_operation(dry_run: false).call

      expect(result.accounts).to eq(0)
      expect(result.rows).to eq({})
    end
  end

  describe 'without an auth database' do
    it 'refuses to construct' do
      expect { Auth::Operations::Customers::PruneClosedAccounts.new(db: nil).tap { nil } }
        .not_to raise_error

      allow(Auth::Database).to receive(:connection).and_return(nil)
      expect { Auth::Operations::Customers::PruneClosedAccounts.new }
        .to raise_error(Onetime::Problem, /Auth database unavailable/)
    end
  end
end
