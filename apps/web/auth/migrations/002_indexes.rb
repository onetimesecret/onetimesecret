# apps/web/auth/migrations/002_indexes.rb
#
# frozen_string_literal: true

#   $ sequel -m apps/web/auth/migrations -M 2 $AUTH_DATABASE_URL_MIGRATIONS
#
#   # Down
#   $ sequel -m apps/web/auth/migrations -M 1 $AUTH_DATABASE_URL_MIGRATIONS
#
# frozen_string_literal: true

MIGRATION_ROOT = __dir__ unless defined?(MIGRATION_ROOT)

Sequel.migration do
  up do
    # Performance indexes for frequently queried columns
    # Created immediately after table definitions for optimal performance
    case database_type
    when :postgres
      sql_file = File.join(MIGRATION_ROOT, 'schemas/postgres/002_indexes_⬆.sql')
      run File.read(sql_file) if File.exist?(sql_file)
    when :sqlite
      sql_file = File.join(MIGRATION_ROOT, 'schemas/sqlite/002_indexes_⬆.sql')
      run File.read(sql_file) if File.exist?(sql_file)
    end
  end

  down do
    # Drop performance indexes
    case database_type
    when :postgres
      sql_file = File.join(MIGRATION_ROOT, 'schemas/postgres/002_indexes_⬇.sql')
      run File.read(sql_file) if File.exist?(sql_file)
    when :sqlite
      sql_file = File.join(MIGRATION_ROOT, 'schemas/sqlite/002_indexes_⬇.sql')
      run File.read(sql_file) if File.exist?(sql_file)
    end
  end
end
