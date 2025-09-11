-- ================================================================
-- Rodauth PostgreSQL Schema - Complete Rollback
-- Removes all authentication tables, views, functions, and data
-- ================================================================

-- Drop all views (depend on tables)
DROP VIEW IF EXISTS active_sessions_with_accounts;
DROP VIEW IF EXISTS accounts_with_status;
DROP VIEW IF EXISTS user_sessions_summary;
DROP VIEW IF EXISTS account_security_summary;

-- Drop all tables in reverse dependency order
-- Example/additional tables first
DROP TABLE IF EXISTS account_email_auth_keys;
DROP TABLE IF EXISTS account_sms_codes;
DROP TABLE IF EXISTS account_webauthn_keys;
DROP TABLE IF EXISTS account_jwt_refresh_keys;
DROP TABLE IF EXISTS account_login_change_keys;
DROP TABLE IF EXISTS account_password_change_times;
DROP TABLE IF EXISTS account_previous_password_hashes;

-- Core authentication tables
DROP TABLE IF EXISTS account_authentication_audit_logs;
DROP TABLE IF EXISTS account_recovery_codes;
DROP TABLE IF EXISTS account_otp_keys;
DROP TABLE IF EXISTS account_active_session_keys;
DROP TABLE IF EXISTS account_remember_keys;
DROP TABLE IF EXISTS account_lockouts;
DROP TABLE IF EXISTS account_login_failures;
DROP TABLE IF EXISTS account_password_reset_keys;
DROP TABLE IF EXISTS account_verification_keys;
DROP TABLE IF EXISTS account_password_hashes;
DROP TABLE IF EXISTS accounts;
DROP TABLE IF EXISTS account_statuses;

-- Drop all PostgreSQL functions
DROP FUNCTION IF EXISTS rodauth_get_salt(BIGINT);
DROP FUNCTION IF EXISTS rodauth_valid_password_hash(BIGINT, TEXT);
DROP FUNCTION IF EXISTS cleanup_expired_tokens();
DROP FUNCTION IF EXISTS update_accounts_updated_at();
DROP FUNCTION IF EXISTS validate_password_complexity(TEXT);
DROP FUNCTION IF EXISTS log_authentication_event(BIGINT, TEXT, JSONB);
DROP FUNCTION IF EXISTS cleanup_old_sessions();
