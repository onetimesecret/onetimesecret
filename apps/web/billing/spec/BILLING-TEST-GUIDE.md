# Billing RSpec Test Guide

This document explains how billing tests work, their Redis usage patterns, and what makes them unique in the test suite.

## Quick Reference

| Concern | Billing Tests | Regular Integration Tests |
|---------|---------------|---------------------------|
| Redis Flush | **Managed by billing helpers** | `flushdb` before/after each test |
| Billing Enabled | Explicitly enabled via tags/helpers | Disabled by default |
| Plan Cache | **Persists unless explicitly cleared** | N/A |
| VCR Cassettes | Auto-wrapped for Stripe API | Not used |
| Helper File | `billing_spec_helper.rb` | `integration_spec_helper.rb` |

## Architecture Overview

```
try/support/billing_helpers.rb             # Shared helpers for RSpec + Tryouts
                                           # (includes conditional RSpec integration)
apps/web/billing/spec/support/
├── billing_spec_helper.rb                 # Billing-specific RSpec config
├── vcr_setup.rb                           # VCR configuration for Stripe API
└── shared_contexts/                       # Reusable test contexts
spec/integration/integration_spec_helper.rb # General integration test hooks
```

## Redis Usage in Billing Tests

### Two Separate Redis Concerns

1. **General Test Data** (secrets, customers, sessions)
   - Flushed by `integration_spec_helper.rb` before/after each test
   - Uses `Familia.dbclient.flushdb`

2. **Plan Cache** (Stripe product/price data)
   - Stored in Redis with prefix `billing_plan:`
   - **NOT automatically flushed** when `billing: true` metadata is set
   - Managed via `BillingTestHelpers.clear_plan_cache!`

### Why Plan Cache Gets Special Treatment

The `billing: true` metadata tag prevents `flushdb` because:

```ruby
# spec/integration/integration_spec_helper.rb
config.before(:each, type: :integration) do |example|
  next if example.metadata[:billing]  # Skip flush for billing tests
  Familia.dbclient.flushdb
end
```

This allows tests to:
1. Set up plan data in `before(:all)` blocks
2. Share plan cache across multiple examples
3. Avoid expensive Stripe API calls per test

### Plan Cache Persistence

| Scenario | Plan Cache Behavior |
|----------|---------------------|
| Test tagged `billing: true` | **Persists** - no auto-flush |
| Test uses `with_billing_enabled { }` | Cleared after block |
| Regular integration test | Flushed with everything else |
| Between test files | **Persists** unless explicitly cleared |

### Clearing Plan Cache Explicitly

```ruby
# In test teardown
BillingTestHelpers.clear_plan_cache!

# Or full cleanup
BillingTestHelpers.cleanup_billing_state!  # clear_plan_cache! + disable_billing!
```

## Billing Test Helpers

### Two Layers of Configuration

```
┌─────────────────────────────────────────────────────────────┐
│ billing_helpers.rb (try/support/)                           │
│ - Shared between RSpec and Tryouts                          │
│ - Core helpers: disable_billing!, restore_billing!          │
│ - Plan cache management: clear_plan_cache!, populate_test_plans │
│ - Conditional RSpec integration (if defined?(RSpec)):       │
│   - Disables billing before each test by default            │
│   - Provides `billing: true` and `billing_cli: true` tags   │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ billing_spec_helper.rb (apps/web/billing/spec/support/)     │
│ - Billing-specific RSpec configuration                      │
│ - VCR wrapping for Stripe API calls                         │
│ - mock_billing_config!, generate_stripe_signature           │
└─────────────────────────────────────────────────────────────┘
```

### Key Helper Methods

```ruby
# Enable billing for a test (auto-cleanup)
with_billing_enabled(plans: [...]) do
  # Test code here
end

# Populate plan cache with test data
setup_test_plan({
  plan_id: 'test_plan_monthly',
  name: 'Test Plan',
  tier: 'single_team',
  interval: 'month',
  region: 'EU',
  entitlements: ['create_secrets', 'custom_domains'],
  limits: { teams: 1, members_per_team: 5 }
})

# Mock billing configuration
mock_billing_config!  # Sets enabled? -> true, provides mock stripe_key

# Generate valid Stripe webhook signature for testing
generate_stripe_signature(payload: json_body, secret: 'whsec_xxx')
```

## Metadata Tags

### Available Tags

| Tag | Effect |
|-----|--------|
| `billing: true` | Enables billing, skips Redis flush |
| `billing_cli: true` | For CLI command tests, enables billing |
| `stripe_sandbox_api: true` | For tests hitting real Stripe sandbox |
| `type: :billing` | Full billing test setup + VCR |
| `type: :integration` | Standard integration setup + VCR (in billing specs) |

### Usage Examples

```ruby
# Tag on describe block
RSpec.describe 'Billing Feature', billing: true do
  # billing enabled, Redis not flushed
end

# Tag on individual test
it 'does something with billing', billing: true do
  # billing enabled for this test only
end

# Type-based (from billing_spec_helper.rb)
RSpec.describe SomeController, type: :billing do
  # Gets all billing setup + VCR wrapping
end
```

## VCR for Stripe API

Billing tests use VCR to record/replay Stripe API calls:

```ruby
# Auto-wrapped based on test type
# Cassette path: spec/cassettes/{Class}/{method}/{test_description}

# Record new cassettes:
STRIPE_API_KEY=sk_test_xxx bundle exec rspec apps/web/billing/spec/...
```

### VCR Behavior by Tag

| Tag | VCR Behavior |
|-----|--------------|
| `type: :billing` | Auto-wrapped |
| `type: :cli` | Auto-wrapped |
| `type: :controller` | Auto-wrapped |
| `type: :integration` | Auto-wrapped |
| `:integration` (symbol) | Auto-wrapped |

## Common Patterns

### Pattern 1: Test Needing Plan Data

```ruby
RSpec.describe 'Feature requiring plans', billing: true do
  before(:all) do
    # Plans persist across examples (no flush)
    BillingTestHelpers.populate_test_plans([{
      plan_id: 'test_monthly',
      tier: 'pro',
      entitlements: ['feature_a'],
      limits: { widgets: 10 }
    }])
  end

  after(:all) do
    BillingTestHelpers.clear_plan_cache!
  end

  it 'uses the plan' do
    plan = Billing::Plan.load('test_monthly')
    expect(plan.tier).to eq('pro')
  end
end
```

### Pattern 2: Temporary Billing Enable

```ruby
it 'tests billing feature' do
  with_billing_enabled(plans: [plan_data]) do
    # Billing enabled, plan cached
    result = some_billing_operation
    expect(result).to be_success
  end
  # Auto-cleanup: plan cache cleared, billing disabled
end
```

### Pattern 3: Webhook Testing

```ruby
it 'processes webhook' do
  payload = { id: 'evt_123', type: 'checkout.session.completed' }.to_json
  signature = generate_stripe_signature(
    payload: payload,
    secret: 'whsec_test_secret'
  )

  post '/v2/billing/webhooks',
       payload,
       'HTTP_STRIPE_SIGNATURE' => signature
end
```

## Troubleshooting

### Tests Fail with "Plan not found"

**Cause**: Plan cache was flushed between tests
**Fix**: Add `billing: true` tag or use `with_billing_enabled`

### Tests Interfere with Each Other

**Cause**: Plan cache persists from previous test
**Fix**: Add explicit cleanup in `after(:each)` or `after(:all)`

```ruby
after(:each) do
  BillingTestHelpers.clear_plan_cache!
end
```

### billing_worker_spec.rb Failures

**Cause**: Missing `integration_spec_helper` require (idempotency keys persist)
**Fix**: Add `require 'integration/integration_spec_helper'`

### VCR Cassette Mismatch

**Cause**: Stripe API response changed
**Fix**: Re-record cassettes with real API key:
```bash
STRIPE_API_KEY=sk_test_xxx bundle exec rspec path/to/spec.rb
```

## File Locations

```
# Core billing specs
apps/web/billing/spec/
├── controllers/           # API endpoint tests
├── operations/            # ProcessWebhookEvent tests
├── cli/                   # CLI command tests
├── integration/           # Stripe client tests
├── models/                # Model unit tests
└── support/
    ├── billing_spec_helper.rb
    ├── vcr_setup.rb
    └── shared_contexts/

# Integration specs using billing
spec/integration/all/jobs/workers/billing_worker_spec.rb

# Billing isolation infrastructure
try/support/billing_helpers.rb    # Shared helpers + conditional RSpec integration
```
