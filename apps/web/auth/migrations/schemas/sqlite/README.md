# SQLite Schema - Authentication Database

Rodauth authentication schema adapted for SQLite with triggers and views.

## SQLite vs PostgreSQL Differences

- **No Stored Functions**: Function logic implemented at application level in Ruby
- **No Row Level Security (RLS)**: Access control enforced in application code
- **Different Date Functions**: Uses `datetime()`, `date()`, `julianday()` instead of `INTERVAL`
- **More Cleanup Triggers**: Inline triggers replace callable functions (6 total vs 3 in PostgreSQL)


## Setup

See apps/web/auth/migrations/README.md for setup instructions.


## Usage Examples

### Password Management

```sql
-- Track password changes
INSERT INTO account_password_change_times (id, changed_at)
VALUES (1, CURRENT_TIMESTAMP);

-- Add previous password for history tracking
INSERT INTO account_previous_password_hashes (account_id, password_hash)
VALUES (1, '$2b$12$old_hash...');

-- Check for recent password reuse
SELECT COUNT(*) FROM account_previous_password_hashes
WHERE account_id = 1 AND password_hash = '$2b$12$...';

-- Get password change history
SELECT changed_at FROM account_password_change_times
WHERE id = 1 ORDER BY changed_at DESC;
```

### Account Queries

```sql
-- Get account with status
SELECT * FROM accounts_with_status WHERE email = 'user@example.com';

-- Find accounts with enhanced security
SELECT * FROM account_security_overview_enhanced
WHERE has_sms = 1 OR has_webauthn = 1;

-- Get account security summary
SELECT
    CASE WHEN EXISTS(SELECT 1 FROM account_password_hashes WHERE id = 1) THEN 1 ELSE 0 END as has_password,
    CASE WHEN EXISTS(SELECT 1 FROM account_otp_keys WHERE id = 1) THEN 1 ELSE 0 END as has_otp,
    CASE WHEN EXISTS(SELECT 1 FROM account_sms_codes WHERE id = 1) THEN 1 ELSE 0 END as has_sms,
    CASE WHEN EXISTS(SELECT 1 FROM account_webauthn_keys WHERE account_id = 1) THEN 1 ELSE 0 END as has_webauthn,
    (SELECT COUNT(*) FROM account_active_session_keys WHERE account_id = 1) as active_sessions,
    (SELECT last_login_at FROM account_activity_times WHERE id = 1) as last_login,
    COALESCE((SELECT number FROM account_login_failures WHERE id = 1), 0) as failed_attempts;
```

### Session Management

```sql
-- View active sessions
SELECT * FROM active_sessions_with_accounts
WHERE account_id = 1 AND session_status = 'Active';

-- Update session activity
UPDATE account_active_session_keys
SET last_use = CURRENT_TIMESTAMP
WHERE account_id = 1 AND session_id = 'session_abc123';
```

### Audit & Monitoring

```sql
-- Get recent auth events
SELECT * FROM recent_auth_events WHERE account_id = 1 LIMIT 10;

-- Clean up old audit logs (via scheduled job)
DELETE FROM account_authentication_audit_logs
WHERE at < datetime('now', '-90 days');
```

### Maintenance

```sql
-- Cleanup expired email auth keys
DELETE FROM account_email_auth_keys WHERE deadline < datetime('now');

-- Cleanup expired JWT refresh tokens
DELETE FROM account_jwt_refresh_keys WHERE deadline < datetime('now');
```
