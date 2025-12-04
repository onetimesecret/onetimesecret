# Tryouts Test Suite

Tryouts tests organized by scope: unit → integration → system. Plain Ruby code that doubles as documentation.

## Structure

```
try/
├── unit/         # Fast, isolated tests (models, logic, utils, config)
├── integration/  # Multi-component tests (middleware, auth, email, web)
├── system/       # Full-system tests (routes, database, initializers)
├── disabled/     # WIP tests (currently domain features)
├── experimental/ # Demos and POCs
└── support/      # Test helpers (test_helpers.rb, test_logic.rb, test_models.rb)
```

## Running Tests

```bash
# All tests
pnpm run test:tryouts:agent try/

# Specific category
pnpm run test:tryouts:agent try/unit/models/v2/

# Single file
pnpm run test:tryouts:agent try/unit/models/v2/customer_try.rb

# Specific test case with verbose output
pnpm run test:tryouts:failures try/unit/models/v2/customer_try.rb:42
```

## Writing Tests

```ruby
require_relative '../../support/test_helpers'

OT.boot! :test, false

## Test description
code_to_test
#=> expected_result
```

**Tryouts are best for:** Realistic code examples, happy paths, demonstrating how things work.
**Use RSpec for:** Edge cases, mocks, complex state machines, security validation.

See `pnpm run test:tryouts --help` for full options and expectation types (`#=>`, `#==>`, `#=:>`, etc.)
