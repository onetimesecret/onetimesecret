# Auth Database Migrations

Sequel migrations for the Rodauth authentication system. These migrations are only used when the application authentication mode is set to full (i.e. `AUTHENTICATION_MODE=full`).

## Initialization

### PostgreSQL

**Run BEFORE first boot:**

```bash
psql -U postgres -h localhost -f apps/web/auth/migrations/schemas/postgres/initialize_auth_db.sql
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

Create the complete database schema with advanced functionality provided by the Sequel and SQL migrations, run the following immediately after running `initialize_auth_db.sql`:

```bash
sequel -m apps/web/auth/migrations $AUTH_DATABASE_URL_MIGRATIONS
```

NOTE: you can rollback by seting the migration index to 0: `sequel -m apps/web/auth/migrations -M 0 $AUTH_DATABASE_URL_MIGRATIONS`

## PostgreSQL Test Database Setup

For running the PostgreSQL integration tests (`spec/integration/full/`), you need a properly configured test database.

### Quick Setup

```bash
# 1. Create fresh test database with onetime_user as owner
psql -U postgres -c "DROP DATABASE IF EXISTS onetime_auth_test;"
psql -U postgres -c "CREATE DATABASE onetime_auth_test OWNER onetime_user;"

# 2. Run migrations with elevated privileges
AUTH_DATABASE_URL_MIGRATIONS="postgresql://postgres@localhost:5432/onetime_auth_test" \
  sequel -m apps/web/auth/migrations $AUTH_DATABASE_URL_MIGRATIONS

# 3. Grant permissions and transfer ownership to test user
psql -U postgres -d onetime_auth_test -c "
  GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO onetime_user;
  GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO onetime_user;
  GRANT USAGE, CREATE ON SCHEMA public TO onetime_user;
"

# 4. Transfer table ownership (required for tests that disable triggers)
psql -U postgres -d onetime_auth_test -c "
  DO \$\$
  DECLARE r RECORD;
  BEGIN
    FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
      EXECUTE 'ALTER TABLE ' || quote_ident(r.tablename) || ' OWNER TO onetime_user';
    END LOOP;
  END \$\$;
"
```

### Running PostgreSQL Tests

```bash
AUTH_DATABASE_URL="postgresql://onetime_user@localhost:5432/onetime_auth_test" \
AUTH_DATABASE_URL_MIGRATIONS="postgresql://postgres@localhost:5432/onetime_auth_test" \
RACK_ENV=test AUTHENTICATION_MODE=full \
bundle exec rspec spec/integration/full/postgres_infrastructure_spec.rb \
               spec/integration/full/database_triggers/postgres_spec.rb
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| `permission denied for table X` | Tables created by postgres, not test user | Grant privileges and transfer ownership (steps 3-4) |
| `must be owner of table X` | Test tries to ALTER TABLE (disable trigger) | Transfer table ownership to test user |
| `permission denied for schema public` | User can't create tables | Grant CREATE on schema public |
| `TIMESTAMPTZ` type mismatch in function | Stale function definition in database | Re-run migrations to update functions |

### Why Ownership Matters

Some PostgreSQL tests (e.g., testing trigger behavior) need to temporarily disable triggers:

```ruby
test_db.run('ALTER TABLE account_jwt_refresh_keys DISABLE TRIGGER trigger_cleanup_expired_tokens_extended')
```

This requires the connected user to **own** the table. Granting ALL PRIVILEGES is not sufficient for ALTER TABLE operations.

### Test Infrastructure Files

- `spec/support/postgres_mode_suite_database.rb` - PostgreSQL test database setup
- `spec/support/full_mode_suite_database.rb` - SQLite in-memory test database setup
- `spec/support/README-postgres-testing.md` - Comprehensive PostgreSQL testing guide
