# spec/integration/authentication/full_mode/database_triggers_postgres_spec.rb
#
# frozen_string_literal: true

# PostgreSQL-specific database trigger integration tests.
#
# Tests the actual behavior of PostgreSQL triggers and functions defined in
# apps/web/auth/migrations/schemas/postgres/003_functions_⬆.sql and
# apps/web/auth/migrations/schemas/postgres/004_triggers_⬆.sql. These tests verify
# that triggers fire correctly during HTTP authentication flows and direct
# database operations.
#
# Triggers Under Test:
# 1. trigger_update_last_login_time (calls update_last_login_time() function)
#    - Fires: AFTER INSERT on account_authentication_audit_logs
#    - When: NEW.message ILIKE '%login%successful%'
#    - Action: INSERT...ON CONFLICT DO UPDATE on account_activity_times
#
# 2. trigger_cleanup_expired_tokens_extended (calls cleanup_expired_tokens_extended() function)
#    - Fires: AFTER INSERT on account_jwt_refresh_keys
#    - Action: DELETE expired tokens from JWT and email auth tables
#
# Database setup is handled by PostgresModeSuiteDatabase (see
# spec/support/postgres_mode_suite_database.rb). The :postgres_database tag
# triggers automatic setup of a PostgreSQL database shared across all tagged
# specs in the suite.
#
# Environment Requirements:
#   AUTH_DATABASE_URL - PostgreSQL connection string
#   AUTH_DATABASE_URL_MIGRATIONS - (Optional) Elevated connection for migrations
#
# Example:
#   AUTH_DATABASE_URL=postgresql://user:pass@localhost/onetime_auth_test

require 'spec_helper'

RSpec.describe 'PostgreSQL Database Triggers', :postgres_database, type: :integration do
  include_context 'auth_rack_test'
  # AuthAccountFactory and test_db are provided by :postgres_database tags

  let(:test_password) { 'Test1234!@' }

  # Helper to login via HTTP - raises on failure for explicit test failures
  def login!(email:, password: test_password)
    post_json '/auth/login', { login: email, password: password }
    unless last_response.status == 200
      raise "Login failed: HTTP #{last_response.status}"
    end
    true
  end

  describe 'Login Activity Trigger (update_last_login_time function)' do
    let(:test_email) { "trigger-login-#{SecureRandom.hex(8)}@example.com" }

    before do
      # Create verified account for login tests
      @account = create_verified_account(db: test_db, email: test_email, password: test_password)
    end

    after do
      # Clean up test data
      cleanup_account(db: test_db, account_id: @account[:id]) if @account
    end

    context 'HTTP login flow' do
      it 'creates account_activity_times record on successful login' do
        # Verify no activity record exists before login
        activity_before = test_db[:account_activity_times].where(id: @account[:id]).first
        expect(activity_before).to be_nil

        # Login via HTTP
        login!(email: test_email)

        # Verify trigger created activity record
        activity = test_db[:account_activity_times].where(id: @account[:id]).first
        expect(activity).not_to be_nil
        expect(activity[:id]).to eq(@account[:id])
      end

      it 'sets last_login_at timestamp matching audit log' do
        login!(email: test_email)

        # Get the audit log entry (use ilike for case-insensitive match like the trigger)
        audit_log = test_db[:account_authentication_audit_logs]
                      .where(account_id: @account[:id])
                      .where(Sequel.ilike(:message, '%login%'))
                      .where(Sequel.ilike(:message, '%successful%'))
                      .order(Sequel.desc(:at))
                      .first

        # Get the activity times record
        activity = test_db[:account_activity_times].where(id: @account[:id]).first

        # Timestamps should match (within a reasonable tolerance for time precision)
        expect(activity[:last_login_at]).to be_within(1).of(audit_log[:at])
      end

      it 'sets last_activity_at timestamp matching audit log' do
        login!(email: test_email)

        # Use ilike for case-insensitive match like the trigger
        audit_log = test_db[:account_authentication_audit_logs]
                      .where(account_id: @account[:id])
                      .where(Sequel.ilike(:message, '%login%'))
                      .where(Sequel.ilike(:message, '%successful%'))
                      .order(Sequel.desc(:at))
                      .first

        activity = test_db[:account_activity_times].where(id: @account[:id]).first

        expect(activity[:last_activity_at]).to be_within(1).of(audit_log[:at])
      end

      it 'updates existing record on subsequent login (ON CONFLICT behavior)' do
        # First login
        login!(email: test_email)
        first_activity = test_db[:account_activity_times].where(id: @account[:id]).first
        first_login_at = first_activity[:last_login_at]

        # Wait a moment to ensure timestamps differ
        sleep 0.1

        # Logout (clear session)
        post_json '/auth/logout', {}

        # Second login
        login!(email: test_email)
        second_activity = test_db[:account_activity_times].where(id: @account[:id]).first
        second_login_at = second_activity[:last_login_at]

        # Verify record was updated, not duplicated
        activity_count = test_db[:account_activity_times].where(id: @account[:id]).count
        expect(activity_count).to eq(1)

        # Verify timestamp was updated
        expect(second_login_at).to be > first_login_at
      end
    end

    context 'direct database trigger' do
      it 'fires on direct INSERT to audit log with "login successful" message' do
        # Insert audit log directly (bypassing HTTP)
        login_time = Time.now
        test_db[:account_authentication_audit_logs].insert(
          account_id: @account[:id],
          at: login_time,
          message: 'login successful'
        )

        # Verify trigger created activity record
        activity = test_db[:account_activity_times].where(id: @account[:id]).first
        expect(activity).not_to be_nil
        expect(activity[:last_login_at]).to be_within(1).of(login_time)
      end

      it 'fires on message containing "login" and "successful" (case-insensitive ILIKE)' do
        login_time = Time.now

        # Test various message formats (PostgreSQL ILIKE is case-insensitive)
        messages = [
          'Login Successful',
          'LOGIN SUCCESSFUL',
          'successful login',
          'User login was successful',
          'Successful LOGIN attempt'
        ]

        messages.each_with_index do |message, index|
          # Create fresh account for each test
          account = create_verified_account(db: test_db)

          test_db[:account_authentication_audit_logs].insert(
            account_id: account[:id],
            at: login_time,
            message: message
          )

          activity = test_db[:account_activity_times].where(id: account[:id]).first
          expect(activity).not_to be_nil, "Trigger failed for message: #{message}"

          # Cleanup
          cleanup_account(db: test_db, account_id: account[:id])
        end
      end

      it 'does not fire on failed login attempts' do
        test_db[:account_authentication_audit_logs].insert(
          account_id: @account[:id],
          at: Time.now,
          message: 'login failure - invalid password'
        )

        # Verify trigger did NOT create activity record
        activity = test_db[:account_activity_times].where(id: @account[:id]).first
        expect(activity).to be_nil
      end

      it 'does not fire on non-login audit events' do
        test_db[:account_authentication_audit_logs].insert(
          account_id: @account[:id],
          at: Time.now,
          message: 'password change'
        )

        activity = test_db[:account_activity_times].where(id: @account[:id]).first
        expect(activity).to be_nil
      end
    end

    context 'ON CONFLICT upsert behavior' do
      it 'updates existing record instead of raising unique constraint error' do
        login_time_1 = Time.now
        login_time_2 = Time.now + 10

        # First insert
        test_db[:account_authentication_audit_logs].insert(
          account_id: @account[:id],
          at: login_time_1,
          message: 'login successful'
        )

        first_activity = test_db[:account_activity_times].where(id: @account[:id]).first
        expect(first_activity[:last_login_at]).to be_within(1).of(login_time_1)

        # Second insert (should trigger ON CONFLICT UPDATE)
        test_db[:account_authentication_audit_logs].insert(
          account_id: @account[:id],
          at: login_time_2,
          message: 'login successful'
        )

        # Verify only one record exists (updated, not duplicated)
        activity_count = test_db[:account_activity_times].where(id: @account[:id]).count
        expect(activity_count).to eq(1)

        # Verify timestamp was updated
        second_activity = test_db[:account_activity_times].where(id: @account[:id]).first
        expect(second_activity[:last_login_at]).to be_within(1).of(login_time_2)
      end
    end
  end

  describe 'Token Cleanup Trigger (cleanup_expired_tokens_extended function)' do
    let(:test_email) { "trigger-cleanup-#{SecureRandom.hex(8)}@example.com" }

    before do
      @account = create_verified_account(db: test_db, email: test_email, password: test_password)
    end

    after do
      cleanup_account(db: test_db, account_id: @account[:id]) if @account
    end

    context 'JWT refresh token cleanup' do
      it 'removes expired JWT refresh tokens when new token is inserted' do
        # Insert expired JWT refresh token
        expired_key = SecureRandom.hex(32)
        test_db[:account_jwt_refresh_keys].insert(
          account_id: @account[:id],
          key: expired_key,
          deadline: Time.now - 3600 # Expired 1 hour ago
        )

        # Verify expired token exists
        expect(test_db[:account_jwt_refresh_keys].where(key: expired_key).count).to eq(1)

        # Insert new (valid) JWT refresh token - this triggers cleanup
        new_key = SecureRandom.hex(32)
        test_db[:account_jwt_refresh_keys].insert(
          account_id: @account[:id],
          key: new_key,
          deadline: Time.now + 86400 # Expires in 24 hours
        )

        # Verify expired token was cleaned up by trigger
        expect(test_db[:account_jwt_refresh_keys].where(key: expired_key).count).to eq(0)

        # Verify new token still exists
        expect(test_db[:account_jwt_refresh_keys].where(key: new_key).count).to eq(1)
      end

      it 'retains valid JWT refresh tokens' do
        # Insert multiple valid tokens
        valid_keys = 3.times.map do |i|
          key = SecureRandom.hex(32)
          test_db[:account_jwt_refresh_keys].insert(
            account_id: @account[:id],
            key: key,
            deadline: Time.now + (i + 1) * 3600 # Expires in future
          )
          key
        end

        # Insert new token to trigger cleanup
        new_key = SecureRandom.hex(32)
        test_db[:account_jwt_refresh_keys].insert(
          account_id: @account[:id],
          key: new_key,
          deadline: Time.now + 86400
        )

        # Verify all valid tokens still exist
        valid_keys.each do |key|
          expect(test_db[:account_jwt_refresh_keys].where(key: key).count).to eq(1)
        end
      end
    end

    context 'email auth key cleanup' do
      it 'removes expired email auth keys when JWT token is inserted' do
        # Insert expired email auth key
        expired_email_key = SecureRandom.hex(32)
        test_db[:account_email_auth_keys].insert(
          id: @account[:id],
          key: expired_email_key,
          deadline: Time.now - 3600, # Expired 1 hour ago
          email_last_sent: Time.now - 7200
        )

        # Verify expired email key exists
        expect(test_db[:account_email_auth_keys].where(key: expired_email_key).count).to eq(1)

        # Insert new JWT token - this triggers cleanup of both JWT and email keys
        new_jwt_key = SecureRandom.hex(32)
        test_db[:account_jwt_refresh_keys].insert(
          account_id: @account[:id],
          key: new_jwt_key,
          deadline: Time.now + 86400
        )

        # Verify expired email key was cleaned up
        expect(test_db[:account_email_auth_keys].where(key: expired_email_key).count).to eq(0)
      end

      it 'retains valid email auth keys' do
        # Insert valid email auth key
        valid_email_key = SecureRandom.hex(32)
        test_db[:account_email_auth_keys].insert(
          id: @account[:id],
          key: valid_email_key,
          deadline: Time.now + 3600, # Expires in future
          email_last_sent: Time.now
        )

        # Insert JWT token to trigger cleanup
        new_jwt_key = SecureRandom.hex(32)
        test_db[:account_jwt_refresh_keys].insert(
          account_id: @account[:id],
          key: new_jwt_key,
          deadline: Time.now + 86400
        )

        # Verify valid email key still exists
        expect(test_db[:account_email_auth_keys].where(key: valid_email_key).count).to eq(1)
      end
    end

    context 'multiple expired tokens' do
      it 'cleans up all expired tokens in a single trigger execution' do
        # Disable trigger during setup to accumulate expired tokens
        test_db.run('ALTER TABLE account_jwt_refresh_keys DISABLE TRIGGER trigger_cleanup_expired_tokens_extended')

        begin
          # Insert multiple expired JWT tokens
          expired_jwt_keys = 5.times.map do |i|
            key = SecureRandom.hex(32)
            test_db[:account_jwt_refresh_keys].insert(
              account_id: @account[:id],
              key: key,
              deadline: Time.now - (i + 1) * 3600 # All expired at different times
            )
            key
          end

          # Insert multiple expired email auth keys (different accounts to avoid PK conflict)
          expired_email_accounts = 3.times.map do
            account = create_verified_account(db: test_db)
            key = SecureRandom.hex(32)
            test_db[:account_email_auth_keys].insert(
              id: account[:id],
              key: key,
              deadline: Time.now - 3600,
              email_last_sent: Time.now - 7200
            )
            { account: account, key: key }
          end

          # Verify all expired tokens exist
          expired_jwt_keys.each do |key|
            expect(test_db[:account_jwt_refresh_keys].where(key: key).count).to eq(1)
          end
          expired_email_accounts.each do |data|
            expect(test_db[:account_email_auth_keys].where(key: data[:key]).count).to eq(1)
          end

          # Re-enable trigger before inserting new token
          test_db.run('ALTER TABLE account_jwt_refresh_keys ENABLE TRIGGER trigger_cleanup_expired_tokens_extended')

          # Insert new token to trigger cleanup
          new_key = SecureRandom.hex(32)
          test_db[:account_jwt_refresh_keys].insert(
            account_id: @account[:id],
            key: new_key,
            deadline: Time.now + 86400
          )

          # Verify all expired JWT tokens were cleaned up
          expired_jwt_keys.each do |key|
            expect(test_db[:account_jwt_refresh_keys].where(key: key).count).to eq(0)
          end

          # Verify all expired email auth keys were cleaned up
          expired_email_accounts.each do |data|
            expect(test_db[:account_email_auth_keys].where(key: data[:key]).count).to eq(0)
          end

          # Cleanup test accounts
          expired_email_accounts.each do |data|
            cleanup_account(db: test_db, account_id: data[:account][:id])
          end
        ensure
          # Always re-enable trigger
          test_db.run('ALTER TABLE account_jwt_refresh_keys ENABLE TRIGGER trigger_cleanup_expired_tokens_extended')
        end
      end
    end

    context 'edge cases' do
      it 'handles trigger when no expired tokens exist' do
        # Insert new token when no expired tokens exist
        new_key = SecureRandom.hex(32)
        expect do
          test_db[:account_jwt_refresh_keys].insert(
            account_id: @account[:id],
            key: new_key,
            deadline: Time.now + 86400
          )
        end.not_to raise_error

        # Verify new token exists
        expect(test_db[:account_jwt_refresh_keys].where(key: new_key).count).to eq(1)
      end

      it 'handles deadline in the past (boundary condition)' do
        # Insert token with deadline in the past to create reliable boundary condition
        # This is more deterministic than using sleep
        boundary_key = SecureRandom.hex(32)
        past_deadline = Time.now - 1  # 1 second in the past
        test_db[:account_jwt_refresh_keys].insert(
          account_id: @account[:id],
          key: boundary_key,
          deadline: past_deadline
        )

        # Insert new token to trigger cleanup
        new_key = SecureRandom.hex(32)
        test_db[:account_jwt_refresh_keys].insert(
          account_id: @account[:id],
          key: new_key,
          deadline: Time.now + 86400
        )

        # Token with past deadline should be cleaned up (deadline < NOW())
        expect(test_db[:account_jwt_refresh_keys].where(key: boundary_key).count).to eq(0)
      end
    end
  end

  describe 'PostgreSQL-Specific Features' do
    context 'get_account_security_summary function' do
      let(:test_email) { "security-summary-#{SecureRandom.hex(8)}@example.com" }

      before do
        @account = create_verified_account(db: test_db, email: test_email, password: test_password)
      end

      after do
        cleanup_account(db: test_db, account_id: @account[:id]) if @account
      end

      it 'returns security summary for account with password only' do
        result = test_db.fetch(
          'SELECT * FROM get_account_security_summary(?)',
          @account[:id]
        ).first

        expect(result[:has_password]).to be true
        expect(result[:has_otp]).to be false
        expect(result[:has_sms]).to be false
        expect(result[:has_webauthn]).to be false
        expect(result[:active_sessions]).to eq(0)
        expect(result[:failed_attempts]).to eq(0)
      end

      it 'detects active sessions' do
        # Create an active session
        session_id = SecureRandom.hex(32)
        test_db[:account_active_session_keys].insert(
          account_id: @account[:id],
          session_id: session_id,
          created_at: Time.now,
          last_use: Time.now
        )

        result = test_db.fetch(
          'SELECT * FROM get_account_security_summary(?)',
          @account[:id]
        ).first

        expect(result[:active_sessions]).to eq(1)
      end

      it 'detects last_login timestamp from activity times' do
        # Trigger login activity record
        login_time = Time.now
        test_db[:account_authentication_audit_logs].insert(
          account_id: @account[:id],
          at: login_time,
          message: 'login successful'
        )

        result = test_db.fetch(
          'SELECT * FROM get_account_security_summary(?)',
          @account[:id]
        ).first

        expect(result[:last_login]).to be_within(1).of(login_time)
      end

      it 'detects failed login attempts' do
        # Create login failure record
        test_db[:account_login_failures].insert(
          id: @account[:id],
          number: 3
        )

        result = test_db.fetch(
          'SELECT * FROM get_account_security_summary(?)',
          @account[:id]
        ).first

        expect(result[:failed_attempts]).to eq(3)
      end
    end

    context 'citext column handling' do
      it 'performs case-insensitive email lookups' do
        test_email = "CaseTest-#{SecureRandom.hex(8)}@Example.COM"
        account = create_verified_account(db: test_db, email: test_email)

        # Lookup with different case variations
        variations = [
          test_email.downcase,
          test_email.upcase,
          test_email.swapcase
        ]

        variations.each do |email_variant|
          found = test_db[:accounts].where(email: email_variant).first
          expect(found).not_to be_nil
          expect(found[:id]).to eq(account[:id])
        end

        # Cleanup
        cleanup_account(db: test_db, account_id: account[:id])
      end
    end
  end

  describe 'Schema Validation' do
    it 'trigger functions execute without database errors (validates column references)' do
      # Instead of parsing SQL with regex, let PostgreSQL validate column references
      # by actually firing the triggers. If trigger SQL references non-existent columns
      # (like NEW.account_id when table has 'id'), PostgreSQL will throw an error.

      account = create_verified_account(db: test_db)

      # Exercise update_last_login_time function/trigger
      expect {
        test_db[:account_authentication_audit_logs].insert(
          account_id: account[:id],
          at: Time.now,
          message: 'Login successful'  # PostgreSQL uses ILIKE (case-insensitive)
        )
      }.not_to raise_error

      # Exercise cleanup_expired_tokens_extended function/trigger
      expect {
        test_db[:account_jwt_refresh_keys].insert(
          account_id: account[:id],
          key: SecureRandom.urlsafe_base64(32),
          deadline: Time.now + 86400
        )
      }.not_to raise_error
    end

    it 'verifies update_last_login_time function exists' do
      result = test_db.fetch(<<~SQL).all
        SELECT proname, prosrc
        FROM pg_proc
        WHERE proname = 'update_last_login_time'
      SQL

      expect(result).not_to be_empty
      expect(result.first[:proname]).to eq('update_last_login_time')
    end

    it 'verifies cleanup_expired_tokens_extended function exists' do
      result = test_db.fetch(<<~SQL).all
        SELECT proname, prosrc
        FROM pg_proc
        WHERE proname = 'cleanup_expired_tokens_extended'
      SQL

      expect(result).not_to be_empty
      expect(result.first[:proname]).to eq('cleanup_expired_tokens_extended')
    end

    it 'verifies trigger is attached to correct table' do
      result = test_db.fetch(<<~SQL).all
        SELECT t.tgname, c.relname
        FROM pg_trigger t
        JOIN pg_class c ON t.tgrelid = c.oid
        WHERE t.tgname = 'trigger_update_last_login_time'
      SQL

      expect(result).not_to be_empty
      expect(result.first[:relname]).to eq('account_authentication_audit_logs')
    end
  end
end
