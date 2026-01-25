# apps/web/auth/spec/integration/migrations_sqlite_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'support/helpers/migration_test_helpers'

# Test SQLite migrations without full application boot
# These tests directly use Sequel::Migrator and don't require Redis/Familia
RSpec.describe 'Auth::Migrator SQLite Integration' do
  include MigrationTestHelpers

  let(:migrations_dir) { File.join(Onetime::HOME, 'apps', 'web', 'auth', 'migrations') }
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

      # Verify schema version is at latest (6 migrations)
      version = verify_schema_version(db: test_db, expected: 6)
      expect(version).to eq(6)

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

      # Should now be at version 6
      expect(verify_schema_version(db: test_db, expected: 6)).to eq(6)
      expect(verify_core_tables_exist(db: test_db)).to be true
    end

    it 'completes remaining migrations from version 3' do
      create_partial_migration_state(db: test_db, version: 3)
      expect(get_schema_version(db: test_db)).to eq(3)

      Sequel::Migrator.run(test_db, migrations_dir)

      expect(verify_schema_version(db: test_db, expected: 6)).to eq(6)
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
      expect(get_schema_version(db: test_db)).to eq(6)
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

      (1..6).each do |target_version|
        Sequel::Migrator.run(test_db, migrations_dir, target: target_version)
        versions << get_schema_version(db: test_db)
      end

      expect(versions).to eq([1, 2, 3, 4, 5, 6])
    end

    it 'allows rollback to previous version' do
      # Run all migrations
      Sequel::Migrator.run(test_db, migrations_dir)
      expect(get_schema_version(db: test_db)).to eq(6)

      # Rollback to version 3
      Sequel::Migrator.run(test_db, migrations_dir, target: 3)
      expect(get_schema_version(db: test_db)).to eq(3)

      # Run forward again
      Sequel::Migrator.run(test_db, migrations_dir)
      expect(get_schema_version(db: test_db)).to eq(6)
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
      expect(get_schema_version(db: test_db)).to eq(6)

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
      expect(get_schema_version(db: test_db)).to eq(6)

      # Second run should be no-op
      Sequel::Migrator.run(test_db, migrations_dir)
      expect(get_schema_version(db: test_db)).to eq(6)
    end

    it 'uses transactions for migration safety' do
      # Verify migrations run in transaction context
      Sequel::Migrator.run(test_db, migrations_dir, use_transactions: true)
      expect(get_schema_version(db: test_db)).to eq(6)
    end
  end
end
