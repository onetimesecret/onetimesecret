# Configuration System Reference - OneTimeSecret

**PROCESSING NOTE**: Content up to "Schema Structure Deep Dive" section contains CRITICAL context for immediate decisions. Content below that section provides detailed reference material - consult only when specific implementation details are needed.


## 🚨 CRITICAL: Schema Validation & Security Boundaries

### Schema-Based Validation System
OneTimeSecret uses a **two-stage validation pattern** for configuration:

1. **Stage 1: Schema Validation** (Declarative)
   - JSON Schema defines structure, types, and defaults
   - Located at `etc/schemas/config.schema.json`
   - Validates YAML structure before any processing
   - Applies default values automatically

2. **Stage 2: Business Processing** (Imperative)
   - Init.d scripts modify config for business logic
   - Located in `etc/init.d/*.rb`
   - Runs AFTER schema validation, BEFORE final freeze
   - Handles dynamic values, security checks, feature flags

### Security-Critical Configuration Paths

#### FORBIDDEN - Never Expose to Frontend
```yaml
site.secret: "CHANGEME"          # Global encryption key
storage.db.connection.url        # Redis credentials
mail.connection.pass             # SMTP password
```

#### Init.d Script Security Example (`etc/init.d/site.rb`)
```ruby
# CRITICAL: Global secret validation
global_secret = config.fetch('secret', nil)
global_secret = nil if global_secret.to_s.strip == 'CHANGEME'

if global_secret.nil? && !allow_nil
  abort 'Global secret cannot be nil - set SECRET env var or site.secret in config'
end

# Store in state, NOT in config that goes to frontend
OT.state['global_secret'] = global_secret
```

### Config-to-Frontend Data Flow

```
YAML → ERB → Configurator → Init Scripts → UIContext → JSON → window.onetime
  ↓      ↓        ↓             ↓            ↓         ↓          ↓
Disk  Template  Schema     Business    Security   Browser    Vue.js
      Render   Validate    Processing  Filter    Injection  Access
```

**Security Boundary**: UIContext filters ALL sensitive data before frontend exposure

## 📋 Init.d Script System - Dynamic Configuration

### Purpose & Execution Order
Init.d scripts modify configuration during boot, similar to Unix init scripts:

1. Scripts correspond to top-level config sections (e.g., `site.rb` → `site:` config)
2. Execute during config processing phase with mutable config
3. Run BEFORE config is frozen
4. Can access other sections via `global` (read-only) and modify own section via `config`

### Available Variables in Scripts
```ruby
global  # Complete frozen config (all sections) - READ ONLY
config  # Mutable config for THIS section only - READ/WRITE

# Example from site.rb:
allow_nil = global.dig('experimental', 'allow_nil_global_secret')
config['authentication']['enabled'] = false  # Modify current section
```

### Common Init.d Patterns

#### Feature Flag Derivation
```ruby
# diagnostics.rb - Derive d9s_enabled from config presence
has_dsn = config.dig('sentry', 'dsn').present?
logging = config.dig('sentry', 'logErrors')
OT.state['d9s_enabled'] = has_dsn && logging
```

#### Authentication Consistency
```ruby
# site.rb - Disable sub-features when main feature is off
if config.dig('authentication', 'enabled') != true
  config['authentication'].each_key do |key|
    config['authentication'][key] = false
  end
end
```

## 🔄 Configuration Pipeline Details

### 1. Environment Variable Normalization
```ruby
# ENV vars override config values
ONETIME_SITE_HOST=example.com → site.host: "example.com"
ONETIME_SITE_SSL=true → site.ssl: true
```

### 2. ERB Template Processing
```erb
# config.yaml can use ERB for dynamic values
site:
  host: <%= ENV.fetch('SITE_HOST', 'localhost:3000') %>
  secret: <%= ENV['SECRET'] || SecureRandom.hex(32) %>
```

### 3. Schema Validation with Defaults
```json
// config.schema.json snippet
"host": {
  "default": "localhost:3000",
  "type": "string"
}
```

### 4. Init Script Processing
Each section's init script runs with access to:
- Frozen complete config (`global`)
- Mutable section config (`config`)
- Boot context (mode, instance info)

### 5. Final Validation & Deep Freeze
- Re-validate against schema after init scripts
- Deep freeze entire configuration
- Configuration becomes immutable

## 🎯 Configuration Sections Quick Reference

### Core Sections with Init Scripts
- **site.rb**: Authentication, secret validation, colonels management
- **storage.rb**: Database connections, Redis configuration
- **mail.rb**: Email validation, SMTP settings
- **logging.rb**: HTTP request logging configuration
- **i18n.rb**: Locale settings, translation paths
- **diagnostics.rb**: Sentry integration, error tracking
- **experimental.rb**: Feature flags, A/B testing

### Key Configuration Patterns

#### Capabilities System
```yaml
capabilities:
  anonymous:
    api: false
    email: false
    custom_domains: false
  authenticated:
    api: true
    email: true
    custom_domains: false
```

#### Feature Flags
```yaml
features:
  domains:
    enabled: true
  regions:
    enabled: false
```

---

## 📑 Schema Structure Deep Dive (Detailed Reference)

### Schema Organization
The configuration schema (`etc/schemas/config.schema.json`) is a JSON Schema (draft 2020-12) that defines:
- Required top-level sections
- Type constraints for each field
- Default values
- Validation patterns (e.g., email format)
- Conditional requirements

### Key Schema Features

#### Default Value Application
```json
"site": {
  "properties": {
    "host": {
      "default": "localhost:3000",
      "type": "string"
    }
  }
}
```
If `site.host` is not specified in YAML, the default is applied during validation.

#### Pattern Validation
```json
"email": {
  "type": "string",
  "format": "email",
  "pattern": "^(?!\\.)(?!.*\\.\\.)([A-Za-z0-9_'+\\-\\.]*)[A-Za-z0-9_+-]@([A-Za-z0-9][A-Za-z0-9\\-]*\\.)+[A-Za-z]{2,}$"
}
```

#### Enum Constraints
```json
"capabilities": {
  "propertyNames": {
    "enum": ["anonymous", "authenticated", "standard", "enhanced"]
  }
}
```

## 📂 Init.d Script Examples

### Complete `site.rb` Walkthrough
```ruby
# 1. Access other sections via 'global'
allow_nil = global.dig('experimental', 'allow_nil_global_secret') || false

# 2. Validate critical security settings
global_secret = config.fetch('secret', nil)
global_secret = nil if global_secret.to_s.strip == 'CHANGEME'

# 3. Abort on security violations
if global_secret.nil? && !allow_nil && !OT.mode?(:cli)
  abort 'Global secret cannot be nil - set SECRET env var or site.secret in config'
end

# 4. Store sensitive data in state (not config)
OT.state['global_secret'] = global_secret

# 5. Enforce consistency rules
if config.dig('authentication', 'enabled') != true
  config['authentication'].each_key do |key|
    config['authentication'][key] = false
  end
end

# 6. Handle legacy config migration
legacy_colonels = config.fetch('colonels', [])
modern_colonels = config.dig('authentication', 'colonels') || []
config['authentication']['colonels'] = (modern_colonels + legacy_colonels).compact.uniq
```

### State vs Config Storage
- **Config**: Data that can be exposed to frontend (after filtering)
- **State**: Sensitive runtime data that must NEVER reach frontend

```ruby
# WRONG - Exposes secret to frontend
config['secret'] = generate_secret()

# RIGHT - Keeps secret in backend-only state
OT.state['secret'] = generate_secret()
```

## 🔐 UIContext & Frontend Integration

### UIContext Class Structure
The `UIContext` class (`lib/onetime/services/ui/ui_context.rb`) is responsible for:
1. Loading configuration
2. Merging with user session data
3. Filtering sensitive information
4. Generating `window.onetime` data

### Data Transformation Pipeline
```ruby
def build_onetime_window_data(req, sess, cust, locale_override)
  # 1. Extract safe config sections
  site = OT.conf.fetch('site', {})

  # 2. Apply security filters
  authentication = site.fetch('authentication', {})
  # Never include: site['secret']

  # 3. Derive feature flags
  jsvars[:d9s_enabled] = diagnostics_enabled?

  # 4. Add user-specific data
  if authenticated
    jsvars[:custid] = cust.custid
    jsvars[:email] = cust.email
  end

  # 5. Return filtered data
  jsvars
end
```

### Security Filtering Implementation
```ruby
# UIContext never accesses these paths:
FORBIDDEN_PATHS = [
  [:site, :secret],
  [:storage, :db, :connection, :url],
  [:mail, :connection, :pass]
]
```

## 🧪 Testing & Validation Patterns

### Configuration Test Patterns
```ruby
RSpec.describe 'Configuration validation' do
  it 'applies schema defaults' do
    config = Onetime::Configurator.new.load!
    expect(config[:site][:host]).to eq('localhost:3000')
  end

  it 'validates required fields' do
    expect {
      Onetime::Configurator.new(config_path: 'invalid.yaml').load!
    }.to raise_error(OT::ConfigValidationError)
  end
end
```

### Init Script Testing
```ruby
RSpec.describe 'Init script processing' do
  it 'modifies config during boot' do
    config = load_config_with_init_scripts

    # Test that authentication sub-features are disabled
    expect(config[:site][:authentication][:enabled]).to eq(false)
    expect(config[:site][:authentication][:signin]).to eq(false)
  end
end
```

### Integration Test Example
```ruby
it 'filters sensitive data from UIContext' do
  ui_context = UIContext.new(req, sess, cust)
  window_data = ui_context.to_frontend_json

  # Verify secrets are filtered
  expect(window_data).not_to include('secret')
  expect(window_data).not_to include('password')
end
```

## 🔧 Troubleshooting Guide

### Common Configuration Errors

#### 1. Schema Validation Failures
```
Error: Configuration validation failed: site.host: type mismatch
```
**Solution**: Check data types match schema expectations

#### 2. Missing Required Fields
```
Error: Required field 'site.secret' not found
```
**Solution**: Ensure all required fields are present or have ENV overrides

#### 3. Init Script Failures
```
Error: Init script site.rb failed: undefined method
```
**Solution**: Check Ruby syntax and available methods in init context

### Debug Techniques

#### Enable Verbose Logging
```bash
ONETIME_DEBUG=1 bundle exec app
```

#### Inspect Processed Config
```ruby
# In console
pp OT.conf.to_h
```

#### Trace Init Script Execution
```ruby
# Add to init script
OT.info "[init] Processing #{config.keys}"
```

### Migration from Old Config Format

#### Old Format
```yaml
:site:
  :secret: <%= ENV['SECRET'] %>
  :host: localhost:3000
```

#### New Format
```yaml
site:
  secret: <%= ENV['SECRET'] %>
  host: localhost:3000
```

**Key Changes**:
- No leading colons on keys
- Proper YAML syntax (not Ruby hash syntax)
- Schema validation enforced

### Performance Considerations

#### Configuration Loading
- Schema validation adds ~50ms to boot time
- Init scripts add ~10ms per script
- Deep freeze adds ~5ms

#### Optimization Tips
1. Minimize ERB template usage
2. Keep init scripts focused
3. Cache configuration in development
4. Use schema defaults instead of init script defaults
