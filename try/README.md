# Tryouts Test Suite

This directory contains the tryouts test suite for Onetime Secret. Tryouts is a plain-Ruby testing framework that emphasizes readable, realistic code that doubles as documentation.

## Directory Structure

```
try/
├── unit/                      # Unit-like tests (isolated, fast)
│   ├── models/v2/            # V2 model behavior tests
│   ├── logic/                # Business logic tests
│   │   ├── authentication/   # Auth logic
│   │   ├── secrets/         # Secret management logic
│   │   ├── account/         # Account operations logic
│   │   └── domains/         # Domain handling logic
│   ├── utils/               # Utility class tests
│   └── config/              # Configuration tests
│
├── integration/              # Integration tests (multiple components)
│   ├── middleware/          # Middleware stack tests
│   ├── authentication/      # Auth flow integration
│   ├── email/              # Email template & sending
│   └── web/                # Web interface tests
│
├── system/                  # System-wide tests
│   ├── database/           # Redis & database tests
│   └── initializers/       # Boot-time initializer tests
│
├── disabled/                # Temporarily disabled tests
│   └── domains/            # Domain-related tests (WIP)
│
├── experimental/            # Experimental/demo code
│
└── support/                 # Test helpers and fixtures
    ├── test_helpers.rb     # General test utilities
    ├── test_logic.rb       # Logic layer test setup
    └── test_models.rb      # Model test setup
```

## Running Tests

### Run All Tests
```bash
bundle exec try --agent try/
```

### Run Specific Category
```bash
bundle exec try --agent try/unit/models/v2/
bundle exec try --agent try/integration/
bundle exec try --agent try/system/
```

### Run Single File
```bash
bundle exec try --agent try/unit/models/v2/customer_try.rb
```

### Debug Specific Test Case
```bash
# Run with verbose output and show failures
bundle exec try --verbose --fails try/unit/models/v2/customer_try.rb

# Run specific test case by line number
bundle exec try --verbose try/unit/models/v2/customer_try.rb:42

# Run range of test cases
bundle exec try --verbose try/unit/models/v2/customer_try.rb:42-100
```

### Agent Mode Options
```bash
# Summary only
bundle exec try --agent --agent-focus summary

# Stop at first failure
bundle exec try --agent --agent-focus first-failure

# Critical issues only
bundle exec try --agent --agent-focus critical
```

## Test Categories

### Unit Tests (`unit/`)
Fast, isolated tests that focus on individual components:
- **Models**: Data layer behavior, validation, persistence
- **Logic**: Business rule enforcement, workflows
- **Utils**: Helper functions, formatters, generators
- **Config**: Configuration loading and validation

**Best for**: Demonstrating how individual classes and methods work

### Integration Tests (`integration/`)
Multi-component tests that verify interactions:
- **Middleware**: Request/response processing, middleware stack
- **Authentication**: Login flows, session management
- **Email**: Template rendering, email delivery
- **Web**: View rendering, template processing

**Best for**: Showing how components work together

### System Tests (`system/`)
Full-system tests covering end-to-end scenarios:
- **Routes**: HTTP endpoint smoke tests
- **Database**: Redis operations, migrations, logging
- **Initializers**: Boot process, legacy data detection

**Best for**: Verifying the complete system works

### Disabled Tests (`disabled/`)
Tests temporarily disabled (usually work-in-progress):
- Currently contains domain-related tests being refactored
- Not run by default

### Experimental (`experimental/`)
Proof-of-concept and demonstration code:
- Not part of regular test suite
- Used for exploration and documentation

## Writing Tryouts

### Basic Structure
```ruby
require_relative '../../support/test_helpers'

OT.boot! :test, false

## Test description
code_to_test
#=> expected_result

## Another test
more_code
#=> another_result
```

### Best Practices

1. **Use realistic code**: Tryouts should look like production code
2. **Avoid test DSL**: No `describe`, `it`, `expect` - just plain Ruby
3. **Focus on happy paths**: Save edge cases for RSpec
4. **Document through examples**: Tests are living documentation
5. **Keep it simple**: If you need complex mocking, use RSpec instead

### Expectation Types
- `#=>` : Equality check
- `#==>` : Regular expression match
- `#=:>` : Class/type check
- `#=!>` : Not equal
- See `bundle exec try --help` for full list

## Tryouts vs RSpec

### Use Tryouts For:
- ✅ Model behavior demonstrations
- ✅ Business logic flows
- ✅ Integration scenarios
- ✅ Configuration examples
- ✅ Database operation patterns

### Use RSpec For:
- ✅ Edge cases & error conditions
- ✅ Mock-heavy tests (external services)
- ✅ Performance benchmarks
- ✅ Security validations
- ✅ Complex state machines

## Maintenance

### Adding New Tests
1. Choose appropriate directory based on test type
2. Follow naming convention: `descriptive_name_try.rb`
3. Use correct `require_relative` path to support files:
   - From `unit/models/v2/`: `require_relative '../../../support/test_helpers'`
   - From `integration/email/`: `require_relative '../../support/test_helpers'`
   - From `system/`: `require_relative '../support/test_helpers'`

### Moving Tests
When moving tests between directories:
1. Use `git mv` to preserve history
2. Update `require_relative` paths to match new depth
3. Run `bundle exec try --agent` to verify

## Additional Resources

- **Tryouts Documentation**: Run `bundle exec try --help`
- **Project Testing Guide**: See `/CLAUDE.md` for testing commands
- **RSpec Tests**: Located in `/spec` directory
- **Frontend Tests**: Vitest (`src/`) and Playwright (`tests/e2e/`)
