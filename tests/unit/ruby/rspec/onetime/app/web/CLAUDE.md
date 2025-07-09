# Ruby Backend Testing Guidelines - Window State Generation

## Critical Security Boundaries

### Sensitive Data Protection
These configuration values must **NEVER** be exposed to the frontend:

#### Database & Infrastructure Secrets
```ruby
# FORBIDDEN - Never expose these config paths:
config.dig(:site, :secret)                    # Global secret key
config.dig(:database, :password)              # Database password
config.dig(:database, :url)                   # Full connection string
config.dig(:redis, :password)                 # Redis password
config.dig(:redis, :url)                      # Redis connection string
config.dig(:mail, :smtp, :password)           # SMTP password
```

#### Payment & API Secrets
```ruby
# FORBIDDEN - Never expose these:
config.dig(:stripe, :secret_key)              # Stripe secret key
config.dig(:stripe, :webhook_secret)          # Stripe webhook secret
config.dig(:sentry, :auth_token)              # Sentry auth token (not DSN)
config.dig(:api, :admin_secret)               # Admin API secrets
```

#### Safe Configuration Exposure
```ruby
# SAFE - These can be exposed to frontend:
config.dig(:site, :host)                      # Public site host
config.dig(:sentry, :dsn)                     # Sentry DSN (public)
config.dig(:stripe, :publishable_key)         # Stripe publishable key
config.dig(:site, :authentication, :enabled)  # Feature flags
```

## UIContext Generation Logic

### Data Transformation Pipeline
The Ruby backend transforms configuration into UIContext through these steps:

1. **Configuration Loading**: YAML → validated config hash
2. **User Context Injection**: Database/session data → user-specific values
3. **Security Filtering**: Remove sensitive data
4. **Type Normalization**: Ensure JSON-safe types
5. **Serialization**: Hash → JSON string → `<script>` tag

### Critical Transformation Points

#### Authentication State Logic
```ruby
# User authentication status drives many other fields
authenticated = session[:authenticated] || false
custid = authenticated ? session[:custid] : nil
cust = authenticated ? load_customer_data(custid) : anonymous_customer_stub

# Anonymous customer stub structure:
anonymous_customer_stub = {
  identifier: 'anon',
  custid: 'anon',
  email: nil,
  role: 'customer',
  verified: nil,
  active: false,
  # ... other nil/default fields
}
```

#### Feature Flag Derivation
```ruby
# Feature flags often derived from config presence:
d9s_enabled = config.dig(:diagnostics, :sentry, :dsn).present? &&
              config.dig(:diagnostics, :sentry, :logErrors)

domains_enabled = config.dig(:domains, :enabled) &&
                  config.dig(:domains, :custom_domains).present?

plans_enabled = config.dig(:plans).present? &&
                config.dig(:stripe, :publishable_key).present?
```

#### Plan Information Logic
```ruby
# Plan information depends on user state:
if authenticated && customer.plan_id.present?
  plan = customer.current_plan.to_frontend_hash
  available_plans = Plan.available_for_customer(customer).to_frontend_hash
  is_paid = customer.paid_plan?
else
  plan = Plan.anonymous.to_frontend_hash
  available_plans = Plan.public_plans.to_frontend_hash
  is_paid = false
end
```

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

## Critical Validation Areas

### Top-Level Key Completeness
The test validates all required top-level keys that frontend expects:

```ruby
REQUIRED_WINDOW_KEYS = %w[
  authenticated custid cust email customer_since
  authentication d9s_enabled diagnostics domains domains_enabled
  frontend_development frontend_host incoming_recipient plans_enabled
  regions regions_enabled secret_options site_host support_host ui
  canonical_domain custom_domains display_domain domain_branding
  domain_id domain_locale domain_logo domain_strategy
  locale default_locale fallback_locale supported_locales i18n_enabled
  ot_version ot_version_long ruby_version shrimp nonce
  plan is_paid default_planid available_plans
  messages global_banner
].freeze
```

### Nested Object Structure Validation

#### Customer Object Requirements
```ruby
# Customer object must have consistent structure:
customer_required_fields = %w[
  identifier custid email role verified last_login locale
  updated created stripe_customer_id stripe_subscription_id
  stripe_checkout_email plan secrets_created secrets_burned
  secrets_shared emails_sent active
]
```

#### Authentication Object Requirements
```ruby
# Authentication must be complete boolean set:
authentication_required_fields = %w[enabled signin signup autoverify]
# All must be true/false, never nil
```

### Data Type Consistency Rules

#### Security Token Generation
```ruby
# CSRF token (shrimp) generation:
# - Must be present and non-empty string
# - Changes on each request
# - Safe to expose (designed for frontend CSRF protection)

# CSP nonce generation:
# - Must be present and non-empty string
# - Unique per request
# - Safe to expose (designed for CSP headers)
```

#### Version Information Format
```ruby
# Version strings must follow pattern:
ot_version: /\A\d+\.\d+\.\d+\z/           # "0.22.3"
ot_version_long: /\A\d+\.\d+\.\d+ \(.+\)\z/ # "0.22.3 (e16fe4ac)"
ruby_version: /\Aruby-\d+\z/              # "ruby-341"
```

### JSON Serialization Safety

#### Type Coercion Rules
```ruby
# Ensure all data is JSON-safe:
# - No Symbol keys (use string keys)
# - No complex objects (serialize to hashes)
# - No infinite recursion
# - Handle nil vs false distinctions properly

# Date/Time serialization:
# - Always use ISO 8601 strings: "2024-01-01T00:00:00Z"
# - Never serialize Time/DateTime objects directly
```

## Branch Migration Considerations

### Old System vs New System Differences

#### Configuration Loading Changes
- **Old**: Simple YAML loading with minimal validation
- **New**: Schema-based validation with two-stage processing
- **Impact**: Config structure more consistent, but validation stricter

#### UIContext Generation Changes
- **Old**: Direct hash manipulation in view helpers
- **New**: Structured UIContext class with transformation methods
- **Impact**: More predictable data structure, easier to test

#### Init Script Impact
- **New System**: Init.d scripts can modify config before UIContext generation
- **Testing**: Must account for config transformations during boot process
- **Validation**: Test both pre-init and post-init config states

### Cross-Branch Testing Strategy

#### Structure-Based Testing
Focus on data structure rather than specific values:
```ruby
# Good - tests structure
expect(ui_context[:authentication]).to be_a(Hash)
expect(ui_context[:authentication]).to have_key(:enabled)

# Avoid - tests specific values (may differ between branches)
expect(ui_context[:site_host]).to eq('specific.domain.com')
```

#### Configuration Path Changes
Some config paths may change between branches:
```ruby
# Old path: config[:site][:branding][:logo_url]
# New path: config[:ui][:header][:branding][:logo][:url]

# Tests should use helper methods to abstract path differences
def extract_logo_url(config)
  # Try new path first, fall back to old path
  config.dig(:ui, :header, :branding, :logo, :url) ||
  config.dig(:site, :branding, :logo_url)
end
```

## Error Handling Patterns

### Configuration Missing/Invalid
```ruby
# Graceful degradation for missing config sections:
authentication_config = config.dig(:site, :authentication) || {}
ui_context[:authentication] = {
  enabled: authentication_config[:enabled] || false,
  signin: authentication_config[:signin] || false,
  signup: authentication_config[:signup] || false,
  autoverify: authentication_config[:autoverify] || false
}
```

### Database Connection Issues
```ruby
# When database unavailable:
# - Customer data should fall back to anonymous
# - Plan data should use defaults
# - No database-dependent fields should cause crashes
```

### Service Failures
```ruby
# When external services fail:
# - Sentry DSN missing → d9s_enabled: false
# - Stripe keys missing → plans_enabled: false
# - Redis unavailable → sessions fall back to anonymous
```

## Debugging Common Issues

### Missing Frontend Properties
1. Check if Ruby backend generates the property
2. Verify security filtering doesn't remove it
3. Confirm JSON serialization doesn't break it
4. Test with different user authentication states

### Type Mismatches
1. Ruby nil → JSON null → JavaScript null
2. Ruby false → JSON false → JavaScript false
3. Ruby Symbol → JSON string → JavaScript string
4. Empty arrays vs nil handling

### Performance Considerations
1. UIContext generation happens on every page load
2. Database queries should be minimal and cached
3. Configuration should be memoized per request
4. Large plan/jurisdiction data should be paginated
