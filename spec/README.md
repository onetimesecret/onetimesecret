# RSpec Test Suite

Tests are organized by authentication mode. Each mode runs in a separate process.

## Modes

| Mode | Description |
|------|-------------|
| `simple` | Redis-only sessions |
| `full` | Rodauth with SQLite or PostgreSQL |
| `disabled` | Public access only |

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
RSpec.describe 'My Feature', type: :integration do
  # Runs in full mode because it's in full/
end
```

No explicit mode tags needed—directory determines the mode.

## Debugging

```bash
# Dry run
bundle exec rspec spec/integration/simple spec/integration/all --dry-run

# Single file
RACK_ENV=test AUTHENTICATION_MODE=full AUTH_DATABASE_URL='sqlite::memory:' \
  bundle exec rspec spec/integration/full/infrastructure_spec.rb
```

## References

- `docs/architecture/decision-records/adr-007-test-process-boundaries.md` — why directory-based separation
- `lib/tasks/spec.rake` — rake task definitions
- `spec/support/` — test helpers and shared contexts
