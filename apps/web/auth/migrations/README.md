# Auth Database Migrations

Sequel migrations for the Rodauth authentication system. Migrations run automatically on application boot when `AUTHENTICATION_MODE=full`.

## Setup

### PostgreSQL

**Run BEFORE first boot:**

```bash
cd apps/web/auth/migrations/schemas/postgres
psql -U postgres -h localhost -f setup_auth_db.sql
```

Creates database `onetime_auth_test`, user `onetime_auth`, and configures privileges for the Rodauth multiple-user security pattern.

See `schemas/postgres/README.md` for details.

### SQLite

No setup required. Database file created automatically at `data/auth.db`.

## Configuration

```bash
export AUTHENTICATION_MODE=full

# Application runtime connection (restricted privileges)
export AUTH_DATABASE_URL=postgresql://onetime_user:pass@localhost/onetime_auth

# Migration-time connection (elevated privileges for CREATE EXTENSION, etc.)
export AUTH_DATABASE_URL_MIGRATIONS=postgresql://postgres@localhost/onetime_auth_test
```

**Why two URLs?** Rodauth security pattern: migrations run with elevated privileges (extensions, grants), application runs with restricted privileges (select, insert, update, delete).

## What Gets Created

**Migration 001:** 23 Rodauth tables (see inline comments in `001_initial.rb`)

**Migration 002:** Database-specific SQL (see headers in `schemas/postgres/002_extras.sql` and `schemas/sqlite/002_extras.sql`):
- Performance indexes
- Monitoring views
- Automatic triggers
- Convenience functions (PostgreSQL only)

## Troubleshooting

**PostgreSQL: "type citext does not exist"**

Migration creates extension automatically. Ensure `AUTH_DATABASE_URL_MIGRATIONS` uses a user with CREATE EXTENSION privileges.

**Check status:**

```sql
SELECT * FROM schema_info;  -- Current version
\dt                          -- List tables (PostgreSQL)
.tables                      -- List tables (SQLite)
```

**Reset database:**

```bash
# PostgreSQL
psql -U postgres -c "DROP DATABASE onetime_auth_test; CREATE DATABASE onetime_auth_test OWNER onetime_auth;"

# SQLite
rm data/auth.db
```
