# apps/web/auth/spec/operations/customers/diagnose_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::Customers::Diagnose.
#
# The SQL-backed sections run against a real in-memory SQLite schema (the
# same tables the Rodauth migrations create, minimally columned) rather than
# per-query doubles, so the actual Sequel query paths are exercised. The rate
# limiter Inspect op is stubbed at its boundary (it has its own spec).
#
# Read-only op — writes no audit event.
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/customers/diagnose_spec.rb

require 'spec_helper'
require 'auth/operations/customers/diagnose'

RSpec.describe Auth::Operations::Customers::Diagnose do
  let(:email) { 'user@example.com' }

  let(:customer) do
    instance_double(
      Onetime::Customer,
      exists?: true,
      extid: 'ur_target',
      email: email,
      role: 'customer',
      verified?: true,
      suspended?: false,
      suspended_at: nil,
      suspended_reason: nil,
      created: 1_700_000_000.0,
      last_login: 1_700_100_000.0,
      locale: 'en',
      planid: 'free_v1',
    )
  end

  # Minimal columns of every table the op touches (001_initial + 006/008).
  let(:db) do
    Sequel.sqlite.tap do |sqlite|
      sqlite.create_table(:accounts) do
        Integer :id
        Integer :status_id
        String :email
        String :external_id
        DateTime :created_at
      end
      sqlite.create_table(:account_password_hashes) { Integer :id }
      sqlite.create_table(:account_password_change_times) do
        Integer :id
        DateTime :changed_at
      end
      sqlite.create_table(:account_activity_times) do
        Integer :id
        DateTime :last_login_at
        DateTime :last_activity_at
      end
      sqlite.create_table(:account_identities) do
        Integer :account_id
        String :provider
        String :issuer
      end
      sqlite.create_table(:account_otp_keys) do
        Integer :id
        Integer :num_failures
      end
      sqlite.create_table(:account_webauthn_keys) { Integer :account_id }
      sqlite.create_table(:account_verification_keys) do
        Integer :id
        DateTime :requested_at
        DateTime :email_last_sent
      end
      sqlite.create_table(:account_password_reset_keys) do
        Integer :id
        DateTime :deadline
        DateTime :email_last_sent
      end
      sqlite.create_table(:account_login_failures) do
        Integer :id
        Integer :number
      end
      sqlite.create_table(:account_lockouts) do
        Integer :id
        DateTime :deadline
        DateTime :email_last_sent
      end
      sqlite.create_table(:account_active_session_keys) do
        Integer :account_id
        String :session_id
        DateTime :last_use
      end
      sqlite.create_table(:account_authentication_audit_logs) do
        Integer :id
        Integer :account_id
        DateTime :at
        String :message
        String :metadata
      end
    end
  end

  def insert_account(status_id: 2, with_password: true)
    db[:accounts].insert(
      id: 42,
      status_id: status_id,
      email: email,
      external_id: 'ur_target',
      created_at: Time.now - 86_400,
    )
    db[:account_password_hashes].insert(id: 42) if with_password
  end

  def limiter_result(entries)
    Onetime::Operations::RateLimit::Inspect::Result.new(
      kind: 'login', subject: email, entries: entries,
    )
  end

  def limiter_entry(key:, exists:, ttl: nil, value: nil)
    Onetime::Operations::RateLimit::Inspect::Entry.new(
      key: key, ttl: ttl, value: value, exists: exists,
    )
  end

  before do
    allow(Auth::Database).to receive(:connection).and_return(db)

    inspect_op = instance_double(Onetime::Operations::RateLimit::Inspect)
    allow(inspect_op).to receive(:call).and_return(limiter_result([]))
    allow(Onetime::Operations::RateLimit::Inspect).to receive(:new).and_return(inspect_op)
  end

  def diagnose(customer: nil, identifier: nil)
    described_class.new(customer: customer, identifier: identifier).call
  end

  def codes(result)
    result.findings.map { |finding| finding[:code] }
  end

  # =========================================================================
  describe 'existence' do
    it 'reports not_found when nothing resolves anywhere' do
      allow(Onetime::Customer).to receive_messages(load_by_extid_or_email: nil, load: nil)

      result = diagnose(identifier: 'ghost@example.com')

      expect(result.found?).to be(false)
      expect(codes(result)).to include(:not_found)
    end

    it 'diagnoses an orphaned auth account reached by email only' do
      allow(Onetime::Customer).to receive_messages(load_by_extid_or_email: nil, load: nil)
      insert_account

      result = diagnose(identifier: email)

      expect(result.found?).to be(true)
      expect(codes(result)).to include(:orphaned_auth_account)
    end

    it 'flags a customer with no auth account row' do
      result = diagnose(customer: customer)

      expect(codes(result)).to include(:missing_auth_account)
    end
  end

  # =========================================================================
  describe 'simple auth mode' do
    it 'degrades every SQL section instead of failing' do
      allow(Auth::Database).to receive(:connection).and_return(nil)

      result = diagnose(customer: customer)

      expect(result.found?).to be(true)
      expect(result.sections[:auth_account][:available]).to be(false)
      expect(result.sections[:audit_log][:available]).to be(false)
      expect(result.sections[:customer][:found]).to be(true)
    end
  end

  # =========================================================================
  describe 'healthy account' do
    it 'produces no findings and a populated read-out' do
      insert_account
      db[:account_activity_times].insert(id: 42, last_login_at: Time.now - 3600, last_activity_at: Time.now)

      result = diagnose(customer: customer)

      expect(result.findings).to eq([])
      account = result.sections[:auth_account]
      expect(account[:status]).to eq('verified')
      expect(account[:has_password]).to be(true)
      expect(account[:email_matches_customer]).to be(true)
      expect(result.sections[:lockout][:login_failures]).to eq(0)
    end
  end

  # =========================================================================
  describe 'verification states' do
    it 'flags unverified + a stale unclicked verification email' do
      insert_account(status_id: 1)
      db[:account_verification_keys].insert(
        id: 42, requested_at: Time.now - (3 * 86_400), email_last_sent: Time.now - (2 * 86_400),
      )

      result = diagnose(customer: customer)

      expect(codes(result)).to include(:unverified, :verification_stale)
    end

    it 'flags an unverified account whose verification key is gone' do
      insert_account(status_id: 1)

      result = diagnose(customer: customer)

      expect(codes(result)).to include(:verification_key_missing)
      expect(codes(result)).not_to include(:verification_stale)
    end
  end

  # =========================================================================
  describe 'lockout and rate limiting' do
    it 'flags an active Rodauth lockout as critical' do
      insert_account
      db[:account_login_failures].insert(id: 42, number: 7)
      db[:account_lockouts].insert(id: 42, deadline: Time.now + 3600, email_last_sent: Time.now)

      result = diagnose(customer: customer)

      expect(codes(result)).to include(:locked_out)
      expect(result.sections[:lockout][:locked]).to be(true)
    end

    it 'reports bare login failures as info when not locked' do
      insert_account
      db[:account_login_failures].insert(id: 42, number: 2)

      result = diagnose(customer: customer)

      finding = result.findings.find { |entry| entry[:code] == :login_failures }
      expect(finding[:severity]).to eq(:info)
    end

    it 'flags an engaged login rate limiter' do
      insert_account
      inspect_op = instance_double(Onetime::Operations::RateLimit::Inspect)
      allow(inspect_op).to receive(:call).and_return(
        limiter_result(
          [
            limiter_entry(key: "login:locked:#{email}", exists: true, ttl: 120, value: '9'),
          ],
        ),
      )
      allow(Onetime::Operations::RateLimit::Inspect).to receive(:new)
        .with(kind: 'login', subject: email).and_return(inspect_op)

      result = diagnose(customer: customer)

      expect(codes(result)).to include(:rate_limited)
    end
  end

  # =========================================================================
  describe 'credential shape' do
    it 'flags email drift between the customer and the accounts row' do
      db[:accounts].insert(
        id: 42,
        status_id: 2,
        email: 'other@example.com',
        external_id: 'ur_target',
        created_at: Time.now,
      )
      db[:account_password_hashes].insert(id: 42)

      result = diagnose(customer: customer)

      expect(codes(result)).to include(:email_drift)
      expect(result.sections[:auth_account][:email_matches_customer]).to be(false)
    end

    it 'reports SSO-only accounts as info, not a defect' do
      insert_account(with_password: false)
      db[:account_identities].insert(account_id: 42, provider: 'oidc', issuer: 'https://idp.example.com')

      result = diagnose(customer: customer)

      finding = result.findings.find { |entry| entry[:code] == :sso_only }
      expect(finding[:severity]).to eq(:info)
      expect(finding[:message]).to include('oidc')
    end

    it 'flags no-credential accounts (no password, no SSO) as a warning' do
      insert_account(with_password: false)

      result = diagnose(customer: customer)

      expect(codes(result)).to include(:no_password)
    end
  end

  # =========================================================================
  describe 'suspension' do
    it 'flags a suspended customer as critical' do
      allow(customer).to receive_messages(suspended?: true, suspended_reason: 'abuse')
      insert_account

      result = diagnose(customer: customer)

      finding = result.findings.find { |entry| entry[:code] == :suspended }
      expect(finding[:severity]).to eq(:critical)
      expect(finding[:message]).to include('abuse')
    end
  end

  # =========================================================================
  describe 'audit log' do
    it 'returns the newest entries first, bounded by the limit' do
      insert_account
      base = Time.now - 1000
      30.times do |index|
        db[:account_authentication_audit_logs].insert(
          id: index + 1, account_id: 42, at: base + index, message: "event_#{index}",
        )
      end

      result = described_class.new(customer: customer, audit_log_limit: 5).call

      entries = result.sections[:audit_log][:entries]
      expect(entries.size).to eq(5)
      expect(entries.first[:message]).to eq('event_29')
    end
  end

  # =========================================================================
  describe 'findings ordering' do
    it 'sorts critical findings ahead of warnings and info' do
      allow(customer).to receive_messages(suspended?: true, suspended_reason: nil)
      insert_account(status_id: 1, with_password: false)
      db[:account_identities].insert(account_id: 42, provider: 'oidc', issuer: '')
      db[:account_verification_keys].insert(id: 42, requested_at: Time.now, email_last_sent: Time.now)

      result = diagnose(customer: customer)

      severities = result.findings.map { |finding| finding[:severity] }
      expect(severities).to eq(severities.sort_by { |severity| described_class::SEVERITY_ORDER[severity] })
      expect(severities.first).to eq(:critical)
    end
  end
end
