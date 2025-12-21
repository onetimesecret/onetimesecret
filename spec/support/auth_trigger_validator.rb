# spec/support/auth_trigger_validator.rb
#
# frozen_string_literal: true

# Validates database trigger SQL against actual schema.
#
# This validator parses trigger definitions from migration SQL files and
# verifies that column references (e.g., NEW.column_name) match the actual
# database schema. It's designed to catch mismatches between trigger SQL
# and table definitions that would only surface at runtime.
#
# Background:
# Triggers in migration 002_extras.rb load raw SQL from database-specific
# schema files. When these SQL files are copied from example templates or
# updated independently from the Sequel DSL migrations, column name mismatches
# can occur.
#
# Example Bug (fixed in commit d72db567e):
# Migration 001_initial.rb creates account_activity_times with column 'id':
#   create_table(:account_activity_times) do
#     foreign_key :id, :accounts, primary_key: true, type: :Bignum
#     DateTime :last_activity_at, null: false
#     DateTime :last_login_at, null: false
#   end
#
# But 002_extras.sql trigger referenced non-existent column 'account_id':
#   INSERT INTO account_activity_times (account_id, ...) VALUES (...)
#
# This bug only surfaced at runtime when a user logged in successfully,
# causing: "SQLite3::SQLException: table account_activity_times has no column
# named account_id"
#
# Validation Strategy:
# - Parse CREATE TRIGGER statements (SQLite) or CREATE FUNCTION (PostgreSQL)
# - Extract INSERT/UPDATE statements and their column lists
# - Verify each column exists in the actual database schema
# - Extract NEW.* and OLD.* references
# - Verify those references exist in the trigger's source table
# - Provide helpful error messages with column suggestions
#
# Usage in Integration Tests:
#   RSpec.describe 'Database Triggers', :full_auth_mode do
#     it 'validates trigger column references' do
#       errors = AuthTriggerValidator.validate(test_db)
#       expect(errors).to be_empty, errors.join("\n")
#     end
#   end
#
# Usage in Unit Tests (with fixtures):
#   validator = AuthTriggerValidator::Validator.new(
#     test_db,
#     schema_base_path: 'spec/fixtures/auth/migrations/schemas'
#   )
#   errors = validator.validate_all_triggers
#   expect(errors).not_to be_empty # Expect buggy fixture to fail
#
# Supported Databases:
# - SQLite: CREATE TRIGGER ... BEGIN ... END; syntax
# - PostgreSQL: CREATE FUNCTION + CREATE TRIGGER syntax
#
module AuthTriggerValidator
  class Validator
    attr_reader :db, :errors
    attr_accessor :schema_base_path

    def initialize(db, schema_base_path: nil)
      @db = db
      @errors = []
      @schema_base_path = schema_base_path
    end

    # Main entry point: validates all triggers for the current database type
    #
    # Returns array of error messages (empty if validation passes)
    def validate_all_triggers
      @errors = []

      case db.database_type
      when :sqlite
        validate_sqlite_triggers
      when :postgres
        validate_postgres_triggers
      else
        @errors << "Unsupported database type: #{db.database_type}"
      end

      @errors
    end

    private

    # Validates SQLite trigger definitions from 002_extras.sql
    def validate_sqlite_triggers
      sql_file = extras_sql_path('sqlite')
      return unless File.exist?(sql_file)

      sql = File.read(sql_file)

      # Extract trigger definitions (CREATE TRIGGER...END;)
      triggers = extract_sqlite_triggers(sql)

      triggers.each do |trigger_name, trigger_sql|
        validate_sqlite_trigger(trigger_name, trigger_sql)
      end
    end

    # Validates PostgreSQL trigger functions and triggers from 002_extras.sql
    def validate_postgres_triggers
      sql_file = extras_sql_path('postgres')
      return unless File.exist?(sql_file)

      sql = File.read(sql_file)

      # Extract function definitions (CREATE OR REPLACE FUNCTION...$$)
      functions = extract_postgres_functions(sql)

      functions.each do |function_name, function_sql|
        validate_postgres_function(function_name, function_sql)
      end
    end

    # Extract SQLite trigger definitions
    # Returns hash: { trigger_name => trigger_sql }
    def extract_sqlite_triggers(sql)
      triggers = {}

      # Match: CREATE TRIGGER name ... END;
      sql.scan(/CREATE\s+TRIGGER\s+(\w+)\s+(.*?)\s+END;/mi) do |name, body|
        triggers[name] = body
      end

      triggers
    end

    # Extract PostgreSQL function definitions
    # Returns hash: { function_name => function_body }
    def extract_postgres_functions(sql)
      functions = {}

      # Match: CREATE OR REPLACE FUNCTION name() ... $$ LANGUAGE plpgsql;
      sql.scan(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+(\w+)\s*\([^)]*\)\s+.*?\$\$\s+(.*?)\s+\$\$/mi) do |name, body|
        functions[name] = body
      end

      functions
    end

    # Validate a single SQLite trigger
    def validate_sqlite_trigger(trigger_name, trigger_sql)
      # Extract target table from trigger SQL
      # Example: "AFTER INSERT ON account_authentication_audit_logs"
      target_table = extract_target_table(trigger_sql)

      unless target_table
        @errors << "Trigger #{trigger_name}: Could not determine target table"
        return
      end

      # Extract column references (NEW.column_name or OLD.column_name)
      column_refs = extract_column_references(trigger_sql)

      # For each table referenced in the trigger body, validate columns exist
      validate_trigger_column_references(trigger_name, trigger_sql, column_refs)
    end

    # Validate a PostgreSQL function that's used by a trigger
    def validate_postgres_function(function_name, function_sql)
      # Extract column references from function body
      column_refs = extract_column_references(function_sql)

      # Validate references against schema
      validate_trigger_column_references(function_name, function_sql, column_refs)
    end

    # Extract target table from trigger definition
    # Returns table name or nil
    def extract_target_table(trigger_sql)
      # Match: ON table_name
      match = trigger_sql.match(/\bON\s+(\w+)/i)
      match ? match[1] : nil
    end

    # Extract column references from SQL (NEW.column or OLD.column)
    # Returns hash: { 'NEW' => Set['col1', 'col2'], 'OLD' => Set['col3'] }
    def extract_column_references(sql)
      refs = Hash.new { |h, k| h[k] = Set.new }

      # Match: NEW.column_name or OLD.column_name
      sql.scan(/\b(NEW|OLD)\.(\w+)/i) do |context, column|
        refs[context.upcase] << column
      end

      refs
    end

    # Validate column references against actual schema
    def validate_trigger_column_references(trigger_name, trigger_sql, column_refs)
      # Extract INSERT/UPDATE statements to determine target tables
      # Example: "INSERT OR REPLACE INTO account_activity_times (account_id, ...)"
      # Example: "INSERT INTO account_activity_times (id, ...)"
      tables_and_columns = extract_insert_update_statements(trigger_sql)

      tables_and_columns.each do |table_name, column_list|
        # Verify table exists
        unless db.table_exists?(table_name.to_sym)
          @errors << "Trigger #{trigger_name}: References non-existent table '#{table_name}'"
          next
        end

        # Get actual schema columns
        schema_columns = db.schema(table_name.to_sym).map { |col| col[0].to_s }.to_set

        # Check each column in the INSERT/UPDATE statement
        column_list.each do |col|
          next if schema_columns.include?(col)

          # Found a column that doesn't exist in the schema
          @errors << build_column_mismatch_error(
            trigger_name, table_name, col, schema_columns
          )
        end
      end

      # Also validate NEW/OLD references if we can determine the source table
      # This catches issues like NEW.account_id when it should be NEW.id
      validate_context_references(trigger_name, trigger_sql, column_refs)
    end

    # Extract INSERT/UPDATE statements and their target columns
    # Returns array of [table_name, [column_list]]
    def extract_insert_update_statements(sql)
      results = []

      # Match: INSERT [OR REPLACE] INTO table_name (col1, col2, ...) VALUES (...)
      # Match: INSERT INTO table_name (col1, col2, ...) VALUES (...) ON CONFLICT ...
      sql.scan(/INSERT\s+(?:OR\s+REPLACE\s+)?INTO\s+(\w+)\s*\(([^)]+)\)/mi) do |table, cols|
        column_list = cols.split(',').map { |c| c.strip.gsub(/^["']|["']$/, '') }
        results << [table, column_list]
      end

      # Match: UPDATE table_name SET col1 = ..., col2 = ...
      sql.scan(/UPDATE\s+(\w+)\s+SET\s+(.*?)(?:WHERE|$)/mi) do |table, set_clause|
        column_list = set_clause.scan(/(\w+)\s*=/).flatten
        results << [table, column_list]
      end

      results
    end

    # Validate NEW/OLD context references
    # This catches cases where trigger uses NEW.column_name but column doesn't exist
    # on the trigger's source table
    def validate_context_references(trigger_name, trigger_sql, column_refs)
      # Extract the table that triggers the event
      # Example: "AFTER INSERT ON account_authentication_audit_logs"
      source_table = nil
      if trigger_sql =~ /(?:AFTER|BEFORE)\s+(?:INSERT|UPDATE|DELETE)\s+ON\s+(\w+)/i
        source_table = $1
      end

      return unless source_table
      return unless db.table_exists?(source_table.to_sym)

      # Get schema for source table
      schema_columns = db.schema(source_table.to_sym).map { |col| col[0].to_s }.to_set

      # Validate NEW references
      if column_refs['NEW']
        column_refs['NEW'].each do |col|
          next if schema_columns.include?(col)

          @errors << "Trigger #{trigger_name}: References NEW.#{col} but " \
                     "source table '#{source_table}' has columns: #{schema_columns.to_a.sort.join(', ')}"
        end
      end

      # Validate OLD references (for UPDATE/DELETE triggers)
      if column_refs['OLD']
        column_refs['OLD'].each do |col|
          next if schema_columns.include?(col)

          @errors << "Trigger #{trigger_name}: References OLD.#{col} but " \
                     "source table '#{source_table}' has columns: #{schema_columns.to_a.sort.join(', ')}"
        end
      end
    end

    # Build detailed error message for column mismatch
    def build_column_mismatch_error(trigger_name, table_name, invalid_column, valid_columns)
      # Try to find a similar column name (likely candidate for the fix)
      suggestions = find_similar_columns(invalid_column, valid_columns)

      error = "Trigger #{trigger_name}: Table '#{table_name}' has no column '#{invalid_column}'. " \
              "Available columns: #{valid_columns.to_a.sort.join(', ')}"

      if suggestions.any?
        error += ". Did you mean: #{suggestions.join(', ')}?"
      end

      error
    end

    # Find columns with similar names (for helpful error messages)
    def find_similar_columns(target, available_columns)
      # Simple heuristic: contains same word parts
      target_parts = target.downcase.split('_')

      available_columns.select do |col|
        col_parts = col.downcase.split('_')
        (target_parts & col_parts).any?
      end.to_a.sort
    end

    # Get path to 002_extras.sql for the given database type
    def extras_sql_path(db_type)
      base = @schema_base_path || File.join(
        Onetime::HOME,
        'apps', 'web', 'auth', 'migrations', 'schemas'
      )

      File.join(base, db_type.to_s, '002_extras.sql')
    end
  end

  # Convenience class method for quick validation
  #
  # Usage:
  #   errors = AuthTriggerValidator.validate(db)
  #   expect(errors).to be_empty
  #
  def self.validate(db)
    validator = Validator.new(db)
    validator.validate_all_triggers
  end
end
