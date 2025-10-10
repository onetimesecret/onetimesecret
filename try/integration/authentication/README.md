# Authentication Test Organization

## Structure

Authentication tests are organized by mode to ensure they run only when appropriate:

```
authentication/
├── basic_mode/       # Tests requiring basic authentication mode
├── advanced_mode/    # Tests requiring advanced (Rodauth) mode
├── disabled_mode/    # Tests for when auth is completely disabled
└── common/          # Tests that work in any mode
```

## Authentication Modes

### Disabled Mode (`AUTHENTICATION_MODE=disabled`)
- No authentication required at all
- Simplest deployment option
- All auth endpoints return 404
- Protected endpoints are publicly accessible
- Use case: Internal tools, demos, simplest setup

### Basic Mode (`AUTHENTICATION_MODE=basic` or unset)
- Default mode
- Redis-based authentication
- Core app handles `/auth/*` routes
- No external database required
- Use case: Standard deployments, small teams

### Advanced Mode (`AUTHENTICATION_MODE=advanced`)
- Rodauth integration
- PostgreSQL database required
- Auth app mounted at `/auth`
- Supports MFA, password policies, account verification
- Use case: Enterprise deployments, compliance requirements

## Running Tests

### Run All Tests for Current Mode
```bash
# Runs tests based on AUTHENTICATION_MODE environment variable
bundle exec try --agent try/integration/authentication/
```

### Run Mode-Specific Tests
```bash
# Basic mode tests only
AUTHENTICATION_MODE=basic bundle exec try --agent try/integration/authentication/basic_mode/

# Advanced mode tests only (requires PostgreSQL)
AUTHENTICATION_MODE=advanced bundle exec try --agent try/integration/authentication/advanced_mode/

# Disabled mode tests
AUTHENTICATION_MODE=disabled bundle exec try --agent try/integration/authentication/disabled_mode/

# Common tests (run in any mode)
bundle exec try --agent try/integration/authentication/common/
```

### Test Files

#### Basic Mode
- `core_auth_try.rb` - Core app authentication flow tests
- `adapter_try.rb` - Auth app adapter behavior in basic mode

#### Advanced Mode
- `rodauth_try.rb` - Rodauth integration tests

#### Disabled Mode
- `public_access_try.rb` - Public access without authentication

#### Common
- `routes_try.rb` - Route behavior tests (work in any mode)

## How Skipping Works

Each mode-specific test file includes:
```ruby
require_relative '../../../support/auth_mode_config'
Object.new.extend(AuthModeConfig).skip_unless_mode :basic
```

This causes the test file to exit cleanly (status 0) if not in the required mode, preventing false failures in CI.

## CI Configuration

The CI workflow should run tests for each mode:
```yaml
strategy:
  matrix:
    auth_mode: ['disabled', 'basic', 'advanced']

env:
  AUTHENTICATION_MODE: ${{ matrix.auth_mode }}
```

This ensures all authentication modes are tested without false positives from mode mismatches.

## Adding New Tests

1. Determine which mode(s) your test requires
2. Place in appropriate directory:
   - Mode-specific: `basic_mode/`, `advanced_mode/`, or `disabled_mode/`
   - Works everywhere: `common/`
3. Add skip logic for mode-specific tests
4. Update this README if adding new test categories
