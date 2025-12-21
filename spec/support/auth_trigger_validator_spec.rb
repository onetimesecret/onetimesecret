# spec/support/auth_trigger_validator_spec.rb
#
# frozen_string_literal: true

require 'sequel'

# Minimal spec for AuthTriggerValidator that doesn't require full app boot
RSpec.describe AuthTriggerValidator do
  # Create a minimal database for testing the validator
  let(:db) do
    Sequel.sqlite.tap do |database|
      # Minimal schema matching 001_initial.rb
      database.create_table(:account_activity_times) do
        Integer :id, primary_key: true
        DateTime :last_activity_at, null: false
        DateTime :last_login_at, null: false
      end

      database.create_table(:account_authentication_audit_logs) do
        Integer :id, primary_key: true
        Integer :account_id, null: false
        DateTime :at, null: false
        String :message, null: false
      end

      database.create_table(:account_jwt_refresh_keys) do
        Integer :id, primary_key: true
        Integer :account_id, null: false
        DateTime :deadline
      end
    end
  end

  # Set HOME for tests
  before do
    unless defined?(Onetime::HOME)
      module Onetime
        HOME = File.expand_path('../../..', __dir__)
      end
    end
  end

  describe '#validate_all_triggers' do
    context 'with buggy migration 002 (fixture)' do
      let(:validator) do
        # Use fixture path with intentionally buggy SQL
        spec_dir = File.expand_path('../..', __FILE__)
        fixture_path = File.join(spec_dir, 'fixtures', 'auth', 'migrations', 'schemas')
        described_class::Validator.new(db, schema_base_path: fixture_path)
      end

      it 'detects column mismatch in triggers' do
        errors = validator.validate_all_triggers

        # Should FAIL because triggers reference account_id but table uses id
        expect(errors).not_to be_empty,
          'Expected validation to fail with buggy migration fixture, but it passed. ' \
          'This indicates the validator is not working correctly.'

        # Verify error message mentions the problematic column
        error_text = errors.join("\n")
        expect(error_text).to include('account_id'),
          "Expected error to mention 'account_id' column, got: #{error_text}"

        # Verify error mentions the target table
        expect(error_text).to include('account_activity_times'),
          "Expected error to mention 'account_activity_times' table, got: #{error_text}"
      end

      it 'provides helpful error messages' do
        errors = validator.validate_all_triggers

        # Should suggest 'id' as alternative to 'account_id'
        error_text = errors.join("\n")
        expect(error_text).to match(/available columns|did you mean/i),
          "Expected error to provide column suggestions, got: #{error_text}"
      end
    end

    context 'with fixed migration 002 (current)' do
      let(:validator) { described_class::Validator.new(db) }

      it 'passes validation' do
        errors = validator.validate_all_triggers

        expect(errors).to be_empty,
          "Expected current migration to pass validation, but got errors:\n#{errors.join("\n")}"
      end
    end
  end

  describe '#extract_column_references' do
    let(:validator) { described_class::Validator.new(db) }

    it 'extracts NEW references' do
      sql = 'INSERT INTO foo (bar) VALUES (NEW.account_id, NEW.created_at)'
      refs = validator.send(:extract_column_references, sql)

      expect(refs['NEW']).to include('account_id')
      expect(refs['NEW']).to include('created_at')
    end

    it 'extracts OLD references' do
      sql = 'WHERE OLD.status = 1 AND OLD.deleted_at IS NULL'
      refs = validator.send(:extract_column_references, sql)

      expect(refs['OLD']).to include('status')
      expect(refs['OLD']).to include('deleted_at')
    end

    it 'handles mixed case' do
      sql = 'VALUES (new.id, OLD.status)'
      refs = validator.send(:extract_column_references, sql)

      expect(refs['NEW']).to include('id')
      expect(refs['OLD']).to include('status')
    end
  end

  describe '#extract_insert_update_statements' do
    let(:validator) { described_class::Validator.new(db) }

    it 'extracts INSERT statements' do
      sql = 'INSERT INTO account_activity_times (id, last_login_at) VALUES (1, NOW())'
      results = validator.send(:extract_insert_update_statements, sql)

      expect(results).to include(['account_activity_times', ['id', 'last_login_at']])
    end

    it 'extracts INSERT OR REPLACE statements' do
      sql = 'INSERT OR REPLACE INTO account_activity_times (account_id, last_login_at)'
      results = validator.send(:extract_insert_update_statements, sql)

      expect(results).to include(['account_activity_times', ['account_id', 'last_login_at']])
    end

    it 'extracts UPDATE statements' do
      sql = 'UPDATE account_activity_times SET last_login_at = NOW(), last_activity_at = NOW()'
      results = validator.send(:extract_insert_update_statements, sql)

      expect(results).to include(['account_activity_times', ['last_login_at', 'last_activity_at']])
    end
  end

  describe '#find_similar_columns' do
    let(:validator) { described_class::Validator.new(db) }

    it 'finds columns with common word parts' do
      available = Set.new(%w[id account_id user_id created_at updated_at])

      similar = validator.send(:find_similar_columns, 'account_id', available)
      expect(similar).to include('account_id')

      # Should suggest 'id' when looking for 'account_id'
      similar = validator.send(:find_similar_columns, 'user_account', available)
      expect(similar).to include('account_id')
    end
  end

  describe 'database type support' do
    let(:validator) { described_class::Validator.new(db) }

    it 'supports SQLite' do
      expect(db.database_type).to eq(:sqlite)
    end

    it 'reports unsupported database types' do
      # Mock an unsupported database type
      allow(db).to receive(:database_type).and_return(:oracle)

      errors = validator.validate_all_triggers
      expect(errors).to include(a_string_matching(/unsupported database type/i))
    end
  end
end
