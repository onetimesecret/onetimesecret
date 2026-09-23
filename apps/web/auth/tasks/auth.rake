# apps/web/auth/tasks/auth.rake
#
# frozen_string_literal: true

# Standalone Rodauth database migration task.
#
# Prefers AUTH_DATABASE_URL_MIGRATIONS (migrator user with DDL privileges)
# over AUTH_DATABASE_URL (app user with DML-only). This matches the
# dual-user privilege separation: the app user never needs CREATE/ALTER.
#
# Usage:
#   bundle exec rake auth:migrate                    # dev/deploy
#   AUTH_DATABASE_URL_MIGRATIONS=... rake auth:migrate  # explicit migrator URL
#
# CI example (run before test jobs):
#   env AUTH_DATABASE_URL_MIGRATIONS=postgresql://onetime_migrator:...@localhost/db \
#       bundle exec rake auth:migrate

namespace :auth do
  desc 'Run Rodauth database migrations (uses AUTH_DATABASE_URL_MIGRATIONS if available)'
  task :migrate do
    require_relative '../database_connection'
    Sequel.extension :migration

    migrations_url = ENV.fetch('AUTH_DATABASE_URL_MIGRATIONS', nil)
    database_url   = ENV.fetch('AUTH_DATABASE_URL', nil)

    url = if migrations_url && !migrations_url.empty?
      migrations_url
    else
      database_url
    end

    abort 'ERROR: Set AUTH_DATABASE_URL or AUTH_DATABASE_URL_MIGRATIONS' unless url && !url.empty?

    migrations_dir = File.expand_path('../migrations', __dir__)
    abort "Migrations directory not found: #{migrations_dir}" unless Dir.exist?(migrations_dir)

    # Same connection options as the app's migration connections: on SQLite,
    # a migrate that overlaps a running app waits for the write lock.
    conn = Auth::DatabaseConnection.open(url)
    begin
      use_advisory_lock = conn.adapter_scheme == :postgres

      Sequel::Migrator.run(
        conn,
        migrations_dir,
        use_transactions: true,
        use_advisory_lock: use_advisory_lock,
      )

      version = conn[:schema_info].first&.fetch(:version, 0)
      puts "Auth database migrated to version #{version}"
    rescue Sequel::AdvisoryLockError
      puts 'Migrations already in progress (advisory lock held by another process)'
    ensure
      conn.disconnect
    end
  end

  desc 'Show current auth database schema version'
  task :version do
    require_relative '../database_connection'

    database_url = ENV.fetch('AUTH_DATABASE_URL', nil)
    abort 'ERROR: Set AUTH_DATABASE_URL' unless database_url && !database_url.empty?

    conn = Auth::DatabaseConnection.open(database_url)
    begin
      version         = conn[:schema_info].first&.fetch(:version, 0)
      migration_files = Dir.glob(File.join(File.expand_path('../migrations', __dir__), '*.rb'))
      puts "Schema version: #{version}/#{migration_files.count}"
    rescue Sequel::DatabaseError
      puts 'Schema version: 0 (schema_info table does not exist)'
    ensure
      conn.disconnect
    end
  end
end
