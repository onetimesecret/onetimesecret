# apps/web/auth/migrations/005_views.rb
#
# frozen_string_literal: true

#   $ sequel -m apps/web/auth/migrations -M 5 $AUTH_DATABASE_URL_MIGRATIONS
#
#   # Down
#   $ sequel -m apps/web/auth/migrations -M 4 $AUTH_DATABASE_URL_MIGRATIONS
#
# frozen_string_literal: true

MIGRATION_ROOT = __dir__ unless defined?(MIGRATION_ROOT)

Sequel.migration do
  up do
    # Convenience views for common account and security queries
    case database_type
    when :postgres
      sql_file = File.join(MIGRATION_ROOT, 'schemas/postgres/005_views_⬆.sql')
      run File.read(sql_file) if File.exist?(sql_file)
    when :sqlite
      sql_file = File.join(MIGRATION_ROOT, 'schemas/sqlite/005_views_⬆.sql')
      run File.read(sql_file) if File.exist?(sql_file)
    end
  end

  down do
    # Drop convenience views
    case database_type
    when :postgres
      sql_file = File.join(MIGRATION_ROOT, 'schemas/postgres/005_views_⬇.sql')
      run File.read(sql_file) if File.exist?(sql_file)
    when :sqlite
      sql_file = File.join(MIGRATION_ROOT, 'schemas/sqlite/005_views_⬇.sql')
      run File.read(sql_file) if File.exist?(sql_file)
    end
  end
end
