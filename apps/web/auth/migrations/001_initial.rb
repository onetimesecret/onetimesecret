# frozen_string_literal: true
# apps/web/auth/migrations/001_initial.rb

MIGRATION_ROOT = __dir__

Sequel.migration do
  DB_TYPE       = DB.adapter_scheme            # :sqlite or :postgres
  SCHEMA_FILE   = File.join(MIGRATION_ROOT, 'schemas', DB_TYPE.to_s, '001_initial.sql')
  ROLLBACK_FILE = File.join(MIGRATION_ROOT, 'schemas', DB_TYPE.to_s, '001_initial_down.sql')

  up do
    return if SCHEMA_FILE.nil?
    raise "SQL file not found: #{SCHEMA_FILE}" unless File.exist?(SCHEMA_FILE)
    run File.read(SCHEMA_FILE)
  end

  down do
    return if ROLLBACK_FILE.nil?
    raise "SQL file not found: #{ROLLBACK_FILE}" unless File.exist?(ROLLBACK_FILE)
    run File.read(ROLLBACK_FILE)
  end
end
