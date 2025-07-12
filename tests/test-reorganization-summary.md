# Test Reorganization Executive Summary

## Current State
Your test structure currently has:
- **Ruby tests** nested deeply under `tests/unit/ruby/` with separate `rspec/` and `try/` subdirectories
- **Tryout files** with numeric prefixes (00-99) that appear to indicate grouping rather than execution order
- **Frontend tests** properly organized under `tests/unit/vue/` and `tests/integration/web/`
- **No root-level `spec/` directory** (conventional for Ruby projects)
- **Tests currently failing** due to recent code restructuring

## Key Recommendations

### 1. Adopt Conventional Root Structure
```
onetimesecret/
├── spec/           # Ruby RSpec tests (NEW)
├── tryouts/        # Tryouts tests (NEW)
└── tests/          # Frontend/E2E tests (NO CHANGE)
```

### 2. Organize by Domain, Not Numbers
Replace numeric prefixes with semantic directories:
- `20_metadata_try.rb` → `tryouts/models/metadata_try.rb`
- `35_ratelimit_try.rb` → `tryouts/logic/ratelimit_try.rb`
- `90_routes_smoketest_try.rb` → `tryouts/integration/routes_smoketest_try.rb`

### 3. Keep Extensions Consistent
- Tryouts keep `.rb` extension (e.g., `metadata_try.rb`)
- Frontend tests remain unchanged in `tests/`

## Benefits of This Approach

1. **Industry Standard** - Follows Ruby community conventions
2. **Tool Compatibility** - IDEs and CI tools expect `spec/` directory
3. **Clear Purpose** - Each directory has a distinct role
4. **Better Discovery** - Easier to find tests by domain
5. **Simpler CI** - No need for complex `find` commands

## Implementation Today

1. **Create Structure**
   ```bash
   mkdir -p spec/{unit,integration,support}
   mkdir -p tryouts/{models,logic,utils,config,middleware,templates,integration,helpers}
   ```

2. **Move Files** - Use git mv to preserve history

3. **Update Paths** - Fix require statements and CI configuration

4. **Verify** - Run test commands to ensure paths work

## Risk Assessment

- **Low Risk**: Tests already failing, so can't break what's already broken
- **High Reward**: Better organization should help fix tests faster
- **Qualitative Success**: Easier navigation and maintenance

This reorganization will make your test suite more maintainable, discoverable, and aligned with Ruby ecosystem standards while preserving the unique benefits of your dual testing approach.
