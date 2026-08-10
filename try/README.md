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

Run tryouts through these scripts (or `tests/lanes/run`, which pins the locale
itself), not a bare `bundle exec try`. The parser reads each file with
`File.read`, so under a non-UTF-8 locale — `LANG`/`LC_ALL` unset, as in a plain
`env -i` shell or some CI images — every file containing a non-ASCII character
(an em-dash in a comment is enough, and ~165 of these files have one) fails to
parse with `invalid byte sequence in US-ASCII`. Tryouts reports that file under
`Syntax Errors` but still **exits 0** when the others pass, so the run reads as
green with the file silently dropped; only the `files_under_test` count gives it
away. `test:tryouts` pins `RUBYOPT=-EUTF-8` so the encoding no longer depends on
the caller's environment.

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
