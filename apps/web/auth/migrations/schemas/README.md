# Database-Specific SQL Schemas

This directory contains database-specific SQL that is loaded by the corresponding Sequel migrations.

## Purpose

While Sequel migrations handle cross-database table creation, certain features are best implemented using database-specific SQL:

- **Views** - Complex JOINs and aggregations for monitoring
- **Functions** - Stored procedures for convenience and performance (PostgreSQL only)
- **Triggers** - Automatic behavior on insert/update/delete
- **Indexes** - Performance optimization
- **Comments** - Self-documenting schema metadata (PostgreSQL only)

## How It Works

The Sequel migrations (`001_initial.rb`, `002_extras.rb`) detect the database type and conditionally load the appropriate SQL file:

```ruby
case database_type
when :postgres
  sql_file = File.join(MIGRATION_ROOT, 'schemas/postgres/002_extras.sql')
  run File.read(sql_file) if File.exist?(sql_file)
when :sqlite
  sql_file = File.join(MIGRATION_ROOT, 'schemas/sqlite/002_extras.sql')
  run File.read(sql_file) if File.exist?(sql_file)
end
```

## Files

### PostgreSQL (`postgres/`)

- `001_initial.sql` - Reference copy of initial schema (for manual review)
- `001_initial_down.sql` - Reference rollback (for manual review)
- `002_extras.sql` - Extended features (views, functions, triggers, indexes)
- `002_extras_down.sql` - Rollback extended features

### SQLite (`sqlite/`)

- `001_initial.sql` - Reference copy of initial schema (for manual review)
- `001_initial_down.sql` - Reference rollback (for manual review)
- `002_extras.sql` - Extended features (views, triggers, indexes)
- `002_extras_down.sql` - Rollback extended features

## PostgreSQL Features

### Views

**`recent_auth_events`** - Authentication events from last 30 days:
```sql
SELECT * FROM recent_auth_events WHERE account_id = 1 LIMIT 10;
```

**`account_security_overview_enhanced`** - Security status aggregation:
```sql
SELECT * FROM account_security_overview_enhanced WHERE has_webauthn = 1;
```

### Functions

**`get_account_security_summary(account_id)`** - Returns security status as a record:
```sql
SELECT * FROM get_account_security_summary(1);
-- Returns: has_password, has_otp, has_sms, has_webauthn, active_sessions, last_login, failed_attempts
```

**`cleanup_old_audit_logs()`** - Removes audit logs older than 90 days:
```sql
SELECT cleanup_old_audit_logs(); -- Returns count of deleted rows
```

**`update_session_last_use(account_id, session_id)`** - Updates session timestamp:
```sql
SELECT update_session_last_use(1, 'session_abc123');
```

### Triggers

**`trigger_update_last_login_time`** - Automatic activity tracking on successful login
**`trigger_cleanup_expired_tokens_extended`** - Automatic token cleanup on JWT insert

## SQLite Features

### Views

Same as PostgreSQL but with SQLite-specific date functions.

### Triggers

**`update_login_activity`** - Automatic activity tracking on successful login
**`cleanup_expired_jwt_refresh_tokens`** - Automatic token cleanup on JWT insert

## Maintenance

### PostgreSQL

```sql
-- Get security summary
SELECT * FROM get_account_security_summary(123);

-- Clean up old audit logs
SELECT cleanup_old_audit_logs();

-- Manual token cleanup
DELETE FROM account_jwt_refresh_keys WHERE deadline < NOW();
DELETE FROM account_email_auth_keys WHERE deadline < NOW();
```

### SQLite

```sql
-- Manual token cleanup
DELETE FROM account_jwt_refresh_keys WHERE deadline < datetime('now');
DELETE FROM account_email_auth_keys WHERE deadline < datetime('now');

-- Clean up old audit logs (manual)
DELETE FROM account_authentication_audit_logs WHERE date(at) < date('now', '-90 days');
```

## Why Not Pure Sequel?

While Sequel has DSLs for views and triggers, raw SQL is:
- **Clearer** for complex queries
- **More maintainable** (easier to test standalone)
- **More powerful** (access to all database features)
- **Better documented** (native SQL syntax)

The hybrid approach uses Sequel for cross-database portability and raw SQL for database-specific optimizations.
