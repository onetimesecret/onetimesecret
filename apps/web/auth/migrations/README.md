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
export AUTH_DATABASE_URL_MIGRATIONS=postgresql://onetime_migrator:@authdb/onetime_auth
```

**Why two URLs?** Rodauth security pattern: migrations run with elevated privileges (extensions, grants), application runs with restricted privileges (select, insert, update, delete).

## Running the Migrations

### Automatic Migrations (Recommended)

**Migrations run automatically during application boot** when `AUTHENTICATION_MODE=full`. The application uses `Auth::Migrator.run_if_needed` during the initialization phase to:

1. Check current schema version in `schema_info` table
2. Run any pending migrations using `AUTH_DATABASE_URL_MIGRATIONS` (elevated privileges)
3. Skip if schema is already current (idempotent)

**No manual intervention needed** - just start the application with proper environment variables configured.

#### Concurrent Deployment Safety

**PostgreSQL**: Uses advisory locks to prevent race conditions when multiple instances start simultaneously (e.g., Kubernetes horizontal scaling, CI/CD deployments).

- First instance acquires `pg_advisory_lock` → runs migrations
- Other instances wait on lock → see completed migrations → skip
- All instances proceed safely once migrations complete

**SQLite**: ⚠️ **Single-instance deployments only**

- No advisory lock support (only file-level OS locking)
- Concurrent writes can corrupt database
- Use blue/green deployments: **stop old instance before starting new**
- Rolling deployments are **NOT SAFE** with SQLite

#### CI/CD Best Practices

**For PostgreSQL (recommended for production):**
```yaml
# Safe for concurrent starts - advisory locks handle coordination
deployment:
  replicas: 3  # All can start simultaneously
  strategy: RollingUpdate
```

**For SQLite (development/single-instance only):**
```yaml
# Requires sequential deployment
deployment:
  replicas: 1
  strategy:
    type: Recreate  # Stop old pod before starting new
```

### Manual Migrations (Optional)

For environments where automatic migrations are not desired, you can run migrations manually before starting the application:

```bash
sequel -m apps/web/auth/migrations $AUTH_DATABASE_URL_MIGRATIONS
```

To disable automatic migrations, set `SKIP_AUTH_MIGRATIONS=true` in environment.

**Rollback**: Set migration index to 0:
```bash
sequel -m apps/web/auth/migrations -M 0 $AUTH_DATABASE_URL_MIGRATIONS
```

### Development Workflow

**Quick start** (SQLite in-memory):
```bash
export AUTHENTICATION_MODE=full
export AUTH_DATABASE_URL=sqlite::memory:
bundle exec thin start
# Migrations run automatically on boot
```

**With persistent database** (SQLite file):
```bash
export AUTHENTICATION_MODE=full
export AUTH_DATABASE_URL=sqlite://data/auth.db
bundle exec thin start
# Database file created if missing, migrations applied automatically
```

**PostgreSQL development**:
```bash
# One-time setup
psql -U postgres -f apps/web/auth/migrations/schemas/postgres/initialize_auth_db.sql

# Normal startup (migrations run automatically)
export AUTHENTICATION_MODE=full
export AUTH_DATABASE_URL=postgresql://onetime_user:pass@localhost/onetime_auth
export AUTH_DATABASE_URL_MIGRATIONS=postgresql://postgres:pass@localhost/onetime_auth
bundle exec thin start
```

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
