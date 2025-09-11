-- ================================================================
-- Rodauth PostgreSQL Essential Schema - Rollback/Down Migration
-- Drops all authentication tables and functions in proper dependency order
-- ================================================================

-- Drop views first (depend on tables)
DROP VIEW IF EXISTS active_sessions_with_accounts;
DROP VIEW IF EXISTS accounts_with_status;

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

-- Drop PostgreSQL functions
DROP FUNCTION IF EXISTS rodauth_get_salt(BIGINT);
DROP FUNCTION IF EXISTS rodauth_valid_password_hash(BIGINT, TEXT);
DROP FUNCTION IF EXISTS cleanup_expired_tokens();
DROP FUNCTION IF EXISTS update_accounts_updated_at();
