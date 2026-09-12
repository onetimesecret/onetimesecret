# apps/web/auth/spec/operations/sync_session_recreate_customer_spec.rb
#
# frozen_string_literal: true

# Unit tests for the rare SyncSession branch where login finds a Rodauth
# accounts row but NO Customer record, and the op has to recreate one.
#
# The point under test is PROVENANCE. The recreated Customer must carry a
# verified/verified_by pair derived from state the auth database still
# holds, mirroring how the record would originally have been created — and
# never a bare status_id mirror: with verify_account disabled every password
# account sits at VERIFIED in SQL, so status alone proves nothing about how
# the address was established (the reason the first attempt at #3973 was
# rejected). The derivation order is:
#
#   status_id != VERIFIED          -> unverified, verified_by nil
#   account_identities row exists  -> 'sso'
#   verify_account enabled         -> 'email'
#   otherwise                      -> 'autoverify'
#   any lookup raises              -> unverified (fail closed) + error log
#
# The identity lookup runs against a REAL migrated SQLite schema so the query
# is exercised against the actual account_identities table; the creation
# itself is delegated to EnsureCustomerForAccount, which is stubbed here and
# has its own contract pinned in omniauth_account_creation_spec.rb.
#
# Run: tests/lanes/run unit --only apps/web/auth/spec/operations/sync_session_recreate_customer_spec.rb

require 'spec_helper'

require 'fileutils'
require 'securerandom'
require 'tmpdir'

require 'auth/account_statuses'
require 'auth/database'
require 'auth/lib/logging'
require 'auth/operations/sync_session'

RSpec.describe Auth::Operations::SyncSession, 'recreating a missing Customer at login' do
  # Same structural-migrations-only setup as set_customer_verification_sql_spec.rb:
  # stop before the first data migration, which reaches for the live Familia
  # connection. account_identities (migration 006, re-keyed by 008) is
  # structural and lands inside that range.
  before(:context) do
    Sequel.extension :migration

    migrations_dir = File.join(Onetime::HOME, 'apps', 'web', 'auth', 'migrations')
    data_migration = Dir.glob(File.join(migrations_dir, '[0-9]*_normalize_customer_emails.rb')).first
    raise 'normalize_customer_emails data migration not found — update this spec' unless data_migration

    structural_target = File.basename(data_migration)[/\A\d+/].to_i - 1

    @db_file = File.join(Dir.tmpdir, "test_auth_#{SecureRandom.hex(4)}.db")
    @db      = Sequel.connect("sqlite://#{@db_file}")
    Sequel::Migrator.run(@db, migrations_dir, target: structural_target, use_transactions: true)
  end

  after(:context) do
    @db.disconnect
    FileUtils.rm_f(@db_file)
  end

  let(:db)        { @db }
  let(:email)     { 'recovered@example.com' }
  let(:status_id) { Auth::AccountStatuses::VERIFIED }
  let(:account_id) { db[:accounts].insert(email: email, status_id: status_id) }
  let(:account)    { { id: account_id, email: email, status_id: status_id, external_id: nil } }
  let(:session)    { { 'session_id' => 'sess_recovery' } }
  let(:request)    { double('Request', ip: '203.0.113.7', user_agent: 'rspec') }

  let(:auth_config) { double('AuthConfig', verify_account_enabled?: true) }
  let(:customer)    { double('Customer', custid: 'cust_recovered', extid: 'ur_recovered') }
  let(:ensure_op)   { instance_double(Auth::Operations::EnsureCustomerForAccount, call: customer) }

  let(:op) do
    described_class.new(
      account: account,
      account_id: account_id,
      session: session,
      request: request,
      correlation_id: 'corr_recovery',
      db: db,
    )
  end

  before do
    db[:account_identities].delete
    db[:accounts].delete

    allow(Onetime).to receive(:auth_config).and_return(auth_config)
    allow(Auth::Operations::EnsureCustomerForAccount).to receive(:new).and_return(ensure_op)
    allow(Auth::Logging).to receive(:log_operation)
    allow(Auth::Logging).to receive(:log_error)
  end

  def add_sso_identity(account_id)
    db[:account_identities].insert(account_id: account_id, provider: 'oidc', uid: "uid-#{account_id}")
  end

  def recreate
    op.send(:recreate_customer)
  end

  def expect_recreated_with(verified:, verified_by:)
    expect(Auth::Operations::EnsureCustomerForAccount).to have_received(:new).with(
      account_id: account_id,
      account: account,
      db: db,
      provisioning_origin: 'login_recovery',
      verified: verified,
      verified_by: verified_by,
    )
    expect(ensure_op).to have_received(:call)
  end

  describe 'derived provenance' do
    it "stamps 'sso' when the account holds an account_identities row" do
      add_sso_identity(account_id)

      expect(recreate).to be(customer)
      expect_recreated_with(verified: true, verified_by: 'sso')
      # An SSO identity settles it: the verify_account flag is not consulted.
      expect(auth_config).not_to have_received(:verify_account_enabled?)
    end

    it "stamps 'email' for a password account when verify_account is enabled" do
      expect(recreate).to be(customer)
      expect_recreated_with(verified: true, verified_by: 'email')
    end

    it "stamps 'autoverify' for a password account when verify_account is disabled" do
      allow(auth_config).to receive(:verify_account_enabled?).and_return(false)

      expect(recreate).to be(customer)
      expect_recreated_with(verified: true, verified_by: 'autoverify')
    end

    context 'when the accounts row is Unverified' do
      let(:status_id) { Auth::AccountStatuses::UNVERIFIED }

      it 'recreates the customer unverified with no provenance, whatever else is true' do
        add_sso_identity(account_id)

        expect(recreate).to be(customer)
        expect_recreated_with(verified: false, verified_by: nil)
        expect(auth_config).not_to have_received(:verify_account_enabled?)
      end
    end
  end

  describe 'fail closed' do
    it 'recreates the customer UNVERIFIED and logs when the identity lookup raises' do
      allow(db).to receive(:[]).and_call_original
      allow(db).to receive(:[]).with(:account_identities).and_raise(Sequel::DatabaseError, 'boom')

      expect(recreate).to be(customer)
      expect_recreated_with(verified: false, verified_by: nil)
      expect(Auth::Logging).to have_received(:log_error).with(
        :customer_recreate_provenance_failed,
        hash_including(account_id: account_id, fallback: 'unverified', correlation_id: 'corr_recovery'),
      )
    end

    it 'recreates the customer UNVERIFIED when the auth config lookup raises' do
      allow(auth_config).to receive(:verify_account_enabled?).and_raise(StandardError, 'config down')

      expect(recreate).to be(customer)
      expect_recreated_with(verified: false, verified_by: nil)
      expect(Auth::Logging).to have_received(:log_error)
        .with(:customer_recreate_provenance_failed, hash_including(account_id: account_id))
    end
  end

  describe 'observability' do
    it 'logs the recreation at WARN with the derived provenance' do
      add_sso_identity(account_id)
      recreate

      expect(Auth::Logging).to have_received(:log_operation).with(
        :customer_recreated_at_login,
        hash_including(
          level: :warn,
          account_id: account_id,
          customer_id: 'cust_recovered',
          external_id: 'ur_recovered',
          provisioning_origin: 'login_recovery',
          verified: true,
          verified_by: 'sso',
          correlation_id: 'corr_recovery',
        ),
      )
    end

    it 'stamps a provisioning_origin from the model vocabulary' do
      expect(Onetime::Customer::PROVISIONING_ORIGINS)
        .to include(described_class::RECOVERY_PROVISIONING_ORIGIN)
    end

    it 'only ever derives verified_by tags from the enforced vocabulary' do
      expect(Onetime::Customer::VERIFIED_BY_VALUES).to include('sso', 'email', 'autoverify')
    end
  end

  describe 'wiring through #ensure_customer_exists' do
    before do
      allow(Onetime::Customer).to receive(:find_by_extid).and_return(nil)
    end

    it 'recreates when no Customer is found and leaves linking to EnsureCustomerForAccount' do
      allow(Onetime::Customer).to receive(:find_by_email).and_return(nil)

      expect(op.send(:ensure_customer_exists)).to be(customer)
      expect_recreated_with(verified: true, verified_by: 'email')
      # The stubbed op did not link, and SyncSession must not have issued its
      # own link-on-login UPDATE on top of the delegated creation.
      expect(db[:accounts].where(id: account_id).get(:external_id)).to be_nil
    end

    it 'falls back to the index retry (and links) when the email index was merely lagging' do
      allow(ensure_op).to receive(:call).and_raise(Familia::RecordExistsError, 'customer:exists')
      # First lookup (find_existing_customer) misses; the retry converges.
      allow(Onetime::Customer).to receive(:find_by_email).and_return(nil, customer)

      expect(op.send(:ensure_customer_exists)).to be(customer)
      expect(db[:accounts].where(id: account_id).get(:external_id)).to eq('ur_recovered')
    end
  end
end
