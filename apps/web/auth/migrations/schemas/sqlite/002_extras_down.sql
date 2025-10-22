-- ================================================================
-- Rollback Extended Features - SQLite
-- ================================================================

-- Drop triggers first
DROP TRIGGER IF EXISTS update_login_activity;
DROP TRIGGER IF EXISTS cleanup_expired_jwt_refresh_tokens;

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
