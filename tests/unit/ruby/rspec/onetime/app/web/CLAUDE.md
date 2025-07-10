# Ruby Backend Testing Guidelines - Window State Generation

**PROCESSING NOTE**: Content up to "DETAILED SECTIONS INDEX" contains CRITICAL context for immediate testing decisions. Content below that section provides detailed reference material - consult only when specific implementation details are needed.

## 🚨 CRITICAL SECURITY BOUNDARIES - MUST NEVER BE EXPOSED

### FORBIDDEN Configuration Paths
```ruby
# These secrets would compromise the entire system if exposed:
config.dig(:site, :secret)            # Global secret key - encrypts all data
config.dig(:database, :password)      # Database access
config.dig(:redis, :password)         # Session store access
config.dig(:stripe, :secret_key)      # Payment processing
config.dig(:api, :admin_secret)       # Admin API access

# SAFE to expose (designed for frontend):
config.dig(:site, :host)              # Public domain
config.dig(:stripe, :publishable_key) # Public Stripe key
config.dig(:sentry, :dsn)             # Error tracking endpoint
```

## UIContext Generation Pipeline - Security Critical Path

1. **Load Config** → 2. **Inject User Data** → 3. **FILTER SECRETS** → 4. **Serialize to JSON**

### Authentication State - Core Security Context
```ruby
# This determines what data the user can access:
authenticated = session[:authenticated] || false
custid = authenticated ? session[:custid] : nil

# Anonymous users get stub data only:
cust = authenticated ? load_customer_data(custid) : {
  identifier: 'anon', custid: 'anon', email: nil,
  role: 'customer', active: false
}
```

### Essential Transformation Logic
```ruby
# Feature flags derived from config + user state:
d9s_enabled = config.dig(:diagnostics, :sentry, :dsn).present?
plans_enabled = config.dig(:stripe, :publishable_key).present?

# Plan access depends on authentication:
if authenticated && customer.paid_plan?
  plan = customer.current_plan  # Full plan details
else
  plan = Plan.anonymous         # Limited features only
end
```

### Required Window Keys (Frontend Contract)
```ruby
REQUIRED_KEYS = %w[
  authenticated custid cust                    # User context
  authentication d9s_enabled plans_enabled     # Feature flags
  site_host frontend_host                      # URLs
  locale supported_locales                     # i18n
  shrimp nonce                                 # Security tokens
  plan is_paid available_plans                 # Subscription
]
```

### Key Validation Areas
1. **Security Filtering**: Verify NO forbidden paths reach frontend
2. **Type Safety**: All values must be JSON-serializable
3. **Structure Completeness**: All required keys present
4. **Authentication Consistency**: User state matches data access

### Critical Test Patterns
```ruby
# Test security boundaries:
expect(window[:site_secret]).to be_nil  # Must never exist

# Test authentication state:
context 'anonymous user' do
  expect(window[:authenticated]).to eq(false)
  expect(window[:cust][:custid]).to eq('anon')
end

# Test feature derivation:
expect(window[:plans_enabled]).to eq(
  config.dig(:stripe, :publishable_key).present?
)
```

---

## 📑 DETAILED SECTIONS INDEX

- **[Test Data Architecture](#test-data-architecture)**: Mock strategies and user state variations
- **[Validation Requirements](#validation-requirements)**: Complete field lists and structure rules
- **[Type Safety & Serialization](#type-safety--serialization)**: JSON compatibility and coercion
- **[Branch Migration Guide](#branch-migration-guide)**: Old vs new system differences
- **[Error Handling Patterns](#error-handling-patterns)**: Graceful degradation strategies
- **[Debugging Guide](#debugging-guide)**: Common issues and solutions

---

## Test Data Architecture

### Configuration Mock Strategy
Tests use minimal config that covers key transformation paths:

```ruby
minimal_test_config = {
  site: {
    secret: 'test-secret-key',  # Never exposed to frontend
    host: 'dev.onetime.dev',    # Safe to expose
    authentication: {
      enabled: true,
      signin: true,
      signup: true,
      autoverify: false
    }
  },
  diagnostics: {
    sentry: {
      dsn: 'https://test@sentry.io/123',  # Safe public DSN
      logErrors: true,
      trackComponents: true
    }
  },
  development: {
    frontend_host: 'http://localhost:5173'
  }
}
```

### User State Variations
Tests must cover different user authentication states:

#### Anonymous User State
```ruby
{
  authenticated: false,
  custid: nil,
  cust: anonymous_customer_stub,
  email: nil,
  customer_since: nil,
  plan: anonymous_plan_stub,
  is_paid: false
}
```

#### Authenticated User State
```ruby
{
  authenticated: true,
  custid: 'test-customer-123',
  cust: authenticated_customer_data,
  email: 'test@example.com',
  customer_since: '2024-01-01T00:00:00Z',
  plan: customer_plan_data,
  is_paid: customer.paid_plan?
}
```

## Validation Requirements

### Complete Top-Level Key List
```ruby
REQUIRED_WINDOW_KEYS = %w[
  # User Context
  authenticated custid cust email customer_since

  # Feature Flags
  authentication d9s_enabled diagnostics domains domains_enabled
  plans_enabled regions regions_enabled

  # URLs & Hosts
  frontend_development frontend_host site_host

  # Domain Configuration
  canonical_domain custom_domains display_domain domain_branding
  domain_id domain_locale domain_logo domain_strategy

  # Localization
  locale default_locale fallback_locale supported_locales i18n_enabled

  # System Info
  ot_version ot_version_long ruby_version

  # Security
  shrimp nonce

  # Plans
  plan is_paid default_planid available_plans

  # UI State
  incoming_recipient secret_options ui messages global_banner
].freeze
```

### Nested Object Structure Requirements

#### Customer Object (Complete Field List)
```ruby
customer_required_fields = %w[
  identifier custid email role verified last_login locale
  updated created stripe_customer_id stripe_subscription_id
  stripe_checkout_email plan secrets_created secrets_burned
  secrets_shared emails_sent active
]
```

#### Authentication Object (All Booleans)
```ruby
authentication_required_fields = %w[enabled signin signup autoverify]
# CRITICAL: All must be true/false, NEVER nil
```

## Type Safety & Serialization

### Security Token Requirements
```ruby
# CSRF Token (shrimp):
# - Non-empty string, changes per request
# - Safe to expose (for CSRF protection)

# CSP Nonce:
# - Non-empty string, unique per request
# - Safe to expose (for Content Security Policy)
```

### Version String Patterns
```ruby
ot_version: /\A\d+\.\d+\.\d+\z/              # "0.22.3"
ot_version_long: /\A\d+\.\d+\.\d+ \(.+\)\z/  # "0.22.3 (e16fe4ac)"
ruby_version: /\Aruby-\d+\z/                 # "ruby-341"
```

### JSON Serialization Rules
```ruby
# Type Safety:
# - NO Symbol keys → use String keys
# - NO complex objects → serialize to Hash
# - NO Time objects → use ISO 8601 strings
# - Distinguish nil vs false correctly

# Date Format: "2024-01-01T00:00:00Z"
```

## Branch Migration Guide

### Key System Differences

| Component | Old System | New System | Testing Impact |
|-----------|------------|------------|----------------|
| Config Loading | Simple YAML | Schema-validated | Stricter validation |
| UIContext | Hash manipulation | UIContext class | More predictable |
| Init Scripts | Not supported | Modify config | Test pre/post states |

### Cross-Branch Testing Strategy

```ruby
# Test structure, not values:
expect(ui_context[:authentication]).to be_a(Hash)
expect(ui_context[:authentication]).to have_key(:enabled)

# Abstract path differences:
def extract_logo_url(config)
  config.dig(:ui, :header, :branding, :logo, :url) ||    # New
  config.dig(:site, :branding, :logo_url)                # Old
end
```

## Error Handling Patterns

### Graceful Degradation Examples
```ruby
# Missing config sections:
auth = config.dig(:site, :authentication) || {}
ui_context[:authentication] = {
  enabled: auth[:enabled] || false,
  signin: auth[:signin] || false,
  signup: auth[:signup] || false,
  autoverify: auth[:autoverify] || false
}

# Service failures:
# Sentry missing → d9s_enabled: false
# Stripe missing → plans_enabled: false
# Redis down → anonymous session
# Database down → anonymous customer stub
```

## Debugging Guide

### Common Issues Checklist

| Issue | Check These | Solution |
|-------|-------------|----------|
| Missing frontend property | 1. Backend generates it<br>2. Not filtered as secret<br>3. JSON serializable | Add to UIContext generation |
| Type mismatch | Ruby → JSON → JS mapping | Use correct type coercion |
| Authentication bugs | Session state consistency | Verify auth flow |
| Performance | Database queries, memoization | Cache per request |

### Type Conversion Reference
```ruby
Ruby nil    → JSON null  → JavaScript null
Ruby false  → JSON false → JavaScript false
Ruby Symbol → JSON error → Convert to String first
Ruby Time   → JSON error → Use ISO 8601 string
```
