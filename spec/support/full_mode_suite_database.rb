# spec/support/full_mode_suite_database.rb
#
# frozen_string_literal: true

# Ensure factory is loaded before we reference it in RSpec.configure
require_relative 'factories/auth_account_factory'

# Suite-level database setup for full auth mode tests.
#
# Creates a single in-memory SQLite database shared across all :full_auth_mode
# tagged specs within a test suite run. This avoids the overhead of creating
# and migrating a database per-file or per-test.
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
    attr_reader :database

    def setup!
      return if @setup_complete

      require 'sequel'
      require 'auth/database'
      Sequel.extension :migration

      # Create in-memory SQLite database
      @database = Sequel.sqlite

      # Run Rodauth migrations
      migrations_path = File.join(Onetime::HOME, 'apps', 'web', 'auth', 'migrations')
      Sequel::Migrator.run(@database, migrations_path)

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

    # Clean all Rodauth tables (for tests that need a fresh database state)
    def clean_tables!
      return unless @database

      AuthAccountFactory::RODAUTH_TABLES.each do |table|
        @database[table].delete if @database.table_exists?(table)
      rescue Sequel::DatabaseError
        nil
      end
    end
  end
end

# RSpec configuration for full auth mode tests with SQLite
RSpec.configure do |config|
  # Lazy setup: first :full_auth_mode, :sqlite_database spec triggers database creation
  # Using before(:context) ensures it runs once per describe block,
  # but setup! is idempotent so it's safe if multiple blocks have the tag
  config.before(:context, :full_auth_mode, :sqlite_database) do
    FullModeSuiteDatabase.setup!
  end

  # Clean tables between describe blocks to catch leaked test data
  # Individual tests should still clean up after themselves, but this
  # provides a safety net without hiding which test leaked data
  config.after(:context, :full_auth_mode, :sqlite_database) do
    FullModeSuiteDatabase.clean_tables!
  end

  # Suite-level teardown: only runs once at the very end
  # Note: Simple/disabled mode tests explicitly clear the stub if needed
  config.after(:suite) do
    FullModeSuiteDatabase.teardown!
  end

  # Include factory methods for all :full_auth_mode, :sqlite_database specs
  config.include AuthAccountFactory, :full_auth_mode, :sqlite_database

  # Provide test_db helper method for :full_auth_mode, :sqlite_database specs
  config.include(Module.new {
    def test_db
      FullModeSuiteDatabase.database
    end
  }, :full_auth_mode, :sqlite_database)
end
