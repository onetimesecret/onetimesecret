# RSpec Test Suite

This document describes the test architecture for OneTimeSecret's RSpec suite.

## Authentication Mode Partitioning

OneTimeSecret runs in discrete authentication modes where certain code paths don't exist in certain modes (reduced attack surface). The test suite mirrors this architecture—**tests are organized by directory and run as separate processes per mode**.

### Why Directory Separation?

The mode boundary is a security architecture decision. It should be visible in the filesystem, not hidden in tag metadata or runtime switching logic.

| Approach | Pros | Cons |
|----------|------|------|
| Tag-based filtering | Flexible | Hidden, can mix modes accidentally |
| **Directory-based** | Visible, explicit, boring | Requires moving files |

We chose directory-based: `spec/integration/simple/`, `spec/integration/full/`, etc.

### Available Modes

| Mode | Description | Auth Stack |
|------|-------------|------------|
| `simple` | Basic session auth | Redis-only sessions |
| `full` | Complete auth with Rodauth | SQLite or PostgreSQL |
| `disabled` | No authentication | Public access only |

## Directory Structure

```
spec/integration/
├── simple/              # AUTHENTICATION_MODE=simple only
│   ├── adapter_spec.rb
│   └── rhales_migration_spec.rb
│
├── full/                # AUTHENTICATION_MODE=full only
│   ├── infrastructure_spec.rb
│   ├── rodauth_spec.rb
│   ├── database_triggers/
│   │   ├── sqlite_spec.rb
│   │   └── postgres_spec.rb
│   └── env_toggles/
│       ├── magic_links_spec.rb
│       ├── mfa_spec.rb
│       └── security_features_spec.rb
│
├── disabled/            # AUTHENTICATION_MODE=disabled only
│   └── public_access_spec.rb
│
└── all/                 # Runs in ALL modes (infrastructure tests)
    ├── puma_fork_registry_workflow_spec.rb
    ├── puma_initializer_fork_spec.rb
    ├── dual_auth_mode_spec.rb
    └── ...
```

## Running Tests

### Via Rake (Recommended)

```bash
# Run specific mode (includes all/ tests)
bundle exec rake spec:integration:simple
bundle exec rake spec:integration:full
bundle exec rake spec:integration:disabled

# Run all modes (separate processes)
bundle exec rake spec:integration:all

# Full mode with PostgreSQL
bundle exec rake spec:integration:full:postgres
```

### Via pnpm

```bash
pnpm test:rspec:integration:simple
pnpm test:rspec:integration:full
pnpm test:rspec:integration:disabled

# Run all modes
pnpm test:rspec:integration
```

### Direct rspec (advanced)

```bash
# Mode-specific tests + infrastructure tests
RACK_ENV=test AUTHENTICATION_MODE=simple bundle exec rspec \
  spec/integration/simple spec/integration/all

RACK_ENV=test AUTHENTICATION_MODE=full AUTH_DATABASE_URL='sqlite::memory:' \
  bundle exec rspec spec/integration/full spec/integration/all
```

## Adding New Integration Tests

1. **Determine which mode** the test requires
2. **Create the file in the appropriate directory**:
   - `spec/integration/simple/` — requires simple auth mode
   - `spec/integration/full/` — requires Rodauth/database auth
   - `spec/integration/disabled/` — requires no authentication
   - `spec/integration/all/` — mode-agnostic (infrastructure tests)
3. **Add `type: :integration`** for Redis cleanup
4. **No explicit mode tags needed** — directory determines the mode

Example:

```ruby
# spec/integration/full/my_new_feature_spec.rb
RSpec.describe 'My New Feature', type: :integration do
  # This test runs only in full mode because it's in full/
end
```

## How It Works

### Directory → Tag Derivation

`spec_helper.rb` automatically derives tags from directory paths:

```ruby
# Files in /integration/simple/ get :simple_auth_mode tag
# Files in /integration/full/ get :full_auth_mode tag
# Files in /integration/disabled/ get :disabled_auth_mode tag
# Files in /integration/all/ get :all_auth_modes tag
```

This is for tooling compatibility. The actual isolation comes from running separate processes.

### Process Isolation

Each mode runs in a separate `bundle exec rspec` process with the appropriate `AUTHENTICATION_MODE` env var. This ensures:

- No load-time pollution between modes
- Mode-specific code paths don't conflict
- Same isolation as production deployment

## CI Integration

CI runs each mode as a separate job:

| Job | Mode | Database |
|-----|------|----------|
| `ruby-integration-simple` | simple | Redis only |
| `ruby-integration-full-sqlite` | full | SQLite |
| `ruby-integration-full-postgres` | full | PostgreSQL |
| `ruby-integration-disabled` | disabled | Redis only |

## State Isolation

### Redis Cleanup

Tests with `type: :integration` automatically get Redis cleanup via `integration_spec_helper.rb`.

### Auth Database Cleanup

The `clean_auth_state` shared context tears down auth databases. See `spec/support/shared_contexts/clean_auth_state.rb`.

### ENV Cleanup

Tests that modify ENV should clean up in `after(:all)`:

```ruby
after(:all) do
  ENV.delete('AUTHENTICATION_MODE')
end
```

## Support Files

```
spec/support/
├── auth_mode_helpers.rb          # Auth mode mocking
├── billing_isolation.rb          # Per-example billing cleanup
├── full_mode_suite_database.rb   # SQLite setup for full mode
├── postgres_mode_suite_database.rb # PostgreSQL setup
└── shared_contexts/
    └── clean_auth_state.rb       # Database teardown between modes
```

## Debugging

### See which tests would run

```bash
bundle exec rspec spec/integration/simple spec/integration/all --dry-run
```

### Run a single test file

```bash
RACK_ENV=test AUTHENTICATION_MODE=full AUTH_DATABASE_URL='sqlite::memory:' \
  bundle exec rspec spec/integration/full/infrastructure_spec.rb
```
