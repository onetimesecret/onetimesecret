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

  def finding(result, code)
    result.findings.find { |entry| entry[:code] == code }
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

    # An orphaned account is only reachable by email if the operator HAS the
    # email. Support is usually handed an extid or the numeric account id from
    # a log line, and neither resolves to a Customer for an orphan.
    it 'diagnoses an orphaned auth account reached by extid only' do
      allow(Onetime::Customer).to receive_messages(load_by_extid_or_email: nil, load: nil)
      insert_account

      result = diagnose(identifier: 'ur_target')

      expect(result.found?).to be(true)
      expect(codes(result)).to include(:orphaned_auth_account)
      expect(result.sections[:auth_account][:account_id]).to eq(42)
    end

    it 'diagnoses an orphaned auth account reached by numeric account id' do
      allow(Onetime::Customer).to receive_messages(load_by_extid_or_email: nil, load: nil)
      insert_account

      result = diagnose(identifier: '42')

      expect(result.found?).to be(true)
      expect(codes(result)).to include(:orphaned_auth_account)
      expect(result.sections[:auth_account][:account_id]).to eq(42)
    end

    # A numeric identifier must never bind a RESOLVED customer to an unrelated
    # accounts row that merely happens to carry that id.
    it 'does not attach an unrelated accounts row to a resolved customer' do
      insert_account
      # Neither existing arm can reach account 42 for this customer, so only the
      # numeric arm could — and it must not fire once a customer has resolved.
      allow(customer).to receive_messages(extid: 'ur_other', email: 'other@example.com')

      result = diagnose(customer: customer, identifier: '42')

      expect(codes(result)).to include(:missing_auth_account)
      expect(result.sections[:auth_account][:found]).to be(false)
    end
  end

  # =========================================================================
  describe 'authdb unavailable' do
    # The connection is LAZY, so an unreachable database surfaces as a raising
    # query rather than a nil connection.
    let(:failing_db) do
      instance_double(Sequel::Database).tap do |double|
        allow(double).to receive(:[])
          .and_raise(Sequel::DatabaseConnectionError, 'could not connect to server')
      end
    end

    it 'reports authdb_unavailable instead of not_found when the query fails' do
      allow(Auth::Database).to receive(:connection).and_return(failing_db)
      allow(Onetime::Customer).to receive_messages(load_by_extid_or_email: nil, load: nil)

      result = diagnose(identifier: 'ghost@example.com')

      expect(codes(result)).to include(:authdb_unavailable)
      expect(codes(result)).not_to include(:not_found)
      expect(result.sections[:auth_account][:reason_code]).to eq(:authdb_error)
    end

    it 'still reports authdb_unavailable when the customer does resolve' do
      allow(Auth::Database).to receive(:connection).and_return(failing_db)

      result = diagnose(customer: customer)

      expect(codes(result)).to include(:authdb_unavailable)
      expect(codes(result)).not_to include(:missing_auth_account)
    end

    # A sidecar query can fail AFTER the accounts row was read, degrading the
    # auth_account section and taking `found: true` with it. Reporting
    # "no such account" for a row just held is the same wrong instruction.
    it 'does not report not_found when a sidecar query degrades the section' do
      allow(Onetime::Customer).to receive_messages(load_by_extid_or_email: nil, load: nil)
      insert_account
      db.drop_table(:account_identities)

      result = diagnose(identifier: email)

      expect(codes(result)).to include(:authdb_unavailable)
      expect(codes(result)).not_to include(:not_found)
      # :authdb_unavailable is the whole story here; naming the same failure
      # again as missing evidence would just pad the summary.
      expect(codes(result)).not_to include(:evidence_incomplete)
    end

    # A whole-authdb failure degrades every section at once. :authdb_unavailable
    # already tells the operator the database did not answer, so the
    # partial-evidence finding must not restate it section by section.
    it 'does not add a second evidence finding when the whole authdb is down' do
      allow(Auth::Database).to receive(:connection).and_return(failing_db)

      result = diagnose(customer: customer)

      expect(codes(result).count(:authdb_unavailable)).to eq(1)
      expect(codes(result)).not_to include(:evidence_incomplete)
    end

    # An identifier wider than bigint cannot be a row id, and asking PG raises —
    # which would surface a typo as a critical "the database is down".
    it 'treats an out-of-range numeric identifier as simply not found' do
      allow(Onetime::Customer).to receive_messages(load_by_extid_or_email: nil, load: nil)
      insert_account

      result = diagnose(identifier: '9' * 25)

      expect(codes(result)).to include(:not_found)
      expect(codes(result)).not_to include(:authdb_unavailable)
    end
  end

  # =========================================================================
  # Sections degrade INDEPENDENTLY of one another: `auth_account` is read first
  # and can succeed while a later sidecar query fails (dropped or ungranted
  # table, statement timeout, connection lost mid-read), and the limiter is a
  # different datastore entirely. Every other check returns silently on an
  # unavailable section, so a partial outage used to produce `findings == []` —
  # a green "auth state looks healthy" over four failed reads.
  describe 'partial evidence' do
    # A narrow Valkey fault (WRONGTYPE, an unknown registry kind, an ACL
    # restriction) — not a full outage, which would break customer resolution
    # first and be reported by other means.
    let(:failing_limiter) do
      instance_double(Onetime::Operations::RateLimit::Inspect).tap do |double|
        allow(double).to receive(:call).and_raise(StandardError, 'Valkey::CommandError: WRONGTYPE')
      end
    end

    it 'names the sections that could not be read while the accounts row is fine' do
      insert_account
      db.drop_table(:account_lockouts)
      db.drop_table(:account_active_session_keys)

      result = diagnose(customer: customer)

      expect(result.sections[:auth_account][:available]).to be(true)
      entry = finding(result, :evidence_incomplete)
      expect(entry[:severity]).to eq(:warning)
      expect(entry[:message]).to include('lockout', 'sessions')
    end

    # The limiter is Redis-backed, so it degrades without the authdb being
    # involved at all — and an engaged limiter is itself a login blocker, which
    # makes an unread limiter a real hole in the verdict.
    it 'names the limiter when its inspection fails' do
      insert_account
      allow(Onetime::Operations::RateLimit::Inspect).to receive(:new).and_return(failing_limiter)

      result = diagnose(customer: customer)

      expect(finding(result, :evidence_incomplete)[:message]).to include('rate_limits')
    end

    # The limiter lives in a different datastore from the authdb, so authdb
    # health cannot gate this check. In simple mode the limiter is one of only
    # TWO login blockers that exist and nothing else fires to compensate, so a
    # narrow Valkey fault here would otherwise read as a healthy account.
    it 'reports an independently-failed limiter in simple auth mode' do
      allow(Auth::Database).to receive(:connection).and_return(nil)
      allow(Onetime::Operations::RateLimit::Inspect).to receive(:new).and_return(failing_limiter)

      result = diagnose(customer: customer)

      expect(finding(result, :evidence_incomplete)[:message]).to include('rate_limits', 'WRONGTYPE')
      expect(codes(result)).not_to include(:authdb_unavailable)
    end

    # The customer record is the one section present in EVERY auth mode, and
    # suspension — which it alone carries — is a hard login blocker.
    # check_customer_state reads a failed `suspended` as nil and returns
    # silently, so "not suspended" and "we could not tell" look identical.
    it 'names the customer section when its read fails' do
      insert_account
      allow(customer).to receive(:suspended?).and_raise(StandardError, 'Redis::TimeoutError')

      result = diagnose(customer: customer)

      expect(finding(result, :evidence_incomplete)[:message]).to include('customer', 'Redis::TimeoutError')
      # `error` is the wire contract the colonel panel renders — normalizing the
      # rescue onto available:/reason: must not drop it.
      expect(result.sections[:customer][:error]).to include('Redis::TimeoutError')
    end

    # An orphan reached by extid resolves to no Customer, so the op never learns
    # an address and there is no limiter key to look up. Nothing failed — firing
    # here would put a warning on every orphan-by-extid/by-id lookup and point
    # support at a healthy database.
    it 'stays silent for an orphan with no address to rate-limit' do
      allow(Onetime::Customer).to receive_messages(load_by_extid_or_email: nil, load: nil)
      insert_account

      result = diagnose(identifier: 'ur_target')

      expect(codes(result)).to include(:orphaned_auth_account)
      expect(codes(result)).not_to include(:evidence_incomplete)
      expect(result.sections[:rate_limits][:reason_code]).to eq(:no_email)
    end

    # With no accounts row the sidecars have nothing to query — a by-design
    # degradation the existence findings already explain, not missing evidence.
    it 'stays silent for the by-design no-account degradation' do
      result = diagnose(customer: customer)

      expect(codes(result)).to include(:missing_auth_account)
      expect(codes(result)).not_to include(:evidence_incomplete)
    end

    it 'stays silent when every section reads' do
      insert_account

      expect(codes(diagnose(customer: customer))).not_to include(:evidence_incomplete)
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
      expect(result.sections[:auth_account][:reason_code]).to eq(:simple_mode)
    end

    # The mirror of the authdb_unavailable case: with no authdb BY DESIGN the
    # Redis customer record is the whole truth, so :not_found is the correct
    # verdict here and must not be swallowed by the unknowable-existence guard.
    it 'still reports not_found for an identifier that resolves to nothing' do
      allow(Auth::Database).to receive(:connection).and_return(nil)
      allow(Onetime::Customer).to receive_messages(load_by_extid_or_email: nil, load: nil)

      result = diagnose(identifier: 'ghost@example.com')

      expect(codes(result)).to include(:not_found)
      expect(codes(result)).not_to include(:authdb_unavailable)
    end

    # Nothing failed: there is no authdb to read. Reporting missing evidence
    # here would put a permanent warning on every simple-mode deployment.
    it 'adds no evidence-incomplete finding for the absent authdb' do
      allow(Auth::Database).to receive(:connection).and_return(nil)

      result = diagnose(customer: customer)

      expect(codes(result)).not_to include(:evidence_incomplete)
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

    it 'parses JSON metadata so the evidence is not one escaped blob' do
      insert_account
      db[:account_authentication_audit_logs].insert(
        id: 1,
        account_id: 42,
        at: Time.now,
        message: 'login_failure',
        metadata: '{"email":"u***r@example.com","ip":"10.0.0.0"}',
      )

      result = diagnose(customer: customer)

      expect(result.sections[:audit_log][:entries].first[:metadata]).to eq(
        { 'email' => 'u***r@example.com', 'ip' => '10.0.0.0' },
      )
    end

    it 'keeps non-JSON metadata verbatim' do
      insert_account
      db[:account_authentication_audit_logs].insert(
        id: 1, account_id: 42, at: Time.now, message: 'login', metadata: 'legacy plain text',
      )

      result = diagnose(customer: customer)

      expect(result.sections[:audit_log][:entries].first[:metadata]).to eq('legacy plain text')
    end

    # Sequel's pg_json JSONArray is NOT an Array (it delegates to one) yet
    # answers to_h, on which it raises TypeError — which would degrade the whole
    # audit_log section. Detection goes through the implicit-conversion
    # protocols so both the wrapper and a bare Array survive.
    describe 'json flattening' do
      subject(:flatten) { described_class.new(identifier: email).method(:plain_json) }

      let(:array_wrapper) do
        Class.new do
          def initialize(inner) = @inner = inner
          def to_ary = @inner

          # Raises TypeError for scalar elements — the trap being guarded.
          def to_h = @inner.to_h
        end
      end

      it 'flattens a bare JSON array without raising' do
        expect(flatten.call([1, 2, 3])).to eq([1, 2, 3])
      end

      it 'flattens an array-like wrapper via to_ary rather than to_h' do
        expect(flatten.call(array_wrapper.new([1, 2, 3]))).to eq([1, 2, 3])
      end

      it 'recurses into nested arrays inside a hash' do
        expect(flatten.call({ 'scopes' => [1, 2] })).to eq({ 'scopes' => [1, 2] })
      end

      # Only the column value is an encoded document; a decoded field that
      # merely looks like JSON is data and must keep its type.
      it 'does not re-decode a nested string that parses as JSON' do
        expect(flatten.call({ 'user_agent' => '42' })).to eq({ 'user_agent' => '42' })
      end

      it 'passes nil through' do
        expect(flatten.call(nil)).to be_nil
      end
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
