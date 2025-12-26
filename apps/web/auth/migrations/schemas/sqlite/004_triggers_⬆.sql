-- ================================================================
-- Rodauth SQLite Triggers (004)
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
--
-- Trigger context: NEW references the inserted audit log row:
--   - NEW.account_id → audit_logs.account_id (FK to accounts.id)
--   - NEW.at         → audit_logs.at (timestamp of the event)
--   - NEW.message    → audit_logs.message (filtered in WHEN clause)
--
-- Data flow: audit_logs.account_id → account_activity_times.id
-- Both are foreign keys to accounts.id, so the value transfer is correct.
--
-- Pattern matching: Uses LOWER() for case-insensitive matching since
-- COLLATE NOCASE doesn't work in trigger WHEN clauses.
-- Matches messages containing both "login" and "successful" in any order,
-- consistent with PostgreSQL's ILIKE behavior.
CREATE TRIGGER trigger_update_last_login_time
AFTER INSERT ON account_authentication_audit_logs
WHEN LOWER(NEW.message) LIKE '%login%' AND LOWER(NEW.message) LIKE '%successful%'
BEGIN
    -- Insert or update activity times using the account_id from the audit log
    INSERT OR REPLACE INTO account_activity_times (id, last_login_at, last_activity_at)
    VALUES (NEW.account_id, NEW.at, NEW.at);
END;

-- Clean up expired tokens when new JWT refresh key is inserted
--
-- Design: Opportunistic global cleanup
-- When any user creates a token, clean up ALL expired tokens system-wide.
-- This avoids needing a separate scheduled cleanup job for low-volume deployments.
--
-- The newly inserted row is excluded from cleanup to ensure predictable behavior
-- even if a token is inserted with a past deadline (edge case, useful for testing).
--
-- Potential concern for high-scale systems:
-- - Cross-account coupling: User A's insert triggers deletes for Users B, C, D...
-- - Lock contention: Large DELETE operations may block concurrent inserts
-- - Unpredictable timing: Cleanup happens based on user activity patterns
-- For high-volume deployments, consider account-scoped cleanup with a separate
-- scheduled job for global maintenance.
--
CREATE TRIGGER trigger_cleanup_expired_tokens_extended
AFTER INSERT ON account_jwt_refresh_keys
BEGIN
    -- Exclude the newly inserted row from cleanup
    DELETE FROM account_jwt_refresh_keys
    WHERE deadline < datetime('now')
      AND NOT (account_id = NEW.account_id AND key = NEW.key);
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
