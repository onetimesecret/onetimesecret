-- ================================================================
-- Rodauth SQLite3 Database Schema
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
    created_at TEXT NOT NULL,
    last_use TEXT NOT NULL,
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

-- ================================================================
-- INITIAL DATA
-- ================================================================

-- Common account statuses
INSERT INTO account_statuses (id, name) VALUES
    (1, 'Unverified'),
    (2, 'Verified'),
    (3, 'Closed');

-- ================================================================
-- UTILITY VIEWS (SQLite3 specific helpers)
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

-- ================================================================
-- SQLITE3 SPECIFIC FUNCTIONS AND TRIGGERS
-- ================================================================

-- Trigger to automatically update activity time on successful logins
CREATE TRIGGER update_last_login_time
AFTER INSERT ON account_authentication_audit_logs
WHEN NEW.message LIKE '%login%successful%'
BEGIN
    INSERT OR REPLACE INTO account_activity_times (account_id, last_login_at, last_activity_at)
    VALUES (NEW.account_id, NEW.at, NEW.at);
END;

-- Trigger to clean up expired tokens (runs on JWT refresh key insert)
CREATE TRIGGER cleanup_expired_jwt_tokens
AFTER INSERT ON account_jwt_refresh_keys
BEGIN
    DELETE FROM account_jwt_refresh_keys
    WHERE deadline < datetime('now');
END;

-- ================================================================
-- SQLITE3 USAGE EXAMPLES
-- ================================================================

/*
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

-- Example: Clean up expired sessions
DELETE FROM account_remember_keys WHERE deadline < datetime('now');
DELETE FROM account_password_reset_keys WHERE deadline < datetime('now');
DELETE FROM account_email_auth_keys WHERE deadline < datetime('now');
*/
