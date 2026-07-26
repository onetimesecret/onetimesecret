# apps/web/auth/spec/operations/set_customer_verification_sql_spec.rb
#
# frozen_string_literal: true

# Regression coverage for #3916 against a REAL schema, and the home of the
# op's whole SQL contract: external_id keying, the live-status constraint,
# the AccountNotFound/AccountClosed taxonomy and the unlinked-row email fallback.
# (The mock-based sibling spec covers only mode/flag control flow.) The
# load-bearing piece mocks cannot express is the PARTIAL unique index on
# accounts.email (`where status_id in (1, 2)`, migrations/001_initial.rb),
# which lets a Closed row share a live row's address. Before the fix, the op
# keyed its UPDATE on bare email:
#   - one row, Closed       -> silent resurrection (3 -> 2)
#   - Closed + live sibling -> Sequel::UniqueConstraintViolation mid-statement
#
# SQLite supports partial indexes, so the migrated schema reproduces both
# cases without needing the Postgres suite.
#
# Schema setup: migrated ONCE per run (before :context), and only through the
# STRUCTURAL migrations — deliberately stopping before the first data
# migration. 007_normalize_customer_emails reaches for the live Familia/Redis
# connection, which a spec process must never touch (shared-state hazard in
# CI), and no migration after 001 reshapes accounts. Same structural/data
# split as MigrationTestHelpers#create_partial_migration_state; the target is
# derived from the data migration's filename so a renumber doesn't rot it
# (the issuer_migration_version precedent). If a future structural migration
# lands AFTER the data migrations and alters accounts, revisit the target.
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/set_customer_verification_sql_spec.rb

require 'spec_helper'

require 'fileutils'
require 'securerandom'
require 'tmpdir'

require 'auth/account_statuses'
require 'auth/database'
require 'auth/operations/set_customer_verification'

RSpec.describe Auth::Operations::SetCustomerVerification, 'with a real (migrated) schema' do
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

  let(:db)          { @db }
  let(:auth_config) { double('AuthConfig', mode: 'full') }

  before do
    allow(Onetime).to receive(:auth_config).and_return(auth_config)
    db[:accounts].delete
  end

  def build_customer(extid:, email:, verified: false)
    double(
      'Customer',
      extid: extid,
      email: email,
      verified?: verified,
      :verified= => nil,
      :verified_by= => nil,
      save: true,
    )
  end

  def insert_account(email:, status_id:, external_id: nil)
    db[:accounts].insert(email: email, status_id: status_id, external_id: external_id)
  end

  def set_verification!(customer, verified:)
    described_class.new(
      customer: customer,
      verified: verified,
      verified_by: verified ? 'cli_provision' : nil,
      db: db,
    ).call
  end

  def verify!(customer)
    set_verification!(customer, verified: true)
  end

  describe 'happy path on an external_id-linked row' do
    it 'verify moves Unverified -> Verified and saves the Customer mirror' do
      id       = insert_account(email: 'up@example.com', status_id: Auth::AccountStatuses::UNVERIFIED, external_id: 'ur_up')
      customer = build_customer(extid: 'ur_up', email: 'up@example.com')

      expect(verify!(customer)).to eq(:success)
      expect(db[:accounts].where(id: id).get(:status_id)).to eq(Auth::AccountStatuses::VERIFIED)
      expect(customer).to have_received(:save)
    end

    it 'unverify moves Verified -> Unverified' do
      id       = insert_account(email: 'down@example.com', status_id: Auth::AccountStatuses::VERIFIED, external_id: 'ur_down')
      customer = build_customer(extid: 'ur_down', email: 'down@example.com', verified: true)

      expect(set_verification!(customer, verified: false)).to eq(:success)
      expect(db[:accounts].where(id: id).get(:status_id)).to eq(Auth::AccountStatuses::UNVERIFIED)
    end

    it 'falls back to Auth::Database.connection when db: is not injected' do
      allow(Auth::Database).to receive(:connection).and_return(db)
      id       = insert_account(email: 'conn@example.com', status_id: Auth::AccountStatuses::UNVERIFIED, external_id: 'ur_conn')
      customer = build_customer(extid: 'ur_conn', email: 'conn@example.com')

      result = described_class.new(
        customer: customer,
        verified: true,
        verified_by: 'cli_provision',
      ).call

      expect(result).to eq(:success)
      expect(db[:accounts].where(id: id).get(:status_id)).to eq(Auth::AccountStatuses::VERIFIED)
    end
  end

  describe 'one-row case: Closed account, no live sibling' do
    it 'refuses to resurrect: raises AccountClosed and leaves status_id=3' do
      id       = insert_account(email: 'gone@example.com', status_id: Auth::AccountStatuses::CLOSED, external_id: 'ur_gone')
      customer = build_customer(extid: 'ur_gone', email: 'gone@example.com')

      expect { verify!(customer) }.to raise_error(described_class::AccountClosed, /ur_gone/)
      expect(db[:accounts].where(id: id).get(:status_id)).to eq(Auth::AccountStatuses::CLOSED)
      expect(customer).not_to have_received(:save)
    end
  end

  describe "two-row case: Closed row shares a live row's address" do
    let!(:live_id) do
      insert_account(email: 'shared@example.com', status_id: Auth::AccountStatuses::UNVERIFIED, external_id: 'ur_live')
    end
    let!(:closed_id) do
      insert_account(email: 'shared@example.com', status_id: Auth::AccountStatuses::CLOSED, external_id: 'ur_gone')
    end

    it 'verifying the live customer touches only the live row' do
      customer = build_customer(extid: 'ur_live', email: 'shared@example.com')

      expect(verify!(customer)).to eq(:success)
      expect(db[:accounts].where(id: live_id).get(:status_id)).to eq(Auth::AccountStatuses::VERIFIED)
      expect(db[:accounts].where(id: closed_id).get(:status_id)).to eq(Auth::AccountStatuses::CLOSED)
    end

    it 'verifying the closed customer raises AccountClosed, not UniqueConstraintViolation' do
      customer = build_customer(extid: 'ur_gone', email: 'shared@example.com')

      expect { verify!(customer) }.to raise_error(described_class::AccountClosed)
      expect(db[:accounts].where(id: live_id).get(:status_id)).to eq(Auth::AccountStatuses::UNVERIFIED)
      expect(db[:accounts].where(id: closed_id).get(:status_id)).to eq(Auth::AccountStatuses::CLOSED)
    end
  end

  describe 'unlinked rows (NULL external_id)' do
    it 'verifies via the email fallback' do
      id       = insert_account(email: 'unlinked@example.com', status_id: Auth::AccountStatuses::UNVERIFIED)
      customer = build_customer(extid: 'ur_unlinked', email: 'unlinked@example.com')

      expect(verify!(customer)).to eq(:success)
      expect(db[:accounts].where(id: id).get(:status_id)).to eq(Auth::AccountStatuses::VERIFIED)
    end

    it 'updates only the live row, never a Closed sibling' do
      closed_id = insert_account(email: 'unlinked2@example.com', status_id: Auth::AccountStatuses::CLOSED)
      live_id   = insert_account(email: 'unlinked2@example.com', status_id: Auth::AccountStatuses::UNVERIFIED)
      customer  = build_customer(extid: 'ur_unlinked2', email: 'unlinked2@example.com')

      expect(verify!(customer)).to eq(:success)
      expect(db[:accounts].where(id: live_id).get(:status_id)).to eq(Auth::AccountStatuses::VERIFIED)
      expect(db[:accounts].where(id: closed_id).get(:status_id)).to eq(Auth::AccountStatuses::CLOSED)
    end

    it 'never claims a row linked to a different customer' do
      other_id = insert_account(email: 'taken@example.com', status_id: Auth::AccountStatuses::UNVERIFIED, external_id: 'ur_other')
      customer = build_customer(extid: 'ur_me', email: 'taken@example.com')

      expect { verify!(customer) }.to raise_error(described_class::AccountNotFound, /ur_me/)
      expect(db[:accounts].where(id: other_id).get(:status_id)).to eq(Auth::AccountStatuses::UNVERIFIED)
      expect(customer).not_to have_received(:save)
    end

    it 'raises AccountClosed when only a Closed unlinked row holds the address' do
      id       = insert_account(email: 'unlinked3@example.com', status_id: Auth::AccountStatuses::CLOSED)
      customer = build_customer(extid: 'ur_unlinked3', email: 'unlinked3@example.com')

      expect { verify!(customer) }.to raise_error(described_class::AccountClosed)
      expect(db[:accounts].where(id: id).get(:status_id)).to eq(Auth::AccountStatuses::CLOSED)
    end
  end

  it 'raises AccountNotFound when no row exists at all' do
    customer = build_customer(extid: 'ur_none', email: 'none@example.com')

    expect { verify!(customer) }.to raise_error(described_class::AccountNotFound, /ur_none/)
    expect(customer).not_to have_received(:save)
  end
end
