# apps/web/auth/spec/integration/full/authdb_sqlite_concurrency_spec.rb
#
# frozen_string_literal: true

# Concurrent writers on a file-backed SQLite authdb wait for each other
# instead of failing.
#
# Reproduced against a running server: 8 parallel POST /auth/create-account on
# `sqlite://tmp/...db` answered one 200 and seven 500s, each
# `SQLite3::BusyException: database is locked` on the accounts INSERT.
# Auth::Database.connect documents the two causes. This spec drives the
# statement pattern that failed (a read, then an INSERT, inside one
# transaction, from several threads) through the connection the application
# really opens, on a real file: an in-memory database has one pooled
# connection and cannot contend with itself, which is why no lane saw this.
#
# The suite stubs Auth::Database.connection; .connect is not stubbed, so this
# is the production configuration under test.

require_relative '../../spec_helper'
require 'tmpdir'
require 'auth/database'

RSpec.describe 'Auth::Database.connect on a file-backed SQLite authdb', type: :integration do
  around do |example|
    Dir.mktmpdir('authdb-concurrency') do |dir|
      @path = File.join(dir, 'auth.db')
      example.run
    end
  end

  let(:db) { Auth::Database.connect("sqlite://#{@path}") }

  before do
    db.create_table(:accounts) do
      primary_key :id
      String :email, null: false, unique: true
    end
  end

  after { db.disconnect }

  # What create-account does, in the order it does it, held open long enough
  # for every thread to be inside its transaction at once.
  def sign_up(email)
    db.transaction do
      db[:accounts].where(email: email).first
      sleep 0.05
      db[:accounts].insert(email: email)
    end
    :created
  rescue Sequel::UniqueConstraintViolation
    :duplicate
  end

  it 'opens transactions in IMMEDIATE mode, where waiting for the write lock is safe' do
    expect(db.transaction_mode).to eq(:immediate)
  end

  # The wait has to release the GVL (busy_handler_timeout=, not Sequel's
  # :timeout alone): otherwise the thread that holds the lock cannot run to
  # release it, and every waiter burns the whole timeout and then fails.
  it 'lets concurrent sign-ups for different logins all succeed, without burning the timeout', :aggregate_failures do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    results = Array.new(6) { |i| Thread.new { sign_up("writer-#{i}@example.com") } }.map(&:value)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    expect(results).to all(eq(:created))
    expect(db[:accounts].count).to eq(6)
    # Six 50 ms transactions in a queue. The defect cost one full busy
    # timeout (5 s) per waiter before failing.
    expect(elapsed).to be < (Auth::Database::SQLITE_BUSY_TIMEOUT_MS / 1000.0)
  end

  it 'turns concurrent sign-ups for one login into one row and unique violations, never a lock error' do
    results = Array.new(6) { Thread.new { sign_up('same@example.com') } }.map(&:value)

    expect(results.tally).to eq(created: 1, duplicate: 5)
  end

  it 'leaves a PostgreSQL connection hash alone' do
    # Only this one call is intercepted: the PostgreSQL lanes' own cleanup
    # hooks connect through Sequel too.
    target = { adapter: 'postgres', host: 'authdb.invalid', database: 'authdb' }
    allow(Sequel).to receive(:connect).and_call_original
    allow(Sequel).to receive(:connect).with(target, anything)
      .and_return(instance_double(Sequel::Database, extension: nil))

    Auth::Database.connect(target)

    expect(Sequel).to have_received(:connect).with(target, hash_excluding(:timeout, :after_connect))
  end
end
