-- ================================================================
-- Rodauth PostgreSQL Functions Rollback (003)
-- Loaded by 002_functions.rb migration (down)
--
-- Removes all database functions created by 002_functions_up.sql
-- ================================================================

-- ================================================================
-- UTILITY FUNCTIONS (from 002_extras)
-- ================================================================

DROP FUNCTION IF EXISTS get_account_security_summary(BIGINT);
DROP FUNCTION IF EXISTS cleanup_old_audit_logs();
DROP FUNCTION IF EXISTS update_session_last_use(BIGINT, VARCHAR);

-- ================================================================
-- TRIGGER FUNCTIONS (from 002_extras and 001_initial)
-- ================================================================

DROP FUNCTION IF EXISTS update_accounts_updated_at();
DROP FUNCTION IF EXISTS cleanup_expired_tokens_extended();
DROP FUNCTION IF EXISTS update_last_login_time();

-- ================================================================
-- SECURITY FUNCTIONS (from 001_initial)
-- ================================================================

DROP FUNCTION IF EXISTS cleanup_expired_tokens();
DROP FUNCTION IF EXISTS rodauth_valid_password_hash(BIGINT, TEXT);
DROP FUNCTION IF EXISTS rodauth_get_salt(BIGINT);
