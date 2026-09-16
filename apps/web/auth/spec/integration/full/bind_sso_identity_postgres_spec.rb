# frozen_string_literal: true

require_relative '../../spec_helper'
require 'thread'
require 'auth/operations/bind_sso_identity'

RSpec.describe Auth::Operations::BindSsoIdentity,
  :postgres_database, type: :integration do
  def run_concurrent_binds(account_ids:, tuple:)
    ready   = Queue.new
    start   = Queue.new
    results = Queue.new
    threads = account_ids.map do |account_id|
      Thread.new do
        ready << true
        start.pop
        outcome = described_class.call(db: test_db, account_id: account_id, **tuple)
        results << outcome
      rescue StandardError => ex
        results << ex
      end
    end

    account_ids.size.times { ready.pop }
    account_ids.size.times { start << true }
    joined = threads.map { |thread| !thread.join(10).nil? }.all?
    threads.each(&:kill) unless joined
    raise 'Concurrent BindSsoIdentity writers timed out' unless joined

    values = account_ids.size.times.map { results.pop }
    error  = values.find { |value| value.is_a?(Exception) }
    raise error if error

    values
  end

  def create_account(label)
    create_verified_account(
      db: setup_db,
      email: "bind-race-#{label}-#{SecureRandom.hex(8)}@example.com",
    )
  end

  after do
    next unless PostgresModeSuiteDatabase.postgres_available?

    test_db[:account_identities].where(provider: 'race-oidc').delete
  end

  it 'leaves one row and returns two idempotent successes for same-account writers' do
    account = create_account('same')
    tuple   = {
      provider: 'race-oidc',
      issuer: "https://issuer-#{SecureRandom.hex(8)}.example.com",
      uid: "sub-#{SecureRandom.hex(12)}",
    }

    outcomes = run_concurrent_binds(account_ids: [account[:id], account[:id]], tuple: tuple)

    expect(outcomes).to contain_exactly(:ok, :ok)
    expect(test_db[:account_identities].where(tuple).all)
      .to contain_exactly(hash_including(account_id: account[:id]))
  end

  it 'leaves one row with one success and one conflict for different-account writers' do
    first  = create_account('first')
    second = create_account('second')
    tuple  = {
      provider: 'race-oidc',
      issuer: "https://issuer-#{SecureRandom.hex(8)}.example.com",
      uid: "sub-#{SecureRandom.hex(12)}",
    }

    outcomes = run_concurrent_binds(account_ids: [first[:id], second[:id]], tuple: tuple)

    expect(outcomes).to contain_exactly(:ok, :conflict)
    rows = test_db[:account_identities].where(tuple).all
    expect(rows.size).to eq(1)
    expect([first[:id], second[:id]]).to include(rows.first[:account_id])
  end
end
