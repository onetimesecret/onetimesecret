# CI Workflow Reorganization Plan

## Executive Summary

This document proposes a holistic reorganization of the CI workflow to improve developer feedback loops. The primary goals are:

1. **Faster feedback on common failures** - Lint and type errors should fail within 60 seconds
2. **Parallelization** - Run independent test suites concurrently
3. **Resource efficiency** - Build artifacts once, share across jobs
4. **Granular visibility** - Know which specific test category failed without reading logs
5. **Smart filtering** - Skip irrelevant tests when only specific files change

## Current State Analysis

### Workflow Inventory

| Workflow | Trigger | Duration | Purpose |
|----------|---------|----------|---------|
| `ci.yml` | push/PR | ~5 min | Main test suite |
| `ruby-lint.yml` | push/PR | ~33s | Rubocop linting |
| `e2e.yml` | manual | ~3 min | Playwright E2E |
| `codeql.yml` | PR | ~2 min | Security scanning |

### Current ci.yml Structure

```
┌─────────────────────────────────────────────────────────────────┐
│                         PARALLEL                                │
├────────────────────────────┬────────────────────────────────────┤
│       test-ruby            │         test-typescript            │
│       (~1m40s)             │         (~1m06s)                   │
│                            │                                    │
│  1. Checkout               │  1. Checkout                       │
│  2. Setup Ruby             │  2. Setup Node                     │
│  3. Setup Node             │  3. pnpm install                   │
│  4. pnpm install           │  4. Type check                     │
│  5. Build frontend         │  5. Lint                           │
│  6. Bundle install         │  6. Run tests                      │
│  7. RSpec (simple mode)    │  7. Type check tests               │
│  8. RSpec (full mode)      │                                    │
│  9. Tryouts (simple)       │                                    │
│ 10. Tryouts (disabled)     │                                    │
│ 11. Tryouts (full)         │                                    │
└────────────────────────────┴────────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │       check-oci-image         │
              │           (~2m45s)            │
              │                               │
              │  1. Checkout                  │
              │  2. pnpm install              │
              │  3. Build frontend (again!)   │
              │  4. Docker build              │
              │  5. Start container           │
              │  6. Health check              │
              └───────────────────────────────┘
```

### Identified Problems

1. **Sequential bottleneck in test-ruby**: A failure in RSpec (simple mode) skips all subsequent tests including tryouts
2. **Duplicate frontend builds**: Built in `test-ruby`, `check-oci-image`, and `e2e` workflows
3. **No pnpm caching**: Node modules reinstalled fresh each run
4. **Lint runs in separate workflow**: Developer must check two workflow results
5. **All-or-nothing test feedback**: Can't easily see which test category failed
6. **No path-based skipping**: Changing only Ruby files still runs all TypeScript tests

## Proposed Architecture

### Design Principles

1. **Fail fast, fail specific** - Fastest checks run first; failures are isolated to their category
2. **Build once, use many** - Frontend assets built once and shared via artifacts
3. **Parallel by default** - Jobs run concurrently unless they have true dependencies
4. **Progressive confidence** - Each tier increases confidence; earlier tiers gate later ones
5. **Path awareness** - Skip irrelevant checks when possible

### Tier Model

```
                              TIER 0: GATE (~30s)
                    ┌────────────────────────────────────┐
                    │  Quick validation before any work  │
                    │  • Workflow path filtering         │
                    │  • Branch name validation          │
                    └──────────────────┬─────────────────┘
                                       │
          ┌────────────────────────────┼────────────────────────────┐
          │                            │                            │
          ▼                            ▼                            ▼
    TIER 1: LINT              TIER 1: BUILD              TIER 1: LINT
    (~30-45s)                 (~35s)                     (~30-45s)
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   ruby-lint     │      │  build-assets   │      │ typescript-lint │
│                 │      │                 │      │                 │
│ • Rubocop       │      │ • pnpm install  │      │ • ESLint        │
│                 │      │ • vite build    │      │ • Type check    │
│                 │      │ • Upload dist/  │      │                 │
└────────┬────────┘      └────────┬────────┘      └────────┬────────┘
         │                        │                        │
         │               ┌────────┴────────┐               │
         │               │                 │               │
         ▼               ▼                 ▼               ▼
    TIER 2: UNIT TESTS (~45-90s)
┌─────────────────────────────────────────────────────────────────┐
│                          PARALLEL                               │
├─────────────────┬─────────────────┬─────────────────────────────┤
│  ruby-unit      │ typescript-unit │     ruby-rspec-unit         │
│  (tryouts)      │    (vitest)     │                             │
│                 │                 │                             │
│ try/unit        │ src/tests/      │ spec/onetime/               │
│ try/system      │                 │ spec/lib/                   │
└────────┬────────┴────────┬────────┴────────┬────────────────────┘
         │                 │                 │
         └─────────────────┼─────────────────┘
                           │
                           ▼
    TIER 3: INTEGRATION TESTS (~60-120s)
┌─────────────────────────────────────────────────────────────────┐
│                          PARALLEL                               │
├─────────────────┬─────────────────┬─────────────────────────────┤
│  ruby-auth-     │  ruby-auth-     │  ruby-auth-                 │
│  simple         │  full           │  disabled                   │
│                 │                 │                             │
│ • RSpec simple  │ • RSpec full    │ • Tryouts                   │
│ • Tryouts       │ • Tryouts       │   disabled_mode             │
│   simple_mode   │   full_mode     │                             │
│   + common      │   + common      │                             │
└────────┬────────┴────────┬────────┴────────┬────────────────────┘
         │                 │                 │
         ▼                 ▼                 ▼
    TIER 4: CONTAINER VALIDATION (~2-3 min)
┌─────────────────────────────────────────────────────────────────┐
│                       check-oci-image                           │
│                                                                 │
│ • Download pre-built assets                                     │
│ • Docker build                                                  │
│ • Start container                                               │
│ • Health check + smoke test                                     │
└─────────────────────────────────────────────────────────────────┘
```

### Job Definitions

#### Tier 0: Gate (Implicit)

Uses GitHub Actions path filters and concurrency controls:

```yaml
on:
  pull_request:
    paths:
      - '**.rb'
      - '**.ts'
      - '**.vue'
      - 'Gemfile*'
      - 'package.json'
      - 'pnpm-lock.yaml'
      - 'Dockerfile'
      # etc.

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
```

#### Tier 1: Lint & Build

**ruby-lint** (~30s)
- Runs Rubocop
- No dependencies
- Can use existing `ruby-lint.yml` workflow or inline

**build-assets** (~35s)
- Checks out code
- Installs pnpm dependencies (with cache)
- Runs `pnpm build`
- Uploads `public/dist/` as artifact
- This is the ONLY job that builds frontend assets

**typescript-lint** (~30s)
- Runs `pnpm lint`
- Runs `pnpm type-check`
- No test execution

#### Tier 2: Unit Tests

**ruby-unit** (~45s)
- Downloads build artifacts (for any tests that need them)
- Runs `bundle exec tryouts try/unit try/system`
- No Redis required (mocked)
- No auth mode dependency

**typescript-unit** (~45s)
- Downloads build artifacts
- Runs `pnpm test`
- Vitest unit tests only

**ruby-rspec-unit** (~30s)
- Runs RSpec unit tests
- `spec/onetime/`, `spec/lib/`, `spec/api/`
- Fast, isolated tests

#### Tier 3: Integration Tests

Each auth mode runs in parallel with its own Redis service:

**ruby-auth-simple** (~60s)
- `AUTHENTICATION_MODE=simple`
- RSpec integration tests for simple mode
- Tryouts: `try/integration/authentication/simple_mode` + `try/integration/authentication/common`

**ruby-auth-full** (~90s)
- `AUTHENTICATION_MODE=full`
- `AUTH_DATABASE_URL=sqlite::memory:`
- RSpec integration tests for full mode
- Tryouts: `try/integration/authentication/full_mode` + `try/integration/authentication/common`

**ruby-auth-disabled** (~30s)
- `AUTHENTICATION_MODE=disabled`
- Tryouts: `try/integration/authentication/disabled_mode` + `try/integration/authentication/common`

#### Tier 4: Container Validation

**check-oci-image** (~2-3 min)
- Downloads pre-built frontend assets
- Builds Docker image
- Starts container with Redis
- Runs health checks

### Path-Based Filtering

Implement conditional job execution based on changed files:

```yaml
jobs:
  changes:
    runs-on: ubuntu-latest
    outputs:
      ruby: ${{ steps.filter.outputs.ruby }}
      typescript: ${{ steps.filter.outputs.typescript }}
      docker: ${{ steps.filter.outputs.docker }}
    steps:
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
            ruby:
              - '**/*.rb'
              - 'Gemfile*'
              - 'spec/**'
              - 'try/**'
            typescript:
              - 'src/**'
              - 'package.json'
              - 'pnpm-lock.yaml'
              - 'tsconfig.json'
              - 'vite.config.ts'
            docker:
              - 'Dockerfile'
              - 'scripts/entrypoint.sh'
              - 'etc/**'

  ruby-unit:
    needs: [changes, build-assets]
    if: needs.changes.outputs.ruby == 'true'
    # ...
```

### Caching Strategy

#### pnpm Store Cache

```yaml
- name: Get pnpm store directory
  shell: bash
  run: echo "STORE_PATH=$(pnpm store path --silent)" >> $GITHUB_OUTPUT
  id: pnpm-cache

- uses: actions/cache@v4
  with:
    path: ${{ steps.pnpm-cache.outputs.STORE_PATH }}
    key: ${{ runner.os }}-pnpm-store-${{ hashFiles('**/pnpm-lock.yaml') }}
    restore-keys: |
      ${{ runner.os }}-pnpm-store-
```

#### Bundler Cache

Already in place via `bundler-cache: true` in ruby/setup-ruby.

#### Build Artifact Sharing

```yaml
# In build-assets job
- name: Upload build artifacts
  uses: actions/upload-artifact@v4
  with:
    name: frontend-build
    path: public/dist/
    retention-days: 1

# In consuming jobs
- name: Download build artifacts
  uses: actions/download-artifact@v4
  with:
    name: frontend-build
    path: public/dist/
```

### Timing Estimates

| Job | Current | Proposed | Change |
|-----|---------|----------|--------|
| First feedback (any failure) | ~60s | ~30s | -50% |
| Lint complete | N/A (separate) | ~45s | - |
| Unit tests complete | N/A | ~90s | - |
| Integration tests complete | ~100s | ~90s | -10% |
| Full pipeline (success) | ~5 min | ~4 min | -20% |
| Full pipeline (lint fail) | ~5 min | ~30s | -94% |

### Workflow File Structure

Proposed file organization:

```
.github/workflows/
├── ci.yml                    # Main orchestration (triggers other workflows)
├── _build-assets.yml         # Reusable: build frontend
├── _lint-ruby.yml            # Reusable: Rubocop
├── _lint-typescript.yml      # Reusable: ESLint + type-check
├── _test-ruby-unit.yml       # Reusable: tryouts unit + system
├── _test-typescript.yml      # Reusable: Vitest
├── _test-ruby-integration.yml # Reusable: auth mode matrix
├── _check-oci-image.yml      # Reusable: Docker validation
└── e2e.yml                   # Playwright (keep separate, manual)
```

Alternative: Single ci.yml with all jobs defined inline (simpler, but longer file).

## Implementation Phases

### Phase 1: Foundation (Low Risk)

1. Add pnpm caching to existing workflow
2. Add concurrency controls
3. Consolidate ruby-lint into ci.yml as first job

### Phase 2: Build Artifact Sharing

1. Create `build-assets` job
2. Modify `test-ruby` to download artifacts instead of building
3. Modify `check-oci-image` to download artifacts
4. Verify artifact contents are correct

### Phase 3: Test Parallelization

1. Split `test-ruby` into `ruby-unit` and `ruby-integration`
2. Create matrix for auth modes in integration tests
3. Split `test-typescript` into `typescript-lint` and `typescript-unit`
4. Verify all test categories still run

### Phase 4: Path Filtering

1. Add `dorny/paths-filter` action
2. Implement conditional job execution
3. Test with Ruby-only and TypeScript-only changes

### Phase 5: Optimization

1. Analyze timing data from new structure
2. Identify further parallelization opportunities
3. Consider self-hosted runners for faster startup

## Considerations

### Pros

- **Faster feedback**: Lint failures caught in 30s, not 5 minutes
- **Better visibility**: Each job shows pass/fail independently
- **Resource efficiency**: Frontend built once, not three times
- **Parallel execution**: Integration tests for different auth modes run simultaneously
- **Maintainability**: Smaller, focused workflow files

### Cons

- **More jobs to monitor**: 8-10 jobs vs current 3
- **Artifact management**: Need to ensure artifacts are correctly passed
- **Complexity**: More moving parts, more potential failure points
- **Cost**: More parallel jobs may increase billable minutes (though faster overall)

### Risks

1. **Artifact compatibility**: Build artifacts must work across all consuming jobs
2. **Race conditions**: Ensure jobs wait for dependencies correctly
3. **Flaky tests**: Parallelization may expose hidden test interdependencies

### Alternatives Considered

1. **Keep monolithic test-ruby, just add caching**: Faster but doesn't improve feedback granularity
2. **Use GitHub Actions matrix for auth modes only**: Partial improvement, still sequential within matrix
3. **Separate workflows for each tier**: Maximum flexibility but harder to manage dependencies

## Success Metrics

- Time to first failure feedback: Target <45s (currently ~60s)
- Time for lint-only changes: Target <60s (currently ~5 min)
- Total successful pipeline time: Target <4 min (currently ~5 min)
- Job failure isolation: Each test category has its own pass/fail status

## Next Steps

1. Review this plan with stakeholders
2. Decide on single-file vs multi-file approach
3. Implement Phase 1 on a feature branch
4. Measure baseline metrics before further changes
5. Proceed with subsequent phases incrementally
