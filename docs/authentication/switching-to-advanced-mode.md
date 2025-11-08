# Switching from Basic to Advanced Auth Mode

**Last Updated:** 2025-10-23
**Applies To:** OneTimeSecret v2.0+

## Overview

OneTimeSecret supports two authentication modes:

- **Basic Mode**: Lightweight authentication managed by Core app using Redis sessions
- **Advanced Mode**: Full-featured authentication using Rodauth with SQL database

Advanced mode enables:
- Multi-factor authentication (TOTP, WebAuthn)
- Passwordless login (magic links, security keys)
- Account verification workflows
- Password reset functionality
- Enhanced security features (lockout, active sessions)
- Audit logging

## Prerequisites

Before switching modes:

1. **Database Setup**: Configure a SQL database (SQLite or PostgreSQL)
2. **Backup**: Back up your Redis data
3. **Downtime Window**: Plan for brief service interruption during migration
4. **Testing**: Test advanced mode in non-production environment first

## Migration Steps

### 1. Configure Database Connection

Set the database URL for the Auth application:

```yaml
# etc/config.yaml
authentication:
  mode: basic  # Keep basic during setup
  database_url: sqlite://data/auth.db
```

Or via environment variable:

```bash
export DATABASE_URL='sqlite://data/auth.db'
# Or for PostgreSQL:
export DATABASE_URL='postgresql://user:pass@localhost/onetime_auth'
```

### 2. Run Database Migrations

Initialize the Rodauth database schema:

```bash
# For SQLite
sqlite3 data/auth.db < apps/web/auth/migrations/schemas/sqlite/001_initial.sql

# For PostgreSQL
psql -U user -d onetime_auth -f apps/web/auth/migrations/schemas/postgres/001_initial.sql
```

Or use Sequel migrations:

```bash
AUTHENTICATION_MODE=advanced bundle exec ruby -e "
  require_relative 'apps/web/auth/migrator'
  Auth::Migrator.run!
"
```

### 3. Sync Existing Customer Accounts

Migrate customer records from Redis to the SQL database:

```bash
# Preview what will be migrated (dry-run mode)
AUTHENTICATION_MODE=advanced bin/ots sync-auth-accounts

# Execute the synchronization
AUTHENTICATION_MODE=advanced bin/ots sync-auth-accounts --run

# Verbose output for detailed progress
AUTHENTICATION_MODE=advanced bin/ots sync-auth-accounts --run -v
```

**What the sync command does:**
- Creates account records in SQL for all Redis customers
- Links accounts via `external_id` field (maps to customer `extid`)
- Sets verification status based on customer state
- Skips anonymous customers automatically
- Idempotent: safe to run multiple times

**Expected output:**
```
Auth Account Synchronization Tool
============================================================

Discovered 1,234 customers in Redis

DRY RUN MODE - No changes will be made
To execute synchronization, run with --run flag

Progress: 1234/1234 customers processed

============================================================
Synchronization Preview
============================================================

Statistics:
  Total customers:     1234
  Skipped (anonymous): 2
  Skipped (existing):  0
  Linked:              0
  Created:             1232
```

### 4. Verify Account Migration

Check that accounts were created correctly:

```bash
# For SQLite
sqlite3 data/auth.db "SELECT COUNT(*) FROM accounts;"
sqlite3 data/auth.db "SELECT id, email, external_id, status_id FROM accounts LIMIT 5;"

# For PostgreSQL
psql -U user -d onetime_auth -c "SELECT COUNT(*) FROM accounts;"
psql -U user -d onetime_auth -c "SELECT id, email, external_id, status_id FROM accounts LIMIT 5;"
```

Verify external_id linking:

```bash
# Check that accounts have external_id populated
sqlite3 data/auth.db "SELECT COUNT(*) FROM accounts WHERE external_id IS NULL;"
# Should return 0
```

### 5. Switch to Advanced Mode

Update your configuration:

```yaml
# etc/config.yaml
authentication:
  mode: advanced
  database_url: sqlite://data/auth.db
  session:
    expire_after: 86400  # 24 hours
```

Or via environment:

```bash
export AUTHENTICATION_MODE=advanced
```

### 6. Restart Application

```bash
# Stop current process
pkill -f puma

# Start with advanced mode
AUTHENTICATION_MODE=advanced bundle exec puma -C config/puma.rb
```

### 7. Verify Authentication Works

Test the authentication flow:

1. **Login Test**: Log in with existing customer credentials
2. **Session Check**: Verify session persistence across requests
3. **Logout Test**: Confirm logout functionality
4. **Registration Test**: Create new account (if enabled)

Check Auth routes are mounted:

```bash
curl -I http://localhost:7143/auth/login
# Should return 200 or redirect, not 404
```

### 8. Enable Advanced Features (Optional)

After successful migration, configure advanced features:

**MFA (TOTP):**
```ruby
# apps/web/auth/config/features.rb
enable :otp, :recovery_codes
```

**WebAuthn (Security Keys):**
```ruby
enable :webauthn, :webauthn_login
```

**Magic Links:**
```ruby
enable :email_auth
```

Restart the application after enabling new features.

## Rollback Procedure

If issues occur, revert to basic mode:

1. Stop the application
2. Change config: `authentication.mode: basic`
3. Restart application
4. Customer data remains in Redis (unchanged)

**Note:** Accounts created during advanced mode will remain in SQL database but won't be used in basic mode.

## Troubleshooting

### Sync Command Shows "Advanced auth mode is not enabled"

**Cause:** `AUTHENTICATION_MODE` not set or set to `basic`
**Solution:** Run with `AUTHENTICATION_MODE=advanced` prefix

### Database Connection Errors

**Cause:** `DATABASE_URL` not configured or database doesn't exist
**Solution:**
- Verify database URL in config or environment
- Create database if it doesn't exist
- Check database permissions

### Customers Can't Log In After Switch

**Cause:** Accounts not synced or external_id mismatch
**Solution:**
```bash
# Re-run sync to fix links
AUTHENTICATION_MODE=advanced bin/ots sync-auth-accounts --run

# Check specific account
sqlite3 data/auth.db "SELECT * FROM accounts WHERE email='user@example.com';"
```

### Session Not Persisting

**Cause:** Session store mismatch between modes
**Solution:** Clear Redis sessions and have users log in again:
```bash
redis-cli KEYS "session:*" | xargs redis-cli DEL
```

## Post-Migration Tasks

1. **Monitor Logs**: Watch for authentication errors in first 24 hours
2. **Update Documentation**: Document any custom auth configuration
3. **Backup Database**: Add SQL database to backup routine
4. **Performance**: Monitor database query performance
5. **Security Audit**: Review enabled Rodauth features and configuration

## Maintenance

### Running Sync Again (Idempotent)

Safe to run sync command multiple times:

```bash
# Adds any new customers created since last sync
AUTHENTICATION_MODE=advanced bin/ots sync-auth-accounts --run
```

### Checking Sync Status

Compare Redis and SQL counts:

```bash
# Redis customer count
redis-cli ZCARD customer:instances

# SQL account count
sqlite3 data/auth.db "SELECT COUNT(*) FROM accounts WHERE status_id IN (1, 2);"
```

### Handling New Features

When enabling new Rodauth features:

1. Check if additional migrations needed
2. Update feature configuration in `apps/web/auth/config/features.rb`
3. Test in development first
4. Restart application in production

## See Also

- [MFA Recovery Workflow](mfa-recovery.md)
- [Magic Link MFA Flow](magic-link-mfa-flow.md)
- Rodauth Documentation: http://rodauth.jeremyevans.net
- Auth Configuration: `apps/web/auth/config/`
