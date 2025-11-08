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
- SQL database required (PostgreSQL or SQLite)
- Auth app mounted at `/auth`
- Supports MFA, password policies, account verification
- Use case: Enterprise deployments, compliance requirements

## Test Environment

### Required Services

**Redis/Valkey** (all modes):
```bash
# Start test database (port 2121)
pnpm run test:database:start

# Check status
pnpm run test:database:status

# Stop when done
pnpm run test:database:stop
```

**SQL Database** (advanced mode only):
- PostgreSQL or SQLite for Rodauth account storage
- Configure via `DATABASE_URL` environment variable
- Examples:
  - PostgreSQL: `postgresql://user:pass@localhost/onetime_test`
  - SQLite: `sqlite://db/test.db`

### Optional Services

**Mailpit** (email testing):
- SMTP server for password reset/verification emails
- Default: `localhost:1025`
- Environment: `MAILPIT_SMTP_HOST`, `MAILPIT_SMTP_PORT`

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

# Advanced mode tests only (requires PostgreSQL or SQLite)
AUTHENTICATION_MODE=advanced bundle exec try --agent try/integration/authentication/advanced_mode/

# Disabled mode tests
AUTHENTICATION_MODE=disabled bundle exec try --agent try/integration/authentication/disabled_mode/

# Common tests (run in any mode)
bundle exec try --agent try/integration/authentication/common/
```

### Debug Specific Failures
```bash
# Verbose output with stack traces for specific test lines
bundle exec try --verbose --fails --stack try/integration/authentication/basic_mode/core_auth_try.rb:169-180

# Agent mode with FAMILIA_DEBUG disabled (cleaner output)
FAMILIA_DEBUG=0 bundle exec try --agent try/integration/authentication/basic_mode/
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

## Test Patterns

### Key Principles

**Controllers**:
- Read from `env['otto.user']` (authenticated user object)
- Read from `env['otto.strategy_result']` (strategy result with session)
- **Never** read directly from session
- Test by mocking `env['otto.user']` and `env['otto.strategy_result']`

**Logic Classes**:
- Receive `StrategyResult` object in constructor
- Access session via `@strategy_result.session` (not `@sess` directly in tests)
- **Only** Logic classes write to session
- Test by creating `StrategyResult` objects with session state
- Verify session changes via `strategy_result.session`

**Key Assertions**:
- Controllers read authentication state from environment only
- Logic classes write session keys after authentication (login/logout/registration)
- Session is cleared on logout via `@sess.clear`
- Customer objects are properly loaded/created from session data
- Error conditions raise appropriate exceptions (`OT::FormError`, etc.)

**Test Approach**:
- **Controller tests**: Set environment variables to simulate auth states
- **Logic tests**: Initialize with `StrategyResult`, verify session mutations
- **Integration tests**: Use `Rack::Test` to simulate full request/response cycle
- **Mode-specific tests**: Auto-skip via `skip_unless_mode` helper

## Adding New Tests

1. Determine which mode(s) your test requires
2. Place in appropriate directory:
   - Mode-specific: `basic_mode/`, `advanced_mode/`, or `disabled_mode/`
   - Works everywhere: `common/`
3. Add skip logic for mode-specific tests:
   ```ruby
   require_relative '../../../support/auth_mode_config'
   Object.new.extend(AuthModeConfig).skip_unless_mode :basic
   ```
4. Follow test patterns above (controllers read env, logic writes session)
5. Update this README if adding new test categories
