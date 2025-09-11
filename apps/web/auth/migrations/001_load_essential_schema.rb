# apps/web/auth/migrations/001_load_essential_schema.rb

Sequel.migration do
  up do
    # Determine database type and load appropriate schema
    schema_file = case database_type
    when :sqlite
      File.join(__dir__, 'schemas/sqlite/essential_schema.sql')
    when :postgres
      File.join(__dir__, 'schemas/postgresql/essential_schema.sql')
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
    # Drop tables in reverse dependency order to avoid foreign key conflicts
    tables_to_drop = %w[
      account_authentication_audit_logs
      account_recovery_codes
      account_otp_keys
      account_active_session_keys
      account_remember_keys
      account_lockouts
      account_login_failures
      account_password_reset_keys
      account_verification_keys
      account_password_hashes
      accounts
      account_statuses
    ]

    puts 'Dropping all authentication tables...'

    tables_to_drop.each do |table_name|
      if table_exists?(table_name.to_sym)
        drop_table(table_name.to_sym)
        puts "Dropped table: #{table_name}"
      end
    end

    # Drop database functions if PostgreSQL
    if database_type == :postgres
      run 'DROP FUNCTION IF EXISTS rodauth_get_salt(BIGINT)'
      run 'DROP FUNCTION IF EXISTS rodauth_valid_password_hash(BIGINT, TEXT)'
      run 'DROP FUNCTION IF EXISTS cleanup_expired_tokens()'
      run 'DROP FUNCTION IF EXISTS update_accounts_updated_at()'
      puts 'Dropped PostgreSQL functions'
    end

    puts 'Schema rollback completed'
  end
end
