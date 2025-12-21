# PostgreSQL Test Infrastructure

## Overview

The `postgres_mode_suite_database.rb` support file provides PostgreSQL-specific test infrastructure for full auth mode integration tests. This infrastructure enables testing of PostgreSQL-specific features like triggers, functions, and constraints that cannot be tested with SQLite.

## Setup

### Prerequisites

1. PostgreSQL 17 installed and running
2. Database user with CREATE DATABASE privileges
3. Environment variables configured

### Environment Variables

```bash
# Required: PostgreSQL connection for running tests
export AUTH_DATABASE_URL="postgresql://user:password@localhost/onetime_auth_test"

# Optional: Elevated connection for running migrations (if different from test connection)
export AUTH_DATABASE_URL_MIGRATIONS="postgresql://admin:password@localhost/onetime_auth_test"
```

### Database Setup

The test infrastructure will automatically:
1. Connect to the PostgreSQL database specified in `AUTH_DATABASE_URL`
2. Run migrations from `apps/web/auth/migrations/`
3. Use elevated connection from `AUTH_DATABASE_URL_MIGRATIONS` if provided

**Note:** The database must already exist. The test suite does not create databases.

```bash
# Create test database (one time)
createdb onetime_auth_test

# Or using psql
psql -c "CREATE DATABASE onetime_auth_test;"
```

## Usage

### Tagging Tests

Use both `:full_auth_mode` and `:postgres_database` tags:

```ruby
RSpec.describe 'My PostgreSQL Test', :full_auth_mode, :postgres_database do
  it 'tests PostgreSQL-specific feature' do
    # Test implementation
  end
end
```

### Test Database Access

The `test_db` helper provides access to the PostgreSQL database:

```ruby
RSpec.describe 'PostgreSQL Triggers', :full_auth_mode, :postgres_database do
  it 'exercises trigger on successful login' do
    # Create test account
    account = create_verified_account(db: test_db, email: 'test@example.com')

    # Insert audit log (should trigger database trigger)
    test_db[:account_authentication_audit_logs].insert(
      account_id: account[:id],
      at: Time.now,
      message: 'login successful'
    )

    # Verify trigger populated account_activity_times
    activity = test_db[:account_activity_times].where(id: account[:id]).first
    expect(activity).not_to be_nil
    expect(activity[:last_login_at]).not_to be_nil
  end
end
```

### Factory Methods

All `AuthAccountFactory` methods are available:

```ruby
# Create verified account with password
account = create_verified_account(
  db: test_db,
  email: 'user@example.com',
  password: 'secure-password'
)

# Create unverified account with verification key
account = create_unverified_account(db: test_db)

# Create account with MFA enabled
account = create_verified_account(db: test_db, with_mfa: true)

# Create active session
session_id = create_active_session(db: test_db, account_id: account[:id])

# Cleanup account and related data
cleanup_account(db: test_db, account_id: account[:id])
```

## Database Lifecycle

### Suite-Level Setup (Lazy Initialization)

The PostgreSQL database is initialized lazily when the first `:postgres_database` spec runs:

1. Connect to PostgreSQL using `AUTH_DATABASE_URL`
2. Verify connection is PostgreSQL (not SQLite or other)
3. Run migrations (using elevated connection if `AUTH_DATABASE_URL_MIGRATIONS` is set)
4. Stub `Auth::Database.connection` to return test database
5. Boot application in test mode
6. Rebuild application registry with test database

**Important:** Setup is idempotent. Multiple describe blocks can have the `:postgres_database` tag without causing issues.

### Context-Level Cleanup

After each `describe` block with `:postgres_database` tag:

1. All Rodauth tables are truncated using `TRUNCATE CASCADE`
2. Sequences are reset to 1
3. This provides isolation between describe blocks

### Suite-Level Teardown

At the very end of the test suite:

1. Database connection is disconnected
2. Original `Auth::Database.connection` method is restored
3. Connection state is reset

## Performance

### Speed Optimizations

- **Lazy initialization**: Database only created once per suite
- **TRUNCATE CASCADE**: Faster than DELETE, handles foreign keys automatically
- **Sequence reset**: Primary keys start at 1 for each describe block
- **Persistent connection**: One connection shared across all PostgreSQL tests

### Expected Performance

- Suite setup: ~2-5 seconds (first test only)
- Per-test overhead: Minimal (uses shared connection)
- Cleanup: <100ms per describe block

## Differences from SQLite Infrastructure

| Feature | SQLite (`full_mode_suite_database.rb`) | PostgreSQL (`postgres_mode_suite_database.rb`) |
|---------|----------------------------------------|-----------------------------------------------|
| Database | In-memory (`sqlite::memory:`) | Real PostgreSQL via `AUTH_DATABASE_URL` |
| Cleanup | `DELETE` per table | `TRUNCATE CASCADE` |
| Migrations | Standard connection | Optional elevated connection |
| Extensions | None | citext, functions, triggers |
| Tags | `:full_auth_mode` | `:full_auth_mode, :postgres_database` |

## Running PostgreSQL Tests

### Run All PostgreSQL Tests

```bash
# Using pnpm script (if configured)
pnpm run test:rspec:postgres

# Using RSpec directly
bundle exec rspec --tag postgres_database

# Run specific file
bundle exec rspec spec/integration/authentication/full_mode/postgres_infrastructure_spec.rb
```

### Run Mixed Tests

Tests tagged with only `:full_auth_mode` will use SQLite (fast, in-memory).
Tests tagged with both `:full_auth_mode, :postgres_database` will use PostgreSQL (real database).

```bash
# Run all full mode tests (SQLite + PostgreSQL)
bundle exec rspec --tag full_auth_mode

# Run only SQLite tests (exclude PostgreSQL)
bundle exec rspec --tag full_auth_mode --tag ~postgres_database

# Run only PostgreSQL tests
bundle exec rspec --tag postgres_database
```

## Troubleshooting

### Connection Errors

**Error:** `AUTH_DATABASE_URL must be set for PostgreSQL tests`

**Solution:** Export `AUTH_DATABASE_URL` before running tests:
```bash
export AUTH_DATABASE_URL="postgresql://user:password@localhost/onetime_auth_test"
```

### Migration Errors

**Error:** `permission denied to create extension`

**Solution:** Use elevated connection for migrations:
```bash
export AUTH_DATABASE_URL_MIGRATIONS="postgresql://admin:password@localhost/onetime_auth_test"
```

Or grant extension privileges:
```sql
ALTER USER testuser WITH SUPERUSER;
```

### Database Type Mismatch

**Error:** `Expected PostgreSQL connection, got: sqlite`

**Solution:** Verify `AUTH_DATABASE_URL` starts with `postgresql://` or `postgres://`

### Stale Data Between Tests

**Symptom:** Tests pass individually but fail when run together

**Cause:** Previous test leaked data; cleanup not happening

**Solution:**
1. Verify `after` blocks clean up test data
2. Check `PostgresModeSuiteDatabase.clean_tables!` is working
3. Add manual cleanup in test:
   ```ruby
   after do
     test_db[:accounts].where(email: 'test@example.com').delete
   end
   ```

## CI Integration

For CI environments (GitHub Actions, etc.):

```yaml
services:
  postgres:
    image: postgres:15
    env:
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: onetime_auth_test
    options: >-
      --health-cmd pg_isready
      --health-interval 10s
      --health-timeout 5s
      --health-retries 5

jobs:
  test:
    runs-on: ubuntu-latest
    env:
      AUTH_DATABASE_URL: postgresql://postgres:postgres@localhost/onetime_auth_test
    steps:
      - name: Run PostgreSQL tests
        run: bundle exec rspec --tag postgres_database
```

## Best Practices

1. **Tag appropriately**: Use `:postgres_database` only when testing PostgreSQL-specific features
2. **Clean up**: Always clean test data in `after` blocks
3. **Isolate tests**: Don't rely on data from other tests
4. **Use factories**: Prefer `create_verified_account` over manual SQL
5. **Document expectations**: Comment why PostgreSQL is needed for the test

## Related Files

- `spec/support/postgres_mode_suite_database.rb` - Infrastructure implementation
- `spec/support/full_mode_suite_database.rb` - SQLite equivalent
- `spec/support/factories/auth_account_factory.rb` - Account creation helpers
- `spec/support/auth_mode_helpers.rb` - Auth mode utilities
- `apps/web/auth/migrations/` - Database migrations
- `apps/web/auth/database.rb` - Auth::Database module
