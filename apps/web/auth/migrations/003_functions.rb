# apps/web/auth/migrations/003_functions.rb
#
# frozen_string_literal: true

#   $ sequel -m apps/web/auth/migrations -M 3 $AUTH_DATABASE_URL_MIGRATIONS
#
#   # Down
#   $ sequel -m apps/web/auth/migrations -M 2 $AUTH_DATABASE_URL_MIGRATIONS
#
# frozen_string_literal: true

MIGRATION_ROOT = __dir__ unless defined?(MIGRATION_ROOT)

Sequel.migration do
  up do
    # Database-specific functions
    # These provide security, trigger automation, and utility functions
    case database_type
    when :postgres
      sql_file = File.join(MIGRATION_ROOT, 'schemas/postgres/003_functions_⬆.sql')
      run File.read(sql_file) if File.exist?(sql_file)
    when :sqlite
      sql_file = File.join(MIGRATION_ROOT, 'schemas/sqlite/003_functions_⬆.sql')
      run File.read(sql_file) if File.exist?(sql_file)
    end
  end

  down do
    # Drop database-specific functions
    case database_type
    when :postgres
      sql_file = File.join(MIGRATION_ROOT, 'schemas/postgres/003_functions_⬇.sql')
      run File.read(sql_file) if File.exist?(sql_file)
    when :sqlite
      sql_file = File.join(MIGRATION_ROOT, 'schemas/sqlite/003_functions_⬇.sql')
      run File.read(sql_file) if File.exist?(sql_file)
    end
  end
end
