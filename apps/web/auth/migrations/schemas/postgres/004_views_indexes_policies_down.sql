-- ================================================================
-- Rodauth PostgreSQL Views, Indexes, Policies Rollback (004)
-- Loaded by 004_views_indexes_policies.rb migration (down)
--
-- Removes views, indexes, and RLS policies created by 004_views_indexes_policies_up.sql
-- ================================================================

-- ================================================================
-- VIEWS (from 002_extras and 001_initial)
-- ================================================================

DROP VIEW IF EXISTS account_security_overview_enhanced;
DROP VIEW IF EXISTS recent_auth_events;
DROP VIEW IF EXISTS active_sessions_with_accounts;
DROP VIEW IF EXISTS accounts_with_status;

-- ================================================================
-- PERFORMANCE INDEXES (from 002_extras)
-- ================================================================

DROP INDEX IF EXISTS idx_previous_password_hashes_account_id;
DROP INDEX IF EXISTS idx_activity_times_last_login;
DROP INDEX IF EXISTS idx_email_auth_keys_deadline;
DROP INDEX IF EXISTS idx_activity_times_last_activity;
DROP INDEX IF EXISTS idx_jwt_refresh_keys_deadline;
DROP INDEX IF EXISTS idx_jwt_refresh_keys_account_id;

-- ================================================================
-- ROW LEVEL SECURITY (from 001_initial)
-- ================================================================

ALTER TABLE account_recovery_codes DISABLE ROW LEVEL SECURITY;
ALTER TABLE account_otp_keys DISABLE ROW LEVEL SECURITY;
ALTER TABLE account_password_hashes DISABLE ROW LEVEL SECURITY;
