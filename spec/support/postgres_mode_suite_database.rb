# spec/support/postgres_mode_suite_database.rb
#
# frozen_string_literal: true

# Ensure factory is loaded before we reference it in RSpec.configure
require_relative 'factories/auth_account_factory'

# Suite-level PostgreSQL database setup for full auth mode tests.
#
# Creates a real PostgreSQL database connection shared across all
# :full_auth_mode, :postgres_database tagged specs within a test suite run.
# This avoids the overhead of creating and migrating a database per-file or
# per-test while ensuring PostgreSQL-specific features (triggers, functions,
# constraints) are properly tested.
#
# The database is lazily initialized when the first :postgres_database spec runs,
# and torn down only at suite end. This ensures:
# - Efficient: One migration run per suite
# - Isolated: Connection stub doesn't leak to non-postgres specs
# - Reliable: Original connection method restored at suite end
# - Realistic: Tests real PostgreSQL behavior (not SQLite)
#
# Environment Variables:
#   AUTH_DATABASE_URL          - PostgreSQL connection for running tests
#   AUTH_DATABASE_URL_MIGRATIONS - (Optional) Elevated connection for migrations
#
# Usage:
#   RSpec.describe 'My Test', :full_auth_mode, :postgres_database do
#     it 'has database access' do
#       expect(test_db).to be_a(Sequel::Database)
#     end
#
#     it 'can create accounts' do
#       account = create_verified_account(db: test_db, email: 'test@example.com')
#       expect(account[:email]).to eq('test@example.com')
#     end
#
#     it 'exercises PostgreSQL triggers' do
#       # Trigger fires on successful login audit log
#       account = create_verified_account(db: test_db)
#       test_db[:account_authentication_audit_logs].insert(
#         account_id: account[:id],
#         at: Time.now,
#         message: 'login successful'
#       )
#       # Check trigger populated account_activity_times
#       activity = test_db[:account_activity_times].where(id: account[:id]).first
#       expect(activity).not_to be_nil
#     end
#   end
#
module PostgresModeSuiteDatabase
  class << self
    attr_reader :database, :migration_database

    # Check if PostgreSQL is available for testing
    # @return [Boolean] true if AUTH_DATABASE_URL is set to a PostgreSQL URL
    def postgres_available?
      return @postgres_available if defined?(@postgres_available)

      database_url = ENV['AUTH_DATABASE_URL']
      @postgres_available = database_url &&
                            !database_url.empty? &&
                            database_url.start_with?('postgresql://', 'postgres://')
    end

    # Reason why PostgreSQL is unavailable (for skip messages)
    # @return [String, nil] message explaining why, or nil if available
    def unavailable_reason
      return nil if postgres_available?

      database_url = ENV['AUTH_DATABASE_URL']
      if database_url.nil? || database_url.empty?
        'AUTH_DATABASE_URL environment variable not set'
      else
        "AUTH_DATABASE_URL must be a PostgreSQL URL (got: #{database_url[0..20]}...)"
      end
    end

    def setup!
      return if @setup_complete

      require 'sequel'
      require 'auth/database'
      Sequel.extension :migration

      # Check if PostgreSQL is available - return early if not (specs will be skipped)
      return unless postgres_available?

      database_url = ENV['AUTH_DATABASE_URL']

      # Create PostgreSQL database connection
      @database = Sequel.connect(database_url)

      # Verify we're connected to PostgreSQL
      unless @database.database_type == :postgres
        raise "Expected PostgreSQL connection, got: #{@database.database_type}"
      end

      # Clean database before running migrations (handles stale state from previous runs)
      clean_database_for_setup

      # Run migrations (may require elevated privileges)
      run_migrations

      # Save original connection method for restoration
      @original_connection_method = Auth::Database.method(:connection)

      # Reset any existing connection before stubbing
      Auth::Database.reset_connection! if Auth::Database.respond_to?(:reset_connection!)

      # Stub the connection to return our test database
      db = @database
      Auth::Database.define_singleton_method(:connection) { db }

      # Ensure application is booted (idempotent in test mode)
      require 'onetime'
      require 'onetime/config'
      Onetime.boot! :test

      # Reset and rebuild registry with our test database connection
      require 'onetime/auth_config'
      require 'onetime/middleware'
      require 'onetime/application/registry'
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry

      @setup_complete = true
    end

    def teardown!
      return unless @setup_complete

      @migration_database&.disconnect
      @migration_database = nil
      @database&.disconnect
      @database = nil

      # Restore original connection method
      if @original_connection_method
        Auth::Database.define_singleton_method(:connection, @original_connection_method)
        @original_connection_method = nil
      end

      # Reset the connection state
      if Auth::Database.respond_to?(:reset_connection!)
        Auth::Database.reset_connection!
      else
        Auth::Database.instance_variable_set(:@connection, nil)
      end

      @setup_complete = false
    end

    def setup_complete?
      @setup_complete == true
    end

    # Clean database for initial setup
    #
    # Uses elevated connection if available to handle CI permission model where
    # onetime_migrator owns tables and onetime_user has limited privileges.
    #
    # Strategy: Drop and recreate schema to ensure clean state, but do this
    # with the migration connection (if available) to preserve permission model.
    def clean_database_for_setup
      # Use migration connection if available (has superuser-like privileges)
      # Otherwise fall back to regular connection
      migration_url = ENV['AUTH_DATABASE_URL_MIGRATIONS']
      use_elevated = migration_url && !migration_url.to_s.empty? && migration_url != ENV['AUTH_DATABASE_URL']

      if use_elevated
        # Create temporary elevated connection for schema cleanup
        elevated_db = Sequel.connect(migration_url)
        begin
          clean_schema_with_connection(elevated_db)
        ensure
          elevated_db.disconnect
        end
      elsif @database
        # Use regular connection (works when running as database owner)
        clean_schema_with_connection(@database)
      end
    rescue Sequel::DatabaseError => e
      warn "[PostgresModeSuiteDatabase] Failed to clean database: #{e.message}"
      # Continue - migrations may still succeed if database is actually clean
    end

    # Perform the actual schema drop/recreate with the given connection
    def clean_schema_with_connection(db)
      # Drop and recreate public schema (removes all objects)
      db.run 'DROP SCHEMA IF EXISTS public CASCADE'
      db.run 'CREATE SCHEMA public'
      db.run 'GRANT ALL ON SCHEMA public TO postgres'
      db.run 'GRANT ALL ON SCHEMA public TO public'

      # Re-apply grants for test users after schema recreation
      apply_schema_grants_with_connection(db)
    end

    # Apply schema-level grants using the given connection
    def apply_schema_grants_with_connection(db)
      # Check if onetime_migrator role exists (CI environment)
      migrator_exists = db.fetch(
        "SELECT 1 FROM pg_roles WHERE rolname = 'onetime_migrator'"
      ).any?

      return unless migrator_exists

      # Re-apply schema grants
      db.run 'GRANT ALL ON SCHEMA public TO onetime_migrator'
      db.run 'GRANT ALL ON SCHEMA public TO onetime_user'

      # Re-apply default privileges so tables created by onetime_migrator
      # are automatically accessible to onetime_user
      db.run <<~SQL
        ALTER DEFAULT PRIVILEGES FOR ROLE onetime_migrator IN SCHEMA public
          GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO onetime_user
      SQL
      db.run <<~SQL
        ALTER DEFAULT PRIVILEGES FOR ROLE onetime_migrator IN SCHEMA public
          GRANT USAGE, SELECT ON SEQUENCES TO onetime_user
      SQL
      db.run <<~SQL
        ALTER DEFAULT PRIVILEGES FOR ROLE onetime_migrator IN SCHEMA public
          GRANT EXECUTE ON FUNCTIONS TO onetime_user
      SQL
    rescue Sequel::DatabaseError => e
      warn "[PostgresModeSuiteDatabase] Failed to apply schema grants: #{e.message}"
      # Continue - may not have permission or roles don't exist
    end


    # Run migrations using elevated connection if available
    # Also stores migration connection for test data setup (infrastructure tests)
    def run_migrations
      migrations_path = File.join(Onetime::HOME, 'apps', 'web', 'auth', 'migrations')

      # Check if we need elevated privileges for migrations
      # Only check ENV var - OT.auth_config is not yet available during setup
      migration_url = ENV['AUTH_DATABASE_URL_MIGRATIONS']

      if migration_url && !migration_url.to_s.empty? && migration_url != ENV['AUTH_DATABASE_URL']
        # Use separate elevated connection for migrations
        # Keep it open for test data setup (infrastructure tests need INSERT privileges)
        @migration_database = Sequel.connect(migration_url)
        Sequel::Migrator.run(@migration_database, migrations_path)
      else
        # Run migrations with standard connection
        Sequel::Migrator.run(@database, migrations_path)
        @migration_database = nil
      end
    end

    # Clean all Rodauth tables using TRUNCATE CASCADE
    # This is faster than DELETE and resets sequences
    # Uses migration_database if available (has TRUNCATE privileges)
    def clean_tables!
      db = @migration_database || @database
      return unless db

      # Disable foreign key checks for cleaning
      # PostgreSQL uses TRUNCATE CASCADE which handles dependencies
      AuthAccountFactory::RODAUTH_TABLES.each do |table|
        next unless db.table_exists?(table)

        begin
          # Use Sequel's truncate method with cascade option for safe identifier handling
          db[table].truncate(cascade: true)
        rescue Sequel::DatabaseError => e
          # Log but don't fail - some tables may have dependencies
          warn "Failed to truncate #{table}: #{e.message}"
        end
      end

      # Reset sequences for primary keys
      # Optimized: fetch all sequences in a single query instead of looping per table
      begin
        # Fetch all sequence names for tables with serial columns using Sequel's DSL
        table_names = AuthAccountFactory::RODAUTH_TABLES.map(&:to_s)
        sequences_to_reset = db[:information_schema__columns]
          .select { Sequel.function(:pg_get_serial_sequence, :table_name, :column_name).as(:sequence_name) }
          .distinct
          .where(table_schema: 'public')
          .where(table_name: table_names)
          .where(Sequel.like(:column_default, 'nextval%'))
          .all

        # Filter out nil results and batch reset all sequences in a single call
        sequence_names = sequences_to_reset
          .map { |row| row[:sequence_name] }
          .compact

        if sequence_names.any?
          alter_commands = sequence_names.map do |seq_name|
            "ALTER SEQUENCE #{Sequel.literal(Sequel.identifier(seq_name))} RESTART WITH 1"
          end
          db.run(alter_commands.join('; '))
        end
      rescue Sequel::DatabaseError
        # Ignore if there's an issue - this is a cleanup optimization
        nil
      end
    end
  end
end

# RSpec configuration for PostgreSQL full auth mode tests
RSpec.configure do |config|
  # Exclude :postgres_database specs entirely when PostgreSQL is unavailable.
  # This prevents errors during spec:fast (unit tests) which don't have PostgreSQL.
  # The specs will be skipped with a clear message about why.
  unless PostgresModeSuiteDatabase.postgres_available?
    config.filter_run_excluding postgres_database: true

    # Log once at suite start that PostgreSQL tests are being skipped
    config.before(:suite) do
      reason = PostgresModeSuiteDatabase.unavailable_reason
      # Only warn if we actually have postgres_database specs (avoid noise in unrelated runs)
      if RSpec.configuration.files_to_run.any? { |f| f.include?('postgres') }
        warn "[PostgresModeSuiteDatabase] Skipping :postgres_database specs: #{reason}"
      end
    end
  end

  # Lazy setup: first :postgres_database spec triggers database creation
  # Using before(:context) ensures it runs once per describe block,
  # but setup! is idempotent so it's safe if multiple blocks have the tag
  config.before(:context, :postgres_database) do
    PostgresModeSuiteDatabase.setup!
  end

  # Clean tables between describe blocks to catch leaked test data
  # Individual tests should still clean up after themselves, but this
  # provides a safety net without hiding which test leaked data
  config.after(:context, :postgres_database) do
    PostgresModeSuiteDatabase.clean_tables!
  end

  # Suite-level teardown: only runs once at the very end
  config.after(:suite) do
    PostgresModeSuiteDatabase.teardown!
  end

  # Include factory methods for all :postgres_database specs
  config.include AuthAccountFactory, :postgres_database

  # Provide test_db helper method for :postgres_database specs
  # test_db: Regular connection for querying (matches application runtime)
  # setup_db: Elevated connection for test data setup (has INSERT privileges)
  config.include(Module.new {
    def test_db
      PostgresModeSuiteDatabase.database
    end

    # Returns elevated connection for test data setup, falls back to test_db
    # Use this for creating test accounts and other setup operations
    def setup_db
      PostgresModeSuiteDatabase.migration_database || PostgresModeSuiteDatabase.database
    end
  }, :postgres_database)
end
