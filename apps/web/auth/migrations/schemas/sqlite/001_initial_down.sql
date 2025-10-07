-- ================================================================
-- Rodauth SQLite3 Schema - Complete Rollback
-- Removes all authentication tables, views, triggers, and data
-- ================================================================

-- Drop all views (depend on tables)
DROP VIEW IF EXISTS active_sessions_with_accounts;
DROP VIEW IF EXISTS accounts_with_status;
DROP VIEW IF EXISTS user_sessions_summary;
DROP VIEW IF EXISTS account_security_summary;

-- Drop all triggers
DROP TRIGGER IF EXISTS cleanup_expired_lockouts;
DROP TRIGGER IF EXISTS cleanup_expired_remember_keys;
DROP TRIGGER IF EXISTS cleanup_expired_reset_keys;
DROP TRIGGER IF EXISTS update_accounts_updated_at;
DROP TRIGGER IF EXISTS log_password_changes;
DROP TRIGGER IF EXISTS cleanup_old_audit_logs;

-- Drop all tables in reverse dependency order
-- Example/additional tables first
DROP TABLE IF EXISTS account_email_auth_keys;
DROP TABLE IF EXISTS account_sms_codes;
DROP TABLE IF EXISTS account_webauthn_keys;
DROP TABLE IF EXISTS account_jwt_refresh_keys;
DROP TABLE IF EXISTS account_login_change_keys;
DROP TABLE IF EXISTS account_password_change_times;
DROP TABLE IF EXISTS account_previous_password_hashes;

-- Authentication tables
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
