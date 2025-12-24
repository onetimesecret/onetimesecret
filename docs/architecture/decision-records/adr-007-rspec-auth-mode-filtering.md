---
id: 007
status: accepted
title: ADR-007: RSpec Authentication Mode Filtering Strategy
---

## Status
Accepted

## Date
2025-12-23

## Context

The test suite includes integration tests that must run under different authentication modes (simple, full, disabled). Each mode has fundamentally different runtime behavior - different database backends, different authentication mechanisms, and different feature availability.

Three mechanisms existed for filtering tests by authentication mode:

1. **Environment variable** (`AUTHENTICATION_MODE=simple|full|disabled`)
   - Controls runtime behavior (database selection, auth adapter configuration)
   - Used in spec_helper.rb exclusion filters to skip tests at runtime

2. **RSpec tags** (`:simple_auth_mode`, `:full_auth_mode`, `:disabled_auth_mode`)
   - Applied to test files and describe blocks
   - Used with `--tag` CLI flag for load-time filtering

3. **Directory structure** (`spec/integration/authentication/{simple_mode,full_mode,disabled_mode}/`)
   - Organizational only, no functional role
   - Visual grouping of related tests

The critical distinction that emerged: **load-time filtering vs runtime filtering**.

- **`--tag` filtering (load-time)**: RSpec never loads files without matching tags. Faster, uses less memory, files must be explicitly tagged.

- **ENV var filtering (runtime)**: RSpec loads all files, then uses before hooks and exclusion filters to skip non-matching examples. Slower, more memory, works with untagged tests via exclusion logic.

The existing implementation used both mechanisms redundantly:
```bash
RACK_ENV=test AUTHENTICATION_MODE=simple bundle exec rspec --tag simple_auth_mode
```

This created confusion about which mechanism was actually responsible for filtering, and whether both were necessary.

## Decision

**Use both mechanisms, but with clear separation of concerns:**

1. **RSpec tags control load-time filtering**
   - All integration tests must have explicit auth mode tags
   - Package.json scripts use `--tag` for efficient load-time filtering
   - Directory structure auto-assigns tags via `define_derived_metadata` (when implemented)

2. **Environment variable controls runtime behavior**
   - Sets up correct database connections
   - Configures authentication adapters
   - Installs appropriate mocks via before hooks
   - Does NOT perform exclusion filtering (that's the tag's job)

3. **Directory structure provides organizational clarity**
   - Groups related tests visually
   - Can automatically assign tags via metadata derivation
   - No direct functional role in filtering

**Implementation requirements:**

- Remove ENV-based exclusion filters from spec_helper.rb (lines 167-174 as of 2025-12-23)
- Keep ENV var for runtime configuration
- Keep `--tag` filtering for load-time efficiency
- Implement directory-based auto-tagging via `define_derived_metadata`
- All integration tests must have explicit mode tags or `:all_auth_modes`

## Consequences

### Positive

- Clear separation: tags = load-time filter, ENV = runtime config
- Faster test execution: only matching files are loaded
- Less memory usage: unneeded test files never enter memory
- Explicit tagging requirement prevents untagged tests from being forgotten
- Auto-tagging from directories reduces manual tagging burden

### Negative

- Requires discipline to tag all new integration tests
- Two mechanisms still exist (can't eliminate either without losing benefits)
- Directory-based auto-tagging requires metadata derivation setup
- Migration work needed to remove existing ENV-based exclusion filters

### Neutral

- Complexity is irreducible given the requirement for both load-time and runtime filtering
- The tag/ENV combination is justified by their distinct purposes
- Documentation burden remains similar (just needs clarification of roles)

## Implementation Notes

### Migration Steps (2025-12-23)

1. **Remove ENV-based exclusion filtering:**
   ```ruby
   # DELETE from spec/spec_helper.rb lines 167-174
   current_mode = ENV.fetch('AUTHENTICATION_MODE', 'simple').to_sym
   config.filter_run_excluding simple_auth_mode: true unless current_mode == :simple
   config.filter_run_excluding full_auth_mode: true unless current_mode == :full
   config.filter_run_excluding disabled_auth_mode: true unless current_mode == :disabled
   ```

2. **Keep ENV var for runtime config:**
   - Leave before hooks that install mocks based on ENV
   - Keep database URL configuration logic
   - Maintain authentication adapter selection

3. **Implement directory-based auto-tagging:**
   ```ruby
   # Add to spec/spec_helper.rb
   config.define_derived_metadata(
     file_path: %r{spec/integration/authentication/(simple_mode|full_mode|disabled_mode)}
   ) do |metadata|
     mode = metadata[:file_path].match(%r{/(simple_mode|full_mode|disabled_mode)/})[1]
     tag_name = mode.sub('_mode', '_auth_mode').to_sym
     metadata[tag_name] = true
   end
   ```

4. **Package.json scripts remain unchanged:**
   - Continue using `--tag` for load-time filtering
   - Continue setting `AUTHENTICATION_MODE` for runtime config
   - Both serve distinct, necessary purposes

### Known Issues

- `spec/integration/dual_auth_mode_spec.rb` has no top-level tag and will fail the tag enforcement check
- Resolution: Split into separate files or add `:all_auth_modes` with nested `skip_unless_mode` helpers
