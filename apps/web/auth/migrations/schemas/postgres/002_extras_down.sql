-- ================================================================
-- Rollback Extended Features - PostgreSQL
-- Drops only database-specific features created in 002_extras.sql
-- Tables are dropped in 002_extras.rb migration
-- ================================================================

-- Drop triggers first (depend on functions)
DROP TRIGGER IF EXISTS trigger_update_last_login_time ON account_authentication_audit_logs;
DROP TRIGGER IF EXISTS trigger_cleanup_expired_tokens_extended ON account_jwt_refresh_keys;

-- Drop functions
DROP FUNCTION IF EXISTS update_last_login_time();
DROP FUNCTION IF EXISTS cleanup_expired_tokens_extended();
DROP FUNCTION IF EXISTS update_session_last_use(BIGINT, VARCHAR);
DROP FUNCTION IF EXISTS cleanup_old_audit_logs();
DROP FUNCTION IF EXISTS get_account_security_summary(BIGINT);

-- Drop Indexes
DROP INDEX IF EXISTS idx_jwt_refresh_keys_account_id;
DROP INDEX IF EXISTS idx_jwt_refresh_keys_deadline;
DROP INDEX IF EXISTS idx_activity_times_last_activity;
DROP INDEX IF EXISTS idx_email_auth_keys_deadline;
DROP INDEX IF EXISTS idx_activity_times_last_login;


-- Drop views
DROP VIEW IF EXISTS recent_auth_events;
DROP VIEW IF EXISTS account_security_overview_enhanced;
