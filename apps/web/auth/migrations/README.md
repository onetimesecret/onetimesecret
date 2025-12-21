# Auth Database Migrations

Sequel migrations for the Rodauth authentication system. Migrations run automatically on application boot when `AUTHENTICATION_MODE=full`.

## Setup

### PostgreSQL

**Run BEFORE first boot:**

```bash
cd apps/web/auth/migrations/schemas/postgres
psql -U postgres -h localhost -f setup_auth_db.sql
```

Creates database `onetime_auth_test`, user `onetime_auth`, and configures privileges for the Rodauth security pattern.

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
