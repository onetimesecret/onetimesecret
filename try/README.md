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
itself), not a bare `bundle exec try`. The parser reads each file with plain
`File.read`, so under a non-UTF-8 locale — `LANG`/`LC_ALL` unset, as in a plain
`env -i` shell or some CI images — the source is tagged US-ASCII and any
non-ASCII byte the parser has to `strip` raises `invalid byte sequence in
US-ASCII`, dropping the whole file. Indented comments and code lines are the
ones that reach that path (a comment starting at column 0 does not); 22 of these
files qualify.

The run still exits non-zero, so CI cannot go green on it, but the report reads
as if it had: `65 testcases passed, 0 failed in 3 files` with
`files_under_test: 2` and a `Syntax Errors` block below the context, or `2 of 2
files passed` in the default formatter. The dropped file's tests are counted
nowhere. `test:tryouts` pins `RUBYOPT=-EUTF-8` so the encoding no longer depends
on the caller's environment. Upstream: delano/tryouts#76.

## Datastore isolation

Every tryout process connects to the test valkey on 127.0.0.1:2163, never a
dev/prod service, and the DB index is per-worktree: `tests/lanes/run` derives
and exports `LANES_DATASTORE_DB` (#4168), and for raw invocations
`try/support/test_helpers.rb` derives an equivalent index from the checkout
path itself. Without that, every raw run in every worktree shared DB 0 with
each other and with interactive rspec runs (which flush it), so a multi-file
run's exact-count assertions on global keys (`colonel_audit_event:events`,
`session:*` scans) failed nondeterministically whenever anything else was
writing. Two runs that collide on one index abort loudly via the
`_lanes:owner` marker; the one case nothing detects is two concurrent raw
runs in the SAME worktree, which share by construction.

Two scope limits. The isolation covers VALKEY ONLY: a raw run still points
`AUTH_DATABASE_URL` at the shared `onetime_auth_test` — only the lane runner
rewrites that to the per-worktree `onetime_auth_test_w<index>` — so full-mode
tryouts touching the auth DB are not isolated by this. And the derived index
lives outside `pnpm run test:database:clean`'s old `${LANES_DATASTORE_DB:-0}`
default, which is why that script now resolves the index through
`try/support/datastore_db.rb` (the derivation's single home, shared with
test_helpers); pin `LANES_DATASTORE_DB=0` to sweep the legacy shared DB
instead.

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
