-- ================================================================
-- Rodauth SQLite3 Database Schema (Essential Tables Only)
-- Authentication and Account Management System
-- Focused on enabled features: base, json, login, logout, create_account, 
-- close_account, login_password_requirements_base, change_password, 
-- reset_password, remember, verify_account, lockout, active_sessions
-- ================================================================

-- Enable foreign key constraints (required for SQLite)
PRAGMA foreign_keys = ON;

-- ================================================================
-- CORE TABLES (Required for all Rodauth configurations)
-- ================================================================

-- Account status lookup table
CREATE TABLE account_statuses (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

-- Main accounts table - core user accounts
-- Note: SQLite doesn't have citext, so emails are case-sensitive by default
-- Consider normalizing to lowercase in application code
CREATE TABLE accounts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT NOT NULL UNIQUE COLLATE NOCASE, -- Case-insensitive in SQLite
    status_id INTEGER NOT NULL DEFAULT 1,
    FOREIGN KEY (status_id) REFERENCES account_statuses(id)
);

-- ================================================================
-- PASSWORD MANAGEMENT (Required for login, change_password features)
-- ================================================================

-- Current password hashes for accounts (separated for security)
CREATE TABLE account_password_hashes (
    id INTEGER PRIMARY KEY, -- Maps to accounts.id (Rodauth uses 'id' not 'account_id')
    password_hash TEXT NOT NULL,
    FOREIGN KEY (id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- Password reset tokens (reset_password feature)
CREATE TABLE account_password_reset_keys (
    id INTEGER PRIMARY KEY, -- Maps to accounts.id
    key TEXT NOT NULL,
    deadline TEXT NOT NULL, -- ISO 8601 datetime string
    email_last_sent TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- ================================================================
-- ACCOUNT VERIFICATION (verify_account feature)
-- ================================================================

-- Email verification tokens for new accounts
CREATE TABLE account_verification_keys (
    id INTEGER PRIMARY KEY, -- Maps to accounts.id
    key TEXT NOT NULL,
    requested_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    email_last_sent TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- ================================================================
-- SESSION MANAGEMENT (remember, active_sessions features)
-- ================================================================

-- Remember me functionality (remember feature)
CREATE TABLE account_remember_keys (
    id INTEGER PRIMARY KEY, -- Maps to accounts.id
    key TEXT NOT NULL,
    deadline TEXT NOT NULL, -- ISO 8601 datetime string
    FOREIGN KEY (id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- Active session tracking (active_sessions feature)
-- Note: Uses account_id (not id) and compound primary key
CREATE TABLE account_active_session_keys (
    account_id INTEGER NOT NULL,
    session_id TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_use TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (account_id, session_id),
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- ================================================================
-- SECURITY AND MONITORING (lockout feature)
-- ================================================================

-- Failed login attempt tracking (lockout feature)
CREATE TABLE account_login_failures (
    id INTEGER PRIMARY KEY, -- Maps to accounts.id
    number INTEGER NOT NULL DEFAULT 1,
    FOREIGN KEY (id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- Account lockout management (lockout feature)
CREATE TABLE account_lockouts (
    id INTEGER PRIMARY KEY, -- Maps to accounts.id
    key TEXT NOT NULL,
    deadline TEXT NOT NULL, -- ISO 8601 datetime string
    email_last_sent TEXT,
    FOREIGN KEY (id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- ================================================================
-- INDEXES FOR PERFORMANCE
-- ================================================================

-- Essential indexes for common queries
CREATE INDEX idx_accounts_email ON accounts(email);
CREATE INDEX idx_accounts_status_id ON accounts(status_id);

-- Indexes for token cleanup and session management
CREATE INDEX idx_password_reset_keys_deadline ON account_password_reset_keys(deadline);
CREATE INDEX idx_remember_keys_deadline ON account_remember_keys(deadline);
CREATE INDEX idx_lockouts_deadline ON account_lockouts(deadline);
CREATE INDEX idx_active_session_keys_last_use ON account_active_session_keys(last_use);
CREATE INDEX idx_active_session_keys_account_id ON account_active_session_keys(account_id);

-- ================================================================
-- INITIAL DATA
-- ================================================================

-- Standard account statuses for Rodauth
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

-- View for active sessions with account details
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

-- ================================================================
-- SQLITE3 MAINTENANCE TRIGGERS
-- ================================================================

-- Automatically clean up expired tokens
CREATE TRIGGER cleanup_expired_tokens
AFTER INSERT ON account_password_reset_keys
BEGIN
    DELETE FROM account_password_reset_keys WHERE deadline < datetime('now');
    DELETE FROM account_remember_keys WHERE deadline < datetime('now');
    DELETE FROM account_lockouts WHERE deadline < datetime('now');
END;

-- Update session activity timestamp
CREATE TRIGGER update_session_last_use
AFTER UPDATE OF last_use ON account_active_session_keys
BEGIN
    -- This trigger ensures consistency in session tracking
    UPDATE account_active_session_keys 
    SET last_use = CURRENT_TIMESTAMP 
    WHERE account_id = NEW.account_id AND session_id = NEW.session_id;
END;

-- ================================================================
-- MAINTENANCE QUERIES (Execute manually as needed)
-- ================================================================

/*
-- Clean up expired tokens manually
DELETE FROM account_password_reset_keys WHERE deadline < datetime('now');
DELETE FROM account_remember_keys WHERE deadline < datetime('now');
DELETE FROM account_lockouts WHERE deadline < datetime('now');

-- Clean up inactive sessions (older than 30 days)
DELETE FROM account_active_session_keys
WHERE date(last_use) < date('now', '-30 days');

-- Update session last_use timestamp (call from application)
UPDATE account_active_session_keys
SET last_use = CURRENT_TIMESTAMP
WHERE account_id = ? AND session_id = ?;

-- Check account status and security
SELECT 
    a.id,
    a.email,
    s.name as status,
    CASE WHEN ph.id IS NOT NULL THEN 'Yes' ELSE 'No' END as has_password,
    COALESCE(lf.number, 0) as failed_attempts,
    COUNT(ask.session_id) as active_sessions
FROM accounts a
JOIN account_statuses s ON a.status_id = s.id
LEFT JOIN account_password_hashes ph ON a.id = ph.id
LEFT JOIN account_login_failures lf ON a.id = lf.id
LEFT JOIN account_active_session_keys ask ON a.id = ask.account_id
WHERE a.id = ?
GROUP BY a.id, a.email, s.name, ph.id, lf.number;

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
FROM account_active_session_keys;
*/

-- ================================================================
-- USAGE EXAMPLES
-- ================================================================

/*
-- Example: Create a new account
INSERT INTO accounts (email, status_id) VALUES ('user@example.com', 1);

-- Example: Set password hash (use bcrypt in application)
INSERT INTO account_password_hashes (id, password_hash)
VALUES (last_insert_rowid(), '$2b$12$...');

-- Example: Verify account
UPDATE accounts SET status_id = 2 WHERE id = 1;
DELETE FROM account_verification_keys WHERE id = 1;

-- Example: Create active session
INSERT INTO account_active_session_keys (account_id, session_id)
VALUES (1, 'session_' || hex(randomblob(16)));

-- Example: Check if email exists
SELECT COUNT(*) FROM accounts WHERE email = 'user@example.com';

-- Example: Get account with status
SELECT * FROM accounts_with_status WHERE email = 'user@example.com';

-- Example: View active sessions for account
SELECT * FROM active_sessions_with_accounts 
WHERE account_id = 1 AND session_status = 'Active';
*/