#!/usr/bin/env ruby

require 'bundler/setup'
require 'sequel'
require 'logger'

# Database connection
database_url = ENV['DATABASE_URL'] || 'sqlite://auth.db'
puts "Connecting to database: #{database_url}"

DB = Sequel.connect(database_url)

# Enable logging in development
if ENV['RACK_ENV'] == 'development'
  DB.loggers << Logger.new($stdout)
end

# Load migrations
Sequel.extension :migration

# Define migrations directory
migrations_dir = File.join(__dir__, 'migrations')

begin
  puts "Running database migrations..."

  # Run migrations
  Sequel::Migrator.run(DB, migrations_dir, use_transactions: true)

  puts "Database migrations completed successfully!"

  # Show current schema version
  if DB.table_exists?(:schema_migrations)
    current_version = DB[:schema_migrations].max(:filename)
    puts "Current schema version: #{current_version}"
  end

rescue => e
  puts "Migration failed: #{e.message}"
  puts e.backtrace.join("\n") if ENV['RACK_ENV'] == 'development'
  exit 1
end

# Optional: Show table structure in development
if ENV['RACK_ENV'] == 'development'
  puts "\nDatabase schema:"
  DB.tables.each do |table|
    puts "  #{table}:"
    DB.schema(table).each do |column, details|
      puts "    #{column}: #{details[:type]} #{details[:null] ? 'NULL' : 'NOT NULL'}"
    end
    puts
  end
end
