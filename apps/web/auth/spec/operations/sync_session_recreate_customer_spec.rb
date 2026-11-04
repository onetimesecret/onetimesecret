# apps/web/auth/spec/operations/sync_session_recreate_customer_spec.rb
#
# frozen_string_literal: true

# Unit tests for the rare SyncSession branch where login finds a Rodauth
# accounts row but NO Customer record, and the op has to recreate one.
#
# The point under test is PROVENANCE. The recreated Customer must carry a
# verified/verified_by pair derived from state the auth database still has,
# mirroring how the record would originally have been created, and never a
# bare status_id mirror: with verify_account disabled every password account
# sits at VERIFIED in SQL, so status alone proves nothing about how the
# address was established (the reason the first attempt at #3973 was
# rejected). Only recorded state decides the tag, never today's config.
# The derivation order is:
#
#   status_id != VERIFIED          -> unverified, verified_by nil
#   account_identities row exists  -> 'sso'
#   otherwise                      -> 'legacy' (never mailbox proof, #4735)
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
require 'auth/operations/ensure_customer_for_account'
require 'auth/operations/sync_session'

RSpec.describe Auth::Operations::SyncSession, 'recreating a missing Customer at login' do
  # Same structural-migrations-only setup as set_customer_verification_sql_spec.rb:
  # stop before the first data migration, which reaches for the live Familia
  # connection. account_identities (migration 006, re-keyed by 008) is
  # structural and sits inside that range.
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

  let(:db) { @db }
  let(:verify_account) { false }
  let(:status_id) { Auth::AccountStatuses::VERIFIED }
  let(:email) { "recover-#{SecureRandom.hex(4)}@example.com" }
  let(:account_id) { db[:accounts].insert(email: email, status_id: status_id) }
  let(:account) { db[:accounts].where(id: account_id).first }
  let(:request) { double('Request', ip: '203.0.113.7', user_agent: 'rspec') }
  let(:auth_config) { double('AuthConfig', verify_account_enabled?: verify_account) }
  let(:created) { double('Customer', custid: 'cust_new', extid: 'ur_new') }
  let(:ensure_op) { instance_double(Auth::Operations::EnsureCustomerForAccount, call: created) }

  let(:op) do
    described_class.new(
      account: account,
      account_id: account_id,
      session: {},
      request: request,
      correlation_id: 'corr_1',
      db: db,
    )
  end

  before do
    allow(Onetime).to receive(:auth_config).and_return(auth_config)
    allow(Auth::Logging).to receive(:log_operation)
    allow(Auth::Logging).to receive(:log_error)
    allow(Auth::Operations::EnsureCustomerForAccount).to receive(:new).and_return(ensure_op)
  end

  # Schema here is pre-008 (structural target stops before the data
  # migration), so no issuer column; the op only filters on account_id.
  def add_sso_identity!
    db[:account_identities].insert(
      account_id: account_id,
      provider: 'oidc',
      uid: SecureRandom.hex(6),
    )
  end

  # The keyword arguments the op handed to EnsureCustomerForAccount.
  def provisioning_kwargs
    kwargs = nil
    allow(Auth::Operations::EnsureCustomerForAccount).to receive(:new) do |**received|
      kwargs = received
      ensure_op
    end
    op.send(:recreate_customer)
    kwargs
  end

  describe 'derived provenance' do
    it "stamps 'sso' when the account has an account_identities row" do
      add_sso_identity!

      expect(provisioning_kwargs).to include(verified: true, verified_by: 'sso')
    end

    # A Verified row does not show how it got there (sync-auth-accounts
    # opens one for any verified Redis customer), so recovery must not
    # mint the mailbox proof that has_system_role? requires (#4735).
    it "stamps 'legacy', not 'email', for a password account" do
      expect(provisioning_kwargs).to include(verified: true, verified_by: 'legacy')
    end

    # Today's verify_account setting says nothing about how an existing row
    # became Verified (it may have been off then, or loaded only through
    # webauthn_verify_account), so the tag must not change with it.
    [true, false].each do |enabled|
      context "when verify_account_enabled? is #{enabled}" do
        let(:verify_account) { enabled }

        it "stamps 'legacy' without consulting the config", :aggregate_failures do
          expect(provisioning_kwargs).to include(verified: true, verified_by: 'legacy')
          expect(auth_config).not_to have_received(:verify_account_enabled?)
        end
      end
    end

    context 'when the accounts row is Unverified' do
      let(:status_id) { Auth::AccountStatuses::UNVERIFIED }
      let(:verify_account) { true }

      it 'recreates the customer unverified with no provenance, whatever else is true' do
        add_sso_identity!

        expect(provisioning_kwargs).to include(verified: false, verified_by: nil)
      end
    end
  end

  describe 'fail closed' do
    it 'recreates the customer UNVERIFIED and logs when the identity lookup raises', :aggregate_failures do
      allow(op).to receive(:sso_identity_present?).and_raise(Sequel::DatabaseError, 'boom')

      expect(provisioning_kwargs).to include(verified: false, verified_by: nil)
      expect(Auth::Logging).to have_received(:log_error)
        .with(:customer_recreate_provenance_failed, hash_including(fallback: 'unverified'))
    end
  end

  describe 'observability' do
    it 'logs the recreation at WARN with the derived provenance' do
      op.send(:recreate_customer)

      expect(Auth::Logging).to have_received(:log_operation).with(
        :customer_recreated_at_login,
        hash_including(
          level: :warn,
          verified: true,
          verified_by: 'legacy',
          provisioning_origin: 'login_recovery',
          customer_id: 'cust_new',
        ),
      )
    end

    it 'stamps a provisioning_origin from the model vocabulary', :aggregate_failures do
      expect(provisioning_kwargs).to include(provisioning_origin: described_class::RECOVERY_PROVISIONING_ORIGIN)
      expect(Onetime::Customer::PROVISIONING_ORIGINS).to include(described_class::RECOVERY_PROVISIONING_ORIGIN)
    end

    it 'only ever derives verified_by tags from the enforced vocabulary' do
      expect(Onetime::Customer::VERIFIED_BY_VALUES).to include('sso', 'legacy')
    end

    it 'never derives a mailbox-proof tag, on any branch' do
      expect(Onetime::Customer::MAILBOX_VERIFIED_BY & %w[sso legacy]).to be_empty
    end

    it 'hands the account, its id and the connection to EnsureCustomerForAccount' do
      expect(provisioning_kwargs).to include(account_id: account_id, account: account, db: db)
    end
  end

  describe 'wiring through #ensure_customer_exists' do
    before do
      allow(op).to receive(:link_customer_to_account)
      allow(op).to receive_messages(find_existing_customer: nil, customer_linked?: false)
    end

    it 'recreates when no Customer is found and leaves linking to EnsureCustomerForAccount', :aggregate_failures do
      expect(op.send(:ensure_customer_exists)).to equal(created)
      expect(op).not_to have_received(:link_customer_to_account)
    end

    it 'falls back to the index retry (and links) when the email index was merely lagging', :aggregate_failures do
      indexed = double('Customer', custid: 'cust_indexed', extid: 'ur_indexed')
      allow(ensure_op).to receive(:call).and_raise(Familia::RecordExistsError.new('exists'))
      allow(op).to receive(:find_customer_by_email).and_return(indexed)

      expect(op.send(:ensure_customer_exists)).to equal(indexed)
      expect(op).to have_received(:link_customer_to_account).with(indexed)
    end
  end
end
