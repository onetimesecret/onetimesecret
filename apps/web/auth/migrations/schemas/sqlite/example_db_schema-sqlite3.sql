-- ================================================================
-- Rodauth SQLite3 Database Schema (Enhanced)
-- Authentication and Account Management System
-- ================================================================

-- Enable foreign key constraints (required for SQLite)
PRAGMA foreign_keys = ON;

-- ================================================================
-- CORE TABLES
-- ================================================================

-- Account status lookup table
CREATE TABLE account_statuses (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

-- Main accounts table - core user accounts
CREATE TABLE accounts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT NOT NULL UNIQUE,
    status_id INTEGER NOT NULL,
    FOREIGN KEY (status_id) REFERENCES account_statuses(id)
);

-- ================================================================
-- PASSWORD MANAGEMENT
-- ================================================================

-- Current password hashes for accounts
CREATE TABLE account_password_hashes (
    account_id INTEGER PRIMARY KEY,
    password_hash TEXT NOT NULL,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- Previous password hashes for password history/reuse prevention
CREATE TABLE account_previous_password_hashes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id INTEGER NOT NULL,
    password_hash TEXT NOT NULL,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- Password change timestamps
CREATE TABLE account_password_change_times (
    account_id INTEGER PRIMARY KEY,
    changed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- Password reset tokens and expiration
CREATE TABLE account_password_reset_keys (
    account_id INTEGER PRIMARY KEY,
    key TEXT NOT NULL,
    deadline TEXT NOT NULL,
    email_last_sent TEXT,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- ================================================================
-- ACCOUNT VERIFICATION AND EMAIL AUTHENTICATION
-- ================================================================

-- Email verification tokens for new accounts
CREATE TABLE account_verification_keys (
    account_id INTEGER PRIMARY KEY,
    key TEXT NOT NULL,
    requested_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    email_last_sent TEXT,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- Email-based authentication tokens
CREATE TABLE account_email_auth_keys (
    account_id INTEGER PRIMARY KEY,
    key TEXT NOT NULL,
    deadline TEXT NOT NULL,
    email_last_sent TEXT,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- Login change verification (email change)
CREATE TABLE account_login_change_keys (
    account_id INTEGER PRIMARY KEY,
    key TEXT NOT NULL,
    login TEXT NOT NULL,
    deadline TEXT NOT NULL,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- ================================================================
-- SESSION MANAGEMENT
-- ================================================================

-- Basic session keys
CREATE TABLE account_session_keys (
    account_id INTEGER PRIMARY KEY,
    key TEXT NOT NULL,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- Remember me functionality
CREATE TABLE account_remember_keys (
    account_id INTEGER PRIMARY KEY,
    key TEXT NOT NULL,
    deadline TEXT NOT NULL,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- Active session tracking
CREATE TABLE account_active_session_keys (
    account_id INTEGER NOT NULL,
    session_id TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_use TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (account_id, session_id),
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- JWT refresh tokens
CREATE TABLE account_jwt_refresh_keys (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id INTEGER NOT NULL,
    key TEXT NOT NULL,
    deadline TEXT NOT NULL,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- ================================================================
-- MULTI-FACTOR AUTHENTICATION
-- ================================================================

-- TOTP/OTP keys and failure tracking
CREATE TABLE account_otp_keys (
    account_id INTEGER PRIMARY KEY,
    key TEXT NOT NULL,
    num_failures INTEGER NOT NULL DEFAULT 0,
    last_use TEXT,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- SMS-based two-factor authentication
CREATE TABLE account_sms_codes (
    account_id INTEGER PRIMARY KEY,
    phone_number TEXT NOT NULL,
    num_failures INTEGER NOT NULL DEFAULT 0,
    code TEXT NOT NULL,
    code_issued_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- Recovery codes for account recovery
CREATE TABLE account_recovery_codes (
    account_id INTEGER NOT NULL,
    code TEXT NOT NULL,
    PRIMARY KEY (account_id, code),
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- ================================================================
-- WEBAUTHN SUPPORT
-- ================================================================

-- WebAuthn user identifiers
CREATE TABLE account_webauthn_user_ids (
    account_id INTEGER PRIMARY KEY,
    webauthn_id TEXT NOT NULL,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- WebAuthn public keys and usage tracking
CREATE TABLE account_webauthn_keys (
    account_id INTEGER NOT NULL,
    webauthn_id TEXT NOT NULL,
    public_key TEXT NOT NULL,
    sign_count INTEGER NOT NULL DEFAULT 0,
    last_use TEXT,
    PRIMARY KEY (account_id, webauthn_id),
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- ================================================================
-- SECURITY AND MONITORING
-- ================================================================

-- Failed login attempt tracking
CREATE TABLE account_login_failures (
    account_id INTEGER PRIMARY KEY,
    number INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- Account lockout management
CREATE TABLE account_lockouts (
    account_id INTEGER PRIMARY KEY,
    key TEXT NOT NULL,
    deadline TEXT NOT NULL,
    email_last_sent TEXT,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- Activity tracking and session expiration
CREATE TABLE account_activity_times (
    account_id INTEGER PRIMARY KEY,
    last_activity_at TEXT,
    last_login_at TEXT,
    expired_at TEXT,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- Authentication audit logging
CREATE TABLE account_authentication_audit_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id INTEGER NOT NULL,
    at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    message TEXT NOT NULL,
    metadata TEXT, -- JSON stored as text
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- ================================================================
-- INDEXES FOR PERFORMANCE
-- ================================================================

-- Essential indexes for common queries
CREATE INDEX idx_accounts_email ON accounts(email);
CREATE INDEX idx_accounts_status_id ON accounts(status_id);
CREATE INDEX idx_auth_audit_logs_account_id ON account_authentication_audit_logs(account_id);
CREATE INDEX idx_auth_audit_logs_at ON account_authentication_audit_logs(at);
CREATE INDEX idx_jwt_refresh_keys_account_id ON account_jwt_refresh_keys(account_id);
CREATE INDEX idx_jwt_refresh_keys_deadline ON account_jwt_refresh_keys(deadline);
CREATE INDEX idx_previous_password_hashes_account_id ON account_previous_password_hashes(account_id);

-- Enhanced indexes for session management and activity tracking
CREATE INDEX idx_active_session_keys_last_use ON account_active_session_keys(last_use);
CREATE INDEX idx_activity_times_last_activity ON account_activity_times(last_activity_at);
CREATE INDEX idx_activity_times_last_login ON account_activity_times(last_login_at);

-- Indexes for token cleanup efficiency
CREATE INDEX idx_password_reset_keys_deadline ON account_password_reset_keys(deadline);
CREATE INDEX idx_email_auth_keys_deadline ON account_email_auth_keys(deadline);
CREATE INDEX idx_remember_keys_deadline ON account_remember_keys(deadline);
CREATE INDEX idx_lockouts_deadline ON account_lockouts(deadline);

-- ================================================================
-- INITIAL DATA
-- ================================================================

-- Common account statuses
INSERT INTO account_statuses (id, name) VALUES
    (1, 'Unverified'),
    (2, 'Verified'),
    (3, 'Closed');

-- ================================================================
-- UTILITY VIEWS
-- ================================================================

-- View to get accounts with readable status names
CREATE VIEW accounts_with_status AS
SELECT
    a.id,
    a.email,
    s.name as status_name,
    a.status_id
FROM accounts a
JOIN account_statuses s ON a.status_id = s.id;

-- View for recent authentication events (last 30 days)
CREATE VIEW recent_auth_events AS
SELECT
    l.id,
    l.account_id,
    a.email,
    l.at,
    l.message,
    l.metadata
FROM account_authentication_audit_logs l
JOIN accounts a ON l.account_id = a.id
WHERE date(l.at) >= date('now', '-30 days')
ORDER BY l.at DESC;

-- Enhanced view for active sessions with account details and activity metrics
CREATE VIEW active_sessions_with_accounts AS
SELECT
    s.account_id,
    a.email,
    s.session_id,
    s.created_at,
    s.last_use,
    ROUND((julianday('now') - julianday(s.last_use)) * 1440, 2) AS minutes_since_last_use,
    CASE
        WHEN (julianday('now') - julianday(s.last_use)) * 1440 > 30 THEN 'Inactive'
        WHEN (julianday('now') - julianday(s.last_use)) * 1440 > 5 THEN 'Idle'
        ELSE 'Active'
    END AS session_status
FROM account_active_session_keys s
JOIN accounts a ON s.account_id = a.id
ORDER BY s.last_use DESC;

-- View for account security overview
CREATE VIEW account_security_overview AS
SELECT
    a.id,
    a.email,
    s.name as status_name,
    CASE WHEN ph.account_id IS NOT NULL THEN 1 ELSE 0 END as has_password,
    CASE WHEN ok.account_id IS NOT NULL THEN 1 ELSE 0 END as has_otp,
    CASE WHEN sc.account_id IS NOT NULL THEN 1 ELSE 0 END as has_sms,
    CASE WHEN wk.account_id IS NOT NULL THEN 1 ELSE 0 END as has_webauthn,
    COALESCE(session_count.count, 0) as active_sessions,
    at.last_login_at,
    COALESCE(lf.number, 0) as failed_attempts
FROM accounts a
JOIN account_statuses s ON a.status_id = s.id
LEFT JOIN account_password_hashes ph ON a.id = ph.account_id
LEFT JOIN account_otp_keys ok ON a.id = ok.account_id
LEFT JOIN account_sms_codes sc ON a.id = sc.account_id
LEFT JOIN account_webauthn_keys wk ON a.id = wk.account_id
LEFT JOIN account_activity_times at ON a.id = at.account_id
LEFT JOIN account_login_failures lf ON a.id = lf.account_id
LEFT JOIN (
    SELECT account_id, COUNT(*) as count
    FROM account_active_session_keys
    GROUP BY account_id
) session_count ON a.id = session_count.account_id;

-- ================================================================
-- SQLITE3 SPECIFIC FUNCTIONS AND TRIGGERS
-- ================================================================

-- Enhanced trigger to automatically update activity time on successful logins
CREATE TRIGGER update_last_login_time
AFTER INSERT ON account_authentication_audit_logs
WHEN NEW.message LIKE '%login%successful%'
BEGIN
    INSERT OR REPLACE INTO account_activity_times (account_id, last_login_at, last_activity_at)
    VALUES (NEW.account_id, NEW.at, NEW.at);
END;

-- Enhanced trigger to clean up expired tokens (runs on JWT refresh key insert)
CREATE TRIGGER cleanup_expired_jwt_tokens
AFTER INSERT ON account_jwt_refresh_keys
BEGIN
    DELETE FROM account_jwt_refresh_keys WHERE deadline < datetime('now');
    DELETE FROM account_password_reset_keys WHERE deadline < datetime('now');
    DELETE FROM account_email_auth_keys WHERE deadline < datetime('now');
    DELETE FROM account_remember_keys WHERE deadline < datetime('now');
    DELETE FROM account_lockouts WHERE deadline < datetime('now');
END;

-- Trigger to update session activity when session is accessed
CREATE TRIGGER update_session_activity
AFTER UPDATE ON account_active_session_keys
WHEN NEW.last_use != OLD.last_use
BEGIN
    UPDATE account_activity_times
    SET last_activity_at = NEW.last_use
    WHERE account_id = NEW.account_id;
END;

-- Trigger to cleanup old audit logs (keep last 1000 per account)
CREATE TRIGGER cleanup_old_audit_logs
AFTER INSERT ON account_authentication_audit_logs
BEGIN
    DELETE FROM account_authentication_audit_logs
    WHERE account_id = NEW.account_id
    AND id NOT IN (
        SELECT id FROM account_authentication_audit_logs
        WHERE account_id = NEW.account_id
        ORDER BY at DESC
        LIMIT 1000
    );
END;

-- ================================================================
-- SQLITE3 MAINTENANCE QUERIES (Examples for manual execution)
-- ================================================================

/*
-- ================================================================
-- MAINTENANCE FUNCTIONS (Execute manually as needed)
-- ================================================================

-- Clean up old audit logs (keep last 90 days)
DELETE FROM account_authentication_audit_logs
WHERE date(at) < date('now', '-90 days');

-- Clean up expired tokens
DELETE FROM account_jwt_refresh_keys WHERE deadline < datetime('now');
DELETE FROM account_password_reset_keys WHERE deadline < datetime('now');
DELETE FROM account_email_auth_keys WHERE deadline < datetime('now');
DELETE FROM account_remember_keys WHERE deadline < datetime('now');
DELETE FROM account_lockouts WHERE deadline < datetime('now');

-- Clean up inactive sessions (older than 30 days)
DELETE FROM account_active_session_keys
WHERE date(last_use) < date('now', '-30 days');

-- Update session last_use timestamp (call from application)
UPDATE account_active_session_keys
SET last_use = CURRENT_TIMESTAMP
WHERE account_id = ? AND session_id = ?;

-- Get account security summary
SELECT * FROM account_security_overview WHERE id = ?;

-- Find accounts with weak security (no MFA)
SELECT email, status_name, has_password, has_otp, has_sms, has_webauthn
FROM account_security_overview
WHERE has_otp = 0 AND has_sms = 0 AND has_webauthn = 0
AND status_name = 'Verified';

-- Find inactive sessions
SELECT * FROM active_sessions_with_accounts
WHERE session_status = 'Inactive';

-- Database statistics
SELECT
    'Total Accounts' as metric,
    COUNT(*) as value
FROM accounts
UNION ALL
SELECT
    'Verified Accounts',
    COUNT(*)
FROM accounts_with_status
WHERE status_name = 'Verified'
UNION ALL
SELECT
    'Active Sessions',
    COUNT(*)
FROM account_active_session_keys
UNION ALL
SELECT
    'Recent Logins (7 days)',
    COUNT(*)
FROM recent_auth_events
WHERE message LIKE '%login%successful%'
AND date(at) >= date('now', '-7 days');

-- ================================================================
-- USAGE EXAMPLES
-- ================================================================

-- Example: Create a new account
INSERT INTO accounts (email, status_id) VALUES ('user@example.com', 1);

-- Example: Set password hash
INSERT INTO account_password_hashes (account_id, password_hash)
VALUES (last_insert_rowid(), '$2b$12$...');

-- Example: Query accounts with status
SELECT * FROM accounts_with_status WHERE status_name = 'Verified';

-- Example: Check if email exists
SELECT COUNT(*) FROM accounts WHERE email = 'user@example.com';

-- Example: Get recent login attempts for account
SELECT * FROM recent_auth_events
WHERE account_id = 1 AND message LIKE '%login%'
ORDER BY at DESC LIMIT 10;

-- Example: Get account security overview
SELECT * FROM account_security_overview WHERE email = 'user@example.com';

-- Example: View active sessions with activity status
SELECT * FROM active_sessions_with_accounts
WHERE account_id = 1
ORDER BY last_use DESC;

-- Example: Find sessions that need cleanup (inactive > 24 hours)
SELECT * FROM active_sessions_with_accounts
WHERE minutes_since_last_use > 1440;

-- Example: Create a new session
INSERT INTO account_active_session_keys (account_id, session_id)
VALUES (1, 'session_' || hex(randomblob(16)));

-- Example: Update session activity (call from application)
UPDATE account_active_session_keys
SET last_use = CURRENT_TIMESTAMP
WHERE account_id = 1 AND session_id = 'session_abc123';

-- Example: Remove inactive sessions
DELETE FROM account_active_session_keys
WHERE date(last_use) < date('now', '-7 days');

-- Example: Get accounts needing security improvements
SELECT email, 'No MFA configured' as recommendation
FROM account_security_overview
WHERE has_otp = 0 AND has_sms = 0 AND has_webauthn = 0
AND status_name = 'Verified'
UNION ALL
SELECT email, 'Multiple failed login attempts'
FROM account_security_overview
WHERE failed_attempts > 5;

-- Example: Audit recent activity for an account
SELECT
    'Login Events' as event_type,
    COUNT(*) as count,
    MAX(at) as last_occurrence
FROM recent_auth_events
WHERE account_id = 1 AND message LIKE '%login%'
UNION ALL
SELECT
    'Password Changes',
    COUNT(*),
    MAX(changed_at)
FROM account_password_change_times
WHERE account_id = 1
UNION ALL
SELECT
    'Active Sessions',
    COUNT(*),
    MAX(last_use)
FROM account_active_session_keys
WHERE account_id = 1;
*/
