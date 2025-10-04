# Tryouts Test Reorganization Plan

## Current State Analysis

### File Distribution
- **Total tryout files**: 63
- **Root level files**: 31 (49%)
- **Organized in subdirs**: 32 (51%)

### Current Structure Issues
1. **Inconsistent organization**: Half the files in root, half in subdirectories
2. **Mixed numbering schemes**: Some prefixed (10_, 20_, etc.), others not
3. **Unclear categorization**: Files like `72_approximated.rb` have unclear purpose
4. **Disabled tests scattered**: Multiple `*_try_disable.rb` files mixed with active tests

### Existing Categories
- `00_middleware/` - Early middleware tests (4 files)
- `50_middleware/` - Domain strategy middleware (4 files)
- `20_models/` - Model tests with many disabled (6 files)
- `60_logic/` - V2 Logic layer tests (11 files)
- `80_database/` - Database/Redis tests (6 files)
- `initializers/` - Initializer tests (1 file)

## Proposed New Structure

### Design Principles
1. **Mirror application structure** for intuitive navigation
2. **Clear separation** between unit-like tests and integration tests
3. **Group by functionality** not by technical layer
4. **Consistent naming** without unnecessary prefixes
5. **Separate active from disabled/experimental** tests

### Recommended Directory Structure

```
try/
├── unit/                      # Unit-like tests (isolated, fast)
│   ├── models/                # Model behavior tests
│   │   ├── v1/               # Legacy V1 models
│   │   └── v2/               # Current V2 models
│   │       ├── customer_try.rb
│   │       ├── metadata_try.rb
│   │       ├── secret_try.rb
│   │       └── session_try.rb
│   │
│   ├── logic/                 # Business logic tests (V2)
│   │   ├── authentication/
│   │   ├── secrets/
│   │   ├── account/
│   │   └── domains/
│   │
│   ├── utils/                 # Utility class tests
│   │   ├── fortunes_try.rb
│   │   ├── safe_dump_try.rb
│   │   └── value_encryption_try.rb
│   │
│   └── config/                # Configuration tests
│       ├── config_try.rb
│       ├── emailer_config_try.rb
│       ├── passphrase_options_try.rb
│       └── secret_options_try.rb
│
├── integration/               # Integration tests (multiple components)
│   ├── middleware/            # Middleware stack tests
│   │   ├── detect_host_try.rb
│   │   ├── domain_strategy_try.rb
│   │   └── encoding_handlers_try.rb
│   │
│   ├── authentication/        # Auth flow integration
│   │   └── routes_try.rb
│   │
│   ├── email/                 # Email template & sending
│   │   ├── template_try.rb
│   │   └── locale_try.rb
│   │
│   └── web/                   # Web interface tests
│       └── template_vuepoint_try.rb
│
├── system/                    # System-wide tests
│   ├── routes_smoketest_try.rb
│   ├── database/
│   │   ├── redis_debug_try.rb
│   │   ├── redis_migrator_try.rb
│   │   └── database_logger_try.rb
│   │
│   └── initializers/
│       └── detect_legacy_data_try.rb
│
├── disabled/                  # Temporarily disabled tests
│   └── domains/              # All *_try_disable.rb files
│
├── experimental/              # Experimental/demo tests
│   └── approximated_try.rb
│
└── support/                   # Test helpers and fixtures
    ├── test_helpers.rb
    ├── test_logic.rb
    └── test_models.rb
```

## File Mapping (Key Examples)

### Models (try/unit/models/v2/)
- `20_metadata_try.rb` → `metadata_try.rb`
- `21_secret_try.rb` → `secret_try.rb`
- `25_customer_try.rb` → `customer_try.rb`
- `30_session_try.rb`, `31_session_extended_try.rb` → `session_try.rb` (merged)

### Logic (try/unit/logic/)
- `60_logic/01_logic_base_try.rb` → `base_try.rb`
- `60_logic/02_logic_authentication_try.rb` → `authentication/authenticate_session_try.rb`
- `60_logic/03_logic_secrets_try.rb` → `secrets/generate_secret_try.rb`
- `60_logic/21_logic_secrets_show_metadata_try.rb` → `secrets/show_metadata_try.rb`

### Utils (try/unit/utils/)
- `10_utils_try.rb` → `utils_try.rb`
- `10_utils_fortunes_try.rb` → `fortunes_try.rb`
- `19_safe_dump_try.rb` → `safe_dump_try.rb`
- `22_value_encryption_try.rb` → `value_encryption_try.rb`

### Integration Tests
- `40_email_template_try.rb` → `integration/email/template_try.rb`
- `00_middleware/*` → `integration/middleware/`
- `50_middleware/*` → `integration/middleware/domain_strategy/`
- `91_authentication_routes_try.rb` → `integration/authentication/routes_try.rb`

### System Tests
- `90_routes_smoketest_try.rb` → `system/routes_smoketest_try.rb`
- `80_database/*` → `system/database/`
- `initializers/*` → `system/initializers/`

### Disabled Tests
- All `*_try_disable.rb` files → `disabled/` (preserving subdirectory structure)

## RSpec vs Tryouts Allocation

### Keep in Tryouts (Best Fit)
- **Model behavior**: Shows actual usage patterns
- **Business logic flows**: Documents how logic classes work
- **Integration scenarios**: Demonstrates component interaction
- **Configuration examples**: Shows real config usage
- **Database operations**: Documents Redis patterns

### Better in RSpec
- **Edge cases & error conditions**: Need comprehensive coverage
- **Mock-heavy tests**: External service interactions
- **Performance tests**: Need benchmarking harness
- **Security validations**: Need systematic coverage
- **Complex state machines**: Need extensive setup/teardown

### Current RSpec Coverage (Keep As-Is)
- `spec/onetime/config/` - Configuration loading & merging (complex edge cases)
- `spec/onetime/mail/` - Email provider adapters (mock-heavy)
- `spec/unit/puma_multi_process_spec.rb` - Server configuration (environment-specific)

## Migration Strategy

### Phase 1: Create Structure
```bash
# Create new directory structure
mkdir -p try/{unit,integration,system,disabled,experimental,support}
mkdir -p try/unit/{models,logic,utils,config}
mkdir -p try/unit/models/{v1,v2}
mkdir -p try/unit/logic/{authentication,secrets,account,domains}
# ... etc
```

### Phase 2: Move Support Files
```bash
# Move helpers first
mv try/test_*.rb try/support/
```

### Phase 3: Systematic Migration
1. Start with clearly categorized files (models, logic)
2. Move and rename files removing number prefixes
3. Merge related files (e.g., session tests)
4. Update require paths in moved files

### Phase 4: Update Documentation
- Add README.md in try/ explaining structure
- Document tryouts vs RSpec decision criteria
- Update CLAUDE.md with new test locations

## Benefits of New Structure

1. **Discoverability**: Mirror app structure = intuitive navigation
2. **Clarity**: Clear separation of test types
3. **Maintainability**: Disabled tests isolated, not scattered
4. **Scalability**: Room to grow without cluttering root
5. **Documentation**: Tests serve as usage examples in logical locations
6. **Developer Experience**: Follows principle of least astonishment

## Next Steps

1. Review and approve this plan
2. Create migration script to automate moves
3. Update require paths programmatically
4. Run full test suite to verify nothing broken
5. Update CI/CD configurations if needed
6. Document changes in changelog
