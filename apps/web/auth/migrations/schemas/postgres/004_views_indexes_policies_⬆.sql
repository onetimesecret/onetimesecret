-- ================================================================
-- Rodauth PostgreSQL Views, Indexes, Policies (004)
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
    CASE WHEN ph.id IS NOT NULL THEN TRUE ELSE FALSE END as has_password,
    CASE WHEN otpk.id IS NOT NULL THEN TRUE ELSE FALSE END as has_otp
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
        WHEN ask.last_use + INTERVAL '30 days' > NOW() THEN 'Active'
        ELSE 'Expired'
    END as session_status,
    EXTRACT(EPOCH FROM (NOW() - ask.last_use))/3600 as hours_since_use
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
WHERE l.at >= NOW() - INTERVAL '30 days'
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
-- ROW LEVEL SECURITY (from 001_initial.sql)
-- ================================================================

-- Enable RLS on sensitive tables
ALTER TABLE account_password_hashes ENABLE ROW LEVEL SECURITY;
ALTER TABLE account_otp_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE account_recovery_codes ENABLE ROW LEVEL SECURITY;

-- Policies will be defined based on application user roles
-- Example: Only password functions can access password hashes
-- CREATE POLICY password_access ON account_password_hashes
--   FOR ALL TO password_user USING (true);

-- ================================================================
-- DOCUMENTATION (from 002_extras.sql)
-- ================================================================

COMMENT ON TABLE account_previous_password_hashes IS 'Previous password hashes for preventing reuse (created in 001_initial.rb)';

COMMENT ON VIEW recent_auth_events IS 'Authentication events from the last 30 days';
COMMENT ON VIEW account_security_overview_enhanced IS 'Enhanced security overview with MFA status and session counts';

COMMENT ON FUNCTION update_last_login_time() IS 'Automatically updates activity times on successful login';
COMMENT ON FUNCTION cleanup_expired_tokens_extended() IS 'Removes expired tokens for new token types';
COMMENT ON FUNCTION update_session_last_use(BIGINT, VARCHAR) IS 'Updates the last_use timestamp for an active session';
COMMENT ON FUNCTION cleanup_old_audit_logs() IS 'Removes audit logs older than 90 days';
COMMENT ON FUNCTION get_account_security_summary(BIGINT) IS 'Returns security status summary for an account';

-- ================================================================
-- USAGE EXAMPLES (from 002_extras.sql)
-- ================================================================

/*
-- Example: Track password changes
INSERT INTO account_password_change_times (account_id, changed_at)
VALUES (1, NOW());

-- Example: Add previous password for history tracking
INSERT INTO account_previous_password_hashes (account_id, password_hash)
VALUES (1, '$2b$12$old_hash...');

-- Example: Get recent auth events
SELECT * FROM recent_auth_events WHERE account_id = 1 LIMIT 10;

-- Example: Get account security summary
SELECT * FROM get_account_security_summary(1);

-- Example: Find accounts with enhanced security features
SELECT * FROM account_security_overview_enhanced
WHERE has_sms = 1 OR has_webauthn = 1;

-- Example: Get password change history for account
SELECT changed_at FROM account_password_change_times
WHERE account_id = 1 ORDER BY changed_at DESC;

-- Example: Check for recent password reuse
SELECT COUNT(*) FROM account_previous_password_hashes
WHERE account_id = 1 AND password_hash = '$2b$12$...';

-- Example: Update session activity
SELECT update_session_last_use(1, 'session_abc123');

-- Example: Clean up old audit logs
SELECT cleanup_old_audit_logs();

-- Example: Cleanup expired email auth keys
DELETE FROM account_email_auth_keys WHERE deadline < NOW();
*/
