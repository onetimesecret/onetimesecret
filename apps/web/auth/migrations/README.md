# Auth Database Migrations

## Overview

This directory contains Sequel migrations for the Rodauth authentication system.

## Structure

```
migrations/
├── 001_initial.rb           # Base Rodauth schema
├── 002_extras.rb            # Extended features (passwordless, MFA, tracking)
└── schemas/
    ├── postgres/
    │   ├── 001_initial.sql
    │   ├── 001_initial_down.sql
    │   ├── 002_extras.sql
    │   └── 002_extras_down.sql
    └── sqlite/
        ├── 001_initial.sql
        ├── 001_initial_down.sql
        ├── 002_extras.sql
        └── 002_extras_down.sql
```

## Migration 001: Initial Schema

Base Rodauth tables including:
- Accounts and statuses
- Password management
- Email verification
- Password reset
- Brute force protection (lockout)
- Remember me
- Active sessions
- OTP (TOTP) for authenticator apps
- Recovery codes
- Audit logging

## Migration 002: Extended Features

Additional authentication features:
- **Email Auth (Magic Links)** - Passwordless email-based login
- **WebAuthn** - Biometric/hardware key authentication (Face ID, Touch ID, YubiKey)
- **Password History** - Prevent password reuse
- **Password Rotation** - Track password change times
- **JWT Refresh Tokens** - For API authentication
- **SMS 2FA** - SMS-based two-factor authentication
- **Activity Tracking** - Login and activity timestamps
- **Session Management** - Enhanced session tracking

## Running Migrations

### Using Sequel CLI

```bash
# PostgreSQL
sequel -m apps/web/auth/migrations postgres://user:pass@localhost/auth_db

# SQLite
sequel -m apps/web/auth/migrations sqlite://data/auth.db
```

### Using App CLI (if available)

```bash
# Run specific migration
bin/ots migrate apps/web/auth/migrations/002_extras.rb --run

# Rollback specific migration
bin/ots migrate apps/web/auth/migrations/002_extras.rb --down
```

### Direct SQL (Not Recommended)

```bash
# PostgreSQL
psql -d auth_db < apps/web/auth/migrations/schemas/postgres/002_extras.sql

# SQLite
sqlite3 data/auth.db < apps/web/auth/migrations/schemas/sqlite/002_extras.sql
```

## Enabling Features

Features are enabled via environment variables in `apps/web/auth/config.rb`:

```bash
# Base features (always enabled)
# - login, logout, create_account, verify_account, reset_password, change_password

# Security features (enabled by default)
ENABLE_SECURITY_FEATURES=true  # lockout, active_sessions

# MFA features
ENABLE_MFA=true  # otp, recovery_codes, remember

# Passwordless features (requires migration 002)
ENABLE_MAGIC_LINKS=true   # email_auth
ENABLE_WEBAUTHN=true      # webauthn
```

## Database Support

- **PostgreSQL** - Full feature support with triggers, functions, views
- **SQLite** - Full feature support with simpler triggers (no functions)

## Schema Differences by Database

### PostgreSQL Advantages
- Database functions for security (password validation)
- More sophisticated triggers
- Better indexing with GIN for JSONB
- INET type for IP addresses

### SQLite Considerations
- Uses INTEGER for timestamps (Unix epoch)
- Simpler trigger syntax
- TEXT type for IP addresses
- No database-level functions

## Monitoring

Both databases include views for monitoring:

### `account_auth_methods`
Shows which authentication methods each account has enabled:
```sql
SELECT * FROM account_auth_methods WHERE email = 'user@example.com';
-- has_password, has_otp, has_webauthn, webauthn_key_count, has_pending_magic_link
```

### `recent_auth_events` (002_extras)
Authentication events from last 30 days:
```sql
SELECT * FROM recent_auth_events WHERE account_id = 1 LIMIT 10;
```

### `account_security_overview_enhanced` (002_extras)
Comprehensive security status:
```sql
SELECT * FROM account_security_overview_enhanced WHERE has_webauthn = 1;
```

## Maintenance

### Cleanup Expired Tokens (PostgreSQL)
```sql
SELECT cleanup_expired_tokens();
SELECT cleanup_old_audit_logs();
```

### Cleanup Expired Tokens (SQLite)
```sql
DELETE FROM account_email_auth_keys WHERE deadline < datetime('now');
DELETE FROM account_jwt_refresh_keys WHERE deadline < datetime('now');
DELETE FROM account_password_reset_keys WHERE deadline < datetime('now');
```

### Check Account Security Status
```sql
-- PostgreSQL
SELECT * FROM get_account_security_summary(1);

-- SQLite/PostgreSQL
SELECT * FROM account_security_overview_enhanced WHERE id = 1;
```

## Rollback

```bash
# Rollback migration 002
sequel -m apps/web/auth/migrations -M 1 postgres://user:pass@localhost/db

# Or manually
psql -d auth_db < apps/web/auth/migrations/schemas/postgres/002_extras_down.sql
```

## See Also

- `docs/PASSWORDLESS_AUTH_IMPLEMENTATION.md` - Frontend implementation guide
- `apps/web/auth/config/features/` - Rodauth feature configurations
