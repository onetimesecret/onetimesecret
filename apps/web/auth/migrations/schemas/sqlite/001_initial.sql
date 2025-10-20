-- ================================================================
-- Rodauth SQLite3 Essential Schema with MFA
-- Authentication and Account Management System
-- Features: base, json, login, logout, create_account, close_account,
-- login_password_requirements_base, change_password, reset_password,
-- remember, verify_account, lockout, active_sessions, otp, recovery_codes
-- ================================================================

-- Enable foreign key constraints (required for SQLite)
PRAGMA foreign_keys = ON;

-- ================================================================
-- CORE TABLES (Required for all Rodauth configurations)
-- ================================================================

-- Account status lookup table
CREATE TABLE account_statuses (
    id INTEGER PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE
);

-- Insert default status values
INSERT INTO account_statuses (id, name) VALUES
    (1, 'Unverified'),
    (2, 'Verified'),
    (3, 'Closed');

-- Main accounts table
CREATE TABLE accounts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    external_id VARCHAR(64) UNIQUE,
    email VARCHAR(255) NOT NULL COLLATE NOCASE,
    status_id INTEGER NOT NULL DEFAULT 1 REFERENCES account_statuses(id),
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login_ip VARCHAR(45),
    last_login_at DATETIME
);

-- Unique email constraint for active accounts only
CREATE UNIQUE INDEX accounts_email_unique ON accounts(email)
WHERE status_id IN (1, 2);

-- Performance indexes
CREATE INDEX accounts_status_id_idx ON accounts(status_id);
CREATE INDEX accounts_created_at_idx ON accounts(created_at);
CREATE INDEX accounts_last_login_at_idx ON accounts(last_login_at);

-- ================================================================
-- PASSWORD MANAGEMENT (Separate table for security)
-- ================================================================

-- Password hashes (stored separately for security)
CREATE TABLE account_password_hashes (
    id INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    password_hash VARCHAR(255) NOT NULL
);

-- ================================================================
-- ACCOUNT VERIFICATION
-- ================================================================

-- Email verification keys
CREATE TABLE account_verification_keys (
    id INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    key VARCHAR(255) NOT NULL UNIQUE,
    requested_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    email_last_sent DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ================================================================
-- PASSWORD RESET FUNCTIONALITY
-- ================================================================

-- Password reset keys
CREATE TABLE account_password_reset_keys (
    id INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    key VARCHAR(255) NOT NULL UNIQUE,
    deadline DATETIME NOT NULL,
    email_last_sent DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ================================================================
-- BRUTE FORCE PROTECTION
-- ================================================================

-- Login failure tracking
CREATE TABLE account_login_failures (
    id INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    number INTEGER NOT NULL DEFAULT 1
);

-- Account lockout management
CREATE TABLE account_lockouts (
    id INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    key VARCHAR(255) NOT NULL UNIQUE,
    deadline DATETIME NOT NULL,
    email_last_sent DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ================================================================
-- REMEMBER ME FUNCTIONALITY
-- ================================================================

-- Remember me tokens
CREATE TABLE account_remember_keys (
    id INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    key VARCHAR(255) NOT NULL UNIQUE,
    deadline DATETIME NOT NULL
);

-- ================================================================
-- SESSION MANAGEMENT
-- ================================================================

-- Active session tracking
CREATE TABLE account_active_session_keys (
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    session_id VARCHAR(255) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_use DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (account_id, session_id)
);

-- Session performance index
CREATE INDEX account_active_session_keys_last_use_idx ON account_active_session_keys(last_use);

-- ================================================================
-- MULTI-FACTOR AUTHENTICATION (OTP)
-- ================================================================

-- OTP (TOTP) secret keys for Google Authenticator, etc.
CREATE TABLE account_otp_keys (
    id INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    key VARCHAR(255) NOT NULL,
    num_failures INTEGER NOT NULL DEFAULT 0,
    last_use DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ================================================================
-- RECOVERY CODES (MFA Backup)
-- ================================================================

-- Recovery codes for MFA bypass
CREATE TABLE account_recovery_codes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    code VARCHAR(255) NOT NULL UNIQUE,
    used_at DATETIME
);

-- Index for efficient lookup
CREATE INDEX account_recovery_codes_account_id_idx ON account_recovery_codes(account_id);
CREATE INDEX account_recovery_codes_code_idx ON account_recovery_codes(code);

-- ================================================================
-- AUDIT AND SECURITY LOGGING
-- ================================================================

-- Authentication audit log
CREATE TABLE account_authentication_audit_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    message TEXT NOT NULL,
    metadata TEXT -- JSON data
);

-- Audit log indexes
CREATE INDEX account_authentication_audit_logs_account_at_idx ON account_authentication_audit_logs(account_id, at);
CREATE INDEX account_authentication_audit_logs_at_idx ON account_authentication_audit_logs(at);

-- ================================================================
-- TRIGGERS FOR DATA MAINTENANCE
-- ================================================================

-- Update account updated_at timestamp
CREATE TRIGGER update_accounts_updated_at
AFTER UPDATE ON accounts
BEGIN
    UPDATE accounts SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

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

-- ================================================================
-- VIEWS FOR COMMON QUERIES
-- ================================================================

-- Account summary with status
CREATE VIEW accounts_with_status AS
SELECT
    a.id,
    a.external_id,
    a.email,
    s.name as status_name,
    a.status_id,
    a.created_at,
    a.updated_at,
    a.last_login_at,
    a.last_login_ip,
    CASE WHEN ph.id IS NOT NULL THEN 1 ELSE 0 END as has_password,
    CASE WHEN otpk.id IS NOT NULL THEN 1 ELSE 0 END as has_otp
FROM accounts a
JOIN account_statuses s ON a.status_id = s.id
LEFT JOIN account_password_hashes ph ON a.id = ph.id
LEFT JOIN account_otp_keys otpk ON a.id = otpk.id;

-- Active sessions with account info
CREATE VIEW active_sessions_with_accounts AS
SELECT
    ask.account_id,
    ask.session_id,
    ask.created_at,
    ask.last_use,
    a.external_id,
    a.email,
    CASE
        WHEN datetime(ask.last_use, '+30 days') > datetime('now') THEN 'Active'
        ELSE 'Expired'
    END as session_status,
    ROUND((julianday('now') - julianday(ask.last_use)) * 24, 2) as hours_since_use
FROM account_active_session_keys ask
JOIN accounts a ON ask.account_id = a.id;

-- ================================================================
-- MAINTENANCE QUERIES (Execute manually as needed)
-- ================================================================

/*
-- Clean up old audit logs (keep last 90 days)
DELETE FROM account_authentication_audit_logs
WHERE at < date('now', '-90 days');

-- Clean up old inactive sessions (30+ days)
DELETE FROM account_active_session_keys
WHERE date(last_use) < date('now', '-30 days');

-- Update session last_use timestamp (call from application)
UPDATE account_active_session_keys
SET last_use = CURRENT_TIMESTAMP
WHERE account_id = ? AND session_id = ?;

-- Check account security status
SELECT
    a.id,
    a.email,
    s.name as status,
    CASE WHEN ph.id IS NOT NULL THEN 'Yes' ELSE 'No' END as has_password,
    CASE WHEN otpk.id IS NOT NULL THEN 'Yes' ELSE 'No' END as has_otp,
    COALESCE(lf.number, 0) as failed_attempts,
    COUNT(ask.session_id) as active_sessions,
    COUNT(rc.id) as unused_recovery_codes
FROM accounts a
JOIN account_statuses s ON a.status_id = s.id
LEFT JOIN account_password_hashes ph ON a.id = ph.id
LEFT JOIN account_otp_keys otpk ON a.id = otpk.id
LEFT JOIN account_login_failures lf ON a.id = lf.id
LEFT JOIN account_active_session_keys ask ON a.id = ask.account_id
LEFT JOIN account_recovery_codes rc ON a.id = rc.account_id AND rc.used_at IS NULL
WHERE a.status_id IN (1, 2)
GROUP BY a.id, a.email, s.name, ph.id, otpk.id, lf.number;

-- Generate recovery codes for account (example)
-- INSERT INTO account_recovery_codes (account_id, code) VALUES
-- (?, 'ABCD-1234'), (?, 'EFGH-5678'), (?, 'IJKL-9012');

-- Example: Check if email exists
-- SELECT COUNT(*) FROM accounts WHERE email = 'user@example.com';

-- Example: Get account with status
-- SELECT * FROM accounts_with_status WHERE email = 'user@example.com';

-- Example: View active sessions for account
-- SELECT * FROM active_sessions_with_accounts
-- WHERE account_id = 1 AND session_status = 'Active';
*/
