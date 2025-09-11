# Rodauth Database Schema Documentation

## Core Schema Requirements

### Essential Tables

**1. Account Statuses Table:**
```sql
-- Status lookup for account verification states
CREATE TABLE account_statuses (
    id INTEGER PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE
);

-- Standard status values
INSERT INTO account_statuses (id, name) VALUES
    (1, 'Unverified'),
    (2, 'Verified'),
    (3, 'Closed');
```

**2. Accounts Table (main user table):**
```sql
-- PostgreSQL version
CREATE TABLE accounts (
    id BIGSERIAL PRIMARY KEY,
    email CITEXT NOT NULL,
    status_id INTEGER NOT NULL DEFAULT 1 REFERENCES account_statuses(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login_ip INET,
    last_login_at TIMESTAMPTZ,
    CONSTRAINT valid_email CHECK (email ~ '^[^,;@ \r\n]+@[^,@; \r\n]+\.[^,@; \r\n]+$')
);

-- SQLite version
CREATE TABLE accounts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email VARCHAR(255) NOT NULL COLLATE NOCASE,
    status_id INTEGER NOT NULL DEFAULT 1 REFERENCES account_statuses(id),
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login_ip VARCHAR(45),
    last_login_at DATETIME
);

-- Unique email constraint for active accounts only
CREATE UNIQUE INDEX accounts_email_unique ON accounts(email)
WHERE status_id IN (1, 2);
```

**3. Password Hashes Table (separate for security):**
```sql
CREATE TABLE account_password_hashes (
    id BIGINT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    password_hash VARCHAR(255) NOT NULL
);
```

### Feature-Specific Tables

**Password Reset:**
```sql
CREATE TABLE account_password_reset_keys (
    id BIGINT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    key VARCHAR(255) NOT NULL UNIQUE,
    deadline TIMESTAMPTZ NOT NULL,
    email_last_sent TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

**Remember Me:**
```sql
CREATE TABLE account_remember_keys (
    id BIGINT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    key VARCHAR(255) NOT NULL UNIQUE,
    deadline TIMESTAMPTZ NOT NULL
);
```

**Account Verification:**
```sql
CREATE TABLE account_verification_keys (
    id BIGINT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    key VARCHAR(255) NOT NULL UNIQUE,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    email_last_sent TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

**Brute Force Protection:**
```sql
CREATE TABLE account_login_failures (
    id BIGINT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    number INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE account_lockouts (
    id BIGINT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    key VARCHAR(255) NOT NULL UNIQUE,
    deadline TIMESTAMPTZ NOT NULL,
    email_last_sent TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);
```

**Active Sessions:**
```sql
CREATE TABLE account_active_session_keys (
    account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    session_id VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_use TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (account_id, session_id)
);
```

**Multi-Factor Authentication (MFA):**
```sql
-- OTP (TOTP) secret keys for Google Authenticator, etc.
CREATE TABLE account_otp_keys (
    id BIGINT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    key VARCHAR(255) NOT NULL,
    num_failures INTEGER NOT NULL DEFAULT 0,
    last_use TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Recovery codes for MFA bypass
CREATE TABLE account_recovery_codes (
    id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    code VARCHAR(255) NOT NULL UNIQUE,
    used_at TIMESTAMPTZ
);
```

**Audit Logging:**
```sql
CREATE TABLE account_authentication_audit_logs (
    id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    message TEXT NOT NULL,
    metadata JSONB  -- PostgreSQL: JSONB, SQLite: TEXT
);
```

## Database-Specific Setup

### PostgreSQL Setup
```bash
# Create database users (for enhanced security)
createuser -U postgres myapp
createuser -U postgres myapp_password

# Create database
createdb -U postgres -O myapp myapp

# Load required extensions
psql -U postgres -c "CREATE EXTENSION citext" myapp

# For PostgreSQL 15+, grant schema permissions
psql -U postgres -c "GRANT CREATE ON SCHEMA public TO myapp_password" myapp
```

### SQLite Setup
```bash
# Ensure data directory exists
mkdir -p data

# Database file will be created automatically at: data/auth.db
# Ensure proper file permissions (600) for security
chmod 600 data/auth.db  # After first creation
```

**Key Differences:**
- **SQLite**: Uses `COLLATE NOCASE` for case-insensitive emails
- **PostgreSQL**: Uses `citext` extension for case-insensitive emails
- **SQLite**: Database stored as single file in `data/auth.db`
- **PostgreSQL**: Network database with separate user accounts for security

Security Considerations

- Separate Password User: For maximum security, use separate database accounts for application logic vs password hash access
- Database Functions: PostgreSQL, MySQL, and SQL Server support database functions that prevent the application user from directly reading
password hashes
- Email Validation: PostgreSQL's citext extension provides case-insensitive email handling with constraints

Your current setup appears to be using SQLite based on the auth.db file, which simplifies deployment but you'll want to ensure proper file
permissions and backup strategies.

## Updated Schema Files

### PostgreSQL Schema (`example_db_schema-pg.sql`)
- **Full-featured schema** with all Rodauth tables for future expansion
- **citext extension** for case-insensitive email handling
- **Partial indexes** for efficient email uniqueness (active accounts only)
- **Advanced features**: audit logging, WebAuthn, MFA, database functions
- **Best for**: Production PostgreSQL deployments

### SQLite Essential Schema (`schemas/sqlite/essential_schema.sql`)
- **Complete essential schema** with MFA and all enabled features
- **COLLATE NOCASE** for case-insensitive emails in SQLite
- **Optimized indexes** and triggers for performance
- **Automatic cleanup** triggers for expired tokens
- **Best for**: Current auth app and development

### PostgreSQL Essential Schema (`schemas/postgres/essential_schema.sql`)
- **Complete essential schema** with MFA and all enabled features
- **citext extension** for case-insensitive email handling
- **Database functions** for enhanced security (password hash isolation)
- **JSONB metadata** with GIN indexes for performance
- **Best for**: Production PostgreSQL deployments

## Key Differences

| Feature | PostgreSQL | SQLite |
|---------|------------|--------|
| Case-insensitive emails | `citext` extension | `COLLATE NOCASE` |
| Account ID column | `id BIGSERIAL` | `id INTEGER AUTOINCREMENT` |
| Session table naming | `account_id` (standard) | `account_id` (standard) |
| Partial indexes | Supported | Not supported (uses triggers) |
| JSON metadata | `JSONB` with GIN indexes | `TEXT` |
| Database functions | PL/pgSQL security functions | Triggers only |
| Timestamps | `TIMESTAMPTZ` | `DATETIME` |

## Schema Loading

The new migration system automatically loads the appropriate schema based on database type:

```ruby
# migrations/001_initial.rb
# Automatically detects database type and loads:
# - schemas/sqlite/001_initial.sql (for SQLite)
# - schemas/postgres/001_initial.sql (for PostgreSQL)
```

**Usage:**
```bash
# SQLite (default)
ruby migrate.rb

# PostgreSQL
DATABASE_URL="postgres://user:pass@localhost/myapp" ruby migrate.rb
```

## Security Notes

- **PostgreSQL**: Supports separate database users for password hash isolation via PL/pgSQL functions
- **SQLite**: Single database file - ensure proper file permissions (`chmod 600 data/auth.db`)
- **Both**: Password hashes stored in separate table following Rodauth security model
- **MFA**: OTP secrets and recovery codes are included in essential schema
- **Audit Logging**: All authentication events are logged for security monitoring

## Enabled Features

The essential schema supports these Rodauth features:
- `base`, `json` - Core functionality and JSON API
- `login`, `logout`, `create_account`, `close_account` - Basic auth flows
- `login_password_requirements_base` - Password validation
- `change_password`, `reset_password` - Password management
- `remember` - "Remember me" functionality
- `verify_account` - Email verification
- `lockout` - Brute force protection
- `active_sessions` - Session tracking
- `otp` - Time-based One-Time Passwords (TOTP/Google Authenticator)
- `recovery_codes` - MFA backup codes


## About Sequel

### Sequel Migrations

- Imperative, not declarative - You write create_table, add_column, etc. commands
- No automatic schema introspection - Sequel doesn't build a model of your "intended" schema from migrations
- No automatic diff detection - It can't compare your models to the database and generate migrations
- Simple version tracking - Just tracks which migration files have been run via a schema_migrations table
- Manual migration writing - You must write each migration by hand

### Django ORM (for comparison)

- Declarative models - Your models define the intended schema
- Automatic migration generation - makemigrations compares models to current schema and generates migration files
- Schema introspection - Builds internal representation of intended vs actual schema
- Automatic diff detection - Can detect model changes and suggest migrations

### What Sequel Does Track

Sequel only tracks:
-- This table is created automatically
CREATE TABLE schema_migrations (
  filename VARCHAR(255) PRIMARY KEY
);

When you run Sequel::Migrator.run(DB, 'migrations'), it:
1. Checks which files in migrations/ haven't been run
2. Runs them in filename order
3. Records the filename in schema_migrations


### Schema Maintenance

For schema drift detection, you'd need external tools like:
  - sqldiff for SQLite
  - migra for PostgreSQL
  - Custom scripts comparing your SQL files to actual schema
