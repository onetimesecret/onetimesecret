# try/unit/operations/change_email_try.rb
#
# frozen_string_literal: true

# Tests for Auth::Operations::ChangeEmail
#
# Covers:
# - Updates accounts.email when account found by extid
# - Returns { success: true, account_id: } on success
# - Clears account_active_session_keys rows for the account
# - Clears account_login_change_keys rows for the account
# - Returns { success: true, skipped: true } when no auth account found
# - Returns { success: false, error: } on Sequel error

require_relative '../../support/test_logic'

OT.boot! :test, false

require 'sequel'
require 'apps/web/auth/database'
require 'apps/web/auth/operations/change_email'

def build_test_sqlite_db
  db = Sequel.sqlite

  db.create_table(:account_statuses) do
    Integer :id, primary_key: true
    String :name, null: false
  end
  db.from(:account_statuses).import([:id, :name], [[1, 'Unverified'], [2, 'Verified'], [3, 'Closed']])

  db.create_table(:accounts) do
    primary_key :id
    Integer :status_id, null: false, default: 2
    String :email, null: false
    String :external_id, unique: true
    DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
  end

  db.create_table(:account_active_session_keys) do
    Integer :account_id, null: false
    String :session_id
    Time :created_at, default: Sequel::CURRENT_TIMESTAMP
    Time :last_use, default: Sequel::CURRENT_TIMESTAMP
    primary_key [:account_id, :session_id]
  end

  db.create_table(:account_login_change_keys) do
    Integer :id, primary_key: true  # FK to accounts.id
    String :key, null: false
    String :login, null: false
    DateTime :deadline
  end

  db
end

# TRYOUTS

## Updates accounts.email to new value when account found by extid
@db1 = build_test_sqlite_db
@old_email1 = 'old1@example.com'
@new_email1 = 'new1@example.com'
@extid1 = 'extid-change-email-001'
@account_id1 = @db1[:accounts].insert(
  email: @old_email1,
  external_id: @extid1,
  status_id: 2,
  created_at: Time.now,
  updated_at: Time.now
)
Auth::Operations::ChangeEmail.call(extid: @extid1, new_email: @new_email1, db: @db1)
@db1[:accounts].where(id: @account_id1).first[:email]
#=> @new_email1

## Returns { success: true, account_id: } on success
@db2 = build_test_sqlite_db
@extid2 = 'extid-change-email-002'
@account_id2 = @db2[:accounts].insert(
  email: 'old2@example.com',
  external_id: @extid2,
  status_id: 2,
  created_at: Time.now,
  updated_at: Time.now
)
result = Auth::Operations::ChangeEmail.call(extid: @extid2, new_email: 'new2@example.com', db: @db2)
[result[:success], result[:account_id]]
#=> [true, @account_id2]

## Clears account_active_session_keys rows for the account
@db3 = build_test_sqlite_db
@extid3 = 'extid-change-email-003'
@account_id3 = @db3[:accounts].insert(
  email: 'old3@example.com',
  external_id: @extid3,
  status_id: 2,
  created_at: Time.now,
  updated_at: Time.now
)
@db3[:account_active_session_keys].insert(
  account_id: @account_id3,
  session_id: 'sess-abc',
  created_at: Time.now,
  last_use: Time.now
)
before_count = @db3[:account_active_session_keys].where(account_id: @account_id3).count
Auth::Operations::ChangeEmail.call(extid: @extid3, new_email: 'new3@example.com', db: @db3)
after_count = @db3[:account_active_session_keys].where(account_id: @account_id3).count
[before_count, after_count]
#=> [1, 0]

## Clears account_login_change_keys rows for the account
@db4 = build_test_sqlite_db
@extid4 = 'extid-change-email-004'
@account_id4 = @db4[:accounts].insert(
  email: 'old4@example.com',
  external_id: @extid4,
  status_id: 2,
  created_at: Time.now,
  updated_at: Time.now
)
@db4[:account_login_change_keys].insert(
  id: @account_id4,
  key: 'pending-key',
  login: 'pending4@example.com',
  deadline: Time.now + 3600
)
before_count = @db4[:account_login_change_keys].where(id: @account_id4).count
Auth::Operations::ChangeEmail.call(extid: @extid4, new_email: 'new4@example.com', db: @db4)
after_count = @db4[:account_login_change_keys].where(id: @account_id4).count
[before_count, after_count]
#=> [1, 0]

## Returns { success: true, skipped: true } when no auth account found for extid
@db5 = build_test_sqlite_db
result = Auth::Operations::ChangeEmail.call(extid: 'extid-nonexistent-999', new_email: 'new5@example.com', db: @db5)
[result[:success], result[:skipped]]
#=> [true, true]

## Returns { success: false, error: } on database error (broken db)
broken_db = Object.new
def broken_db.table_exists?(_) = true
def broken_db.[](table)
  raise Sequel::Error, 'simulated DB failure'
end
def broken_db.transaction
  yield
rescue Sequel::Error
  raise
end
result = Auth::Operations::ChangeEmail.call(extid: 'extid-broken', new_email: 'x@example.com', db: broken_db)
[result[:success], result[:error].include?('simulated DB failure')]
#=> [false, true]
