-- ================================================================
-- Rodauth SQLite3 Essential Schema - Rollback/Down Migration
-- Drops all authentication tables in proper dependency order
-- ================================================================

-- Drop views first (depend on tables)
DROP VIEW IF EXISTS active_sessions_with_accounts;
DROP VIEW IF EXISTS accounts_with_status;

-- Drop triggers
DROP TRIGGER IF EXISTS cleanup_expired_lockouts;
DROP TRIGGER IF EXISTS cleanup_expired_remember_keys;
DROP TRIGGER IF EXISTS cleanup_expired_reset_keys;
DROP TRIGGER IF EXISTS update_accounts_updated_at;

-- Drop tables in reverse dependency order to avoid foreign key conflicts
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
