# apps/web/auth/spec/integration/full/remove_authentication_data_concurrency_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode, PostgreSQL only)
# =============================================================================
#
# The parent-row lock in RemoveAuthenticationData.delete_dependent_rows.
#
# On PostgreSQL an INSERT into a table referencing accounts.id takes a KEY
# SHARE lock on the accounts row. The status update Rodauth's close_account
# makes first (FOR NO KEY UPDATE) does not block it, so a request still in
# flight for the account, a login writing its audit row say, could commit a
# child row between the closure's child deletes and its delete of the row
# itself; that last delete then fails its foreign-key check and the closure
# rolls back, after the Redis customer is already gone. With the row locked
# FOR UPDATE from the first child delete to the commit, the insert waits and
# then fails on the missing parent instead.
#
# Both paths are exercised: the outright deletion every caller outside
# Rodauth runs, and the close_account hook's sequence (retain, Rodauth's own
# audit row, then the delete_account override) inside one outer transaction.
# A second connection plays the in-flight request. SQLite cannot show the
# race (one writer at a time) and ignores FOR UPDATE, so the file is
# PostgreSQL-only. Without the lock both examples fail: the insert returns
# at once with :inserted and the closure's own delete is what fails.
#
# Run:
#   tests/lanes/run full-pg --only \
#     apps/web/auth/spec/integration/full/remove_authentication_data_concurrency_spec.rb
# =============================================================================

require_relative '../../spec_helper'
require 'auth/operations/remove_authentication_data'

RSpec.describe 'RemoveAuthenticationData against a concurrent child insert',
  :postgres_database,
  type: :integration do
  let(:db) { test_db }
  let(:account) { create_verified_account(db: db) }
  let(:account_id) { account[:id] }
  let(:operation) { Auth::Operations::RemoveAuthenticationData }

  before do
    insert_audit_row(db, account_id)
  end

  after do
    cleanup_account(db: db, account_id: account_id)
  end

  def insert_audit_row(db, account_id)
    db[:account_authentication_audit_logs].insert(
      account_id: account_id,
      at: Time.now,
      message: 'login successful',
    )
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # The in-flight request: on its own connection, once told to go, it tries
  # to insert an audit row for the account and reports when it started, how
  # long the attempt took and how it ended.
  def start_writer(db, account_id, go:, attempting:)
    # rubocop:disable-next ThreadSafety/NewThread -- the second connection is the subject
    Thread.new do
      go.pop
      attempting.push(true)
      started = monotonic_now
      outcome = begin
        insert_audit_row(db, account_id)
        :inserted
      rescue Sequel::ForeignKeyConstraintViolation
        :foreign_key_violation
      end
      { started: started, blocked_for: monotonic_now - started, outcome: outcome }
    end
  end

  # Called with the lock held and the children gone: release the writer, then
  # give its insert time to reach the server and block there before the
  # closure continues. Generous on purpose; the assertions are on ordering
  # and on the insert having waited, not on the exact wait.
  def release_writer(go, attempting)
    go.push(true)
    attempting.pop
    sleep 0.5
  end

  def expect_insert_waited_for_the_commit(writer, committed_at)
    report = writer.value
    expect(report[:outcome]).to eq(:foreign_key_violation)
    expect(report[:started]).to be < committed_at
    expect(report[:blocked_for]).to be >= 0.3
    expect(db[:accounts].where(id: account_id).count).to eq(0)
    expect(db[:account_authentication_audit_logs].where(account_id: account_id).count).to eq(0)
  end

  it 'outright deletion: the insert waits for the commit, then fails on the missing account' do
    go         = Queue.new
    attempting = Queue.new
    writer     = start_writer(db, account_id, go: go, attempting: attempting)

    allow(operation).to receive(:delete_dependent_rows).and_wrap_original do |original, *args, **kwargs|
      deleted = original.call(*args, **kwargs)
      release_writer(go, attempting)
      deleted
    end

    result       = operation.call(extid: account[:external_id], db: db, revoke_sessions: false)
    committed_at = monotonic_now

    expect(result).to include(success: true, account_id: account_id)
    expect_insert_waited_for_the_commit(writer, committed_at)
  end

  it 'the close_account hook sequence: the insert waits for the commit, then fails on the missing account' do
    go         = Queue.new
    attempting = Queue.new
    writer     = start_writer(db, account_id, go: go, attempting: attempting)

    db.transaction do
      result = operation.call(extid: account[:external_id], db: db, revoke_sessions: false, retain_account: true)
      expect(result).to include(success: true, account_id: account_id)

      # What Rodauth's audit_logging writes after the hook returns.
      db[:account_authentication_audit_logs].insert(account_id: account_id, at: Time.now, message: 'Account closed')
      release_writer(go, attempting)

      # The delete_account override (config/hooks/account.rb), then Rodauth's
      # own delete of the row.
      operation.delete_dependent_rows(db, account_id)
      db[:accounts].where(id: account_id).delete
    end
    committed_at = monotonic_now

    expect_insert_waited_for_the_commit(writer, committed_at)
  end
end
