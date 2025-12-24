# RSpec Test Suite

This document describes the test architecture for OneTimeSecret's RSpec suite.

## Authentication Mode Partitioning

OneTimeSecret runs in discrete authentication modes where certain code paths don't exist in certain modes (reduced attack surface). The test suite mirrors this architecture—**tests are not meant to run in a single process across all modes**.

| Approach | Load behavior | Matches prod? | Catches unrelated syntax errors |
|----------|---------------|---------------|--------------------------------|
| `--tag` filtering | Only matching files loaded | Yes | No |
| Env-var + runtime skip | All files loaded, non-matching skipped | No | Yes |


### Available Modes

| Mode | Description | Auth Stack |
|------|-------------|------------|
| `simple` | Basic session auth | Redis-only sessions |
| `full` | Complete auth with Rodauth | SQLite or PostgreSQL |
| `disabled` | No authentication | Public access only |

### Running Tests by Mode

```bash
# Simple mode (default)
pnpm test:rspec:simple

# Full mode with SQLite
pnpm test:rspec:full

# Full mode with PostgreSQL
pnpm test:rspec:full:postgres

# Disabled mode
pnpm test:rspec:disabled
```

## Tagging Integration Tests

All integration tests in `spec/integration/` **must** have an auth mode tag. Tests without tags **fail immediately** with a clear error message.

### Available Tags

| Tag | When to Use | Example |
|-----|-------------|---------|
| `:simple_auth_mode` | Test requires simple auth mode | `spec/integration/authentication/simple_mode/adapter_spec.rb` |
| `:full_auth_mode` | Test requires Rodauth/database auth | `spec/integration/authentication/full_mode/infrastructure_spec.rb` |
| `:disabled_auth_mode` | Test requires no authentication | `spec/integration/authentication/disabled_mode/public_access_spec.rb` |
| `:all_auth_modes` | Test is mode-agnostic (infrastructure, etc.) | `spec/integration/puma_fork_registry_workflow_spec.rb` |

### What Happens Without Tags

Untagged integration tests fail immediately with:

```
Integration test missing required auth mode tag!

File: spec/integration/example_spec.rb
Test: Example description

All integration tests in spec/integration/ MUST have an auth mode tag:
  - :simple_auth_mode   - runs only in simple mode
  - :full_auth_mode     - runs only in full mode
  - :disabled_auth_mode - runs only in disabled mode
  - :all_auth_modes     - runs in all modes (mode-agnostic tests)

Fix: Add the appropriate tag to your RSpec.describe block
```

## Test Distribution

Current test counts by mode:

| Mode | Integration Tests |
|------|-------------------|
| simple | ~118 |
| full | ~338 |
| disabled | ~87 |

Full mode has the most tests because most auth features require Rodauth.

## Directory Structure

```
spec/
├── spec_helper.rb           # Main config, auth mode filtering
├── integration/             # Integration tests (require mode tags)
│   ├── authentication/      # Auth-specific tests
│   │   ├── full_mode/       # Rodauth, MFA, sessions
│   │   ├── simple_mode/     # Basic auth adapter
│   │   ├── disabled_mode/   # Public access
│   │   └── common/          # Shared route tests
│   ├── api/                 # API endpoint tests
│   └── puma_*.rb            # Infrastructure tests (:all_auth_modes)
├── onetime/                 # Unit tests (run in any mode)
├── lib/                     # Library unit tests
├── cli/                     # CLI command tests
└── support/
    ├── auth_mode_helpers.rb          # Auth mode mocking
    ├── billing_isolation.rb          # Per-example billing cleanup
    ├── full_mode_suite_database.rb   # SQLite setup for full mode
    ├── postgres_mode_suite_database.rb # PostgreSQL setup
    └── shared_contexts/
        └── clean_auth_state.rb       # Database teardown between modes
```

## CI Integration

CI runs each mode as a separate job:

- `ruby-integration-simple` — Simple mode tests
- `ruby-integration-full-sqlite` — Full mode with SQLite
- `ruby-integration-full-postgres` — Full mode with PostgreSQL
- `ruby-integration-disabled` — Disabled mode tests

This ensures complete isolation between modes.

## State Isolation

### Redis Cleanup

Tests tagged `type: :integration` automatically get Redis cleanup via `integration_spec_helper.rb`.

### Auth Database Cleanup

The `clean_auth_state` shared context tears down auth databases between mode switches. See `spec/support/shared_contexts/clean_auth_state.rb`.

### ENV Cleanup

Tests that modify ENV should clean up in `after(:all)`. See `spec/integration/admin_interface_spec.rb` for an example.

## Adding New Integration Tests

1. Determine which auth mode(s) your test requires
2. Add the appropriate tag to your `RSpec.describe` (see Examples above)
3. Add `type: :integration` for Redis cleanup
4. Run with the matching mode command to verify:

```bash
pnpm test:rspec:full spec/integration/path/to/new_spec.rb
```

## Debugging

### See which tests would run

```bash
AUTHENTICATION_MODE=simple bundle exec rspec spec/integration --dry-run
```

### Run all tests regardless of mode (advanced)

```bash
RSPEC_ALL_MODES=1 bundle exec rspec spec/integration
```

### Check mode filtering output

When running locally (not CI), spec_helper prints:
```
[RSpec] AUTHENTICATION_MODE=simple
        Excluding: full_auth_mode, disabled_auth_mode
        Integration tests require: simple_auth_mode tag
```
