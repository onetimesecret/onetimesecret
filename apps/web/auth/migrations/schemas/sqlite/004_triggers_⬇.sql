-- ================================================================
-- Rodauth SQLite Triggers Rollback (004)
-- Loaded by 003_triggers.rb migration (down)
--
-- Removes all database triggers created by 003_triggers_up.sql
-- ================================================================

-- ================================================================
-- ENHANCED TRIGGERS (from 002_extras)
-- ================================================================

DROP TRIGGER IF EXISTS trigger_cleanup_expired_tokens_extended;
DROP TRIGGER IF EXISTS trigger_update_last_login_time;

-- ================================================================
-- CLEANUP TRIGGERS FROM 001_initial
-- ================================================================

DROP TRIGGER IF EXISTS cleanup_expired_lockouts;
DROP TRIGGER IF EXISTS cleanup_expired_remember_keys;
DROP TRIGGER IF EXISTS cleanup_expired_reset_keys;

-- ================================================================
-- CORE TRIGGERS (from 001_initial)
-- ================================================================

DROP TRIGGER IF EXISTS update_accounts_updated_at;
