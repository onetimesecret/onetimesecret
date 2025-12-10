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

### Phase 1: Foundation (Low Risk) ✅ COMPLETED

1. ✅ Add pnpm caching to existing workflow
2. ✅ Add concurrency controls
3. ✅ Consolidate ruby-lint into ci.yml as first job

### Phase 2: Build Artifact Sharing ✅ COMPLETED

1. ✅ Create `build-assets` job
2. ✅ Modify `test-ruby` to download artifacts instead of building
3. ✅ Modify `check-oci-image` to download artifacts
4. ✅ Verify artifact contents are correct

### Phase 3: Test Parallelization

**Goal**: Run independent test suites concurrently to reduce wall-clock time and provide granular failure feedback.

**Current State** (after Phase 2):
- `test-ruby` runs all Ruby tests sequentially: RSpec (simple) → RSpec (full) → tryouts (simple) → tryouts (disabled) → tryouts (full)
- If RSpec simple mode fails, all subsequent tests are skipped
- No visibility into which specific test category failed without reading logs

**Target State**:
- Split into 4 parallel jobs with independent pass/fail status
- Each auth mode runs in its own job with dedicated Redis
- Unit tests separated from integration tests

#### 3.1 New Job Structure

```yaml
# Tier 2: Unit Tests (no Redis required, fast)
ruby-unit:
  needs: [ruby-lint, build-assets]
  # Runs: try/unit, try/system, try/cli, try/security
  # No AUTHENTICATION_MODE needed (tests don't depend on it)

# Tier 3: Integration Tests (Redis required, parallel by auth mode)
ruby-integration-simple:
  needs: [ruby-unit]
  env:
    AUTHENTICATION_MODE: simple
  # Runs: RSpec (filtered), try/integration/authentication/simple_mode, try/integration/authentication/common

ruby-integration-full:
  needs: [ruby-unit]
  env:
    AUTHENTICATION_MODE: full
    AUTH_DATABASE_URL: sqlite::memory:
  # Runs: RSpec (filtered), try/integration/authentication/full_mode, try/integration/authentication/common

ruby-integration-disabled:
  needs: [ruby-unit]
  env:
    AUTHENTICATION_MODE: disabled
  # Runs: try/integration/authentication/disabled_mode, try/integration/authentication/common
```

#### 3.2 Test File Categorization

**Unit tests** (no Redis, no auth mode):
```
try/unit/           # 61 files - Pure unit tests
try/system/         # 11 files - System-level tests (logging, routes)
try/cli/            # 1 file - CLI command tests
try/security/       # 1 file - Security tests
try/features/       # 2 files - Feature tests
spec/onetime/       # 17 files - Config, jobs, migration specs
spec/lib/           # 1 file - Library specs
spec/api/           # 1 file - API logic specs
spec/cli/           # 7 files - CLI specs
```

**Integration tests by auth mode**:
```
# Simple mode
try/integration/authentication/simple_mode/  # 2 files
try/integration/authentication/common/       # 1 file (shared)
spec/integration/ (filtered by tag)

# Full mode
try/integration/authentication/full_mode/    # 9 files
try/integration/authentication/common/       # 1 file (shared)
spec/integration/ (filtered by tag)

# Disabled mode
try/integration/authentication/disabled_mode/ # 1 file
try/integration/authentication/common/        # 1 file (shared)
```

**Other integration tests** (run with simple mode):
```
try/integration/middleware/     # 6 files
try/integration/boot/           # 2 files
try/integration/auth/           # 1 file
try/integration/web/            # 1 file
try/integration/api/            # 6 files
try/integration/email/          # 3 files
try/integration/billing/        # 2 files
```

#### 3.3 RSpec Tag Strategy

**IMPLEMENTED**: RSpec integration tests use auth mode tags for filtering:

| Tag | Usage | Tests That Run |
|-----|-------|----------------|
| `:simple_auth_mode` | Tests for simple mode or mode-agnostic | `dual_auth_mode_spec.rb` (Simple Mode section), `puma_multi_process_spec.rb`, `rhales_migration_spec.rb` |
| `:full_auth_mode` | Tests requiring full auth mode (Rodauth/SQL) | `dual_auth_mode_spec.rb` (Full Mode section), `advanced_auth_mode_spec.rb`, `admin_interface_spec.rb`, `rodauth_hooks_spec.rb` |

Tag examples:

```ruby
# Mode-specific nested context (dual_auth_mode_spec.rb)
RSpec.describe 'Dual Authentication Mode Integration', type: :request do
  describe 'Simple Mode Configuration', :simple_auth_mode do
    # tests simple mode behavior
  end

  describe 'Full Mode - Auth Endpoints', :full_auth_mode do
    # tests full mode behavior
  end
end

# Full mode only spec (advanced_auth_mode_spec.rb)
RSpec.describe 'Full Authentication Mode', :full_auth_mode, type: :integration do
  # skip_unless_mode :full  # Double-safety: skip if mode doesn't match
  # ...
end

# Mode-agnostic spec runs in simple mode job (puma_multi_process_spec.rb)
RSpec.describe 'Puma Multi-Process Integration', :simple_auth_mode, type: :integration do
  # tests that don't depend on auth mode
end
```

CI runs with `--tag` filtering:
```bash
# Simple mode job
bundle exec rspec --tag simple_auth_mode spec/integration/

# Full mode job
bundle exec rspec --tag full_auth_mode spec/integration/
```

#### 3.4 Implementation Steps

1. **Analyze test dependencies**
   - Run each tryout directory in isolation to verify no cross-dependencies
   - Identify any tests that require specific auth modes

2. **Create ruby-unit job**
   - Copy setup steps from test-ruby
   - Run: `bundle exec tryouts try/unit try/system try/cli try/security try/features`
   - Run: `bundle exec rspec spec/onetime spec/lib spec/api spec/cli`
   - No Redis service needed (mock or skip)

3. **Create ruby-integration-simple job**
   - Add Redis service
   - Set `AUTHENTICATION_MODE=simple`
   - Run: `bundle exec rspec --tag auth_mode_simple spec/integration/`
   - Run: `bundle exec tryouts try/integration/authentication/simple_mode try/integration/authentication/common`
   - Run: `bundle exec tryouts try/integration/middleware try/integration/boot try/integration/auth try/integration/web try/integration/api try/integration/email try/integration/billing`

4. **Create ruby-integration-full job**
   - Add Redis service
   - Set `AUTHENTICATION_MODE=full`, `AUTH_DATABASE_URL=sqlite::memory:`
   - Run: `bundle exec rspec --tag auth_mode_full spec/integration/`
   - Run: `bundle exec tryouts try/integration/authentication/full_mode try/integration/authentication/common`

5. **Create ruby-integration-disabled job**
   - Add Redis service
   - Set `AUTHENTICATION_MODE=disabled`
   - Run: `bundle exec tryouts try/integration/authentication/disabled_mode try/integration/authentication/common`

6. **Update check-oci-image dependencies**
   - Change `needs: [test-ruby, test-typescript]`
   - To: `needs: [ruby-integration-simple, ruby-integration-full, ruby-integration-disabled, test-typescript]`

#### 3.5 Expected Timing

| Job | Duration | Runs After |
|-----|----------|------------|
| ruby-unit | ~30-45s | ruby-lint, build-assets |
| ruby-integration-simple | ~45-60s | ruby-unit |
| ruby-integration-full | ~60-90s | ruby-unit |
| ruby-integration-disabled | ~20-30s | ruby-unit |
| **Total wall-clock** | ~2-2.5min | (vs ~1.5min sequential) |

Note: Wall-clock time may increase slightly due to job startup overhead, but failure feedback is much faster and more specific.

#### 3.6 Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Tests have hidden dependencies on auth mode | Run full test suite locally with each mode before splitting |
| Job startup overhead exceeds time savings | Monitor timing; consider combining small jobs if overhead > 20s |
| Redis port conflicts in parallel jobs | Each job has isolated Redis service container |
| RSpec tags missing on some tests | Default untagged tests to run in simple mode |

---

### Phase 4: Path Filtering

**Goal**: Skip irrelevant tests when only specific file types change, reducing CI time for focused changes.

**Current State**:
- All jobs run on every push/PR regardless of what changed
- Changing a single Ruby file triggers TypeScript tests
- Changing only documentation triggers all tests

**Target State**:
- Ruby-only changes skip TypeScript jobs
- TypeScript-only changes skip Ruby jobs
- Documentation-only changes skip all test jobs
- Dockerfile changes trigger container validation

#### 4.1 Path Categories

```yaml
filters:
  ruby:
    - '**/*.rb'
    - 'Gemfile'
    - 'Gemfile.lock'
    - '.rubocop.yml'
    - 'spec/**'
    - 'try/**'
    - 'apps/**'
    - 'lib/**'
    - 'bin/**'

  typescript:
    - 'src/**/*.ts'
    - 'src/**/*.vue'
    - 'src/**/*.tsx'
    - 'package.json'
    - 'pnpm-lock.yaml'
    - 'tsconfig.json'
    - 'vite.config.ts'
    - 'tailwind.config.ts'
    - 'eslint.config.ts'

  frontend-assets:
    - 'src/**'
    - 'public/**'
    - 'package.json'
    - 'pnpm-lock.yaml'
    - 'vite.config.ts'
    - 'tailwind.config.ts'

  docker:
    - 'Dockerfile'
    - 'Dockerfile-lite'
    - 'scripts/entrypoint.sh'
    - 'etc/**'
    - 'config.ru'

  documentation:
    - '**/*.md'
    - 'docs/**'
    - 'LICENSE'
    - '.github/FUNDING.yml'

  ci:
    - '.github/workflows/**'
    - '.github/actions/**'
```

#### 4.2 Job Conditions

```yaml
jobs:
  changes:
    runs-on: ubuntu-latest
    outputs:
      ruby: ${{ steps.filter.outputs.ruby }}
      typescript: ${{ steps.filter.outputs.typescript }}
      frontend-assets: ${{ steps.filter.outputs.frontend-assets }}
      docker: ${{ steps.filter.outputs.docker }}
      ci: ${{ steps.filter.outputs.ci }}
    steps:
      - uses: actions/checkout@v4
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
            frontend-assets:
              - 'src/**'
              - 'public/**'
              - 'vite.config.ts'
            docker:
              - 'Dockerfile*'
              - 'scripts/entrypoint.sh'
              - 'etc/**'
            ci:
              - '.github/**'

  ruby-lint:
    needs: changes
    if: needs.changes.outputs.ruby == 'true' || needs.changes.outputs.ci == 'true'
    # ...

  typescript-lint:
    needs: changes
    if: needs.changes.outputs.typescript == 'true' || needs.changes.outputs.ci == 'true'
    # ...

  build-assets:
    needs: changes
    if: needs.changes.outputs.frontend-assets == 'true' || needs.changes.outputs.ci == 'true'
    # ...

  ruby-unit:
    needs: [changes, ruby-lint, build-assets]
    if: |
      always() &&
      (needs.changes.outputs.ruby == 'true' || needs.changes.outputs.ci == 'true') &&
      (needs.ruby-lint.result == 'success' || needs.ruby-lint.result == 'skipped') &&
      (needs.build-assets.result == 'success' || needs.build-assets.result == 'skipped')
    # ...

  check-oci-image:
    needs: [changes, ruby-integration-simple, ruby-integration-full, ruby-integration-disabled, test-typescript]
    if: |
      always() &&
      (needs.changes.outputs.docker == 'true' || needs.changes.outputs.frontend-assets == 'true' || needs.changes.outputs.ci == 'true') &&
      !contains(needs.*.result, 'failure')
    # ...
```

#### 4.3 Special Cases

**CI workflow changes** (`.github/**`):
- Always run all jobs to validate the workflow itself

**Documentation-only changes**:
- Skip all test jobs
- Optionally run a lightweight "docs-lint" job (markdownlint, link checking)

**Mixed changes** (Ruby + TypeScript):
- Run all jobs (default behavior)

**Force full run**:
- Add `[ci full]` to commit message to bypass path filtering
- Useful for pre-release validation

#### 4.4 Implementation Steps

1. **Add dorny/paths-filter action**
   - Pin to specific version for reproducibility
   - Test filter patterns match expected files

2. **Create changes job**
   - First job in workflow, no dependencies
   - Outputs boolean for each category

3. **Add conditions to existing jobs**
   - Use `if:` conditions referencing changes outputs
   - Handle `skipped` state in dependent jobs

4. **Test path filtering locally**
   - Use `act` tool to simulate GitHub Actions
   - Verify correct jobs run for various change sets

5. **Add force-full mechanism**
   - Check commit message for `[ci full]`
   - Or use workflow_dispatch input

#### 4.5 Expected Savings

| Change Type | Jobs Skipped | Time Saved |
|-------------|--------------|------------|
| Ruby only | typescript-lint, test-typescript | ~1-2 min |
| TypeScript only | ruby-lint, ruby-unit, ruby-integration-* | ~2-3 min |
| Documentation only | All test jobs | ~4-5 min |
| Dockerfile only | ruby-*, typescript-* (runs container only) | ~3-4 min |

#### 4.6 Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Missing path patterns | Start with broad patterns, refine based on false negatives |
| Skipped jobs cause missed regressions | Require full CI run before merge to main |
| Complex `if:` conditions hard to maintain | Extract to reusable workflow or composite action |
| `dorny/paths-filter` breaking changes | Pin to specific SHA, not just version tag |

---

### Phase 5: Composite Actions ✅ COMPLETED

**Goal**: Reduce duplication and improve maintainability by extracting common setup patterns into reusable composite actions.

**PR**: #2146

#### 5.1 Composite Actions Created

Three composite actions in `.github/actions/`:

1. **setup-ruby-test-env**: Ruby environment, artifacts, config, secrets
2. **setup-node-env**: Node.js, pnpm, caching
3. **run-ruby-tests**: Parameterized RSpec/Tryouts execution

#### 5.2 Benefits

- **DRY**: Common setup steps defined once, reused across jobs
- **Maintainability**: Changes to setup logic in one place
- **Consistency**: All jobs use identical setup procedures
- **Readability**: Main workflow file is shorter and clearer

#### 5.3 Implementation

```yaml
# Example usage in ci.yml
- uses: ./.github/actions/setup-ruby-test-env
  with:
    ruby-version: '3.4'
    download-assets: true

- uses: ./.github/actions/run-ruby-tests
  with:
    auth-mode: simple
    test-framework: rspec
```

#### 5.4 YAML Anchors

Used inline YAML anchors to reduce repetition for common values:

```yaml
jobs:
  ruby-unit:
    runs-on: &runs-on ubuntu-24.04
    timeout-minutes: &timeout 15
```

---

### Phase 6: Optimization

**Goal**: Fine-tune the CI pipeline to maximize **developer experience** through faster feedback and clearer failure messages.

**Context**: As a public open-source repository, GitHub Actions minutes are **unlimited and free**. Cost optimization is irrelevant—focus is purely on developer time savings.

**Current State** (after Phase 5):
- Tiered architecture with parallelization
- Path-based filtering reduces unnecessary runs
- Build artifacts shared across jobs
- Composite actions for reusable setup patterns

**Target State**:
- Sub-30s feedback for lint failures
- Sub-3min for full successful run
- Clear, actionable failure messages

#### 6.1 Historical Usage Context

GitHub Actions billing data (public repo = $0 billed):

| Month | Linux Minutes | Gross Cost | Notes |
|-------|--------------|------------|-------|
| Jul 2025 | 6,971 | $55.88 | Baseline |
| Aug 2025 | 6,993 | $56.27 | Stable |
| Sep 2025 | 9,767 | $78.68 | +39% |
| Oct 2025 | 9,759 | $78.56 | Stable |
| Nov 2025 | 25,036 | $202.01 | CI reorganization work |
| Dec 2025 | 5,112 | $41.20 | Back to normal (partial) |

The November spike reflects the cost of developing Phases 1-5—worth it for the improved CI structure. All amounts show $0 billed due to public repo status.

#### 6.2 Optimization Priorities

**Priority: HIGH - Developer Time Savings**

**6.2.1 Faster First-Failure Feedback**

Current: ~45s to first failure
Target: <30s

Focus areas:
- Lint jobs run immediately (no dependencies)
- Composite actions reduce setup boilerplate
- Fail-fast on obvious errors (syntax, type errors)

**6.2.2 Clearer Failure Messages**

Add structured job summaries:

```yaml
- name: Generate failure summary
  if: failure()
  run: |
    echo "## ❌ Test Failures" >> $GITHUB_STEP_SUMMARY
    echo "### Quick Links" >> $GITHUB_STEP_SUMMARY
    echo "- [View full logs](${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }})" >> $GITHUB_STEP_SUMMARY
    if [ -f tmp/rspec_results.json ]; then
      echo "### Failed Examples" >> $GITHUB_STEP_SUMMARY
      jq -r '.examples[] | select(.status == "failed") | "- \(.full_description)"' tmp/rspec_results.json >> $GITHUB_STEP_SUMMARY
    fi
```

**6.2.3 Test Rebalancing**

Analyze test timing to balance parallel jobs:

```bash
# Generate timing report
bundle exec rspec --format json --out timing.json
jq '.examples | group_by(.file_path) | map({file: .[0].file_path, time: (map(.run_time) | add)}) | sort_by(.time) | reverse' timing.json
```

Goal: Each integration job completes within 60-90s of each other.

**Priority: MEDIUM - Reliability**

**6.2.4 Flaky Test Detection**

Add retry with tracking:

```ruby
# spec/spec_helper.rb
RSpec.configure do |config|
  config.around(:each) do |example|
    example.run
    if example.exception
      # Log flaky candidate if it passed on retry
      example.run
      if example.exception.nil?
        File.open('tmp/flaky_tests.log', 'a') { |f| f.puts example.location }
      end
    end
  end
end
```

Track flaky tests over time; quarantine repeat offenders.

**Priority: LOW - Minor Gains**

**6.2.5 Job Startup Reduction**

Current overhead per job:
- Checkout: ~1-2s
- Ruby setup: ~5-10s (with cache)
- Node setup: ~2-3s
- pnpm install: ~6-10s (with cache)
- Artifact download: ~2-5s

Already optimized via composite actions. Further gains require Docker-based runners (complexity not justified).

#### 6.3 Approaches NOT Recommended

**❌ 6.3.1 Incremental Testing**

```yaml
# DON'T DO THIS
files=$(git diff --name-only ${{ github.event.before }} ${{ github.sha }} | grep '\.rb$')
```

Problems:
- `github.event.before` unreliable on force pushes/rebases
- Test file mapping heuristics miss transitive dependencies
- Risk of missed regressions outweighs time savings

**❌ 6.3.2 Test Result Caching**

```yaml
# DON'T DO THIS
key: test-results-${{ hashFiles('**/*.rb', 'spec/**', 'try/**') }}
```

Problems:
- Doesn't account for: env vars, Ruby version, gem updates, config changes
- Can silently skip tests when dependencies change
- False confidence in "green" CI

**❌ 6.3.3 Self-Hosted Runners**

Not recommended because:
- Zero cost benefit (public repo = free minutes)
- Significant maintenance burden
- Security implications for open-source repo
- GitHub-hosted runners are reliable and fast enough

**❌ 6.3.4 Parallel Tests Within Jobs (Tryouts)**

The Tryouts framework does not support parallelization—tests share state via instance variables. RSpec could use `parallel_tests` gem, but added complexity isn't justified given current job durations.

#### 6.4 Implementation Steps

1. **Add failure summaries** (1-2 hours)
   - Structured output for failed tests
   - Links to relevant logs

2. **Collect timing data** (1 week passive)
   - Add timing to job summaries
   - Identify slowest tests/jobs

3. **Rebalance if needed** (2-4 hours)
   - Move slow tests between jobs
   - Target even job durations

4. **Flaky test tracking** (2-4 hours)
   - Add retry logic
   - Log flaky candidates
   - Review weekly

#### 6.5 Success Criteria

| Metric | Current | Target | Method |
|--------|---------|--------|--------|
| First feedback | ~45s | <30s | Lint jobs, composite actions |
| Full pipeline | ~4 min | <3 min | Test rebalancing |
| Failure clarity | Logs only | Structured summary | Job summaries |
| Flaky test rate | Unknown | <1% | Detection + quarantine |

#### 6.6 Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Over-optimization breaks reliability | Keep full test suite; no clever skipping |
| Flaky tests erode confidence | Track, quarantine, fix root causes |
| Job summaries add noise | Keep summaries concise; failures only |

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
