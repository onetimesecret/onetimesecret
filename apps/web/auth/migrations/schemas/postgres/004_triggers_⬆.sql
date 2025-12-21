-- ================================================================
-- Rodauth PostgreSQL Triggers (004)
-- Loaded by 003_triggers.rb migration
-- ================================================================

-- ================================================================
-- TRIGGERS USING FUNCTIONS FROM 002_functions.sql
-- ================================================================

CREATE TRIGGER update_accounts_updated_at
    BEFORE UPDATE ON accounts
    FOR EACH ROW
    EXECUTE FUNCTION update_accounts_updated_at();

-- Trigger to automatically update activity time on successful logins
CREATE TRIGGER trigger_update_last_login_time
    AFTER INSERT ON account_authentication_audit_logs
    FOR EACH ROW
    EXECUTE FUNCTION update_last_login_time();

-- Trigger to clean up expired tokens (runs on JWT refresh key insert)
CREATE TRIGGER trigger_cleanup_expired_tokens_extended
    AFTER INSERT ON account_jwt_refresh_keys
    FOR EACH ROW
    EXECUTE FUNCTION cleanup_expired_tokens_extended();
