# spec/integration/authentication/full_mode/postgres_infrastructure_spec.rb
#
# frozen_string_literal: true

# Verify that the PostgreSQL test infrastructure is working correctly.
# These tests validate the PostgresModeSuiteDatabase setup before running
# actual PostgreSQL-specific tests (triggers, functions, constraints).

require 'spec_helper'

RSpec.describe 'PostgreSQL Mode Test Infrastructure', :full_auth_mode, :postgres_database, type: :integration do
  before(:all) do
    require 'onetime'
    require 'onetime/config'
    Onetime.boot! :test
    require 'onetime/auth_config'
    require 'auth/database'
  end

  describe 'PostgresModeSuiteDatabase' do
    it 'provides a test_db' do
      expect(test_db).to be_a(Sequel::Database)
    end

    it 'connects to PostgreSQL' do
      expect(test_db.database_type).to eq(:postgres)
    end

    it 'creates accounts table' do
      expect(test_db.tables).to include(:accounts)
    end

    it 'creates account_password_hashes table' do
      expect(test_db.tables).to include(:account_password_hashes)
    end

    it 'creates account_statuses with seed data' do
      statuses = test_db[:account_statuses].all
      expect(statuses.map { |s| s[:name] }).to contain_exactly('Unverified', 'Verified', 'Closed')
    end

    it 'creates account_activity_times table' do
      expect(test_db.tables).to include(:account_activity_times)
    end

    it 'creates account_authentication_audit_logs table' do
      expect(test_db.tables).to include(:account_authentication_audit_logs)
    end

    it 'uses citext extension for email column' do
      # PostgreSQL-specific: email column should use citext type
      schema = test_db.schema(:accounts)
      email_column = schema.find { |col| col[0] == :email }
      expect(email_column).not_to be_nil
      # citext appears as :string type in Sequel but with db_type 'citext'
      expect(email_column[1][:db_type]).to eq('citext')
    end
  end

  describe 'AuthAccountFactory with PostgreSQL' do
    describe '#create_verified_account' do
      it 'creates an account with verified status' do
        account = create_verified_account(db: test_db, email: 'postgres-test@example.com')
        expect(account[:status_id]).to eq(AuthAccountFactory::STATUS_VERIFIED)
        expect(account[:email]).to eq('postgres-test@example.com')
      end

      it 'creates a password hash' do
        account = create_verified_account(db: test_db, email: 'postgres-test@example.com')
        hash_row = test_db[:account_password_hashes].where(id: account[:id]).first
        expect(hash_row).not_to be_nil
        expect(hash_row[:password_hash]).to start_with('$2')
      end

      it 'generates random email when not provided' do
        account = create_verified_account(db: test_db)
        expect(account[:email]).to match(/test-[a-f0-9]+@example\.com/)

        # Cleanup
        cleanup_account(db: test_db, account_id: account[:id])
      end
    end
  end

  describe 'PostgreSQL-specific features' do
    describe 'account_activity_times table structure' do
      it 'has id column (not account_id) as primary key' do
        schema = test_db.schema(:account_activity_times)
        id_column = schema.find { |col| col[0] == :id }
        expect(id_column).not_to be_nil
        expect(id_column[1][:primary_key]).to be true
      end

      it 'does not have account_id column' do
        schema = test_db.schema(:account_activity_times)
        account_id_column = schema.find { |col| col[0] == :account_id }
        expect(account_id_column).to be_nil
      end

      it 'has last_activity_at column' do
        schema = test_db.schema(:account_activity_times)
        column = schema.find { |col| col[0] == :last_activity_at }
        expect(column).not_to be_nil
      end

      it 'has last_login_at column' do
        schema = test_db.schema(:account_activity_times)
        column = schema.find { |col| col[0] == :last_login_at }
        expect(column).not_to be_nil
      end
    end

    describe 'database triggers' do
      it 'has update_last_login_time trigger function' do
        # Query PostgreSQL for the function
        result = test_db.fetch(<<~SQL).all
          SELECT proname
          FROM pg_proc
          WHERE proname = 'update_last_login_time'
        SQL
        expect(result).not_to be_empty
      end

      it 'has trigger_update_last_login_time on audit logs table' do
        # Query PostgreSQL for the trigger
        result = test_db.fetch(<<~SQL).all
          SELECT tgname
          FROM pg_trigger
          WHERE tgname = 'trigger_update_last_login_time'
        SQL
        expect(result).not_to be_empty
      end

      it 'has cleanup_expired_tokens_extended trigger function' do
        result = test_db.fetch(<<~SQL).all
          SELECT proname
          FROM pg_proc
          WHERE proname = 'cleanup_expired_tokens_extended'
        SQL
        expect(result).not_to be_empty
      end
    end
  end

  describe 'Database cleanup' do
    it 'can truncate tables successfully' do
      # Create a test account
      account = create_verified_account(db: test_db)

      # Verify it exists
      expect(test_db[:accounts].where(id: account[:id]).count).to eq(1)

      # Clean tables
      PostgresModeSuiteDatabase.clean_tables!

      # Verify it was cleaned
      expect(test_db[:accounts].count).to eq(0)
      expect(test_db[:account_password_hashes].count).to eq(0)
    end
  end
end
