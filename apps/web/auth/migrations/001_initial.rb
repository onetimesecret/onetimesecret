# apps/web/auth/migrations/001_initial.rb

MIGRATION_ROOT = __dir__

Sequel.migration do
  up do
    db_type       = adapter_scheme            # :sqlite or :postgres
    schema_file   = File.join(MIGRATION_ROOT, 'schemas', db_type.to_s, '001_initial.sql')

    raise "SQL file not found: #{schema_file}" unless File.exist?(schema_file)

    run File.read(schema_file)
  end

  down do
    db_type       = adapter_scheme            # :sqlite or :postgres
    rollback_file = File.join(MIGRATION_ROOT, 'schemas', db_type.to_s, '001_initial_down.sql')

    raise "SQL file not found: #{rollback_file}" unless File.exist?(rollback_file)

    run File.read(rollback_file)
  end
end
