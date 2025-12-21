-- ================================================================
-- Rodauth SQLite Triggers (003)
-- Loaded by 003_triggers.rb migration
--
-- SQLite triggers use inline SQL instead of calling functions
-- ================================================================

-- ================================================================
-- CORE TRIGGERS (from 001_initial.sql)
-- ================================================================

-- Update account updated_at timestamp on any account update
CREATE TRIGGER update_accounts_updated_at
AFTER UPDATE ON accounts
BEGIN
    UPDATE accounts SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- ================================================================
-- ENHANCED TRIGGERS (from 002_extras.sql)
-- ================================================================

-- Automatically update activity time on successful logins
-- Triggered when audit log contains successful login message
CREATE TRIGGER trigger_update_last_login_time
AFTER INSERT ON account_authentication_audit_logs
WHEN NEW.message LIKE '%login%successful%'
BEGIN
    INSERT OR REPLACE INTO account_activity_times (id, last_login_at, last_activity_at)
    VALUES (NEW.account_id, NEW.at, NEW.at);
END;

-- Clean up expired tokens when new JWT refresh key is inserted
-- Removes expired JWT refresh keys and email auth keys
CREATE TRIGGER trigger_cleanup_expired_tokens_extended
AFTER INSERT ON account_jwt_refresh_keys
BEGIN
    DELETE FROM account_jwt_refresh_keys WHERE deadline < datetime('now');
    DELETE FROM account_email_auth_keys WHERE deadline < datetime('now');
END;

-- ================================================================
-- CLEANUP TRIGGERS FROM 001_initial.sql
-- ================================================================
--
-- Note: SQLite has more cleanup triggers than PostgreSQL because SQLite
-- cannot use stored functions. PostgreSQL consolidates these cleanups into
-- a single cleanup_expired_tokens() function callable from scheduled jobs.
-- SQLite requires separate inline triggers for each token type.
--

-- Clean up expired password reset keys
CREATE TRIGGER cleanup_expired_reset_keys
AFTER INSERT ON account_password_reset_keys
BEGIN
    DELETE FROM account_password_reset_keys WHERE deadline < datetime('now');
END;

-- Clean up expired remember keys
CREATE TRIGGER cleanup_expired_remember_keys
AFTER INSERT ON account_remember_keys
BEGIN
    DELETE FROM account_remember_keys WHERE deadline < datetime('now');
END;

-- Clean up expired lockouts
CREATE TRIGGER cleanup_expired_lockouts
AFTER INSERT ON account_lockouts
BEGIN
    DELETE FROM account_lockouts WHERE deadline < datetime('now');
END;
