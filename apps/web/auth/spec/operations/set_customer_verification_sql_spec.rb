# apps/web/auth/spec/operations/set_customer_verification_sql_spec.rb
#
# frozen_string_literal: true

# Regression coverage for #3916 against a REAL schema. The mock-based spec
# (set_customer_verification_spec.rb) pins the keying contract; these examples
# exercise the part mocks cannot: the PARTIAL unique index on accounts.email
# (`where status_id in (1, 2)`, migrations/001_initial.rb), which lets a
# Closed row share a live row's address. Before the fix, the op keyed its
# UPDATE on bare email:
#   - one row, Closed       -> silent resurrection (3 -> 2)
#   - Closed + live sibling -> Sequel::UniqueConstraintViolation mid-statement
#
# SQLite supports partial indexes, so the migrated schema reproduces both
# cases without needing the Postgres suite.
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/set_customer_verification_sql_spec.rb

require 'spec_helper'

require 'fileutils'
require 'securerandom'
require 'tmpdir'

require 'auth/operations/set_customer_verification'

RSpec.describe Auth::Operations::SetCustomerVerification, 'with a real (migrated) schema' do
  let(:migrations_dir) { File.join(Onetime::HOME, 'apps', 'web', 'auth', 'migrations') }
  let(:test_db_file)   { File.join(Dir.tmpdir, "test_auth_#{SecureRandom.hex(4)}.db") }
  let(:db) do
    Sequel.extension :migration
    connection = Sequel.connect("sqlite://#{test_db_file}")
    Sequel::Migrator.run(connection, migrations_dir, use_transactions: true)
    connection
  end
  let(:auth_config) { double('AuthConfig', mode: 'full') }

  after do
    db.disconnect
    FileUtils.rm_f(test_db_file)
  end

  before { allow(Onetime).to receive(:auth_config).and_return(auth_config) }

  def build_customer(extid:, email:)
    double(
      'Customer',
      extid: extid,
      email: email,
      verified?: false,
      :verified= => nil,
      :verified_by= => nil,
      save: true,
    )
  end

  def insert_account(email:, status_id:, external_id: nil)
    db[:accounts].insert(email: email, status_id: status_id, external_id: external_id)
  end

  def verify!(customer)
    described_class.new(
      customer: customer,
      verified: true,
      verified_by: 'cli_provision',
      db: db,
    ).call
  end

  describe 'one-row case: Closed account, no live sibling' do
    it 'refuses to resurrect: raises AccountClosed and leaves status_id=3' do
      id       = insert_account(email: 'gone@example.com', status_id: 3, external_id: 'ur_gone')
      customer = build_customer(extid: 'ur_gone', email: 'gone@example.com')

      expect { verify!(customer) }.to raise_error(described_class::AccountClosed)
      expect(db[:accounts].where(id: id).get(:status_id)).to eq(3)
      expect(customer).not_to have_received(:save)
    end
  end

  describe "two-row case: Closed row shares a live row's address" do
    let!(:live_id)   { insert_account(email: 'shared@example.com', status_id: 1, external_id: 'ur_live') }
    let!(:closed_id) { insert_account(email: 'shared@example.com', status_id: 3, external_id: 'ur_gone') }

    it 'verifying the live customer touches only the live row' do
      customer = build_customer(extid: 'ur_live', email: 'shared@example.com')

      expect(verify!(customer)).to eq(:success)
      expect(db[:accounts].where(id: live_id).get(:status_id)).to eq(2)
      expect(db[:accounts].where(id: closed_id).get(:status_id)).to eq(3)
    end

    it 'verifying the closed customer raises AccountClosed, not UniqueConstraintViolation' do
      customer = build_customer(extid: 'ur_gone', email: 'shared@example.com')

      expect { verify!(customer) }.to raise_error(described_class::AccountClosed)
      expect(db[:accounts].where(id: live_id).get(:status_id)).to eq(1)
      expect(db[:accounts].where(id: closed_id).get(:status_id)).to eq(3)
    end
  end

  describe 'legacy rows (NULL external_id)' do
    it 'verifies via the email fallback' do
      id       = insert_account(email: 'legacy@example.com', status_id: 1)
      customer = build_customer(extid: 'ur_legacy', email: 'legacy@example.com')

      expect(verify!(customer)).to eq(:success)
      expect(db[:accounts].where(id: id).get(:status_id)).to eq(2)
    end

    it 'updates only the live row, never a Closed sibling' do
      closed_id = insert_account(email: 'legacy2@example.com', status_id: 3)
      live_id   = insert_account(email: 'legacy2@example.com', status_id: 1)
      customer  = build_customer(extid: 'ur_legacy2', email: 'legacy2@example.com')

      expect(verify!(customer)).to eq(:success)
      expect(db[:accounts].where(id: live_id).get(:status_id)).to eq(2)
      expect(db[:accounts].where(id: closed_id).get(:status_id)).to eq(3)
    end

    it 'never claims a row linked to a different customer' do
      other_id = insert_account(email: 'taken@example.com', status_id: 1, external_id: 'ur_other')
      customer = build_customer(extid: 'ur_me', email: 'taken@example.com')

      expect { verify!(customer) }.to raise_error(described_class::AccountNotFound)
      expect(db[:accounts].where(id: other_id).get(:status_id)).to eq(1)
    end

    it 'raises AccountClosed when only a Closed legacy row holds the address' do
      id       = insert_account(email: 'legacy3@example.com', status_id: 3)
      customer = build_customer(extid: 'ur_legacy3', email: 'legacy3@example.com')

      expect { verify!(customer) }.to raise_error(described_class::AccountClosed)
      expect(db[:accounts].where(id: id).get(:status_id)).to eq(3)
    end
  end

  it 'raises AccountNotFound when no row exists at all' do
    customer = build_customer(extid: 'ur_none', email: 'none@example.com')

    expect { verify!(customer) }.to raise_error(described_class::AccountNotFound)
  end
end
