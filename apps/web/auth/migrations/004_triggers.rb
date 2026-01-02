# apps/web/auth/migrations/004_triggers.rb
#
# frozen_string_literal: true

#   $ sequel -m apps/web/auth/migrations -M 4 $AUTH_DATABASE_URL_MIGRATIONS
#
#   # Down
#   $ sequel -m apps/web/auth/migrations -M 3 $AUTH_DATABASE_URL_MIGRATIONS
#
# frozen_string_literal: true

MIGRATION_ROOT = __dir__ unless defined?(MIGRATION_ROOT)

Sequel.migration do
  up do
    # Database-specific triggers
    case database_type
    when :postgres
      sql_file = File.join(MIGRATION_ROOT, 'schemas/postgres/004_triggers_⬆.sql')
      run File.read(sql_file) if File.exist?(sql_file)
    when :sqlite
      sql_file = File.join(MIGRATION_ROOT, 'schemas/sqlite/004_triggers_⬆.sql')
      run File.read(sql_file) if File.exist?(sql_file)
    end
  end

  down do
    # Drop database-specific triggers
    case database_type
    when :postgres
      sql_file = File.join(MIGRATION_ROOT, 'schemas/postgres/004_triggers_⬇.sql')
      run File.read(sql_file) if File.exist?(sql_file)
    when :sqlite
      sql_file = File.join(MIGRATION_ROOT, 'schemas/sqlite/004_triggers_⬇.sql')
      run File.read(sql_file) if File.exist?(sql_file)
    end
  end
end
