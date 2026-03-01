# OT.conf String Key Migration - Inventory & Plan

**Date:** 2025-11-21
**Goal:** Migrate all `OT.conf` access from symbol keys to string keys comprehensively
**Reason:** Standardize on string keys for consistency with external data formats and enable automated migration

## Current State Analysis

### Summary Statistics
- **Total `.dig()` calls:** 33 (all using symbols)
- **Total `.fetch()` calls:** 15 (all using symbols)
- **Total bracket `[]` calls:** ~50+ (mostly symbols in tests)
- **Estimated total lines to change:** ~90-110

### Symbol Key Usage Breakdown

#### 1. `.dig()` Method (33 occurrences)

**Pattern:** `OT.conf.dig(:symbol1, :symbol2, ...)`
**Target:** `OT.conf.dig('string1', 'string2', ...)`

##### Production Files (23):
```
lib/onetime/helpers/homepage_mode_helpers.rb:39
  OT.conf.dig('site', 'interface', 'ui')

lib/onetime/initializers/print_log_banner.rb:17
  OT.conf.dig('site', 'secret_options')

lib/onetime/initializers/connect_databases.rb:8
  OT.conf.dig(:redis, :dbs)
  apps/web/core/controllers/account.rb:45
    OT.conf.dig('site', 'plans')

  apps/web/core/controllers/account.rb:67
    OT.conf.dig('site', 'authentication')

  apps/web/core/controllers/helpers.rb:89
  OT.conf.dig(:experimental, :csp, :enabled)

apps/web/core/controllers/helpers.rb:123
  OT.conf.dig(:development, :enabled)
  apps/web/core/application.rb:25
    OT.conf.dig('site', 'interface', 'ui', 'enabled')

  apps/api/v1/logic/authentication/authenticate_session.rb:15
    OT.conf.dig('site', 'authentication', 'colonels')

  apps/api/v1/logic/secrets/base_secret_action.rb:23
    OT.conf.dig('site', 'secret_options', 'passphrase')

  apps/api/v1/logic/secrets/generate_secret.rb:18
    OT.conf.dig('site', 'secret_options', 'password_generation')

  apps/api/v1/models/custom_domain.rb:45
    OT.conf.dig('site', 'host')

  apps/api/v1/controllers/helpers.rb:63
  OT.conf.dig(:experimental, :csp, :enabled)

apps/api/v1/controllers/helpers.rb:97
  OT.conf.dig(:development, :enabled)
  apps/api/v2/logic/account/create_account.rb:78
    OT.conf.dig('site', 'authentication', 'colonels')

  apps/api/v2/logic/account/create_account.rb:79
    OT.conf.dig('site', 'authentication', 'allowed_signup_domains')

  apps/api/v2/logic/authentication/authenticate_session.rb:15
    OT.conf.dig('site', 'authentication', 'colonels')

  apps/api/v2/logic/secrets/base_secret_action.rb:23
    OT.conf.dig('site', 'secret_options', 'passphrase')

  apps/api/v2/logic/secrets/generate_secret.rb:18
    OT.conf.dig('site', 'secret_options', 'password_generation')

  apps/api/v2/logic/welcome.rb:45
    OT.conf.dig('site', 'plans', 'webook_signing_secret')

  apps/api/v2/logic/feedback.rb:34
    OT.conf.dig('site', 'authentication', 'colonels')

  apps/api/v2/logic/feedback.rb:67
    OT.conf.dig('site', 'authenticity', 'secret_key')

  apps/api/v2/models/custom_domain.rb:45
    OT.conf.dig('site', 'host')

  apps/api/v2/controllers/challenges.rb:23
    OT.conf.dig('site', 'authenticity', 'secret_key')

apps/api/v2/controllers/helpers.rb:63
  OT.conf.dig(:experimental, :csp, :enabled)

apps/api/v2/controllers/helpers.rb:97
  OT.conf.dig(:development, :enabled)
```

##### Test Files (10):
```
tests/unit/ruby/try/17_passphrase_validation_try.rb:7
tests/unit/ruby/try/60_logic/02_logic_base_try.rb (3 instances)
tests/unit/ruby/try/16_config_passphrase_options_try.rb (3 instances)
```

#### 2. `.fetch()` Method (15 occurrences)

**Pattern:** `OT.conf.fetch(:symbol, default)`
**Target:** `OT.conf.fetch('string', default)`

```
lib/onetime/mail/views/base.rb:45
  OT.conf.fetch(:emailer, {})

lib/onetime/middleware/domain_strategy.rb:12
  OT.conf.fetch(:site, {})

lib/onetime/initializers/load_locales.rb:8
  OT.conf.fetch(:internationalization, {})

lib/onetime/initializers/load_locales.rb:9
  OT.conf.fetch(:locales, ['en'])

lib/onetime/initializers/print_log_banner.rb:8
  OT.conf.fetch(:site)

lib/onetime/initializers/print_log_banner.rb:9
  OT.conf.fetch(:emailer, {})

lib/onetime/initializers/print_log_banner.rb:34
  OT.conf.fetch(key, false)  # key is symbol from array

apps/web/core/views/helpers/initialize_view_vars.rb:46
  OT.conf.fetch(:site, {})

apps/web/core/views/helpers/initialize_view_vars.rb:47
  OT.conf.fetch(:incoming, {})

apps/web/core/views/helpers/initialize_view_vars.rb:48
  OT.conf.fetch(:development, {})

apps/web/core/views/helpers/initialize_view_vars.rb:49
  OT.conf.fetch(:diagnostics, {})

apps/api/v1/logic/base.rb:23
  OT.conf.fetch(:site, {})

apps/api/v2/logic/colonel/get_colonel_info.rb:12
  OT.conf.fetch(:site, {})

apps/api/v2/logic/base.rb:23
  OT.conf.fetch(:site, {})

apps/api/v2/logic/account/get_account.rb:34
  OT.conf.fetch(:site, {})
```

#### 3. Bracket `[]` Access (50+ occurrences)

**Pattern:** `OT.conf[:symbol][:nested]`
**Target:** `OT.conf['string']['nested']`

Mostly in test files:
```
tests/unit/ruby/try/17_mail_validation.rb
tests/unit/ruby/try/35_ratelimit_try.rb
tests/unit/ruby/try/17_passphrase_validation_try.rb
tests/unit/ruby/try/60_logic/24_logic_destroy_account_try.rb
tests/unit/ruby/try/68_receive_feedback_try.rb
tests/unit/ruby/try/16_config_emailer_try.rb (many instances)
tests/unit/ruby/try/15_config_try.rb (many instances)
```

#### 4. `.key?()` Method (1 occurrence)

```
tests/unit/ruby/try/16_config_passphrase_options_try.rb:10
  OT.conf.key?(:site)
```

### Secondary Hash Access

After retrieving config sections, nested access also uses symbols:
```ruby
site_config = OT.conf.fetch(:site, {})
value = site_config[:authentication][:enabled]  # These also need migration
```

## Migration Strategy

### Phase 1: Revert Recent Symbol Change (IMMEDIATE)
- Revert commit 4bae0232 that changed `homepage_mode_helpers.rb` to symbols
- This file was already correct with string keys before

### Phase 2: Automated Find & Replace
Use regex-based transformation for bulk changes:

#### A. `.dig()` Method
```bash
# Pattern: OT.conf.dig(:word1, :word2, ...)
# Replace: OT.conf.dig('word1', 'word2', ...)

find . -name "*.rb" -type f -exec sed -i.bak \
  's/OT\.conf\.dig(\([^)]*\))/OT.conf.dig(\1)/g; s/:\([a-z_][a-z0-9_]*\)/'"'"'\1'"'"'/g' {} \;
```

#### B. `.fetch()` Method
```bash
# Pattern: OT.conf.fetch(:word, default)
# Replace: OT.conf.fetch('word', default)

find . -name "*.rb" -type f -exec sed -i.bak \
  's/OT\.conf\.fetch(:\([a-z_][a-z0-9_]*\)/OT.conf.fetch('"'"'\1'"'"'/g' {} \;
```

#### C. Bracket `[]` Access
```bash
# Pattern: OT.conf[:word]
# Replace: OT.conf['word']

find . -name "*.rb" -type f -exec sed -i.bak \
  's/OT\.conf\[:\([a-z_][a-z0-9_]*\)\]/OT.conf['"'"'\1'"'"']/g' {} \;
```

#### D. `.key?()` Method
```bash
# Pattern: OT.conf.key?(:word)
# Replace: OT.conf.key?('word')

find . -name "*.rb" -type f -exec sed -i.bak \
  's/OT\.conf\.key\?(:\([a-z_][a-z0-9_]*\))/OT.conf.key?('"'"'\1'"'"')/g' {} \;
```

### Phase 3: Manual Review Checklist

**Critical files requiring manual verification:**

1. **lib/onetime/helpers/homepage_mode_helpers.rb** - Just fixed, needs revert
2. **apps/web/core/views/helpers/initialize_view_vars.rb** - View vars, frontend-facing
3. **lib/onetime/initializers/*.rb** - Bootstrap code, critical
4. **apps/api/v*/logic/authentication/*.rb** - Security-critical
5. **apps/api/v*/logic/secrets/*.rb** - Secret handling, security-critical

### Phase 4: Test & Validate

**Test Coverage:**
```bash
# Run all tests
bundle exec ruby try.rb

# Specific config tests
bundle exec ruby try.rb tests/unit/ruby/try/15_config_try.rb
bundle exec ruby try.rb tests/unit/ruby/try/16_config_emailer_try.rb
bundle exec ruby try.rb tests/unit/ruby/try/16_config_passphrase_options_try.rb
```

**Manual Verification:**
```bash
# Start server and check logs
UI_HOMEPAGE_MODE=internal UI_HOMEPAGE_MATCHING_CIDRS=127.0.0.0/24 \
  DEBUG_HTTP=1 ONETIME_DEBUG=1 bundle exec puma -p 7143

# Verify homepage mode works
curl http://localhost:7143/

# Check config loading in console
bundle exec ruby -I lib -r onetime -e "puts OT.conf['site']['authentication'].inspect"
```

### Phase 5: YAML Config Migration & Loader Change

**CRITICAL:** The config is loaded with symbol keys at the YAML level!

**Current Implementation (lib/onetime/config.rb:113):**
```ruby
def load(path=nil)
  path ||= self.path
  raise ArgumentError, "Bad path (#{path})" unless File.readable?(path)
  parsed_template = ERB.new(File.read(path))
  YAML.load(parsed_template.result)  # ← Creates symbol keys from :key notation!
end
```

**YAML Files (etc/defaults/config.defaults.yaml):**
```yaml
:site:        # Symbol notation → creates {site: ...} (symbol key)
  :host: foo
```

**To use string keys, we need THREE changes:**

#### A. Update YAML Loader (lib/onetime/config.rb)
```ruby
def load(path=nil)
  path ||= self.path
  raise ArgumentError, "Bad path (#{path})" unless File.readable?(path)
  parsed_template = ERB.new(File.read(path))

  # Load with string keys instead of symbols
  # YAML.safe_load defaults to string keys
  YAML.safe_load(parsed_template.result, aliases: true, permitted_classes: [Symbol])
end
```

**Note:** `YAML.safe_load` defaults to string keys. `YAML.load` creates symbols for `:key` notation.

#### B. Update YAML Files
Convert from symbol notation to string notation:
```bash
# Before (etc/defaults/config.defaults.yaml):
:site:
  :host: example.com
  :authentication:
    :enabled: true

# After:
site:
  host: example.com
  authentication:
    enabled: true
```

**Migration Script (for all YAML files):**
```bash
# Remove leading colons from YAML keys
find etc/ -name "*.yaml" -type f -exec sed -i.bak 's/^  *:\([a-z_][a-z0-9_]*\):/  \1:/g' {} \;
```

#### C. Update deep_clone Method (lib/onetime/config.rb:364)

The comment explicitly mentions avoiding JSON because it converts to strings - **we WANT that now!**

**Current:**
```ruby
def deep_clone(config_hash)
  # JSON is another option but it turns all the symbol keys into strings
  YAML.load(YAML.dump(config_hash))
end
```

**Option 1 (Stay with YAML, ensure string keys):**
```ruby
def deep_clone(config_hash)
  YAML.safe_load(YAML.dump(config_hash), aliases: true)
end
```

**Option 2 (Use JSON for guaranteed strings - RECOMMENDED):**
```ruby
require 'json'

def deep_clone(config_hash)
  # Explicitly convert to strings via JSON round-trip
  JSON.parse(JSON.generate(config_hash))
end
```

#### D. Update DEFAULTS constant (lib/onetime/config.rb:10-83)

The `DEFAULTS` hash also uses symbol keys and gets merged with loaded config:

**Current:**
```ruby
DEFAULTS = {
  site: {
    secret: nil,
    domains: { enabled: false },
  }
}
```

**Must change to:**
```ruby
DEFAULTS = {
  'site' => {
    'secret' => nil,
    'domains' => { 'enabled' => false },
  }
}
```

## Risk Assessment

### Low Risk:
- Test files (can be fixed after production)
- Development-only features (`:development`, `:experimental`)
- Non-critical features (`:diagnostics`, `:incoming`)

### Medium Risk:
- View serializers (affects frontend, well-tested)
- Rate limiting (`:limits`)
- Email configuration (`:emailer`)

### High Risk:
- Authentication (`:authentication`, `:colonels`)
- Secret options (`:secret_options`, `:passphrase`)
- Database connections (`:redis`, `:dbs`)
- Core site config (`:site`)

## Rollback Strategy

1. **Git branch:** Create `feature/string-keys-migration`
2. **Keep backups:** sed creates `.bak` files automatically
3. **Atomic commit:** Single commit for easy revert
4. **Staged rollout:** Test in development → staging → production
5. **Feature flag:** None needed (no runtime toggle)

## Implementation Timeline

1. **Phase 1:** Revert recent change (homepage_mode_helpers.rb) - 5 min
2. **Phase 2:** Automated Ruby code replacement (dig, fetch, []) - 15 min
3. **Phase 3:** Manual review of critical files - 30 min
4. **Phase 4:** Update YAML loader & deep_clone - 15 min
5. **Phase 5:** Update DEFAULTS constant (75 lines) - 20 min
6. **Phase 6:** Convert YAML files (etc/*.yaml) - 10 min
7. **Phase 7:** Testing (unit + integration) - 45 min
8. **Total:** ~2.5 hours

## Success Criteria

- [ ] YAML loader (config.rb) uses YAML.safe_load for string keys
- [ ] deep_clone method ensures string keys
- [ ] DEFAULTS constant uses string keys
- [ ] All YAML config files use string-style keys (no :colons)
- [ ] All `OT.conf` access in Ruby code uses string keys
- [ ] All tests pass (unit + integration)
- [ ] Server starts without errors
- [ ] Homepage mode functionality works
- [ ] Authentication works (critical)
- [ ] Secret creation works (critical)
- [ ] No deprecation warnings
- [ ] Config can be loaded from console successfully

## Comprehensive Test Plan

```bash
# 1. Unit tests
bundle exec ruby try.rb tests/unit/ruby/try/15_config_try.rb
bundle exec ruby try.rb tests/unit/ruby/try/16_config_emailer_try.rb
bundle exec ruby try.rb tests/unit/ruby/try/16_config_passphrase_options_try.rb

# 2. Console verification
bundle exec ruby -I lib -r onetime -e "
  Onetime.boot!(:cli)
  puts 'Config loaded successfully'
  puts 'Site host: ' + OT.conf['site']['host'].to_s
  puts 'Auth enabled: ' + OT.conf['site']['authentication']['enabled'].to_s
"

# 3. Server start
bundle exec puma -p 7143 -t 2:4 -w 0 -e development

# 4. Homepage mode test
UI_HOMEPAGE_MODE=internal UI_HOMEPAGE_MATCHING_CIDRS=127.0.0.0/24 \
  ONETIME_DEBUG=1 bundle exec puma -p 7143
# Verify logs show homepage mode detection

# 5. API test
curl -X POST http://localhost:7143/api/v2/generate \
  -H "Content-Type: application/json" \
  -d '{"secret":"test123","ttl":300}'
```

## Notes

- This is a **BREAKING CHANGE** affecting:
  - YAML config files (syntax change)
  - Ruby code accessing OT.conf (symbol → string)
  - Any external code/plugins accessing OT.conf
  - Config loading mechanism (YAML.load → YAML.safe_load)
- **Migration path:** Users must update their etc/config.yaml files
- **Automated migration:** Provide yq/sed script for users
- Consider making OT.conf use HashWithIndifferentAccess for forward compatibility
- Document the breaking change in CHANGELOG.md with migration instructions
- Update developer documentation to specify string keys as standard
- Add deprecation notices in previous release if possible
