# apps/web/auth/migrations/006_policies.rb
#
# Run manually:
#   # Up
#   $ sequel -m apps/web/auth/migrations -M 6 $AUTH_DATABASE_URL_MIGRATIONS
#
#   # Down
#   $ sequel -m apps/web/auth/migrations -M 5 $AUTH_DATABASE_URL_MIGRATIONS
#
# frozen_string_literal: true

MIGRATION_ROOT = __dir__ unless defined?(MIGRATION_ROOT)

Sequel.migration do
  up do
    # Row Level Security policies for database-level access control
    # Note: SQLite does not support RLS - policies must be implemented in application
    case database_type
    when :postgres
      sql_file = File.join(MIGRATION_ROOT, 'schemas/postgres/006_policies_⬆.sql')
      run File.read(sql_file) if File.exist?(sql_file)
    when :sqlite
      sql_file = File.join(MIGRATION_ROOT, 'schemas/sqlite/006_policies_⬆.sql')
      run File.read(sql_file) if File.exist?(sql_file)
    end
  end

  down do
    # Disable Row Level Security
    case database_type
    when :postgres
      sql_file = File.join(MIGRATION_ROOT, 'schemas/postgres/006_policies_⬇.sql')
      run File.read(sql_file) if File.exist?(sql_file)
    when :sqlite
      sql_file = File.join(MIGRATION_ROOT, 'schemas/sqlite/006_policies_⬇.sql')
      run File.read(sql_file) if File.exist?(sql_file)
    end
  end
end
