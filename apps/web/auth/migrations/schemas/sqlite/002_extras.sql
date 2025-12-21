-- ================================================================
-- Rodauth SQLite Extended Features (002)
-- Loaded by 002_extras.rb migration
--
-- Tables are created in 001_initial.rb and 002_extras.rb
-- This file provides SQLite-specific enhancements:
-- - Performance indexes
-- - Monitoring views
-- - Automatic triggers
-- ================================================================

-- ================================================================
-- PERFORMANCE INDEXES
-- ================================================================

CREATE INDEX account_previous_password_hashes_account_id_idx ON account_previous_password_hashes(account_id);
CREATE INDEX account_jwt_refresh_keys_account_id_idx ON account_jwt_refresh_keys(account_id);
CREATE INDEX account_jwt_refresh_keys_deadline_idx ON account_jwt_refresh_keys(deadline);
CREATE INDEX account_email_auth_keys_deadline_idx ON account_email_auth_keys(deadline);
CREATE INDEX account_activity_times_last_activity_idx ON account_activity_times(last_activity_at);
CREATE INDEX account_activity_times_last_login_idx ON account_activity_times(last_login_at);

-- ================================================================
-- ADDITIONAL VIEWS
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
WHERE date(l.at) >= date('now', '-30 days')
ORDER BY l.at DESC;

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
-- ADDITIONAL TRIGGERS
-- ================================================================

-- Trigger to automatically update activity time on successful logins
CREATE TRIGGER update_login_activity
AFTER INSERT ON account_authentication_audit_logs
WHEN NEW.message LIKE '%login%successful%'
BEGIN
    INSERT OR REPLACE INTO account_activity_times (id, last_login_at, last_activity_at)
    VALUES (NEW.account_id, NEW.at, NEW.at);
END;

-- Enhanced trigger to clean up expired JWT tokens
CREATE TRIGGER cleanup_expired_jwt_refresh_tokens
AFTER INSERT ON account_jwt_refresh_keys
BEGIN
    DELETE FROM account_jwt_refresh_keys WHERE deadline < datetime('now');
    DELETE FROM account_email_auth_keys WHERE deadline < datetime('now');
END;

-- ================================================================
-- MAINTENANCE EXAMPLES (For new features only)
-- ================================================================

/*
-- Clean up expired JWT refresh tokens
DELETE FROM account_jwt_refresh_keys WHERE deadline < datetime('now');

-- Clean up expired email auth tokens
DELETE FROM account_email_auth_keys WHERE deadline < datetime('now');

-- Find accounts with enhanced security features
SELECT * FROM account_security_overview_enhanced
WHERE has_sms = 1 OR has_webauthn = 1;

-- Get password change history for account
SELECT changed_at FROM account_password_change_times
WHERE account_id = ? ORDER BY changed_at DESC;

-- Check for recent password reuse
SELECT COUNT(*) FROM account_previous_password_hashes
WHERE account_id = ? AND password_hash = ?;
*/
