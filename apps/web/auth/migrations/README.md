# Auth Database Migrations

Sequel migrations for the Rodauth authentication system. These migrations are only used when the application authentication mode is set to full (i.e. `AUTHENTICATION_MODE=full`).

## Initialization

### PostgreSQL

**Run BEFORE first boot:**

```bash
psql -U postgres -h localhost -f apps/web/auth/migrations/schemas/postgres/setup_auth_db.sql
```

Creates database `onetime_auth`, and two roles: `oneitme_migrator` and `onetime_user`, each with privileges appropriate for their purpose.

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

## Running the Migrations

### In Development

To get up and running, the database will be automatically created and the default simplified schema applied when you start the application. This is done by Rodauth::Tools which provides a clean starting point for development and testing. This does not include the advanced functionality provided by the Sequel and SQL migrations.

When working on existing features, create the complete database schema before the first boot as well. See In Production below.

### In Production

Create the complete database schema with advanced functionality provided by the Sequel and SQL migrations, run the following immediately after running `setup_auth_db.sql`:

```bash
sequel -m apps/web/auth/migrations $AUTH_DATABASE_URL_MIGRATIONS
```

NOTE: you can rollback by seting the migration index to 0: `sequel -m apps/web/auth/migrations -M 0 $AUTH_DATABASE_URL_MIGRATIONS`
