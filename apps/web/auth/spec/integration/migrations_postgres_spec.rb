# apps/web/auth/spec/integration/migrations_postgres_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'support/helpers/migration_test_helpers'

# Test PostgreSQL migrations with real database
# Requires AUTH_DATABASE_URL to be set to a PostgreSQL database
RSpec.describe 'Auth::Migrator PostgreSQL Integration', :postgres_database do
  include MigrationTestHelpers

  let(:migrations_dir) { File.join(Onetime::HOME, 'apps', 'web', 'auth', 'migrations') }
  let(:test_db) { PostgresModeSuiteDatabase.database }

  before do
    # Clean slate for each test
    drop_all_tables(db: test_db)
  end

  describe 'first boot with no database' do
    it 'creates complete schema from scratch' do
      # Verify no schema exists
      expect(test_db.table_exists?(:schema_info)).to be false
      expect(test_db.table_exists?(:accounts)).to be false

      # Run migrations
      Sequel.extension :migration
      Sequel::Migrator.run(test_db, migrations_dir, use_transactions: true)

      # Verify schema version is at latest (5 migrations)
      version = verify_schema_version(db: test_db, expected: 5)
      expect(version).to eq(5)

      # Verify all core tables exist
      expect(verify_core_tables_exist(db: test_db)).to be true
    end

    it 'enables citext extension for case-insensitive email' do
      Sequel::Migrator.run(test_db, migrations_dir)

      # Verify citext extension is enabled
      result = test_db.fetch(<<~SQL).first
        SELECT EXISTS (
          SELECT 1 FROM pg_extension WHERE extname = 'citext'
        ) AS exists
      SQL

      expect(result[:exists]).to be true
    end

    it 'creates PostgreSQL-specific constraints' do
      Sequel::Migrator.run(test_db, migrations_dir)

      # Try to insert invalid email (should fail constraint)
      expect do
        test_db[:accounts].insert(
          email: 'invalid-email', # Missing @ and domain
          status_id: 2,
          external_id: SecureRandom.uuid
        )
      end.to raise_error(Sequel::CheckConstraintViolation)
    end
  end

  describe 'subsequent boots are idempotent' do
    before do
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
      create_partial_migration_state(db: test_db, version: 1)
      expect(get_schema_version(db: test_db)).to eq(1)

      Sequel::Migrator.run(test_db, migrations_dir)

      expect(verify_schema_version(db: test_db, expected: 5)).to eq(5)
      expect(verify_core_tables_exist(db: test_db)).to be true
    end

    it 'completes remaining migrations from version 3' do
      create_partial_migration_state(db: test_db, version: 3)
      expect(get_schema_version(db: test_db)).to eq(3)

      Sequel::Migrator.run(test_db, migrations_dir)

      expect(verify_schema_version(db: test_db, expected: 5)).to eq(5)
    end

    it 'maintains data integrity when completing migrations' do
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
      expect(get_schema_version(db: test_db)).to eq(5)
    end
  end

  describe 'migration failure handling' do
    it 'rolls back transaction on migration error' do
      invalid_migrations_dir = File.join(Dir.tmpdir, 'nonexistent_migrations')

      expect do
        Sequel::Migrator.run(test_db, invalid_migrations_dir)
      end.to raise_error(Sequel::Migrator::Error)

      # Verify no partial schema was created
      expect(test_db.table_exists?(:accounts)).to be false
    end

    it 'preserves existing schema on failed migration attempt' do
      Sequel::Migrator.run(test_db, migrations_dir)
      initial_version = get_schema_version(db: test_db)

      expect do
        Sequel::Migrator.run(test_db, '/nonexistent/path')
      end.to raise_error(Sequel::Migrator::Error)

      expect(get_schema_version(db: test_db)).to eq(initial_version)
    end
  end

  describe 'PostgreSQL-specific features' do
    before do
      Sequel::Migrator.run(test_db, migrations_dir)
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
      account_id = test_db[:accounts].insert(
        email: 'trigger@example.com',
        status_id: 2,
        external_id: SecureRandom.uuid
      )

      original_updated_at = test_db[:accounts].where(id: account_id).get(:updated_at)

      # Wait to ensure timestamp difference
      sleep 0.1

      # Update account (trigger should fire)
      test_db[:accounts].where(id: account_id).update(status_id: 1)

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
      it 'uses the same connection for migrations' do
        # Default case - when migrations URL not set, use standard URL
        expect(ENV['AUTH_DATABASE_URL_MIGRATIONS']).to be_nil

        Sequel::Migrator.run(test_db, migrations_dir)
        expect(get_schema_version(db: test_db)).to eq(5)
      end
    end

    context 'when AUTH_DATABASE_URL_MIGRATIONS is different (elevated)' do
      it 'allows separate credentials for migrations' do
        # Use postgres user to create a restricted test user
        # This demonstrates the production pattern: elevated user for migrations, restricted for runtime

        # Clean database first
        drop_all_tables(db: test_db)

        # Ensure clean user state - drop and recreate
        begin
          test_db.run("DROP USER IF EXISTS onetime_app_test")
          test_db.run("CREATE USER onetime_app_test WITH PASSWORD 'testpass'")
        rescue Sequel::DatabaseError => e
          raise "Failed to create test user: #{e.message}"
        end

        # Explicitly revoke default CREATE privilege on public schema
        # (PostgreSQL grants CREATE to PUBLIC role by default)
        test_db.run("REVOKE CREATE ON SCHEMA public FROM PUBLIC")
        test_db.run("REVOKE CREATE ON SCHEMA public FROM onetime_app_test")

        # Create restricted connection (before granting any permissions)
        restricted_url = 'postgresql://onetime_app_test:testpass@localhost:5432/onetime_auth_test'
        restricted_db = Sequel.connect(restricted_url)

        begin
          # Verify restricted user cannot create tables (no CREATE privilege)
          expect do
            restricted_db.run("CREATE TABLE test_table (id INT)")
          end.to raise_error(Sequel::DatabaseError, /permission denied/)

          # Set up dual URLs
          original_migration_url = ENV['AUTH_DATABASE_URL_MIGRATIONS']
          ENV['AUTH_DATABASE_URL_MIGRATIONS'] = ENV['AUTH_DATABASE_URL'] # postgres user (elevated)

          # Run migrations using elevated connection
          # This creates tables, functions, triggers with postgres privileges
          Sequel::Migrator.run(test_db, migrations_dir)

          # Grant CRUD permissions to restricted user on created tables
          test_db.run("GRANT USAGE ON SCHEMA public TO onetime_app_test")
          tables = test_db.tables
          tables.each do |table|
            test_db.run("GRANT SELECT, INSERT, UPDATE, DELETE ON #{table} TO onetime_app_test")
          end

          # Verify restricted user can perform CRUD but cannot create new tables
          expect(restricted_db[:accounts].count).to eq(0)  # Can read

          # Can insert
          account_id = restricted_db[:accounts].insert(
            email: 'restricted@example.com',
            status_id: 2,
            external_id: SecureRandom.uuid
          )
          expect(account_id).to be > 0

          # Can update
          restricted_db[:accounts].where(id: account_id).update(status_id: 1)
          expect(restricted_db[:accounts].where(id: account_id).first[:status_id]).to eq(1)

          # Can delete
          restricted_db[:accounts].where(id: account_id).delete
          expect(restricted_db[:accounts].where(id: account_id).count).to eq(0)

          # Verify migrations completed successfully
          expect(get_schema_version(db: test_db)).to eq(5)
          expect(verify_core_tables_exist(db: test_db)).to be true
        ensure
          restricted_db.disconnect if restricted_db
          ENV['AUTH_DATABASE_URL_MIGRATIONS'] = original_migration_url

          # Cleanup: revoke privileges, drop test user, restore default permissions
          begin
            # Revoke all privileges before dropping user
            test_db.run("REVOKE ALL ON SCHEMA public FROM onetime_app_test")
            tables = test_db.tables
            tables.each do |table|
              test_db.run("REVOKE ALL ON #{table} FROM onetime_app_test")
            end

            test_db.run("DROP USER IF EXISTS onetime_app_test")

            # Restore default CREATE privilege for PUBLIC role
            test_db.run("GRANT CREATE ON SCHEMA public TO PUBLIC")
          rescue Sequel::DatabaseError => e
            warn "Failed to cleanup test user: #{e.message}"
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
      Sequel::Migrator.run(
        test_db,
        migrations_dir,
        use_advisory_lock: true,
      )

      expect(get_schema_version(db: test_db)).to eq(5)
    end

    it 'runs migrations idempotently with locks' do
      # First run
      Sequel::Migrator.run(test_db, migrations_dir, use_advisory_lock: true)
      expect(get_schema_version(db: test_db)).to eq(5)

      # Second run should be no-op
      Sequel::Migrator.run(test_db, migrations_dir, use_advisory_lock: true)
      expect(get_schema_version(db: test_db)).to eq(5)
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
        test_db[:accounts].insert(
          email: 'test@example.com',
          status_id: 999, # Invalid foreign key
          external_id: SecureRandom.uuid
        )
      end.to raise_error(Sequel::ForeignKeyConstraintViolation)
    end

    it 'enforces unique constraints on verified accounts only' do
      email = 'unique@example.com'

      # Insert verified account
      test_db[:accounts].insert(
        email: email,
        status_id: 2, # Verified
        external_id: SecureRandom.uuid
      )

      # Try to insert duplicate verified account with same email
      expect do
        test_db[:accounts].insert(
          email: email,
          status_id: 2, # Verified
          external_id: SecureRandom.uuid
        )
      end.to raise_error(Sequel::UniqueConstraintViolation)
    end

    it 'allows duplicate emails for closed accounts' do
      email = 'closed@example.com'

      # Insert first closed account
      test_db[:accounts].insert(
        email: email,
        status_id: 3, # Closed
        external_id: SecureRandom.uuid
      )

      # Should allow second closed account with same email
      # (partial index only enforces uniqueness for status_id 1 and 2)
      expect do
        test_db[:accounts].insert(
          email: email,
          status_id: 3, # Closed
          external_id: SecureRandom.uuid
        )
      end.not_to raise_error
    end
  end
end
