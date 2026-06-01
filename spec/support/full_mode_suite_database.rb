# spec/support/full_mode_suite_database.rb
#
# frozen_string_literal: true

# Ensure factory is loaded before we reference it in RSpec.configure
require_relative 'factories/auth_account_factory'

# Suite-level database setup for full auth mode tests.
#
# Connects to whatever AUTH_DATABASE_URL specifies — SQLite (in-memory or
# file-backed) or PostgreSQL — so the same DB-agnostic specs can run against
# either engine. When no URL is set, defaults to in-memory SQLite for local
# development speed.
#
# The database is lazily initialized when the first :full_auth_mode spec runs,
# and torn down only at suite end. This ensures:
# - Efficient: One migration run per suite
# - Isolated: Connection stub doesn't leak to non-full_auth_mode specs
# - Reliable: Original connection method restored at suite end
#
# Usage:
#   RSpec.describe 'My Test', :full_auth_mode do
#     it 'has database access' do
#       expect(test_db).to be_a(Sequel::Database)
#     end
#
#     it 'can create accounts' do
#       account = create_verified_account(db: test_db, email: 'test@example.com')
#       expect(account[:email]).to eq('test@example.com')
#     end
#   end
#
module FullModeSuiteDatabase
  class << self
    attr_reader :database, :migration_database

    def setup!
      return if @setup_complete

      require 'sequel'
      require 'auth/database'
      Sequel.extension :migration

      database_url = ENV.fetch('AUTH_DATABASE_URL', nil)

      @using_postgres = database_url &&
                        database_url.start_with?('postgresql://', 'postgres://')

      @database = if @using_postgres
        Sequel.connect(database_url)
      elsif database_url && database_url.start_with?('sqlite')
        Sequel.connect(database_url)
      else
        Sequel.sqlite
      end

      if @using_postgres
        clean_postgres_for_setup
        run_postgres_migrations
      else
        migrations_path = File.join(Onetime::HOME, 'apps', 'web', 'auth', 'migrations')
        Sequel::Migrator.run(@database, migrations_path)
      end

      # Save original connection method for restoration
      @original_connection_method = Auth::Database.method(:connection)

      # Reset any existing connection before stubbing
      Auth::Database.reset_connection! if Auth::Database.respond_to?(:reset_connection!)

      # Stub the connection to return our test database
      db = @database
      Auth::Database.define_singleton_method(:connection) { db }

      # Boot the application with a forced fresh boot.
      #
      # `force: true` resets boot state first so the full initializer chain
      # re-runs here. A plain `Onetime.boot! :test` is idempotent in test mode
      # and silently skips when boot state is already :started — which happens
      # whenever an earlier spec (e.g. spec/integration/all boot/config specs)
      # booted first. The skip is mostly harmless, except it bypasses the
      # ConfigureFamilia initializer that sets Familia's encryption keys and
      # current_key_version. Those are process-global; if a prior connect_to_db:
      # false boot left boot :started without running ConfigureFamilia, the
      # encryption config is never populated and any encrypted-field write
      # (e.g. Receipt.spawn_pair) raises "Key version cannot be nil".
      # Forcing a fresh boot guarantees ConfigureFamilia runs for the suite.
      require 'onetime'
      require 'onetime/config'
      Onetime.boot!(:test, force: true)

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

    def postgres?
      @using_postgres == true
    end

    def engine_label
      postgres? ? 'PostgreSQL' : 'SQLite'
    end

    # Clean all Rodauth tables (for tests that need a fresh database state)
    def clean_tables!
      return unless @database

      if postgres?
        clean_tables_postgres!
      else
        clean_tables_sqlite!
      end
    end

    private

    def clean_tables_sqlite!
      AuthAccountFactory::RODAUTH_TABLES.each do |table|
        @database[table].delete if @database.table_exists?(table)
      rescue Sequel::DatabaseError
        nil
      end
    end

    def clean_tables_postgres!
      db = @migration_database || @database
      AuthAccountFactory::RODAUTH_TABLES.each do |table|
        next unless db.table_exists?(table)
        db[table].truncate(cascade: true, restart: true)
      rescue Sequel::DatabaseError => e
        warn "Failed to truncate #{table}: #{e.message}"
      end
    end

    # Drop all tables so migrations re-run from scratch on PostgreSQL.
    # Mirrors PostgresModeSuiteDatabase#clean_database_for_setup.
    def clean_postgres_for_setup
      migration_url = ENV['AUTH_DATABASE_URL_MIGRATIONS']
      use_elevated = migration_url &&
                     !migration_url.to_s.empty? &&
                     migration_url != ENV['AUTH_DATABASE_URL']

      if use_elevated
        elevated_db = Sequel.connect(migration_url)
        begin
          drop_all_tables(elevated_db)
        ensure
          elevated_db.disconnect
        end
      else
        drop_all_tables(@database)
      end
    end

    def drop_all_tables(db)
      tables = db.tables
      if tables.any?
        table_list = tables.map { |t| db.literal(Sequel.identifier(t)) }.join(', ')
        db.run "DROP TABLE IF EXISTS #{table_list} CASCADE"
      end

      our_functions = %w[
        rodauth_get_salt
        rodauth_valid_password_hash
        cleanup_expired_tokens
        update_last_login_time
        cleanup_expired_tokens_extended
        update_accounts_updated_at
        update_session_last_use
        cleanup_old_audit_logs
        get_account_security_summary
      ]
      db.run "DROP FUNCTION IF EXISTS #{our_functions.join(', ')} CASCADE"
    end

    def run_postgres_migrations
      migrations_path = File.join(Onetime::HOME, 'apps', 'web', 'auth', 'migrations')
      migration_url = ENV['AUTH_DATABASE_URL_MIGRATIONS']

      if migration_url && !migration_url.to_s.empty? && migration_url != ENV['AUTH_DATABASE_URL']
        @migration_database ||= Sequel.connect(migration_url)
        Sequel::Migrator.run(@migration_database, migrations_path)
      else
        Sequel::Migrator.run(@database, migrations_path)
        @migration_database = nil
      end
    end
  end
end

# RSpec configuration for full auth mode tests (SQLite or PostgreSQL)
RSpec.configure do |config|
  # Database setup lambda - shared between :full_auth_mode and :sqlite_database tags
  # Setup is idempotent, so it's safe if multiple hooks trigger it
  full_mode_setup = lambda do |example_or_group|
    # Skip if this is a PG-only spec (handled by PostgresModeSuiteDatabase)
    metadata = example_or_group.respond_to?(:metadata) ? example_or_group.metadata : example_or_group.class.metadata
    return if metadata[:postgres_database]

    FullModeSuiteDatabase.setup!
  end

  full_mode_cleanup = lambda do |example_or_group|
    metadata = example_or_group.respond_to?(:metadata) ? example_or_group.metadata : example_or_group.class.metadata
    return if metadata[:postgres_database]

    FullModeSuiteDatabase.clean_tables!
  end

  # Lazy setup for :full_auth_mode specs (derived from spec/integration/full/ directory)
  # This ensures the database is set up even without explicit :sqlite_database tag
  config.before(:context, :full_auth_mode, &full_mode_setup)
  config.after(:context, :full_auth_mode, &full_mode_cleanup)

  # Also support explicit :sqlite_database tag for backward compatibility
  config.before(:context, :sqlite_database, &full_mode_setup)
  config.after(:context, :sqlite_database, &full_mode_cleanup)

  # Per-test cleanup to prevent data leakage between tests within the same context.
  # The context-level cleanup only runs at the end of a describe block, but tests
  # within that block may create data that affects subsequent tests.
  full_mode_per_test_cleanup = lambda do |example|
    metadata = example.respond_to?(:metadata) ? example.metadata : example.class.metadata
    return if metadata[:postgres_database]
    return unless FullModeSuiteDatabase.setup_complete?

    FullModeSuiteDatabase.clean_tables!
  end

  config.after(:each, :full_auth_mode, &full_mode_per_test_cleanup)
  config.after(:each, :sqlite_database, &full_mode_per_test_cleanup)

  # Suite-level teardown: only runs once at the very end
  # Note: Simple/disabled mode tests explicitly clear the stub if needed
  config.after(:suite) do
    if FullModeSuiteDatabase.setup_complete?
      warn "[FullModeSuiteDatabase] Suite ran on #{FullModeSuiteDatabase.engine_label}"
    end
    FullModeSuiteDatabase.teardown!
  end

  # Include factory methods for :full_auth_mode specs (excluding postgres)
  config.include AuthAccountFactory, :full_auth_mode
  config.include AuthAccountFactory, :sqlite_database

  # Provide test_db helper method
  test_db_module = Module.new {
    def test_db
      FullModeSuiteDatabase.database
    end
  }
  config.include(test_db_module, :full_auth_mode)
  config.include(test_db_module, :sqlite_database)
end
