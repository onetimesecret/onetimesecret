# spec/support/helpers/migration_test_helpers.rb
#
# frozen_string_literal: true

require 'sequel'
require 'fileutils'
require 'timeout'
require 'concurrent'

# Shared helpers for migration integration tests
#
# Provides utilities for:
# - Creating and cleaning up test databases
# - Simulating partial migration states
# - Verifying schema versions and table existence
# - Running concurrent migration processes (PostgreSQL only)
#
# Usage:
#   RSpec.describe 'Migrations', :full_auth_mode do
#     include MigrationTestHelpers
#
#     it 'completes partial migrations' do
#       db = create_partial_migration_state(version: 3)
#       Auth::Migrator.run_if_needed
#       expect(verify_schema_version(db: db)).to eq(5)
#     end
#   end
#
module MigrationTestHelpers
  # Create a fresh database connection for testing migrations
  #
  # @param url [String] Database URL (defaults to ENV['AUTH_DATABASE_URL'])
  # @return [Sequel::Database] Database connection
  def create_test_database_connection(url: nil)
    url ||= ENV['AUTH_DATABASE_URL'] || 'sqlite::memory:'
    Sequel.connect(url)
  end

  # Get the current schema version from the database
  #
  # @param db [Sequel::Database] Database connection
  # @return [Integer] Current schema version (0 if schema_info table doesn't exist)
  def get_schema_version(db:)
    return 0 unless db.table_exists?(:schema_info)

    db[:schema_info].first&.fetch(:version, 0) || 0
  end

  # Verify the schema version matches expected value
  #
  # @param db [Sequel::Database] Database connection
  # @param expected [Integer] Expected schema version
  # @return [Integer] Actual schema version
  def verify_schema_version(db:, expected: nil)
    version = get_schema_version(db: db)
    expect(version).to eq(expected) if expected
    version
  end

  # Check if a table exists in the database
  #
  # @param db [Sequel::Database] Database connection
  # @param table_name [Symbol] Table name to check
  # @return [Boolean] True if table exists
  def verify_table_exists(db:, table_name:)
    db.table_exists?(table_name)
  end

  # Create a database with partial migration state (migrated to specific version)
  #
  # @param db [Sequel::Database] Database connection
  # @param version [Integer] Target migration version (1-5)
  # @return [Sequel::Database] Database with partial migrations
  def create_partial_migration_state(db:, version:)
    raise ArgumentError, 'version must be between 1 and 5' unless (1..5).cover?(version)

    Sequel.extension :migration
    migrations_dir = File.join(Onetime::HOME, 'apps', 'web', 'auth', 'migrations')

    Sequel::Migrator.run(
      db,
      migrations_dir,
      target: version,
      use_transactions: true,
    )

    db
  end

  # Drop all Rodauth tables from the database (clean slate)
  #
  # For PostgreSQL with dual-user setup (CI environment), this method uses
  # the elevated migration connection to drop/recreate the schema, ensuring
  # proper ownership and default privileges are maintained.
  #
  # @param db [Sequel::Database] Database connection
  def drop_all_tables(db:)
    if db.database_type == :postgres
      # For PostgreSQL: drop and recreate public schema (fastest, most thorough)
      # Removes tables, views, functions, triggers, extensions - everything
      #
      # Use elevated connection if available to handle CI permission model
      migration_url = ENV['AUTH_DATABASE_URL_MIGRATIONS']
      use_elevated = migration_url && !migration_url.to_s.empty? && migration_url != ENV['AUTH_DATABASE_URL']

      if use_elevated
        elevated_db = Sequel.connect(migration_url)
        begin
          drop_and_recreate_postgres_schema(elevated_db)
        ensure
          elevated_db.disconnect
        end
      else
        drop_and_recreate_postgres_schema(db)
      end
    else
      # For SQLite: drop tables individually (no schema support)
      tables = %i[
        account_sms_codes
        account_recovery_codes
        account_otp_unlocks
        account_otp_keys
        account_webauthn_keys
        account_webauthn_user_ids
        account_session_keys
        account_active_session_keys
        account_activity_times
        account_password_change_times
        account_email_auth_keys
        account_lockouts
        account_login_failures
        account_remember_keys
        account_login_change_keys
        account_verification_keys
        account_jwt_refresh_keys
        account_password_reset_keys
        account_authentication_audit_logs
        account_previous_password_hashes
        account_password_hashes
        accounts
        account_statuses
        account_identities
        schema_info
      ]

      tables.each do |table|
        db.drop_table?(table)
      rescue Sequel::DatabaseError
        # Ignore errors - table might not exist
        nil
      end
    end
  rescue Sequel::DatabaseError => e
    warn "[MigrationTestHelpers] Failed to drop tables: #{e.message}"
    # Continue - tests may fail but at least we tried
  end

  private

  # Drop and recreate PostgreSQL public schema with proper grants
  def drop_and_recreate_postgres_schema(db)
    db.run 'DROP SCHEMA IF EXISTS public CASCADE'
    db.run 'CREATE SCHEMA public'
    db.run 'GRANT ALL ON SCHEMA public TO postgres'
    db.run 'GRANT ALL ON SCHEMA public TO public'

    # Re-apply grants for CI test users if they exist
    apply_ci_schema_grants(db)
  end

  # Apply schema grants for CI environment test users
  def apply_ci_schema_grants(db)
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
  rescue Sequel::DatabaseError
    # Ignore if grants fail - may not have permission or roles don't exist
    nil
  end

  # Simulate concurrent process boot by running migrations in parallel threads
  # Each thread runs migrations independently (like separate app instances)
  #
  # @param process_count [Integer] Number of concurrent processes to simulate (default: 3)
  # @param database_url [String] Database URL for all processes
  # @param migrations_dir [String] Path to migrations directory
  # @param timeout_seconds [Integer] Maximum time to wait for all processes (default: 10)
  # @return [Array<Hash>] Results from each thread with :success, :error, :version
  def simulate_concurrent_boot(process_count: 3, database_url:, migrations_dir:, timeout_seconds: 10)
    results = Concurrent::Array.new
    threads = []

    process_count.times do |i|
      threads << Thread.new do
        result = { process_id: i, success: false, error: nil, version: nil }

        begin
          # Each "process" creates its own database connection
          # This simulates separate application instances
          db = Sequel.connect(database_url)

          begin
            # Run migrations directly using Sequel::Migrator
            # This simulates what Auth::Migrator.run_if_needed does internally
            Sequel.extension :migration
            Sequel::Migrator.run(
              db,
              migrations_dir,
              use_transactions: true,
              use_advisory_lock: db.adapter_scheme == :postgres,
            )

            result[:version] = get_schema_version(db: db)
            result[:success] = true
          ensure
            db.disconnect
          end
        rescue StandardError => e
          result[:error]   = e.message
          result[:success] = false
        end

        results << result
      end
    end

    # Wait for all threads with timeout
    Timeout.timeout(timeout_seconds) do
      threads.each(&:join)
    end

    results.to_a
  rescue Timeout::Error
    threads.each(&:kill)
    raise 'Concurrent migration test timed out'
  end

  # Verify all core Rodauth tables exist (migration 001)
  #
  # @param db [Sequel::Database] Database connection
  # @return [Boolean] True if all tables exist
  def verify_core_tables_exist(db:)
    core_tables = %i[
      account_statuses
      accounts
      account_password_hashes
      account_authentication_audit_logs
      account_password_reset_keys
      account_jwt_refresh_keys
      account_verification_keys
      account_login_change_keys
      account_remember_keys
      account_login_failures
      account_lockouts
      account_email_auth_keys
      account_password_change_times
      account_activity_times
      account_session_keys
      account_active_session_keys
      account_webauthn_user_ids
      account_webauthn_keys
      account_otp_keys
      account_otp_unlocks
      account_recovery_codes
      account_sms_codes
      account_previous_password_hashes
    ]

    core_tables.all? { |table| db.table_exists?(table) }
  end

  # Verify PostgreSQL-specific features exist (functions, triggers, views)
  #
  # @param db [Sequel::Database] Database connection
  # @return [Hash] Status of each feature type
  def verify_postgres_features(db:)
    return { functions: false, triggers: false, views: false } unless db.database_type == :postgres

    {
      functions: postgres_functions_exist?(db: db),
      triggers: postgres_triggers_exist?(db: db),
      views: postgres_views_exist?(db: db),
    }
  end

  private

  # Check if PostgreSQL functions exist (migration 003)
  def postgres_functions_exist?(db:)
    # Check for rodauth_get_salt function (created by migration 003)
    result = db.fetch(<<~SQL).first
      SELECT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE proname = 'rodauth_get_salt'
      ) AS exists
    SQL

    result[:exists]
  end

  # Check if PostgreSQL triggers exist (migration 004)
  def postgres_triggers_exist?(db:)
    # Check for trigger on accounts table
    result = db.fetch(<<~SQL).first
      SELECT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'update_accounts_updated_at'
      ) AS exists
    SQL

    result[:exists]
  end

  # Check if PostgreSQL views exist (migration 005)
  def postgres_views_exist?(db:)
    # Check for at least one view (adjust based on actual view names)
    result = db.fetch(<<~SQL).first
      SELECT COUNT(*) AS count
      FROM pg_views
      WHERE schemaname = 'public'
        AND viewname LIKE 'account_%'
    SQL

    result[:count] > 0
  end
end
