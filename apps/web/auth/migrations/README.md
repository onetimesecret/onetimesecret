# Auth Database Migrations

## Overview

Sequel migrations for the Rodauth authentication system. Migrations run automatically on application boot in full authentication mode.

## Structure

```
migrations/
├── 001_initial.rb           # Base Rodauth schema (Sequel migration)
├── 002_extras.rb            # Extended features (Sequel migration)
└── schemas/                 # Database-specific SQL (loaded by migrations)
    ├── postgres/
    │   ├── 001_initial.sql
    │   ├── 001_initial_down.sql
    │   ├── 002_extras.sql         # Views, functions, triggers, indexes
    │   └── 002_extras_down.sql
    └── sqlite/
        ├── 001_initial.sql
        ├── 001_initial_down.sql
        ├── 002_extras.sql         # Views, triggers, indexes
        └── 002_extras_down.sql
```

## Migration 001: Initial Schema

Creates core Rodauth tables:
- `accounts` - User accounts with email (citext on PostgreSQL)
- `account_statuses` - Account states (unverified, verified, closed)
- `account_password_hashes` - Bcrypt password storage
- `account_verification_keys` - Email verification tokens
- `account_password_reset_keys` - Password reset tokens
- `account_login_failures` / `account_lockouts` - Brute force protection
- `account_remember_keys` - Remember me functionality
- `account_active_session_keys` - Session tracking
- `account_otp_keys` - TOTP authenticator app support
- `account_recovery_codes` - Backup codes for MFA
- `account_authentication_audit_logs` - Login/auth event logging
- `account_webauthn_user_ids` / `account_webauthn_keys` - Hardware key support
- `account_email_auth_keys` - Magic link authentication
- `account_sms_codes` - SMS 2FA codes
- `account_jwt_refresh_keys` - JWT refresh tokens

## Migration 002: Extended Features

Adds password history and database-specific enhancements:

**Cross-database:**
- `account_previous_password_hashes` - Password reuse prevention

**PostgreSQL-specific (via schemas/postgres/002_extras.sql):**
- Performance indexes on foreign keys and deadlines
- `recent_auth_events` view - Last 30 days of authentication events
- `account_security_overview_enhanced` view - Comprehensive security status
- `update_last_login_time()` function + trigger - Automatic activity tracking
- `cleanup_expired_tokens_extended()` function + trigger - Token cleanup
- `update_session_last_use()` function - Session tracking helper
- `cleanup_old_audit_logs()` function - Audit log maintenance
- `get_account_security_summary()` function - Security status query

**SQLite-specific (via schemas/sqlite/002_extras.sql):**
- Performance indexes on foreign keys and deadlines
- `recent_auth_events` view - Last 30 days of authentication events
- `account_security_overview_enhanced` view - Comprehensive security status
- `update_login_activity` trigger - Automatic activity tracking
- `cleanup_expired_jwt_refresh_tokens` trigger - Token cleanup

## Database Trigger Testing

Migration 002 includes database triggers (SQLite) and functions (PostgreSQL) that execute automatically. These are tested to ensure trigger SQL matches the actual schema.

### Schema Validation

**Validator:** `spec/support/auth_trigger_validator.rb`

Parses trigger SQL from migration files and verifies:
- Column references in triggers match actual table schema
- `NEW.column_name` patterns exist in target tables
- Foreign key columns are consistent
- INSERT/UPDATE statements use correct column names

Catches schema/SQL mismatches before deployment.

### Test Coverage

**SQLite Triggers:**
- `spec/integration/authentication/full_mode/database_triggers_sqlite_spec.rb`
- Tests: Login activity tracking, token cleanup, schema validation
- Tag: `:full_auth_mode`

**PostgreSQL Triggers:**
- `spec/integration/authentication/full_mode/database_triggers_postgres_spec.rb`
- Tests: Function-based triggers, upsert behavior, cleanup functions
- Tag: `:full_auth_mode, :postgres_database`

### Running Trigger Tests

```bash
# SQLite trigger tests (in-memory)
bundle exec rspec spec/integration/authentication/full_mode/database_triggers_sqlite_spec.rb

# PostgreSQL trigger tests (requires running PostgreSQL)
export AUTH_DATABASE_URL=postgresql://postgres:postgres@localhost/onetime_auth_test
bundle exec rspec --tag postgres_database

# Schema validation only
bundle exec rspec --tag trigger_validation
```

### CI Integration

PostgreSQL trigger tests run automatically in CI when backend or migration files change:
- Job: `ruby-integration-full-postgres`
- Service: PostgreSQL 16 container
- Path: `.github/ci-test-paths.json`

### Troubleshooting Trigger Validation

**"Column not found" error:**
- Check trigger SQL in `schemas/{postgres,sqlite}/002_extras.sql`
- Verify column names match table definition in `001_initial.rb`
- Example: `account_activity_times` uses `id` not `account_id`

**Trigger not firing:**
- Verify trigger condition matches test data
- Check audit log message format: `%login%successful%`
- Use direct DB INSERT to isolate from HTTP layer

**PostgreSQL function errors:**
- Ensure function exists: `SELECT proname FROM pg_proc WHERE proname = 'update_last_login_time';`
- Check function SQL syntax in `002_extras.sql`
- Verify trigger references correct function name

## Database Setup

### PostgreSQL

**IMPORTANT:** Run the setup script BEFORE first boot with `AUTHENTICATION_MODE=full`.

```bash
cd apps/web/auth/migrations/schemas/postgres
psql -U postgres -h localhost -f setup_auth_db.sql
```

This creates:
- Database: `onetime_auth_test`
- User: `onetime_auth` with password
- Grants: Schema privileges and default privileges for future migrations

See `apps/web/auth/migrations/schemas/postgres/README.md` for details.

### SQLite

No setup required. Database file created automatically at `data/auth.db`.

## Running Migrations

### Automatic (Recommended)

Migrations run automatically on application boot when `AUTHENTICATION_MODE=full`:

```bash
export AUTHENTICATION_MODE=full
export AUTH_DATABASE_URL=postgresql://user:pass@localhost/onetime_auth_test

# For migrations requiring elevated privileges (PostgreSQL extensions, grants)
export AUTH_DATABASE_URL_MIGRATIONS=postgresql://postgres@localhost/onetime_auth_test

bin/ots boot-test
```

### Manual (Sequel CLI)

```bash
# PostgreSQL
sequel -m apps/web/auth/migrations postgresql://user:pass@localhost/auth_db

# SQLite
sequel -m apps/web/auth/migrations sqlite://data/auth.db
```

## Database Support

**PostgreSQL** (Recommended for production):
- `citext` extension for case-insensitive email
- `jsonb` for audit log metadata
- Better concurrency and performance
- Partial indexes for soft-deleted accounts

**SQLite** (Development/testing):
- Simpler setup, single file
- Case-insensitive email via COLLATE NOCASE
- JSON text storage
- Good for development

## Configuration

Set in `etc/auth.yaml` (captured from environment variables):

```yaml
full:
  database_url: <%= ENV['AUTH_DATABASE_URL'] || 'sqlite://data/auth.db' %>
  database_url_migrations: <%= ENV['AUTH_DATABASE_URL_MIGRATIONS'] || nil %>
```

**Why two URLs?**
- `database_url` - Application runtime connection (restricted privileges)
- `database_url_migrations` - Migration-time connection (elevated privileges for CREATE EXTENSION, etc.)

## Troubleshooting

### PostgreSQL: "type citext does not exist"

The migration creates the extension automatically. Ensure migrations run with a user that has CREATE EXTENSION privileges:

```bash
export AUTH_DATABASE_URL_MIGRATIONS=postgresql://postgres@localhost/onetime_auth_test
```

### Check Migration Status

```sql
-- Current schema version
SELECT * FROM schema_info;

-- List tables
\dt  -- PostgreSQL
.tables  -- SQLite
```

### Reset Database

```bash
# PostgreSQL
psql -U postgres -c "DROP DATABASE onetime_auth_test; CREATE DATABASE onetime_auth_test OWNER onetime_auth;"

# SQLite
rm data/auth.db
```
