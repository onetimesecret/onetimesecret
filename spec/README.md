# RSpec Test Suite

Tests are organized by authentication mode. Each mode runs in a separate process.

## Modes

| Mode       | Description                       |
| ---------- | --------------------------------- |
| `simple`   | Redis-only sessions               |
| `full`     | Rodauth with SQLite or PostgreSQL |
| `disabled` | Public access only                |

## Running Tests

```bash
# Via rake (recommended)
bundle exec rake spec:integration:simple
bundle exec rake spec:integration:full
bundle exec rake spec:integration:disabled
bundle exec rake spec:integration:all        # all modes

# Via pnpm
pnpm test:rspec:integration:simple
pnpm test:rspec:integration:full
pnpm test:rspec:integration:disabled
```

See `lib/tasks/spec.rake` for all available tasks.

## Adding Tests

Place test files in the directory matching the required mode:

```
spec/integration/simple/    # AUTHENTICATION_MODE=simple
spec/integration/full/      # AUTHENTICATION_MODE=full
spec/integration/disabled/  # AUTHENTICATION_MODE=disabled
spec/integration/all/       # runs in every mode
```

Example:

```ruby
# spec/integration/full/my_feature_spec.rb
RSpec.describe "My Feature", type: :integration do
  # Runs in full mode because it's in full/
end
```

No explicit mode tags needed—directory determines the mode.

## RSpec or Tryouts

Model and library behavior is covered by both `spec/unit` and `try/unit`. The
deciding question is whether the test has to alter process-shared state and
restore it afterwards. Tryouts run every file in one process and cannot undo a
`prepend` or a reopened class, so anything that instruments a Familia model, a
frozen index object, or a library class to observe a call belongs in RSpec,
where stubs are per example and restored on every exit path. Stub the
app-level accessor to return a delegator over the real object rather than
patching the object itself; see
`spec/unit/onetime/models/custom_domain/destroy_canonical_release_spec.rb`.
A linear scenario over real records with no stubs stays a tryout. The full
rule is in `try/README.md`.

Unit specs may hit the real datastore. Tag them `:datastore` so a reader knows
they do; the tag is descriptive only, `spec_helper` does nothing with it. What
makes such specs safe is the lane runner's per-run Valkey DB index, not the
tag, so run them through `tests/lanes/run`, never bare `rspec`.

## Debugging

```bash
# Dry run
bundle exec rspec spec/integration/simple spec/integration/all --dry-run

# Single file
RACK_ENV=test AUTHENTICATION_MODE=full AUTH_DATABASE_URL='sqlite::memory:' \
  bundle exec rspec spec/integration/full/infrastructure_spec.rb
```

## References

- `docs/adr/adr-007-test-process-boundaries.md` — why directory-based separation
- `try/README.md` — when a test is a tryout and when it is a spec
- `lib/tasks/spec.rake` — rake task definitions
- `spec/support/` — test helpers and shared contexts
