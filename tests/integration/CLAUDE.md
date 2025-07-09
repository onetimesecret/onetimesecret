# Integration Testing Guidelines - Config to Frontend Data Flow

**PROCESSING NOTE**: Content up to "Quick Reference Index" contains CRITICAL context for immediate testing decisions. Content below "Detailed Implementation Guidelines" provides detailed reference material - consult only when specific implementation details are needed.

## CRITICAL: End-to-End Data Flow Security

### Security Boundary Rules (MUST VERIFY)
```
YAML Config → Configurator → Init Scripts → UIContext → JSON → window.onetime
     ↓              ↓            ↓          ↓         ↓         ↓
  Secrets       Process       Filter    SECURITY   Browser   Type-safe
  Present      & Derive     Sections   BOUNDARY   Parsing     Access
```

**CRITICAL VALIDATION**: At UIContext stage, ALL sensitive data MUST be filtered:
```ruby
# These keys MUST exist in config but NEVER appear in UIContext/JSON/window:
SENSITIVE_KEYS = %w[
  database_password redis_password stripe_secret_key mail_password global_secret
  aws_secret_key stripe_webhook_secret sentry_server_dsn jwt_secret
]

# Integration test MUST verify each boundary:
SENSITIVE_KEYS.each do |key|
  expect(config_contains_path?(config, key)).to be_true    # Present in config
  expect(ui_context.to_s).not_to include(key)             # NOT in UIContext
  expect(JSON.generate(ui_context)).not_to include(key)   # NOT in JSON
end
```

### Cross-Boundary Validation Rules

#### 1. Feature Flag Consistency (CRITICAL)
Feature flags MUST be derived consistently from config values:
```ruby
# d9s_enabled = Sentry DSN present AND logging enabled
dsn_present = config.dig(:diagnostics, :sentry, :dsn).present?
logging_on = config.dig(:diagnostics, :sentry, :logErrors) == true
expect(ui_context[:d9s_enabled]).to eq(dsn_present && logging_on)

# domains_enabled = domains.enabled AND custom_domains present
domains_on = config.dig(:domains, :enabled) == true
has_domains = config.dig(:domains, :custom_domains).present?
expect(ui_context[:domains_enabled]).to eq(domains_on && has_domains)
```

#### 2. JSON Serialization Safety (CRITICAL)
ALL data MUST survive JSON round-trip without type corruption:
```ruby
json_string = JSON.generate(ui_context)
parsed = JSON.parse(json_string)

# Booleans MUST remain booleans (not strings/nil)
%w[authenticated d9s_enabled domains_enabled].each do |field|
  expect(parsed[field]).to be_in([true, false])
end

# Numbers MUST remain numbers (not strings)
expect(parsed.dig('secret_options', 'default_ttl')).to be_a(Numeric)

# Arrays MUST remain arrays (not nil/strings)
expect(parsed['supported_locales']).to be_a(Array)
```

#### 3. Authentication State Validation (CRITICAL)
Authentication config MUST flow consistently to frontend:
```ruby
# Config values MUST match UIContext exactly
auth_config = config.dig(:site, :authentication)
ui_auth = ui_context[:authentication]

%w[enabled signin signup autoverify].each do |field|
  expect(ui_auth[field.to_sym]).to eq(auth_config[field.to_sym])
end

# User state MUST be complete and type-safe
if session_exists?
  expect(ui_context[:authenticated]).to eq(true)
  expect(ui_context[:custid]).to match(/^[a-z0-9]{24}$/)
  expect(ui_context[:email]).to match(/@/)
else
  expect(ui_context[:authenticated]).to eq(false)
  expect(ui_context[:custid]).to be_nil
  expect(ui_context[:email]).to be_nil
end
```

## Quick Reference Index

### Detailed Sections Below:
- **User State Variations** (Line 106): Anonymous vs Authenticated user contexts
- **JSON Serialization Details** (Line 146): Type preservation and safety checks
- **Cross-Branch Compatibility** (Line 191): Migration and version-agnostic helpers
- **Performance Testing** (Line 247): UIContext generation benchmarks
- **Error Condition Handling** (Line 277): Graceful degradation scenarios
- **Maintenance Guidelines** (Line 306): Adding new fields and debugging

### Key Test Helpers:
- `test_json_serialization_safety()` - Validates type preservation
- `extract_authentication_config()` - Cross-version config extraction
- `validate_ui_context_structure()` - Version-agnostic validation
- `test_ui_context_generation_performance()` - Performance benchmarks

---

## Detailed Implementation Guidelines

### User State Variations

#### Anonymous User Integration
```ruby
# When no session/authentication:
user_context = simulate_anonymous_user_context(config)

required_anonymous_fields = {
  authenticated: false,
  custid: nil,
  email: nil,
  customer_since: nil,
  is_paid: false
}

required_anonymous_fields.each do |field, expected_value|
  expect(user_context[field]).to eq(expected_value),
    "Anonymous user #{field} should be #{expected_value}"
end
```

#### Authenticated User Integration
```ruby
# When user session present:
user_context = simulate_authenticated_user_context(config, customer_data)

required_authenticated_fields = {
  authenticated: true,
  custid: customer_data[:custid],
  email: customer_data[:email],
  customer_since: customer_data[:created_at].iso8601,
  is_paid: customer_data[:plan_type] != 'anonymous'
}

required_authenticated_fields.each do |field, expected_value|
  expect(user_context[field]).to eq(expected_value),
    "Authenticated user #{field} should be #{expected_value}"
end
```

### JSON Serialization Details

#### Type Safety Through Serialization
```ruby
def test_json_serialization_safety(ui_context)
  # Test round-trip serialization
  json_string = JSON.generate(ui_context)
  parsed_back = JSON.parse(json_string)

  # Critical type preservation checks:
  boolean_fields = %w[authenticated d9s_enabled domains_enabled regions_enabled plans_enabled]
  boolean_fields.each do |field|
    original = ui_context[field.to_sym]
    roundtrip = parsed_back[field]
    expect(roundtrip).to be_in([true, false]), "#{field} not boolean after JSON roundtrip"
    expect(roundtrip).to eq(original), "#{field} value changed during JSON roundtrip"
  end

  # Numeric field preservation:
  numeric_fields = %w[secret_options.default_ttl]
  numeric_fields.each do |field_path|
    original = ui_context.dig(*field_path.split('.').map(&:to_sym))
    roundtrip = parsed_back.dig(*field_path.split('.'))
    expect(roundtrip).to be_a(Numeric), "#{field_path} not numeric after JSON roundtrip"
  end

  # Array field preservation:
  array_fields = %w[secret_options.ttl_options supported_locales messages]
  array_fields.each do |field_path|
    original = ui_context.dig(*field_path.split('.').map(&:to_sym))
    roundtrip = parsed_back.dig(*field_path.split('.'))
    expect(roundtrip).to be_a(Array), "#{field_path} not array after JSON roundtrip"
  end
end
```

### Cross-Branch Compatibility Testing

#### Configuration Path Migration
```ruby
# Test helper that works across config structure changes:
def extract_authentication_config(config)
  # Try new structure first:
  new_path = config.dig(:site, :authentication)
  return new_path if new_path.present?

  # Fall back to old structure:
  old_path = config.dig(:authentication)
  return old_path if old_path.present?

  # Default fallback:
  { enabled: false, signin: false, signup: false, autoverify: false }
end

def extract_diagnostics_config(config)
  # New structure:
  new_path = config.dig(:diagnostics, :sentry)
  return new_path if new_path.present?

  # Old structure:
  old_path = config.dig(:sentry)
  return old_path if old_path.present?

  # Default:
  { dsn: nil, logErrors: false, trackComponents: false }
end
```

#### Version-Agnostic Validation
```ruby
# Tests that work across different implementation versions:
def validate_ui_context_structure(ui_context)
  # Structure tests (version-agnostic):
  expect(ui_context).to be_a(Hash)
  expect(ui_context[:authentication]).to be_a(Hash)
  expect(ui_context[:secret_options]).to be_a(Hash)
  expect(ui_context[:messages]).to be_a(Array)

  # Presence tests (required regardless of version):
  required_keys = %w[authenticated locale ot_version shrimp]
  required_keys.each do |key|
    expect(ui_context).to have_key(key.to_sym), "Missing required key: #{key}"
  end

  # Type tests (must be consistent regardless of values):
  expect(ui_context[:authenticated]).to be_in([true, false])
  expect(ui_context[:locale]).to be_a(String)
  expect(ui_context[:ot_version]).to be_a(String)
  expect(ui_context[:shrimp]).to be_a(String)
end
```

### Performance Integration Testing

#### UIContext Generation Performance
```ruby
def test_ui_context_generation_performance(config)
  # Measure UIContext generation time:
  start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  ui_context = generate_ui_context(config, user_session)

  end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  generation_time = (end_time - start_time) * 1000 # Convert to ms

  expect(generation_time).to be < 100, "UIContext generation too slow: #{generation_time}ms"

  # Measure JSON serialization time:
  start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  json_string = JSON.generate(ui_context)

  end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  serialization_time = (end_time - start_time) * 1000

  expect(serialization_time).to be < 50, "JSON serialization too slow: #{serialization_time}ms"

  # Size validation:
  expect(json_string.bytesize).to be < 50_000, "UIContext JSON too large: #{json_string.bytesize} bytes"
end
```

### Error Condition Integration

#### Graceful Degradation Testing
```ruby
def test_missing_config_sections(incomplete_config)
  # Test with deliberately incomplete config:
  ui_context = generate_ui_context(incomplete_config, nil)

  # Should not crash, should provide sensible defaults:
  expect(ui_context[:authentication][:enabled]).to be_in([true, false])
  expect(ui_context[:d9s_enabled]).to be_in([true, false])
  expect(ui_context[:locale]).to be_a(String)
  expect(ui_context[:supported_locales]).to be_a(Array)
  expect(ui_context[:supported_locales]).not_to be_empty
end

def test_database_unavailable_scenario
  # Simulate database connection failure:
  allow(Customer).to receive(:find).and_raise(ActiveRecord::ConnectionNotEstablished)

  ui_context = generate_ui_context(config, authenticated_session)

  # Should fall back to anonymous user data:
  expect(ui_context[:authenticated]).to eq(false)
  expect(ui_context[:cust]).to be_nil
  expect(ui_context[:is_paid]).to eq(false)
end
```

### Integration Test Maintenance

#### Adding New Configuration Fields
When adding new config → UIContext mappings:

1. **Add to config schema validation**
2. **Add UIContext transformation logic**
3. **Add security filtering test**
4. **Add JSON serialization test**
5. **Add cross-branch compatibility helper**
6. **Update required keys list**

#### Debugging Integration Failures
Common failure patterns:

1. **Missing config path**: Check if init scripts modified config structure
2. **Type mismatch**: Verify JSON serialization preserves types
3. **Security leak**: Ensure sensitive data filtered at UIContext stage
4. **Performance regression**: Monitor UIContext generation and JSON size
5. **Cross-branch incompatibility**: Use version-agnostic validation helpers
