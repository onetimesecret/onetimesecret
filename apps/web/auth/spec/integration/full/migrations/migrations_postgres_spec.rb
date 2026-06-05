# apps/web/auth/spec/integration/migrations_postgres_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'support/helpers/migration_test_helpers'

# Test PostgreSQL migrations with real database
# Requires AUTH_DATABASE_URL to be set to a PostgreSQL database
#
# WARNING: Each example drops all tables before running, which destroys
# state set up by PostgresModeSuiteDatabase. Sibling :postgres_database
# specs recover because setup! checks schema_intact? and re-migrates.
#
# In CI environment with dual-user setup:
# - test_db (onetime_user): For verifying migrations (SELECT access)
# - migration_db (onetime_migrator or test_db): For running migrations (CREATE/ALTER)
RSpec.describe 'Auth::Migrator PostgreSQL Integration', :postgres_database do
  include MigrationTestHelpers

  EXPECTED_SCHEMA_VERSION = PostgresModeSuiteDatabase::EXPECTED_SCHEMA_VERSION

  let(:migrations_dir) { File.join(Onetime::HOME, 'apps', 'web', 'auth', 'migrations') }
  let(:test_db) { PostgresModeSuiteDatabase.database }
  let(:migration_db) { PostgresModeSuiteDatabase.migration_database || test_db }
  let(:setup_db) { migration_db }

  before do
    # Clean slate for each test (uses elevated connection if available)
    drop_all_tables(db: test_db)
  end

  describe 'first boot with no database' do
    it 'creates complete schema from scratch' do
      # Verify no schema exists
      expect(test_db.table_exists?(:schema_info)).to be false
      expect(test_db.table_exists?(:accounts)).to be false

      # Run migrations
      Sequel.extension :migration
      run_test_migrations(migration_db: migration_db, migrations_dir: migrations_dir)

      # Verify schema version is at latest
      version = verify_schema_version(db: test_db, expected: EXPECTED_SCHEMA_VERSION)
      expect(version).to eq(EXPECTED_SCHEMA_VERSION)

      # Verify all core tables exist
      expect(verify_core_tables_exist(db: test_db)).to be true
    end

    it 'enables citext extension for case-insensitive email' do
      run_test_migrations(migration_db: migration_db, migrations_dir: migrations_dir)

      # Verify citext extension is enabled
      result = test_db.fetch(<<~SQL).first
        SELECT EXISTS (
          SELECT 1 FROM pg_extension WHERE extname = 'citext'
        ) AS exists
      SQL

      expect(result[:exists]).to be true
    end

    it 'creates PostgreSQL-specific constraints' do
      run_test_migrations(migration_db: migration_db, migrations_dir: migrations_dir)

      # Try to insert invalid email (should fail constraint)
      expect do
        setup_db[:accounts].insert(
          email: 'invalid-email', # Missing @ and domain
          status_id: 2,
          external_id: SecureRandom.uuid
        )
      end.to raise_error(Sequel::CheckConstraintViolation)
    end
  end

  describe 'subsequent boots are idempotent' do
    before do
      run_test_migrations(migration_db: migration_db, migrations_dir: migrations_dir)
    end

    it 'does not modify schema when run again' do
      initial_version = get_schema_version(db: test_db)
      initial_tables  = test_db.tables.sort

      # Run migrations again
      Sequel::Migrator.run(migration_db, migrations_dir)

      expect(get_schema_version(db: test_db)).to eq(initial_version)
      expect(test_db.tables.sort).to eq(initial_tables)
    end

    it 'preserves existing data' do
      # Create test account
      account_id = setup_db[:accounts].insert(
        email: 'test@example.com',
        status_id: 2,
        external_id: SecureRandom.uuid
      )

      # Run migrations again
      Sequel::Migrator.run(migration_db, migrations_dir)

      # Verify data still exists
      account = test_db[:accounts].where(id: account_id).first
      expect(account[:email]).to eq('test@example.com')
    end
  end

  describe 'partial migration state' do
    it 'completes remaining migrations from version 1' do
      create_partial_migration_state(db: migration_db, version: 1)
      expect(get_schema_version(db: test_db)).to eq(1)

      run_test_migrations(migration_db: migration_db, migrations_dir: migrations_dir)

      expect(verify_schema_version(db: test_db, expected: EXPECTED_SCHEMA_VERSION)).to eq(EXPECTED_SCHEMA_VERSION)
      expect(verify_core_tables_exist(db: test_db)).to be true
    end

    it 'completes remaining migrations from version 3' do
      create_partial_migration_state(db: migration_db, version: 3)
      expect(get_schema_version(db: test_db)).to eq(3)

      run_test_migrations(migration_db: migration_db, migrations_dir: migrations_dir)

      expect(verify_schema_version(db: test_db, expected: EXPECTED_SCHEMA_VERSION)).to eq(EXPECTED_SCHEMA_VERSION)
    end

    it 'maintains data integrity when completing migrations' do
      create_partial_migration_state(db: migration_db, version: 1)

      # Insert test data
      account_id = setup_db[:accounts].insert(
        email: 'partial@example.com',
        status_id: 1,
        external_id: SecureRandom.uuid
      )

      # Complete migrations
      run_test_migrations(migration_db: migration_db, migrations_dir: migrations_dir)

      # Verify data survived
      account = test_db[:accounts].where(id: account_id).first
      expect(account[:email]).to eq('partial@example.com')
      expect(get_schema_version(db: test_db)).to eq(EXPECTED_SCHEMA_VERSION)
    end
  end

  describe 'migration failure handling' do
    it 'rolls back transaction on migration error' do
      invalid_migrations_dir = File.join(Dir.tmpdir, 'nonexistent_migrations')

      expect do
        Sequel::Migrator.run(migration_db, invalid_migrations_dir)
      end.to raise_error(Sequel::Migrator::Error)

      # Verify no partial schema was created
      expect(test_db.table_exists?(:accounts)).to be false
    end

    it 'preserves existing schema on failed migration attempt' do
      Sequel::Migrator.run(migration_db, migrations_dir)
      # Use migration_db for reading too — in CI dual-user setup, test_db may not
      # have SELECT on tables created by migration_db
      initial_version = get_schema_version(db: migration_db)

      expect do
        Sequel::Migrator.run(migration_db, '/nonexistent/path')
      end.to raise_error(Sequel::Migrator::Error)

      expect(get_schema_version(db: migration_db)).to eq(initial_version)
    end
  end

  describe 'PostgreSQL-specific features' do
    before do
      run_test_migrations(migration_db: migration_db, migrations_dir: migrations_dir)
    end

    it 'creates database functions from migration 003' do
      features = verify_postgres_features(db: test_db)
      expect(features[:functions]).to be true
    end

    it 'creates triggers from migration 004' do
      features = verify_postgres_features(db: test_db)
      expect(features[:triggers]).to be true
    end

    it 'creates views from migration 005' do
      features = verify_postgres_features(db: test_db)
      expect(features[:views]).to be true
    end

    it 'updates updated_at timestamp automatically via trigger' do
      # Insert account
      account_id = setup_db[:accounts].insert(
        email: 'trigger@example.com',
        status_id: 2,
        external_id: SecureRandom.uuid
      )

      original_updated_at = test_db[:accounts].where(id: account_id).get(:updated_at)

      # Wait to ensure timestamp difference
      sleep 0.1

      # Update account (trigger should fire)
      setup_db[:accounts].where(id: account_id).update(status_id: 1)

      new_updated_at = test_db[:accounts].where(id: account_id).get(:updated_at)

      # Timestamp should be updated
      expect(new_updated_at).to be > original_updated_at
    end

    it 'uses advisory locks for concurrent migrations' do
      # Verify advisory lock is supported
      result = test_db.fetch(<<~SQL).first
        SELECT pg_try_advisory_lock(1234) AS acquired
      SQL

      expect(result[:acquired]).to be true

      # Release lock
      test_db.fetch("SELECT pg_advisory_unlock(1234)")
    end
  end

  describe 'dual URL handling' do
    context 'when AUTH_DATABASE_URL_MIGRATIONS is not set' do
      around do |example|
        # Temporarily unset migrations URL for this test
        original = ENV['AUTH_DATABASE_URL_MIGRATIONS']
        ENV.delete('AUTH_DATABASE_URL_MIGRATIONS')
        example.run
      ensure
        ENV['AUTH_DATABASE_URL_MIGRATIONS'] = original if original
      end

      it 'uses the same connection for migrations' do
        # Default case - when migrations URL not set, use standard URL
        expect(ENV['AUTH_DATABASE_URL_MIGRATIONS']).to be_nil

        Sequel::Migrator.run(migration_db, migrations_dir)
        expect(get_schema_version(db: test_db)).to eq(EXPECTED_SCHEMA_VERSION)
      end
    end

    context 'when AUTH_DATABASE_URL_MIGRATIONS is different (elevated)' do
      it 'allows separate credentials for migrations' do
        superuser_db = connect_as_superuser
        skip 'PostgreSQL superuser connection not available' unless superuser_db

        original_migration_url = nil
        restricted_db = nil

        begin
          drop_all_tables(db: test_db)

          # Preconditions: initialize_test_db.sql must have provisioned this role
          # with USAGE (but not CREATE) on public. Fail loudly if not.
          user_provisioned = superuser_db.fetch(
            "SELECT 1 FROM pg_user WHERE usename = 'onetime_migrator_test'"
          ).any?
          expect(user_provisioned).to be(true),
            'onetime_migrator_test role missing — run initialize_test_db.sql'

          has_usage = superuser_db.fetch(
            "SELECT has_schema_privilege('onetime_migrator_test', 'public', 'USAGE') AS ok"
          ).first[:ok]
          expect(has_usage).to be(true),
            'onetime_migrator_test lacks USAGE on public — run initialize_test_db.sql'

          has_create = superuser_db.fetch(
            "SELECT has_schema_privilege('onetime_migrator_test', 'public', 'CREATE') AS ok"
          ).first[:ok]
          expect(has_create).to be(false),
            'onetime_migrator_test has CREATE on public — run initialize_test_db.sql to reset grants'

          restricted_url = build_pg_url(user: 'onetime_migrator_test', password: 'testpass')
          restricted_db = Sequel.connect(restricted_url)

          expect do
            restricted_db.run("CREATE TABLE test_table (id INT)")
          end.to raise_error(Sequel::DatabaseError, /permission denied/)

          original_migration_url = ENV['AUTH_DATABASE_URL_MIGRATIONS']
          ENV['AUTH_DATABASE_URL_MIGRATIONS'] = ENV['AUTH_DATABASE_URL']

          Sequel::Migrator.run(migration_db, migrations_dir)

          # Grant DML on the freshly-created tables (simulates production
          # post-migration grant step for the restricted app user)
          setup_db.tables.each do |table|
            setup_db.run("GRANT SELECT, INSERT, UPDATE, DELETE ON #{table} TO onetime_migrator_test")
          end

          expect(restricted_db[:accounts].count).to eq(0)

          account_id = restricted_db[:accounts].insert(
            email: 'restricted@example.com',
            status_id: 2,
            external_id: SecureRandom.uuid
          )
          expect(account_id).to be > 0

          restricted_db[:accounts].where(id: account_id).update(status_id: 1)
          expect(restricted_db[:accounts].where(id: account_id).first[:status_id]).to eq(1)

          restricted_db[:accounts].where(id: account_id).delete
          expect(restricted_db[:accounts].where(id: account_id).count).to eq(0)

          expect(get_schema_version(db: test_db)).to eq(EXPECTED_SCHEMA_VERSION)
          expect(verify_core_tables_exist(db: test_db)).to be true
        ensure
          restricted_db&.disconnect
          ENV['AUTH_DATABASE_URL_MIGRATIONS'] = original_migration_url

          begin
            setup_db.tables.each do |table|
              setup_db.run("REVOKE ALL ON #{table} FROM onetime_migrator_test")
            end
          rescue Sequel::DatabaseError => e
            warn "Failed to cleanup test grants: #{e.message}"
          ensure
            superuser_db.disconnect
          end
        end
      end
    end
  end

  describe 'multi-host URL parsing' do
    it 'parses single-host PostgreSQL URL' do
      url = 'postgresql://user:pass@localhost:5432/testdb'
      opts = Auth::Database.parse_postgres_multihost_url(url)

      expect(opts[:adapter]).to eq('postgres')
      expect(opts[:host]).to eq('localhost')
      expect(opts[:port]).to eq(5432)
      expect(opts[:database]).to eq('testdb')
      expect(opts[:user]).to eq('user')
      expect(opts[:password]).to eq('pass')
    end

    it 'extracts primary host from multi-host URL' do
      url = 'postgresql://user:pass@host1:5432,host2:5433/testdb'
      opts = Auth::Database.parse_postgres_multihost_url(url)

      # Should use first host only
      expect(opts[:host]).to eq('host1')
      expect(opts[:port]).to eq(5432)
      expect(opts[:database]).to eq('testdb')
    end

    it 'handles URL with query parameters' do
      url = 'postgresql://user:pass@localhost:5432/testdb?sslmode=require'
      opts = Auth::Database.parse_postgres_multihost_url(url)

      expect(opts[:sslmode]).to eq('require')
    end

    it 'defaults to port 5432 when not specified' do
      url = 'postgresql://user:pass@localhost/testdb'
      opts = Auth::Database.parse_postgres_multihost_url(url)

      expect(opts[:port]).to eq(5432)
    end

    it 'raises error for invalid URL format' do
      expect do
        Auth::Database.parse_postgres_multihost_url('invalid-url')
      end.to raise_error(ArgumentError, /Invalid PostgreSQL URL format/)
    end
  end

  describe 'Sequel::Migrator with advisory locks' do
    it 'runs migrations with advisory lock enabled' do
      # PostgreSQL supports advisory locks for concurrent safety
      # Note: test_db may have sufficient privileges if it's the same as migration_db
      Sequel::Migrator.run(
        migration_db,
        migrations_dir,
        use_advisory_lock: true,
      )

      expect(get_schema_version(db: test_db)).to eq(EXPECTED_SCHEMA_VERSION)
    end

    it 'runs migrations idempotently with locks' do
      # First run
      Sequel::Migrator.run(migration_db, migrations_dir, use_advisory_lock: true)
      expect(get_schema_version(db: test_db)).to eq(EXPECTED_SCHEMA_VERSION)

      # Second run should be no-op
      Sequel::Migrator.run(migration_db, migrations_dir, use_advisory_lock: true)
      expect(get_schema_version(db: test_db)).to eq(EXPECTED_SCHEMA_VERSION)
    end
  end

  describe 'all migrations applied correctly' do
    before do
      run_test_migrations(migration_db: migration_db, migrations_dir: migrations_dir)
    end

    it 'creates all expected tables from migration 001' do
      expect(verify_core_tables_exist(db: test_db)).to be true
    end

    it 'creates indexes from migration 002' do
      # Verify key indexes exist from migration 002
      # (Note: email index is created in 001, not 002)
      indexes_jwt = test_db.indexes(:account_jwt_refresh_keys)
      expect(indexes_jwt).not_to be_empty

      # Verify JWT refresh keys indexes exist
      account_id_idx = indexes_jwt.values.find { |idx| idx[:columns] == [:account_id] }
      expect(account_id_idx).not_to be_nil
    end

    it 'enforces foreign key constraints' do
      expect do
        setup_db[:accounts].insert(
          email: 'test@example.com',
          status_id: 999, # Invalid foreign key
          external_id: SecureRandom.uuid
        )
      end.to raise_error(Sequel::ForeignKeyConstraintViolation)
    end

    it 'enforces unique constraints on verified accounts only' do
      email = 'unique@example.com'

      # Insert verified account
      setup_db[:accounts].insert(
        email: email,
        status_id: 2, # Verified
        external_id: SecureRandom.uuid
      )

      # Try to insert duplicate verified account with same email
      expect do
        setup_db[:accounts].insert(
          email: email,
          status_id: 2, # Verified
          external_id: SecureRandom.uuid
        )
      end.to raise_error(Sequel::UniqueConstraintViolation)
    end

    it 'allows duplicate emails for closed accounts' do
      email = 'closed@example.com'

      # Insert first closed account
      setup_db[:accounts].insert(
        email: email,
        status_id: 3, # Closed
        external_id: SecureRandom.uuid
      )

      # Should allow second closed account with same email
      # (partial index only enforces uniqueness for status_id 1 and 2)
      expect do
        setup_db[:accounts].insert(
          email: email,
          status_id: 3, # Closed
          external_id: SecureRandom.uuid
        )
      end.not_to raise_error
    end
  end
end
