# OneTimeSecret Test Suite

The test suite follows Ruby conventions with clear separation by test type and purpose.

## Directory Structure

```plaintext
onetimesecret/
├── spec/                    # RSpec behavior tests
│   ├── unit/               # Unit tests
│   ├── integration/        # Integration tests
│   └── support/            # Shared helpers and fixtures
├── tryouts/                # Documentation-as-tests (Tryouts gem)
│   ├── models/            # Model tryouts
│   ├── logic/             # Business logic tryouts
│   ├── utils/             # Utility tryouts
│   ├── config/            # Configuration tryouts
│   ├── middleware/        # Middleware tryouts
│   ├── templates/         # Template tryouts
│   ├── integration/       # Integration tryouts
│   └── helpers/           # Tryout helpers
└── tests/                  # Frontend and E2E tests
    ├── unit/
    │   └── vue/           # Vue component unit tests
    └── integration/
        ├── api/           # API integration tests
        └── web/           # Playwright E2E tests
```

## Running Tests

### Ruby Tests
```bash
# RSpec tests
bundle exec rspec

# Tryouts
bundle exec try tryouts/**/*_try.rb

# All Ruby tests
bundle exec rake test
```

### Frontend Tests
```bash
# Vue unit tests
npm run test:unit

# Playwright E2E tests
npm run test:e2e

# All frontend tests
npm test
```

### Run Everything
```bash
./run_tests.sh
```

## Test Types

- **RSpec**: Behavior-driven tests for Ruby code
- **Tryouts**: Executable documentation that serves as both tests and usage examples
- **Vue Tests**: Component unit tests using Vitest
- **Playwright**: End-to-end browser automation tests

## CI/CD

GitHub Actions workflows in `.github/workflows/`:
- `ci.yml`: Ruby tests (RSpec and Tryouts)
- `vue-tests.yml`: Vue unit tests
- `playwright.yml`: E2E tests (currently requires local setup)

## Notes

- Tests are currently being updated due to major code restructuring
- Playwright tests require Ruby, Caddy, and Redis running locally
- See individual test directories for specific documentation

## Migration

To migrate from old test structure to current organization:
```bash
./migration-script-runner.sh
```

Migration includes:
- Move RSpec tests to `spec/` directory
- Reorganize tryouts by category in `tryouts/`
- Co-locate frontend tests under `src/`
- Update CI configuration

For rollback: `./migration-script-rollback.sh`
See `TROUBLESHOOTING.md` for issues.
