# apps/web/auth/migrations/001_load_essential_schema.rb

Sequel.migration do
  up do
    # Determine database type and load appropriate schema
    schema_file = case database_type
    when :sqlite
      File.join(__dir__, 'schemas/sqlite/001_essential_schema.sql')
    when :postgres
      File.join(__dir__, 'schemas/postgresql/001_essential_schema.sql')
    else
      raise "Unsupported database type: #{database_type}. Supported: sqlite, postgres"
    end

    unless File.exist?(schema_file)
      raise "Schema file not found: #{schema_file}"
    end

    puts "Loading essential schema for #{database_type} from #{File.basename(schema_file)}"

    # Read and execute the SQL schema file
    sql_content = File.read(schema_file)

    # Execute the entire SQL content at once
    # SQLite can handle multiple statements separated by semicolons
    run sql_content

    puts 'Essential schema loaded successfully'
  end

  down do
    # Determine database type and load appropriate down migration schema
    schema_down_file = case database_type
    when :sqlite
      File.join(__dir__, 'schemas/sqlite/001_essential_schema_down.sql')
    when :postgres
      File.join(__dir__, 'schemas/postgresql/001_essential_schema_down.sql')
    else
      raise "Unsupported database type: #{database_type}. Supported: sqlite, postgres"
    end

    unless File.exist?(schema_down_file)
      raise "Schema down file not found: #{schema_down_file}"
    end

    puts "Rolling back essential schema for #{database_type} using #{File.basename(schema_down_file)}"

    # Read and execute the SQL down migration file
    sql_content = File.read(schema_down_file)

    # Execute the entire SQL content at once
    run sql_content

    puts 'Schema rollback completed'
  end
end
