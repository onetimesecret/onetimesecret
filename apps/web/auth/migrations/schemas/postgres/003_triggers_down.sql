-- ================================================================
-- Rodauth PostgreSQL Triggers Rollback (003)
-- Loaded by 003_triggers.rb migration (down)
--
-- Removes all database triggers created by 003_triggers_up.sql
-- ================================================================

-- ================================================================
-- TRIGGERS FROM 002_extras AND 001_initial
-- ================================================================

DROP TRIGGER IF EXISTS trigger_cleanup_expired_tokens_extended ON account_jwt_refresh_keys;
DROP TRIGGER IF EXISTS trigger_update_last_login_time ON account_authentication_audit_logs;
DROP TRIGGER IF EXISTS update_accounts_updated_at ON accounts;
