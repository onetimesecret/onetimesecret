-- ================================================================
-- Rodauth SQLite Performance Indexes Rollback (002)
-- ================================================================

DROP INDEX IF EXISTS idx_previous_password_hashes_account_id;
DROP INDEX IF EXISTS idx_email_auth_keys_deadline;
DROP INDEX IF EXISTS idx_activity_times_last_login;
DROP INDEX IF EXISTS idx_activity_times_last_activity;
DROP INDEX IF EXISTS idx_jwt_refresh_keys_deadline;
DROP INDEX IF EXISTS idx_jwt_refresh_keys_account_id;
