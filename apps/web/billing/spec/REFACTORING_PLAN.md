# Billing Controller Test Suite Refactoring Plan

## Problem Statement

Current test suite (`billing_controller_spec.rb`, 431 lines) has several issues:

1. **VCR Overuse**: All tests wrapped in VCR even when Stripe API not needed
2. **Mixed Concerns**: Unit tests (validation) mixed with integration tests (Stripe API)
3. **Region Mismatch**: Controller gets 'LL' from config, Stripe test plans use 'EU'
4. **Brittle Dependencies**: Tests depend on Stripe API state instead of controlled test data

## Solution Overview

Separate tests into two categories:

| Category | Purpose | Stripe API | VCR | Test Data Source |
|----------|---------|------------|-----|------------------|
| **Unit** | Validation, authorization, plan lookup | No | No | `spec/billing.test.yaml` |
| **Integration** | Stripe checkout, webhooks, invoices | Yes | Yes | Stripe API (via VCR) |

## File Structure

```
apps/web/billing/spec/
├── billing.test.yaml                           # Test plan definitions (NEW)
│
├── support/
│   ├── shared_contexts/                        # (NEW DIRECTORY)
│   │   ├── with_test_plans.rb                  # Load plans from YAML
│   │   ├── with_authenticated_customer.rb      # Session/customer setup
│   │   ├── with_organization.rb                # Organization setup
│   │   └── with_stripe_vcr.rb                  # Stripe API + VCR wrapper
│   │
│   ├── billing_spec_helper.rb                  # Keep current helpers
│   ├── vcr_setup.rb                            # Keep VCR config
│   └── shared_examples/                        # Keep existing
│
└── controllers/
    ├── billing_controller_spec.rb              # EXISTING (to be split)
    ├── billing_controller_unit_spec.rb         # (NEW) Unit tests
    └── billing_controller_integration_spec.rb  # (NEW) Integration tests
```

## Shared Context Design

### 1. `with_test_plans`

**Purpose**: Load test plans from `spec/billing.test.yaml` without Stripe API

**Usage**:
```ruby
RSpec.describe 'BillingController' do
  include_context 'with_test_plans'

  it 'returns validation error' do
    expect(test_plan_exists?('single_team')).to be true
  end
end
```

**Behavior**:
- Clears Redis plan cache (forces config fallback)
- Mocks region as 'EU' (matches test plans)
- Provides helpers: `test_plan(tier)`, `test_plan_id(tier, interval)`, `test_entitlements`

**Dependencies**:
- `spec/billing.test.yaml` must exist
- `Billing::Config.load_plans` (already supports ConfigResolver)
- `Billing::Plan.list_plans_from_config` (fallback when cache empty)

### 2. `with_authenticated_customer`

**Purpose**: Authenticated customer with session and cleanup

**Usage**:
```ruby
RSpec.describe 'BillingController' do
  include Rack::Test::Methods
  include_context 'with_authenticated_customer'

  it 'allows authenticated access' do
    get '/billing/api/plans'
    expect(last_response.status).to eq(200)
  end
end
```

**Provides**:
- `customer` - Authenticated customer instance
- `create_other_customer` - Create non-authenticated customer
- `authenticate_as(customer)` - Switch session
- `clear_authentication` - Remove session
- Automatic cleanup

### 3. `with_organization`

**Purpose**: Organization owned by authenticated customer

**Usage**:
```ruby
RSpec.describe 'BillingController' do
  include_context 'with_authenticated_customer'
  include_context 'with_organization'

  it 'accesses organization data' do
    get "/billing/api/org/#{organization.extid}"
    expect(last_response.status).to eq(200)
  end
end
```

**Provides**:
- `organization` - Organization owned by customer
- `create_organization_member` - Add non-owner member
- `create_other_organization` - Additional organization
- `set_stripe_customer(id)` - Associate Stripe customer
- Automatic cleanup

**Requirements**:
- Must be used with `with_authenticated_customer`

### 4. `with_stripe_vcr`

**Purpose**: Stripe API integration with VCR cassettes

**Usage**:
```ruby
RSpec.describe 'BillingController', :integration do
  include_context 'with_stripe_vcr'
  include_context 'with_authenticated_customer'
  include_context 'with_organization'

  it 'creates checkout session', :vcr do
    post "/billing/api/org/#{organization.extid}/checkout", {
      tier: 'single_team',
      billing_cycle: 'monthly'
    }.to_json

    expect(last_response.status).to eq(200)
  end
end
```

**Provides**:
- Stripe plan cache refresh (via VCR)
- Region mocking (EU)
- `cached_stripe_plan(tier, interval)` - Get plan from cache
- `stripe_price_id_for(tier)` - Get Stripe price ID

**Requirements**:
- Test must be tagged `:vcr`
- `STRIPE_API_KEY` for recording
- VCR cassettes for playback

## Test Categorization

### Unit Tests (with_test_plans)

**No Stripe API, No VCR, Uses billing.test.yaml**

```ruby
# apps/web/billing/spec/controllers/billing_controller_unit_spec.rb
RSpec.describe 'Billing::Controllers::BillingController' do
  include Rack::Test::Methods
  include_context 'with_test_plans'
  include_context 'with_authenticated_customer'
  include_context 'with_organization'

  describe 'GET /billing/api/plans' do
    it 'returns list of available plans'
    it 'does not require authentication'
  end

  describe 'GET /billing/api/org/:extid' do
    it 'returns billing overview for organization'
    it 'returns nil subscription when no subscription'
    it 'returns 403 when customer is not member'
    it 'returns 403 when organization does not exist'
    it 'requires authentication'
  end

  describe 'POST /billing/api/org/:extid/checkout' do
    it 'returns 400 when tier is missing'
    it 'returns 400 when billing_cycle is missing'
    it 'returns 404 when plan is not found'
    it 'returns 403 when customer is not owner'
    it 'requires authentication'
  end

  describe 'GET /billing/api/org/:extid/invoices' do
    it 'returns empty list when no Stripe customer'
    it 'returns 403 when customer is not member'
    it 'requires authentication'
  end
end
```

**Tests Moved**: 11 tests (validation, authorization, basic structure)

### Integration Tests (with_stripe_vcr)

**Uses Stripe API, VCR cassettes, Real Stripe data**

```ruby
# apps/web/billing/spec/controllers/billing_controller_integration_spec.rb
RSpec.describe 'Billing::Controllers::BillingController', :integration, :vcr do
  include Rack::Test::Methods
  include_context 'with_stripe_vcr'
  include_context 'with_authenticated_customer'
  include_context 'with_organization'

  describe 'GET /billing/api/plans' do
    it 'handles plan cache refresh failures gracefully', :vcr
  end

  describe 'GET /billing/api/org/:extid' do
    it 'returns subscription data when active subscription', :vcr
  end

  describe 'POST /billing/api/org/:extid/checkout' do
    it 'creates Stripe checkout session', :vcr
    it 'uses existing Stripe customer if available', :vcr
    it 'includes metadata in subscription', :vcr
    it 'uses idempotency key to prevent duplicates', :vcr
  end

  describe 'GET /billing/api/org/:extid/invoices' do
    it 'returns list of invoices for organization', :vcr
    it 'handles Stripe errors gracefully', :vcr
  end
end
```

**Tests Moved**: 7 tests (Stripe API interactions)

## Migration Steps

### Step 1: Verify Test Config
```bash
# Verify billing.test.yaml loads correctly
bundle exec ruby -e "
require_relative 'apps/web/billing/config'
ENV['RACK_ENV'] = 'test'
plans = Billing::Config.load_plans
puts \"Plans loaded: #{plans.keys.join(', ')}\"
"
```

### Step 2: Load Shared Contexts
Update `apps/web/billing/spec/support/billing_spec_helper.rb`:
```ruby
# Load shared contexts
Dir[File.join(__dir__, 'shared_contexts', '*.rb')].each { |f| require f }
```

### Step 3: Create Unit Test File
Extract validation tests to `billing_controller_unit_spec.rb`

### Step 4: Create Integration Test File
Extract Stripe API tests to `billing_controller_integration_spec.rb`

### Step 5: Verify Tests Pass
```bash
# Unit tests (fast, no VCR)
bundle exec rspec apps/web/billing/spec/controllers/billing_controller_unit_spec.rb

# Integration tests (with VCR)
bundle exec rspec apps/web/billing/spec/controllers/billing_controller_integration_spec.rb
```

### Step 6: Archive Original File
Keep original for reference during migration:
```bash
mv apps/web/billing/spec/controllers/billing_controller_spec.rb \
   apps/web/billing/spec/controllers/billing_controller_spec.rb.archive
```

## Benefits

1. **Faster Tests**: Unit tests run without VCR overhead (11 tests, ~80% faster)
2. **Better Isolation**: Unit tests don't depend on Stripe API or cassettes
3. **Clearer Intent**: Test type obvious from filename and context usage
4. **Easier Maintenance**: Shared contexts reduce duplication
5. **Flexible Testing**: Easy to add new tests with appropriate setup

## Configuration Details

### spec/billing.test.yaml Structure

```yaml
schema_version: "1.0"
app_identifier: "onetimesecret"
enabled: true
stripe_key: "sk_test_mock"
webhook_signing_secret: "whsec_test_mock"

entitlements:
  create_secrets:
    category: core
    description: Can create basic secrets
  # ... more entitlements

plans:
  free_v1:
    name: "Free"
    tier: free
    region: EU  # Must match mock_region! in tests
    # ... limits, entitlements

  identity_plus_v1:
    name: "Identity Plus"
    tier: single_team
    region: EU  # Must match mock_region! in tests
    prices:
      - price_id: price_test_monthly
        interval: month
        amount: 1200
```

**Key Points**:
- Region must be 'EU' to match test Stripe products
- ConfigResolver loads this automatically when `RACK_ENV=test`
- Minimal set of plans (only what tests need)

## Compatibility Notes

### ConfigResolver Support

Already supports test config resolution:
```ruby
# lib/onetime/utils/config_resolver.rb
def resolve(name)
  if test_environment?
    test_path = File.join(base, 'spec', "#{name}.test.yaml")
    return test_path if File.exist?(test_path)
  end

  default_path = File.join(base, 'etc', "#{name}.yaml")
  return default_path if File.exist?(default_path)
end
```

### Billing::Config Integration

Uses ConfigResolver internally:
```ruby
# apps/web/billing/config.rb
def self.config_path
  File.join(Onetime::HOME, 'etc', 'billing.yaml')
end
```

**Note**: Need to update `config_path` to use ConfigResolver:
```ruby
def self.config_path
  Onetime::Utils::ConfigResolver.resolve('billing') ||
    File.join(Onetime::HOME, 'etc', 'billing.yaml')
end
```

### Plan Loading Fallback

Already supports config fallback:
```ruby
# apps/web/billing/models/plan.rb
def self.load_from_config(plan_id)
  plans_hash = Billing::Config.load_plans
  # ... lookup logic
end

def self.list_plans_from_config
  plans_hash = Billing::Config.load_plans
  # ... conversion logic
end
```

## Next Actions

1. Update `Billing::Config.config_path` to use ConfigResolver
2. Create unit test file with shared contexts
3. Create integration test file with shared contexts
4. Verify all tests pass
5. Archive original test file
6. Update documentation

## Success Criteria

- [ ] All 18 tests pass (11 unit + 7 integration)
- [ ] Unit tests run without VCR (~80% faster)
- [ ] Integration tests use VCR cassettes
- [ ] No region mismatch errors
- [ ] Plan lookup works from test config
- [ ] Shared contexts reduce code duplication by >50%
