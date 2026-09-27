# apps/web/auth/spec/integration/full/create_account_duplicate_race_spec.rb
#
# frozen_string_literal: true

# A sign-up that loses a race for its login answers exactly like an ordinary
# duplicate sign-up, which answers exactly like a fresh one (audit 2026-08-02
# M-2).
#
# POST /auth/create-account checks for an existing account before it inserts
# (before_create_account; verify_account's new_account check is bypassed on
# this route). A request that passes it while another sign-up for the same
# login is between its own checks and its commit reaches the INSERT and gets a
# unique violation. Stock Rodauth answers that with 422 and a field-error
# reading "already an account with this login": a different status and body
# from the ordinary duplicate, saying what the generic answer exists not to
# say. config/overrides/account_enumeration.rb (save_account) routes it
# through the ordinary answer: the same success a fresh sign-up gets.
#
# The race is produced two ways:
#
# - exactly: the winner's row is inserted from inside the loser's request,
#   after the loser's existence checks and before its INSERT. The same
#   statement order on every engine, so it runs the same on SQLite and
#   PostgreSQL (full-sqlite, full-pg, full-pg-agnostic lanes).
# - for real: several threads sign up with one login at once. On PostgreSQL
#   the losers reach the INSERT together; on the in-memory SQLite lane the
#   single pooled connection serializes them and the hook catches the loser.
#   Either way: one account, no 500, and every sign-up gets the same answer.
#
# The 500s that concurrent sign-ups produced on a file-backed SQLite authdb
# are a connection-settings defect, covered in authdb_sqlite_concurrency_spec.rb.
#
# RUN:
#   tests/lanes/run full-sqlite --only apps/web/auth/spec/integration/full/create_account_duplicate_race_spec.rb

require_relative '../../spec_helper'
require 'rack/test'
require 'securerandom'

RSpec.describe 'A sign-up that loses a race answers like an ordinary duplicate', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    boot_onetime_app
  end

  let(:db) { Auth::Database.connection }
  let(:password) { 'Race-Test1234!xyz' }
  let(:login) { "signup-race-#{SecureRandom.hex(6)}@example.com" }

  before do
    skip 'Auth database not configured (run with AUTH_DATABASE_URL set)' unless defined?(Auth::Database) && db

    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw).and_return(true)
    @created_emails = [login]
  end

  after do
    Array(@created_emails).each do |email|
      purge_account(email)
      Onetime::Customer.find_by_email(email)&.destroy!
    rescue StandardError => ex
      warn "[signup race spec] cleanup failed for #{email}: #{ex.message}"
    end
  end

  def purge_account(email)
    row = db[:accounts].where(email: email).first
    return unless row

    db.tables.each do |table|
      next if table == :accounts

      db.foreign_key_list(table).each do |fk|
        next unless fk[:table].to_s == 'accounts'

        db[table].where(fk[:columns].first => row[:id]).delete
      end
    rescue Sequel::Error
      next
    end

    db[:accounts].where(id: row[:id]).delete
  end

  # One sign-up from a browser of its own: fresh session, fresh CSRF token.
  # Its own Rack::Test session, so it is safe to call from several threads.
  def sign_up(email)
    browser = Rack::Test::Session.new(Rack::MockSession.new(app))
    browser.header 'Accept', 'application/json'
    browser.get '/auth'
    token = browser.last_response.headers['X-CSRF-Token']

    browser.header 'Content-Type', 'application/json'
    browser.header 'X-CSRF-Token', token if token
    browser.post '/auth/create-account', JSON.generate(
      login: email,
      'login-confirm' => email,
      password: password,
      'password-confirm' => password,
      shrimp: token,
    )
    answer(browser.last_response)
  end

  # Everything a caller can tell two responses apart by.
  def answer(response)
    body = JSON.parse(response.body)
    body.delete('request_id')
    { status: response.status, body: body }
  end

  # Make the next sign-up lose: the winner's row appears after the loser's
  # existence checks (Customer.email_exists? is the last of them) and before
  # its INSERT.
  def lose_race_to(status_id)
    inserted = false
    allow(Onetime::Customer).to receive(:email_exists?).and_wrap_original do |original, email|
      exists = original.call(email)
      unless inserted || exists
        inserted = true
        db[:accounts].insert(email: email, status_id: status_id)
      end
      exists
    end
  end

  # A sign-up for a login nobody has, answered by creating its account.
  def fresh_sign_up
    fresh = "signup-fresh-#{SecureRandom.hex(6)}@example.com"
    @created_emails << fresh
    sign_up(fresh)
  end

  { 1 => 'an unverified', 2 => 'a verified' }.each do |status_id, label|
    it "answers the loser exactly like an ordinary duplicate when the winner is #{label} account", :aggregate_failures do
      lose_race_to(status_id)
      lost     = sign_up(login)
      ordinary = sign_up(login) # the row exists now, so the wrapper above stays out of it

      expect(lost).to eq(ordinary)
      expect(lost).to eq(fresh_sign_up)
      expect(lost[:status]).to eq(200)
      expect(lost[:body].to_s).not_to match(/already|field-error/i)
      expect(db[:accounts].where(email: login).count).to eq(1)
    end
  end

  it 'answers a sign-up for an unverified account exactly like one for a verified account', :aggregate_failures do
    verified = "signup-verified-#{SecureRandom.hex(6)}@example.com"
    @created_emails << verified
    db[:accounts].insert(email: login, status_id: 1)
    db[:accounts].insert(email: verified, status_id: 2)

    expect(sign_up(login)).to eq(sign_up(verified))
    expect(sign_up(login)).to eq(fresh_sign_up)
    expect(sign_up(login)[:status]).to eq(200)
  end

  it 'logs an ordinary duplicate at info and keeps the error for an account with no customer record', :aggregate_failures do
    events = []
    allow(Auth::Logging).to receive(:log_auth_event).and_wrap_original do |original, event, **fields|
      events << [event, fields[:level]]
      original.call(event, **fields)
    end

    expect(sign_up(login)[:status]).to eq(200)
    sign_up(login)
    expect(events).to include([:registration_blocked_existing_account, :info])
    expect(events.map(&:first)).not_to include(:registration_blocked_auth_db_conflict)

    orphan = "signup-orphan-#{SecureRandom.hex(6)}@example.com"
    @created_emails << orphan
    db[:accounts].insert(email: orphan, status_id: 2)
    sign_up(orphan)
    expect(events).to include([:registration_blocked_auth_db_conflict, :error])
  end

  it 'answers a duplicate with the ordinary answer when Redis is unreachable', :aggregate_failures do
    db[:accounts].insert(email: login, status_id: 2)
    ordinary = sign_up(login)

    events = []
    allow(Auth::Logging).to receive(:log_auth_event).and_wrap_original do |original, event, **fields|
      events << [event, fields[:level], fields[:customer_lookup_error]]
      original.call(event, **fields)
    end
    allow(Onetime::Customer).to receive(:email_exists?).and_raise(Redis::CannotConnectError, 'redis down')

    expect(sign_up(login)).to eq(ordinary)
    expect(ordinary[:status]).to eq(200)
    expect(events).to include([:registration_blocked_existing_account, :warn, 'Redis::CannotConnectError'])
    expect(events.map(&:first)).not_to include(:registration_blocked_auth_db_conflict)
  end

  it 'never answers 500, creates one account, and gives every sign-up the same answer', :aggregate_failures do
    answers  = Array.new(6) { Thread.new { sign_up(login) } }.map(&:value)
    ordinary = sign_up(login)

    expect(answers.map { |a| a[:status] }).not_to include(500)
    expect(answers.uniq).to eq([ordinary])
    expect(ordinary[:status]).to eq(200)
    expect(db[:accounts].where(email: login).count).to eq(1)
  end
end
