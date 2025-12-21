-- ================================================================
-- Rodauth SQLite Views, Indexes, Policies (004)
-- Loaded by 004_views_indexes_policies.rb migration
-- ================================================================

-- ================================================================
-- PERFORMANCE INDEXES (from 002_extras.sql)
-- ================================================================

CREATE INDEX idx_jwt_refresh_keys_account_id ON account_jwt_refresh_keys(account_id);
CREATE INDEX idx_jwt_refresh_keys_deadline ON account_jwt_refresh_keys(deadline);
CREATE INDEX idx_activity_times_last_activity ON account_activity_times(last_activity_at);
CREATE INDEX idx_email_auth_keys_deadline ON account_email_auth_keys(deadline);
CREATE INDEX idx_activity_times_last_login ON account_activity_times(last_login_at);
CREATE INDEX idx_previous_password_hashes_account_id ON account_previous_password_hashes(account_id);

-- ================================================================
-- VIEWS (from 001_initial.sql and 002_extras.sql)
-- ================================================================

-- Account summary with status (from 001_initial.sql)
-- Note: last_login_at available via JOIN with account_activity_times if needed
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

-- Active sessions with account info (from 001_initial.sql)
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

-- View for recent authentication events (last 30 days) (from 002_extras.sql)
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

-- Enhanced account security overview with additional MFA options (from 002_extras.sql)
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
-- ROW LEVEL SECURITY
-- ================================================================
--
-- SQLite Limitation: No Row Level Security
--
-- SQLite does not support Row Level Security (RLS) policies.
-- Application-level access control must be implemented in Ruby code.
--
-- PostgreSQL equivalent that cannot be implemented:
-- - ALTER TABLE account_password_hashes ENABLE ROW LEVEL SECURITY;
-- - ALTER TABLE account_otp_keys ENABLE ROW LEVEL SECURITY;
-- - ALTER TABLE account_recovery_codes ENABLE ROW LEVEL SECURITY;
--
-- Security recommendations for SQLite:
-- 1. Use connection-level restrictions in application code
-- 2. Implement data access policies in Sequel models
-- 3. Use separate database connections with limited permissions where possible
-- 4. Validate all queries through ORM layer (avoid raw SQL)

-- ================================================================
-- DOCUMENTATION
-- ================================================================
--
-- SQLite Limitation: No COMMENT ON Syntax
--
-- SQLite does not support COMMENT ON TABLE/VIEW/FUNCTION statements.
-- Documentation is maintained in migration files and code comments.
--
-- Table/View Descriptions (for reference):
-- - account_previous_password_hashes: Previous password hashes for preventing reuse
-- - recent_auth_events: Authentication events from the last 30 days
-- - account_security_overview_enhanced: Enhanced security overview with MFA status and session counts
--
-- Note: Function comments are not applicable as SQLite has no stored functions

-- ================================================================
-- USAGE EXAMPLES (adapted from 002_extras.sql)
-- ================================================================

/*
-- Example: Track password changes
INSERT INTO account_password_change_times (id, changed_at)
VALUES (1, CURRENT_TIMESTAMP);

-- Example: Add previous password for history tracking
INSERT INTO account_previous_password_hashes (account_id, password_hash)
VALUES (1, '$2b$12$old_hash...');

-- Example: Get recent auth events
SELECT * FROM recent_auth_events WHERE account_id = 1 LIMIT 10;

-- Example: Find accounts with enhanced security features
SELECT * FROM account_security_overview_enhanced
WHERE has_sms = 1 OR has_webauthn = 1;

-- Example: Get password change history for account
SELECT changed_at FROM account_password_change_times
WHERE id = 1 ORDER BY changed_at DESC;

-- Example: Check for recent password reuse
SELECT COUNT(*) FROM account_previous_password_hashes
WHERE account_id = 1 AND password_hash = '$2b$12$...';

-- Example: Update session activity (application-level)
UPDATE account_active_session_keys
SET last_use = CURRENT_TIMESTAMP
WHERE account_id = 1 AND session_id = 'session_abc123';

-- Example: Clean up old audit logs (application-level, e.g., via scheduled job)
DELETE FROM account_authentication_audit_logs
WHERE at < datetime('now', '-90 days');

-- Example: Cleanup expired email auth keys
DELETE FROM account_email_auth_keys WHERE deadline < datetime('now');

-- Example: Get security summary (application-level query)
SELECT
    CASE WHEN EXISTS(SELECT 1 FROM account_password_hashes WHERE id = 1) THEN 1 ELSE 0 END as has_password,
    CASE WHEN EXISTS(SELECT 1 FROM account_otp_keys WHERE id = 1) THEN 1 ELSE 0 END as has_otp,
    CASE WHEN EXISTS(SELECT 1 FROM account_sms_codes WHERE id = 1) THEN 1 ELSE 0 END as has_sms,
    CASE WHEN EXISTS(SELECT 1 FROM account_webauthn_keys WHERE account_id = 1) THEN 1 ELSE 0 END as has_webauthn,
    (SELECT COUNT(*) FROM account_active_session_keys WHERE account_id = 1) as active_sessions,
    (SELECT last_login_at FROM account_activity_times WHERE id = 1) as last_login,
    COALESCE((SELECT number FROM account_login_failures WHERE id = 1), 0) as failed_attempts;
*/
