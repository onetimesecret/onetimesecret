-- ================================================================
-- Rollback Extended Features - PostgreSQL
-- ================================================================

-- Drop triggers first
DROP TRIGGER IF EXISTS trigger_update_last_login_time ON account_authentication_audit_logs;
DROP TRIGGER IF EXISTS trigger_cleanup_expired_tokens_extended ON account_jwt_refresh_keys;

-- Drop functions
DROP FUNCTION IF EXISTS update_last_login_time();
DROP FUNCTION IF EXISTS cleanup_expired_tokens_extended();
DROP FUNCTION IF EXISTS update_session_last_use(BIGINT, VARCHAR);
DROP FUNCTION IF EXISTS cleanup_old_audit_logs();
DROP FUNCTION IF EXISTS get_account_security_summary(BIGINT);

-- Drop views
DROP VIEW IF EXISTS recent_auth_events;
DROP VIEW IF EXISTS account_security_overview_enhanced;

-- Drop tables (reverse order of creation)
DROP TABLE IF EXISTS account_activity_times;
DROP TABLE IF EXISTS account_webauthn_keys;
DROP TABLE IF EXISTS account_webauthn_user_ids;
DROP TABLE IF EXISTS account_sms_codes;
DROP TABLE IF EXISTS account_jwt_refresh_keys;
DROP TABLE IF EXISTS account_session_keys;
DROP TABLE IF EXISTS account_login_change_keys;
DROP TABLE IF EXISTS account_email_auth_keys;
DROP TABLE IF EXISTS account_password_change_times;
DROP TABLE IF EXISTS account_previous_password_hashes;
