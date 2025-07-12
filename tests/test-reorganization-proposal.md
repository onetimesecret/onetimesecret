# OneTimeSecret Test Reorganization Proposal

## Current Structure Analysis

### Observed Issues
1. **Mixed numbering schemes** in tryouts (00, 05, 10, etc.) - unclear if execution order or categorization
2. **Test helpers mixed with test files** in tryouts directory
3. **Integration tests mixing languages** - Ruby and TypeScript specs in same directory
4. **Unclear separation** between API and web integration tests
5. **No clear spec directory** at project root (conventional for Ruby projects)

## Proposed New Structure

```
onetimesecret/
├── spec/                          # RSpec tests (Ruby convention)
│   ├── spec_helper.rb
│   ├── .rspec
│   ├── unit/
│   │   ├── apps/                  # Application-specific specs
│   │   ├── middleware/            # Middleware specs
│   │   ├── models/                # Model specs
│   │   └── utils/                 # Utility specs
│   ├── integration/
│   │   ├── api/                   # API integration specs
│   │   └── routes/                # Route integration specs
│   └── support/                   # Shared test helpers
│       ├── fixtures/
│       └── helpers/
│
├── tryouts/                       # Tryouts tests (documentation-as-tests)
│   ├── .tryouts
│   ├── models/                    # Model tryouts
│   │   ├── metadata.try
│   │   ├── secret.try
│   │   ├── customer.try
│   │   └── session.try
│   ├── logic/                     # Business logic tryouts
│   │   ├── encryption.try
│   │   ├── ratelimit.try
│   │   └── authentication.try
│   ├── utils/                     # Utility tryouts
│   │   ├── config.try
│   │   ├── logging.try
│   │   └── fortunes.try
│   └── helpers/                   # Tryout helpers
│       └── test_helpers.rb
│
└── tests/                         # Frontend & E2E tests
    ├── unit/                      # Frontend unit tests
    │   └── vue/
    │       ├── components/
    │       ├── composables/
    │       ├── stores/
    │       ├── utils/
    │       └── setup/             # Test setup files
    │
    ├── integration/               # E2E integration tests
    │   ├── e2e/                   # Playwright E2E tests
    │   │   ├── auth/
    │   │   ├── secrets/
    │   │   └── common/
    │   └── api/                   # API collection tests
    │       └── postman/
    │
    └── fixtures/                  # Shared test fixtures
```

## Migration Strategy

### Phase 1: Directory Structure
1. Create new directory structure
2. Set up configuration files (.rspec, .tryouts)
3. Create helper/support file templates

### Phase 2: RSpec Migration
```bash
# Move RSpec tests to conventional location
mv tests/unit/ruby/rspec/* spec/unit/
mv tests/integration/*.spec.rb spec/integration/

# Update spec_helper.rb paths
# Update require statements in specs
```

### Phase 3: Tryouts Reorganization
```bash
# Reorganize tryouts by domain
mkdir -p tryouts/{models,logic,utils,helpers}

# Move files, removing number prefixes
mv tests/unit/ruby/try/20_metadata_try.rb tryouts/models/metadata_try.rb
mv tests/unit/ruby/try/35_ratelimit_try.rb tryouts/logic/ratelimit_try.rb
# ... continue for all tryout files
```

### Phase 4: Frontend Tests
- Keep Vue unit tests in `tests/unit/vue/` (NO CHANGES)
- Keep E2E tests in `tests/integration/web/` (NO CHANGES)

## File Naming Conventions

### RSpec
- Unit tests: `{class_name}_spec.rb`
- Integration tests: `{feature}_integration_spec.rb`
- Use `instance_double` for strict interface verification
- Use `double` for isolated behavior testing

### Tryouts
- Model tryouts: `{model_name}_try.rb` (keep `_try.rb` suffix)
- Logic tryouts: `{feature}_try.rb`
- No numbering prefixes (use explicit requires if order matters)
- Include comprehensive header comments explaining:
  - What is being tested
  - Why it's important
  - What scenarios are covered

### Frontend (NO CHANGES)
- Unit tests: `{Component}.spec.ts` in `tests/unit/vue/`
- E2E tests: `{feature}-{action}.spec.ts` in `tests/integration/web/`

## Tryout Organization Guidelines

### Header Template for Tryouts
```ruby
# frozen_string_literal: true

# These tryouts test the functionality of [Class/Module Name].
# The [Class/Module] is responsible for [primary responsibility].
#
# We're testing various aspects of [Class/Module], including:
# 1. [First aspect]
# 2. [Second aspect]
# 3. [Third aspect]
#
# These tests aim to ensure that [specific goal], which is crucial
# for [business reason/application function].

require_relative '../helpers/test_helpers'

# Uncomment for debugging
# Familia.debug = true

OT.boot! :test, true
```

### Tryout Syntax Conventions
- Use `##` for test descriptions
- Use `#=>` for expected output
- Keep examples concise and readable
- Focus on demonstrating usage patterns

## Configuration Updates

### .rspec
```
--require spec_helper
--format documentation
--color
```

### spec/spec_helper.rb
```ruby
require 'bundler/setup'
require_relative '../lib/onetime'

RSpec.configure do |config|
  config.include SpecHelpers

  # Load support files
  Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }
end
```

### tryouts/.tryouts
```ruby
# Tryouts configuration
require_relative 'helpers/test_helpers'

# Set up test environment
ENV['RACK_ENV'] = 'test'
```

## Benefits

1. **Clear Separation** - RSpec for behavior testing, Tryouts for documentation/examples
2. **Conventional Structure** - Follows Ruby community standards
3. **Better Organization** - Tests grouped by type and domain
4. **Easier Navigation** - Logical file placement
5. **Improved Maintainability** - Clear where new tests should go
6. **Better Tool Integration** - IDEs and tools expect conventional structures

## Migration Checklist

- [ ] Create new directory structure
- [ ] Update CI/CD pipelines for new test paths
- [ ] Migrate RSpec tests
- [ ] Reorganize Tryouts (remove number prefixes)
- [ ] Update require paths in all test files
- [ ] Update test runner configurations
- [ ] Update documentation/README files
- [ ] Update .gitignore if needed
- [ ] Run full test suite to verify
- [ ] Update developer onboarding docs

## Current Directory Mapping

Based on the analysis, here's how the current numbered tryout files would map to the new structure:

### Tryouts Mapping
```
# Current → New Location (keeping .rb extension)
00_middleware/* → tryouts/middleware/
05_logging*.rb → tryouts/utils/logging_try.rb
10_*utils*.rb → tryouts/utils/
11_cached_method_try.rb → tryouts/utils/cached_method_try.rb
15_config_try.rb → tryouts/config/config_try.rb
16_config_*.rb → tryouts/config/
17_mail_validation.rb → tryouts/utils/mail_validation_try.rb
19_safe_dump_try.rb → tryouts/utils/safe_dump_try.rb
20_metadata*.rb → tryouts/models/metadata_try.rb
20_models/* → tryouts/models/
21_secret_try.rb → tryouts/models/secret_try.rb
22_value_encryption_try.rb → tryouts/logic/encryption_try.rb
23_app_settings_try.rb → tryouts/config/app_settings_try.rb
23_passphrase_try.rb → tryouts/logic/passphrase_try.rb
25_customer_try.rb → tryouts/models/customer_try.rb
26_email_receipt_try.rb → tryouts/logic/email_receipt_try.rb
30_session*.rb → tryouts/models/session_try.rb
35_ratelimit_try.rb → tryouts/logic/ratelimit_try.rb
40_email_template*.rb → tryouts/templates/
42_web_template_vuepoint_try.rb → tryouts/templates/vuepoint_try.rb
50_middleware/* → tryouts/middleware/
50_subdomain_try.rb → tryouts/logic/subdomain_try.rb
60_logic/* → tryouts/logic/
68_receive_feedback_try.rb → tryouts/logic/receive_feedback_try.rb
72_approximated.rb → tryouts/utils/approximated_try.rb
75_stripe_event_try.rb → tryouts/logic/stripe_event_try.rb
90_routes_smoketest_try.rb → tryouts/integration/routes_smoketest_try.rb
91_authentication_routes_try.rb → tryouts/integration/authentication_routes_try.rb
99_truemail_config_try.rb → tryouts/config/truemail_try.rb

# Helper files
test_*.rb → tryouts/helpers/
```

### RSpec Mapping
```
# Current structure already mostly follows conventions
tests/unit/ruby/rspec/* → spec/unit/*
tests/integration/*.spec.rb → spec/integration/*
```

### Frontend Tests (NO CHANGES)
```
# Keep exactly as-is
tests/unit/vue/* → tests/unit/vue/*
tests/integration/web/* → tests/integration/web/*
```
