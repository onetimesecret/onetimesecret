# PostgreSQL Schema - Authentication Database

Rodauth authentication schema with functions, triggers, views, and Row Level Security policies.

## Setup

Run before first boot with `AUTHENTICATION_MODE=full`:

```bash
psql -U postgres -h localhost -f apps/web/auth/migrations/schemas/postgres/setup_auth_db.sql
```

## Usage Examples

### Password Management

```sql
-- Track password changes
INSERT INTO account_password_change_times (account_id, changed_at)
VALUES (1, NOW());

-- Add previous password for history tracking
INSERT INTO account_previous_password_hashes (account_id, password_hash)
VALUES (1, '$2b$12$old_hash...');

-- Check for recent password reuse
SELECT COUNT(*) FROM account_previous_password_hashes
WHERE account_id = 1 AND password_hash = '$2b$12$...';

-- Get password change history
SELECT changed_at FROM account_password_change_times
WHERE account_id = 1 ORDER BY changed_at DESC;
```

### Account Queries

```sql
-- Get account with status
SELECT * FROM accounts_with_status WHERE email = 'user@example.com';

-- Find accounts with enhanced security
SELECT * FROM account_security_overview_enhanced
WHERE has_sms = 1 OR has_webauthn = 1;

-- Get account security summary
SELECT * FROM get_account_security_summary(1);
```

### Session Management

```sql
-- View active sessions
SELECT * FROM active_sessions_with_accounts
WHERE account_id = 1 AND session_status = 'Active';

-- Update session activity
SELECT update_session_last_use(1, 'session_abc123');
```

### Audit & Monitoring

```sql
-- Get recent auth events
SELECT * FROM recent_auth_events WHERE account_id = 1 LIMIT 10;

-- Clean up old audit logs
SELECT cleanup_old_audit_logs();
```

### Maintenance

```sql
-- Cleanup expired email auth keys
DELETE FROM account_email_auth_keys WHERE deadline < NOW();

-- Cleanup expired JWT refresh tokens
DELETE FROM account_jwt_refresh_keys WHERE deadline < NOW();
```
