# apps/web/auth/spec/integration/migrations_sqlite_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'support/helpers/migration_test_helpers'

# Test SQLite migrations without full application boot
# These tests directly use Sequel::Migrator and don't require Redis/Familia
RSpec.describe 'Auth::Migrator SQLite Integration', :sqlite_database do
  include MigrationTestHelpers

  let(:migrations_dir) { File.join(Onetime::HOME, 'apps', 'web', 'auth', 'migrations') }
  # Derive the latest schema version from the migration files so this spec does
  # not need editing each time a migration lands (the gap that left it at 6).
  let(:latest_version) { Dir.glob(File.join(migrations_dir, '[0-9]*_*.rb')).count }
  let(:test_db_file) { File.join(Dir.tmpdir, "test_auth_#{SecureRandom.hex(4)}.db") }
  let(:test_db) { Sequel.connect("sqlite://#{test_db_file}") }

  before(:all) do
    # Enable migration extension for all tests
    Sequel.extension :migration
  end

  after do
    test_db.disconnect if test_db
    File.delete(test_db_file) if File.exist?(test_db_file)
  end

  describe 'first boot with no database' do
    it 'creates complete schema from scratch' do
      # Verify no schema exists
      expect(test_db.table_exists?(:schema_info)).to be false
      expect(test_db.table_exists?(:accounts)).to be false

      # Run migrations
      Sequel.extension :migration
      Sequel::Migrator.run(test_db, migrations_dir, use_transactions: true)

      # Verify schema version is at latest
      version = verify_schema_version(db: test_db, expected: latest_version)
      expect(version).to eq(latest_version)

      # Verify all core tables exist
      expect(verify_core_tables_exist(db: test_db)).to be true
    end

    it 'populates account_statuses reference table' do
      Sequel.extension :migration
      Sequel::Migrator.run(test_db, migrations_dir)

      statuses = test_db[:account_statuses].all
      expect(statuses).to contain_exactly(
        hash_including(id: 1, name: 'Unverified'),
        hash_including(id: 2, name: 'Verified'),
        hash_including(id: 3, name: 'Closed')
      )
    end

    it 'creates schema_info table for version tracking' do
      Sequel.extension :migration
      Sequel::Migrator.run(test_db, migrations_dir)

      expect(test_db.table_exists?(:schema_info)).to be true
      expect(test_db[:schema_info].count).to eq(1)
    end
  end

  describe 'subsequent boots are idempotent' do
    before do
      # Run migrations once
      Sequel.extension :migration
      Sequel::Migrator.run(test_db, migrations_dir)
    end

    it 'does not modify schema when run again' do
      initial_version = get_schema_version(db: test_db)
      initial_tables  = test_db.tables.sort

      # Run migrations again
      Sequel::Migrator.run(test_db, migrations_dir)

      expect(get_schema_version(db: test_db)).to eq(initial_version)
      expect(test_db.tables.sort).to eq(initial_tables)
    end

    it 'preserves existing data' do
      # Create test account
      account_id = test_db[:accounts].insert(
        email: 'test@example.com',
        status_id: 2,
        external_id: SecureRandom.uuid
      )

      # Run migrations again
      Sequel::Migrator.run(test_db, migrations_dir)

      # Verify data still exists
      account = test_db[:accounts].where(id: account_id).first
      expect(account[:email]).to eq('test@example.com')
    end
  end

  describe 'partial migration state' do
    it 'completes remaining migrations from version 1' do
      # Migrate to version 1 only
      create_partial_migration_state(db: test_db, version: 1)
      expect(get_schema_version(db: test_db)).to eq(1)

      # Run full migration
      Sequel::Migrator.run(test_db, migrations_dir)

      # Should now be at the latest version
      expect(verify_schema_version(db: test_db, expected: latest_version)).to eq(latest_version)
      expect(verify_core_tables_exist(db: test_db)).to be true
    end

    it 'completes remaining migrations from version 3' do
      create_partial_migration_state(db: test_db, version: 3)
      expect(get_schema_version(db: test_db)).to eq(3)

      Sequel::Migrator.run(test_db, migrations_dir)

      expect(verify_schema_version(db: test_db, expected: latest_version)).to eq(latest_version)
    end

    it 'maintains data integrity when completing migrations' do
      # Migrate to version 1
      create_partial_migration_state(db: test_db, version: 1)

      # Insert test data
      account_id = test_db[:accounts].insert(
        email: 'partial@example.com',
        status_id: 1,
        external_id: SecureRandom.uuid
      )

      # Complete migrations
      Sequel::Migrator.run(test_db, migrations_dir)

      # Verify data survived
      account = test_db[:accounts].where(id: account_id).first
      expect(account[:email]).to eq('partial@example.com')
      expect(get_schema_version(db: test_db)).to eq(latest_version)
    end
  end

  describe 'migration failure handling' do
    it 'rolls back transaction on migration error' do
      # Create a corrupted migration by attempting to run with invalid path
      invalid_migrations_dir = File.join(Dir.tmpdir, 'nonexistent_migrations')

      expect do
        Sequel::Migrator.run(test_db, invalid_migrations_dir)
      end.to raise_error(Sequel::Migrator::Error)

      # Verify no partial schema was created
      expect(test_db.table_exists?(:accounts)).to be false
    end

    it 'preserves existing schema on failed migration attempt' do
      # Run migrations successfully first
      Sequel::Migrator.run(test_db, migrations_dir)
      initial_version = get_schema_version(db: test_db)

      # Attempt to run with corrupted path (will fail)
      expect do
        Sequel::Migrator.run(test_db, '/nonexistent/path')
      end.to raise_error(Sequel::Migrator::Error)

      # Schema version should be unchanged
      expect(get_schema_version(db: test_db)).to eq(initial_version)
    end
  end

  describe 'schema version tracking' do
    it 'increments version for each migration' do
      versions = []

      (1..latest_version).each do |target_version|
        Sequel::Migrator.run(test_db, migrations_dir, target: target_version)
        versions << get_schema_version(db: test_db)
      end

      expect(versions).to eq((1..latest_version).to_a)
    end

    it 'allows rollback to previous version' do
      # Run all migrations
      Sequel::Migrator.run(test_db, migrations_dir)
      expect(get_schema_version(db: test_db)).to eq(latest_version)

      # Rollback to version 3
      Sequel::Migrator.run(test_db, migrations_dir, target: 3)
      expect(get_schema_version(db: test_db)).to eq(3)

      # Run forward again
      Sequel::Migrator.run(test_db, migrations_dir)
      expect(get_schema_version(db: test_db)).to eq(latest_version)
    end
  end

  describe 'migration 012 (ADR-051 expand: login + contact verification columns)' do
    before do
      Sequel::Migrator.run(test_db, migrations_dir)
    end

    let(:columns) { test_db.schema(:accounts).map(&:first) }

    it 'adds the four nullable columns and keeps email NOT NULL' do
      expect(columns).to include(:login, :email_verified_at, :email_verified_by, :email_verification_hold)

      expect do
        test_db[:accounts].insert(status_id: 2, external_id: SecureRandom.uuid)
      end.to raise_error(Sequel::NotNullConstraintViolation)
    end

    it 'lets the current binary keep inserting rows with NULL login (NULLs are distinct)' do
      a = test_db[:accounts].insert(email: 'a-012@example.com', status_id: 2)
      b = test_db[:accounts].insert(email: 'b-012@example.com', status_id: 2)

      expect(test_db[:accounts].where(id: [a, b], login: nil).count).to eq(2)
    end

    it 'refuses two rows with the same login' do
      a = test_db[:accounts].insert(email: 'a-012@example.com', status_id: 2, login: 'objid-a')
      b = test_db[:accounts].insert(email: 'b-012@example.com', status_id: 2)

      expect(test_db[:accounts].where(id: a).get(:login)).to eq('objid-a')
      expect do
        test_db[:accounts].where(id: b).update(login: 'objid-a')
      end.to raise_error(Sequel::UniqueConstraintViolation)
    end

    it 'rolls back without touching pre-existing columns or rows' do
      id = test_db[:accounts].insert(
        email: 'keep-012@example.com', status_id: 2, external_id: SecureRandom.uuid,
        login: 'objid-keep', email_verified_by: 'email',
      )

      Sequel::Migrator.run(test_db, migrations_dir, target: 11)

      cols = test_db.schema(:accounts).map(&:first)
      expect(cols).not_to include(:login, :email_verified_at, :email_verified_by, :email_verification_hold)
      expect(test_db[:accounts].where(id: id).get(:email)).to eq('keep-012@example.com')

      Sequel::Migrator.run(test_db, migrations_dir)
      expect(test_db.schema(:accounts).map(&:first)).to include(:login)
      expect(test_db[:accounts].where(id: id).get(:login)).to be_nil
    end
  end

  describe 'all migrations applied correctly' do
    before do
      Sequel::Migrator.run(test_db, migrations_dir)
    end

    it 'creates all expected tables from migration 001' do
      expect(verify_core_tables_exist(db: test_db)).to be true
    end

    it 'creates indexes from migration 002' do
      # Verify performance indexes exist (created by SQL file)
      indexes = test_db.indexes(:account_jwt_refresh_keys)
      account_id_index = indexes.values.find { |idx| idx[:columns].include?(:account_id) }
      expect(account_id_index).not_to be_nil

      # Verify activity times indexes
      activity_indexes = test_db.indexes(:account_activity_times)
      expect(activity_indexes).not_to be_empty
    end

    it 'applies database-specific features for SQLite' do
      # SQLite doesn't have functions/triggers/views like PostgreSQL
      # but we can verify the migration ran without error
      expect(get_schema_version(db: test_db)).to eq(latest_version)

      # Verify SQLite-specific constraints work
      expect do
        test_db[:accounts].insert(
          email: nil, # NOT NULL constraint
          status_id: 2,
          external_id: SecureRandom.uuid
        )
      end.to raise_error(Sequel::NotNullConstraintViolation)
    end

    it 'enforces foreign key constraints' do
      # Try to insert account with invalid status_id
      expect do
        test_db[:accounts].insert(
          email: 'test@example.com',
          status_id: 999, # Invalid foreign key
          external_id: SecureRandom.uuid
        )
      end.to raise_error(Sequel::ForeignKeyConstraintViolation)
    end

    it 'enforces unique constraints' do
      email = 'unique@example.com'

      # Insert first account
      test_db[:accounts].insert(
        email: email,
        status_id: 2,
        external_id: SecureRandom.uuid
      )

      # Try to insert duplicate email
      expect do
        test_db[:accounts].insert(
          email: email,
          status_id: 2,
          external_id: SecureRandom.uuid
        )
      end.to raise_error(Sequel::UniqueConstraintViolation)
    end
  end

  describe 'Sequel::Migrator behavior' do
    it 'runs migrations idempotently' do
      # First run
      Sequel::Migrator.run(test_db, migrations_dir)
      expect(get_schema_version(db: test_db)).to eq(latest_version)

      # Second run should be no-op
      Sequel::Migrator.run(test_db, migrations_dir)
      expect(get_schema_version(db: test_db)).to eq(latest_version)
    end

    it 'uses transactions for migration safety' do
      # Verify migrations run in transaction context
      Sequel::Migrator.run(test_db, migrations_dir, use_transactions: true)
      expect(get_schema_version(db: test_db)).to eq(latest_version)
    end
  end

  # Regression (#3840 Phase 0 / #3838 item 5): the issuer-scoped migration re-keys
  # account_identities from (provider, uid) to (provider, issuer, uid) to close a
  # cross-tenant SSO takeover. On SQLite the `down` path restores (provider, uid)
  # as a STANDALONE unique index; the `up` path's drop_constraint rebuilds the
  # table but cannot see that index (it re-creates it). Without the explicit
  # idempotent DROP INDEX in `up`, an up->down->up cycle left the stale
  # (provider, uid) unique in place and silently re-imposed the old key —
  # defeating issuer-scoping. This guards that cycle.
  describe 'issuer-scoped migration (008) reversibility' do
    # issuer_migration_version and insert_account come from MigrationTestHelpers.
    it 'preserves (provider, issuer, uid) uniqueness after an up->down->up cycle' do
      v = issuer_migration_version

      # up to the migration, roll it back (down), then re-apply it (up).
      Sequel::Migrator.run(test_db, migrations_dir, target: v)
      Sequel::Migrator.run(test_db, migrations_dir, target: v - 1)
      Sequel::Migrator.run(test_db, migrations_dir, target: v)

      acct_a = insert_account(test_db, 'cycle-a@example.com')
      acct_b = insert_account(test_db, 'cycle-b@example.com')
      ids = test_db[:account_identities]

      # Two IdPs asserting the same sub (uid) under different issuers must coexist.
      ids.insert(account_id: acct_a, provider: 'oidc', issuer: 'https://idp-a.example', uid: 'shared-sub')
      expect do
        ids.insert(account_id: acct_b, provider: 'oidc', issuer: 'https://idp-b.example', uid: 'shared-sub')
      end.not_to raise_error
      expect(ids.where(provider: 'oidc', uid: 'shared-sub').count).to eq(2)

      # A true (provider, issuer, uid) duplicate is still rejected.
      expect do
        ids.insert(account_id: acct_b, provider: 'oidc', issuer: 'https://idp-a.example', uid: 'shared-sub')
      end.to raise_error(Sequel::UniqueConstraintViolation)

      # The stale (provider, uid) unique index must be gone.
      uniques = test_db.indexes(:account_identities).values.select { |i| i[:unique] }.map { |i| i[:columns] }
      expect(uniques).to include(%i[provider issuer uid])
      expect(uniques).not_to include(%i[provider uid])
    end

    # The `down` block documents that a rollback CANNOT collapse two issuers back
    # onto a single (provider, uid) key. Pin that it fails LOUDLY (rather than
    # silently dropping a row and re-opening the takeover) and preserves the data.
    it 'refuses to roll back when colliding-issuer rows exist' do
      v = issuer_migration_version
      Sequel::Migrator.run(test_db, migrations_dir, target: v)

      acct_a = insert_account(test_db, 'rollback-a@example.com')
      acct_b = insert_account(test_db, 'rollback-b@example.com')
      ids = test_db[:account_identities]
      ids.insert(account_id: acct_a, provider: 'oidc', issuer: 'https://idp-a.example', uid: 'dup-sub')
      ids.insert(account_id: acct_b, provider: 'oidc', issuer: 'https://idp-b.example', uid: 'dup-sub')

      expect do
        Sequel::Migrator.run(test_db, migrations_dir, target: v - 1)
      end.to raise_error(Sequel::DatabaseError)

      # Rollback aborted: schema stays at v and both rows survive (no silent loss).
      expect(get_schema_version(db: test_db)).to eq(v)
      expect(ids.where(uid: 'dup-sub').count).to eq(2)
    end
  end

  # 011 adds the nullable remember_until column the gate and the sweep read
  # (lib/onetime/session/remember_me.rb). Existing rows must come through
  # as NULL (not remembered), and the column must go away cleanly on rollback.
  describe 'remember_until migration (011)' do
    it 'adds a nullable remember_until to account_active_session_keys and removes it on rollback', :aggregate_failures do
      Sequel::Migrator.run(test_db, migrations_dir, target: 10)
      acct = insert_account(test_db, 'remember-migration@example.com')
      test_db[:account_active_session_keys].insert(account_id: acct, session_id: 'pre-011')

      Sequel::Migrator.run(test_db, migrations_dir, target: 11)
      expect(test_db.schema(:account_active_session_keys).to_h).to include(remember_until: hash_including(allow_null: true))
      expect(test_db[:account_active_session_keys].where(session_id: 'pre-011').get(:remember_until)).to be_nil

      Sequel::Migrator.run(test_db, migrations_dir, target: 10)
      expect(test_db.schema(:account_active_session_keys).map(&:first)).not_to include(:remember_until)
      expect(test_db[:account_active_session_keys].where(session_id: 'pre-011').count).to eq(1)
    end
  end
end
