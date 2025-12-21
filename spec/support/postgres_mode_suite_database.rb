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
    attr_reader :database

    def setup!
      return if @setup_complete

      require 'sequel'
      require 'auth/database'
      Sequel.extension :migration

      # Ensure PostgreSQL connection is available
      database_url = ENV.fetch('AUTH_DATABASE_URL') do
        raise 'AUTH_DATABASE_URL must be set for PostgreSQL tests (e.g., postgresql://user:pass@localhost/onetime_auth_test)'
      end

      unless database_url.start_with?('postgresql://', 'postgres://')
        raise "AUTH_DATABASE_URL must be a PostgreSQL URL (current URL format invalid)"
      end

      # Create PostgreSQL database connection
      @database = Sequel.connect(database_url)

      # Verify we're connected to PostgreSQL
      unless @database.database_type == :postgres
        raise "Expected PostgreSQL connection, got: #{@database.database_type}"
      end

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

    # Run migrations using elevated connection if available
    def run_migrations
      migrations_path = File.join(Onetime::HOME, 'apps', 'web', 'auth', 'migrations')

      # Check if we need elevated privileges for migrations
      migration_url = ENV['AUTH_DATABASE_URL_MIGRATIONS']

      if migration_url && migration_url != ENV['AUTH_DATABASE_URL']
        # Use separate elevated connection for migrations only
        migration_db = Sequel.connect(migration_url)
        begin
          Sequel::Migrator.run(migration_db, migrations_path)
        ensure
          migration_db.disconnect
        end
      else
        # Run migrations with standard connection
        Sequel::Migrator.run(@database, migrations_path)
      end
    end

    # Clean all Rodauth tables using TRUNCATE CASCADE
    # This is faster than DELETE and resets sequences
    def clean_tables!
      return unless @database

      # Disable foreign key checks for cleaning
      # PostgreSQL uses TRUNCATE CASCADE which handles dependencies
      AuthAccountFactory::RODAUTH_TABLES.each do |table|
        next unless @database.table_exists?(table)

        begin
          # Use Sequel's truncate method with cascade option for safe identifier handling
          @database[table].truncate(cascade: true)
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
        sequences_to_reset = @database[:information_schema__columns]
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
          @database.run(alter_commands.join('; '))
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
  # Lazy setup: first :postgres_database spec triggers database creation
  # Using before(:context) ensures it runs once per describe block,
  # but setup! is idempotent so it's safe if multiple blocks have the tag
  config.before(:context, :full_auth_mode, :postgres_database) do
    PostgresModeSuiteDatabase.setup!
  end

  # Clean tables between describe blocks to catch leaked test data
  # Individual tests should still clean up after themselves, but this
  # provides a safety net without hiding which test leaked data
  config.after(:context, :full_auth_mode, :postgres_database) do
    PostgresModeSuiteDatabase.clean_tables!
  end

  # Suite-level teardown: only runs once at the very end
  config.after(:suite) do
    PostgresModeSuiteDatabase.teardown!
  end

  # Include factory methods for all :postgres_database specs
  config.include AuthAccountFactory, :full_auth_mode, :postgres_database

  # Provide test_db helper method for :postgres_database specs
  config.include(Module.new {
    def test_db
      PostgresModeSuiteDatabase.database
    end
  }, :full_auth_mode, :postgres_database)
end
