# Handoff: Container E2E Boot Failure Investigation

**Branch:** `fix/2267-container-e2e-boot-failure`
**Created:** 2025-12-26
**Status:** RESOLVED

## Resolution

**Root Cause:** `PrintLogBanner` initializer was missing a dependency on `:familia_config`.

The initializer calls `Familia.dbclient.info` (line 49) to display Redis version in the startup banner, but it only depended on `:logging`. This caused it to potentially run before `ConfigureFamilia`, which sets `Familia.uri` from the `REDIS_URL` environment variable.

Without this dependency, `Familia.uri` defaulted to `redis://127.0.0.1:6379`, causing connection failures in Docker environments where Redis/Valkey runs on a different host.

**Fix:** Added `:familia_config` to `PrintLogBanner`'s dependencies in `lib/onetime/initializers/print_log_banner.rb`:

```ruby
# Before
@depends_on = [:logging]

# After
@depends_on = [:logging, :familia_config]
```

**Commit:** `1745fbb1a` - "[#2267] Fix container E2E boot failure - add Familia dependency"

## Problem Statement

The `container-e2e-tests` job in CI is failing. The Docker container starts but the application never becomes ready, causing a 120-second timeout waiting for `/health` or `/` to respond.

**Last successful develop CI:** Dec 24, 2025 (PR #2259 - "Replace custom Ruby i18n with ruby-i18n gem")

## What We Know

### CI Failure Pattern
```
container-e2e-tests → Wait for application to be ready → timeout (exit code 124)
```

The workflow waits for either endpoint to respond:
```bash
until curl -f -s http://localhost:3000/health > /dev/null 2>&1 || \
      curl -f -s http://localhost:3000/ > /dev/null 2>&1; do
```

Neither responds within 120 seconds.

### Likely Root Cause

The app starts but `Onetime.boot!` fails, leaving `Onetime.ready?` as false. The `StartupReadiness` middleware then returns 503 for all requests. Since `curl -f` fails on HTTP errors (4xx/5xx), the health check never succeeds.

**Key file:** `lib/onetime/middleware/startup_readiness.rb:104-105`
```ruby
def call(env)
  return @app.call(env) if Onetime.ready?
  # ... returns 503 if not ready
```

### Recent Changes That Could Affect Boot

1. **PR #2264** - "Implement Kubernetes-style boot state model for test isolation"
   - Changed `ready?` from `@ready == true` to `boot_state == BOOT_STARTED`
   - Added boot state constants: `BOOT_NOT_STARTED`, `BOOT_STARTING`, `BOOT_STARTED`, `BOOT_FAILED`
   - Modified `lib/onetime/boot.rb` significantly

2. **PR #2259** - "Replace custom Ruby i18n with ruby-i18n gem" (last green CI)
   - This was the last working state

### What Was Fixed in This Session

1. **Integration test locale configuration** (merged in PR #2266)
   - `auth_mode_spec.rb` and `rhales_migration_spec.rb` were using deprecated `OT.instance_variable_set(:@supported_locales, ...)`
   - Fixed to use `Onetime::Runtime.internationalization = ...`
   - These tests now pass locally

2. **Billing test helper architecture** (merged in PR #2266)
   - Separated framework-agnostic helpers from RSpec-specific code
   - Files now in `apps/web/billing/lib/test_support/` and `apps/web/billing/spec/support/`

## Investigation Steps for Next Developer

### 1. Get Container Logs (Critical First Step)

Either trigger CI with debug enabled:
```bash
gh workflow run e2e.yml --ref develop -f debug=true
```

Or test locally:
```bash
# Build the image
docker build -t ots-test .

# Start Redis
docker run -d --name redis-test -p 6379:6379 redis:7

# Start app with same env as CI
docker run -d --name ots-test \
  --link redis-test:redis \
  -p 3000:3000 \
  -e REDIS_URL=redis://redis:6379/0 \
  -e SECRET=$(openssl rand -hex 32) \
  -e HOST=localhost:3000 \
  -e SSL=false \
  -e RACK_ENV=production \
  ots-test

# Check logs immediately
docker logs -f ots-test
```

### 2. Check Boot State

If you can get a shell into the container:
```ruby
# In Rails console or irb with app loaded
Onetime.boot_state  # Should be :started
Onetime.ready?      # Should be true
Onetime.boot_error  # Should be nil
```

### 3. Compare Working vs Broken

```bash
# Diff between last green (2259) and current
git diff 6d8431fb0..develop -- lib/onetime/boot.rb
git diff 6d8431fb0..develop -- config.ru
```

### 4. Potential Issues to Check

1. **Boot state not transitioning to STARTED**
   - Check if any initializer is failing silently
   - Check if `@boot_state` is being set correctly

2. **Missing environment variables**
   - CI doesn't set `AUTHENTICATION_MODE` (defaults to 'simple')
   - Check if any new required env vars were added

3. **Initializer order/dependency issues**
   - `lib/onetime/initializers/` files run in dependency order
   - A failing initializer could leave boot incomplete

4. **Runtime state not initialized**
   - `Onetime::Runtime.internationalization` must be set for locales to work
   - Check `LoadLocales` initializer

## Files to Focus On

| File | Purpose |
|------|---------|
| `lib/onetime/boot.rb` | Boot process and state management |
| `lib/onetime/middleware/startup_readiness.rb` | Returns 503 if not ready |
| `config.ru` | Calls `Onetime.boot! :app` |
| `lib/onetime/initializers/*.rb` | Individual boot steps |
| `.github/workflows/e2e.yml` | CI workflow definition |
| `Dockerfile` | Container build |

## Quick Verification Commands

```bash
# Run unit tests (should pass)
RACK_ENV=test AUTHENTICATION_MODE=simple timeout 90 bundle exec rspec spec/unit

# Run integration tests (should pass after PR #2266 fixes)
RACK_ENV=test AUTHENTICATION_MODE=simple timeout 120 bundle exec rspec spec/integration/simple

# Test boot locally in production mode
RACK_ENV=production SECRET=test123 HOST=localhost:3000 SSL=false bundle exec ruby -e "require './config/boot'; Onetime.boot! :app; puts Onetime.ready?"
```

## Success Criteria

1. `container-e2e-tests` CI job passes
2. App responds on `/` within reasonable time (< 30s)
3. `Onetime.ready?` returns true after boot
4. No regressions in other CI jobs

## Notes

- The Ruby integration tests (T3 jobs) also have some failures but those are separate issues (postgres infrastructure, VCR cassettes)
- Focus on getting the container to boot first, then address other CI issues
