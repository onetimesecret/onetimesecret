-- ================================================================
-- Rodauth SQLite Views (005)
-- Loaded by 005_views.rb migration
--
-- Convenience views for common account and security queries
-- SQLite-specific syntax adaptations from PostgreSQL equivalents
-- ================================================================

-- ================================================================
-- ACCOUNT VIEWS
-- ================================================================

-- Account summary with status (from 001_initial.sql)
-- Note: SQLite uses 1/0 instead of TRUE/FALSE
CREATE VIEW accounts_with_status AS
SELECT
    a.id,
    a.external_id,
    a.email,
    s.name as status_name,
    a.status_id,
    a.created_at,
    a.updated_at,
    CASE WHEN ph.id IS NOT NULL THEN 1 ELSE 0 END as has_password,
    CASE WHEN otpk.id IS NOT NULL THEN 1 ELSE 0 END as has_otp
FROM accounts a
JOIN account_statuses s ON a.status_id = s.id
LEFT JOIN account_password_hashes ph ON a.id = ph.id
LEFT JOIN account_otp_keys otpk ON a.id = otpk.id;

-- ================================================================
-- SESSION VIEWS
-- ================================================================

-- Active sessions with account info (from 001_initial.sql)
-- Note: SQLite uses datetime() functions instead of INTERVAL
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
-- AUDIT VIEWS
-- ================================================================

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
WHERE l.at >= datetime('now', '-30 days')
ORDER BY l.at DESC;

-- ================================================================
-- SECURITY VIEWS
-- ================================================================

-- Enhanced account security overview with additional MFA options
CREATE VIEW account_security_overview_enhanced AS
SELECT
    a.id,
    a.email,
    s.name as status_name,
    CASE WHEN ph.id IS NOT NULL THEN 1 ELSE 0 END as has_password,
    CASE WHEN otpk.id IS NOT NULL THEN 1 ELSE 0 END as has_otp,
    CASE WHEN sc.id IS NOT NULL THEN 1 ELSE 0 END as has_sms,
    CASE WHEN wk.account_id IS NOT NULL THEN 1 ELSE 0 END as has_webauthn,
    COALESCE(session_count.count, 0) as active_sessions,
    at.last_login_at,
    COALESCE(lf.number, 0) as failed_attempts
FROM accounts a
JOIN account_statuses s ON a.status_id = s.id
LEFT JOIN account_password_hashes ph ON a.id = ph.id
LEFT JOIN account_otp_keys otpk ON a.id = otpk.id
LEFT JOIN account_sms_codes sc ON a.id = sc.id
LEFT JOIN account_webauthn_keys wk ON a.id = wk.account_id
LEFT JOIN account_activity_times at ON a.id = at.id
LEFT JOIN account_login_failures lf ON a.id = lf.id
LEFT JOIN (
    SELECT account_id, COUNT(*) as count
    FROM account_active_session_keys
    GROUP BY account_id
) session_count ON a.id = session_count.account_id;

-- ================================================================
-- DOCUMENTATION
-- ================================================================
--
-- SQLite Limitation: No COMMENT ON Syntax
--
-- View descriptions (for reference):
-- - accounts_with_status: Account summary with status and basic security flags
-- - active_sessions_with_accounts: Active sessions with account details and expiration status
-- - recent_auth_events: Authentication events from the last 30 days
-- - account_security_overview_enhanced: Enhanced security overview with MFA status and session counts

-- ================================================================
-- USAGE EXAMPLES
-- ================================================================

/*
-- Example: Get account with status
SELECT * FROM accounts_with_status WHERE email = 'user@example.com';

-- Example: View active sessions for account
SELECT * FROM active_sessions_with_accounts
WHERE account_id = 1 AND session_status = 'Active';

-- Example: Get recent auth events for account
SELECT * FROM recent_auth_events WHERE account_id = 1 LIMIT 10;

-- Example: Find accounts with enhanced security features
SELECT * FROM account_security_overview_enhanced
WHERE has_sms = 1 OR has_webauthn = 1;
*/
