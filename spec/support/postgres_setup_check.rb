#!/usr/bin/env ruby
# spec/support/postgres_setup_check.rb
#
# frozen_string_literal: true

# Quick verification script for PostgreSQL test infrastructure setup.
# Run this to verify your environment is correctly configured before running
# PostgreSQL integration tests.
#
# Usage:
#   ruby spec/support/postgres_setup_check.rb
#
# Expected output:
#   ✓ All checks passed - PostgreSQL test infrastructure is ready

require 'sequel'

class PostgresSetupCheck
  REQUIRED_VARS = %w[AUTH_DATABASE_URL].freeze
  OPTIONAL_VARS = %w[AUTH_DATABASE_URL_MIGRATIONS].freeze

  def self.run
    new.run
  end

  def run
    puts "PostgreSQL Test Infrastructure Setup Check"
    puts "=" * 50
    puts

    check_environment_variables
    check_database_connection
    check_database_type
    check_database_permissions
    check_migrations_exist

    puts
    puts "✓ All checks passed - PostgreSQL test infrastructure is ready"
    puts
    puts "To run PostgreSQL tests:"
    puts "  bundle exec rspec --tag postgres_database"
    puts
    0
  rescue StandardError => e
    puts
    puts "✗ Setup check failed: #{e.message}"
    puts
    puts "See spec/support/README-postgres-testing.md for setup instructions"
    1
  end

  private

  def check_environment_variables
    print "Checking environment variables... "

    REQUIRED_VARS.each do |var|
      unless ENV[var]
        raise "Required environment variable #{var} is not set"
      end
    end

    puts "✓"

    OPTIONAL_VARS.each do |var|
      if ENV[var]
        puts "  - #{var}: configured (elevated privileges)"
      else
        puts "  - #{var}: not set (will use standard connection)"
      end
    end
  end

  def check_database_connection
    print "Checking database connection... "

    database_url = ENV.fetch('AUTH_DATABASE_URL')

    unless database_url.start_with?('postgresql://', 'postgres://')
      raise "AUTH_DATABASE_URL must be a PostgreSQL URL, got: #{database_url}"
    end

    @db = Sequel.connect(database_url)
    @db.test_connection

    puts "✓"
    puts "  - Connected to: #{database_url.gsub(/:[^:@]+@/, ':***@')}"
  rescue Sequel::DatabaseConnectionError => e
    raise "Cannot connect to database: #{e.message}"
  end

  def check_database_type
    print "Checking database type... "

    db_type = @db.database_type

    unless db_type == :postgres
      raise "Expected PostgreSQL database, got: #{db_type}"
    end

    # Get PostgreSQL version
    version = @db.fetch("SELECT version()").first[:version]
    version_number = version.match(/PostgreSQL ([\d.]+)/)[1]

    puts "✓"
    puts "  - Database type: PostgreSQL"
    puts "  - Version: #{version_number}"
  end

  def check_database_permissions
    print "Checking database permissions... "

    # Test basic permissions
    test_table = "postgres_setup_check_#{Time.now.to_i}"

    @db.create_table(test_table.to_sym) do
      primary_key :id
      String :test_column
    end

    @db[test_table.to_sym].insert(test_column: 'test')
    @db.drop_table(test_table.to_sym)

    puts "✓"
    puts "  - Can create tables"
    puts "  - Can insert data"
    puts "  - Can drop tables"
  rescue Sequel::DatabaseError => e
    raise "Insufficient database permissions: #{e.message}"
  end

  def check_migrations_exist
    print "Checking migrations directory... "

    # Try to find Onetime::HOME
    if defined?(Onetime::HOME)
      home = Onetime::HOME
    elsif ENV['ONETIME_HOME']
      home = ENV['ONETIME_HOME']
    elsif File.exist?(File.expand_path('../../lib/onetime.rb', __dir__))
      home = File.expand_path('../..', __dir__)
    else
      raise "Cannot locate project root (Onetime::HOME)"
    end

    migrations_path = File.join(home, 'apps', 'web', 'auth', 'migrations')

    unless File.directory?(migrations_path)
      raise "Migrations directory not found: #{migrations_path}"
    end

    migration_files = Dir[File.join(migrations_path, '*.rb')]

    if migration_files.empty?
      raise "No migration files found in: #{migrations_path}"
    end

    puts "✓"
    puts "  - Migrations directory: #{migrations_path}"
    puts "  - Migration files: #{migration_files.count}"
  ensure
    @db&.disconnect
  end
end

exit PostgresSetupCheck.run if __FILE__ == $PROGRAM_NAME
