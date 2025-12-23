# Billing and Entitlement Test Patterns

This guide documents best practices for writing tests that involve billing and entitlements, ensuring proper test isolation per Issue #2228.

## Problem Statement

Test isolation was failing because:

1. **Plan Cache Pollution**: Tests that enabled billing populated Redis plan cache, affecting subsequent tests
2. **Shared State**: Billing state persisted across test files in the suite
3. **Default Behavior**: Tests needed billing disabled by default to avoid dependency on external billing config

## Solution

Billing is now **disabled by default** in all tests (Tryouts and RSpec), with opt-in mechanisms for tests that need billing enabled.

## Architecture

### Core Components

1. **`try/support/billing_helpers.rb`**: Shared isolation helpers used by both Tryouts and RSpec
2. **`try/support/test_helpers.rb`**: Tryouts test setup (calls `BillingTestHelpers.disable_billing!`)
3. **`spec/support/billing_isolation.rb`**: RSpec hooks that disable billing before each test
4. **`spec/spec_helper.rb`**: Loads billing isolation support

### Key Mechanisms

**Default State:**
- Billing config path: `/nonexistent/billing_disabled_for_tests.yaml` (non-existent file)
- Plan cache: Empty
- Entitlements: Standalone mode (full entitlements without restrictions)

**Test Redis:**
- Port: `2121` (not `6379`) to avoid conflicts with development
- URI: Set via `ENV['VALKEY_URL']` or `ENV['REDIS_URL']` in test_helpers.rb

## Writing Tests

### Tryouts Tests

#### Tests Without Billing

Most tests should work with billing disabled (default):

```ruby
#!/usr/bin/env ruby
require_relative '../support/test_helpers'

## Customer gets standalone entitlements by default
# Billing is disabled, so full entitlements are available
customer = Onetime::Customer.create(email: 'test@example.com')
customer.can?(:create_secrets)
#=> true
```

#### Tests With Billing Enabled

Use `BillingTestHelpers.with_billing_enabled` for tests that need billing:

```ruby
#!/usr/bin/env ruby
require_relative '../support/test_helpers'

## Test organization entitlements with specific plan
plans_data = [{
  plan_id: 'identity_v1',
  name: 'Identity Plus',
  tier: 2,
  interval: 'month',
  region: 'us',
  entitlements: ['create_secrets', 'custom_domains'],
  limits: { 'teams.max' => '1' }
}]

result = BillingTestHelpers.with_billing_enabled(plans: plans_data) do
  # Create organization and check entitlements
  org = Onetime::Organization.new(planid: 'identity_v1')
  org.can?('custom_domains')
end

result
#=> true

## After block, billing is disabled and cache is cleared
Billing::Plan.all.empty?
#=> true
```

### RSpec Tests

#### Tests Without Billing

Default behavior - no special setup needed:

```ruby
require 'spec_helper'

RSpec.describe 'Feature requiring entitlement check' do
  it 'uses standalone entitlements when billing disabled' do
    customer = Onetime::Customer.create(email: 'test@example.com')

    expect(customer.can?(:create_secrets)).to be true
  end
end
```

#### Tests With Billing Enabled

Use `billing: true` tag or `with_billing_enabled` helper:

```ruby
require 'spec_helper'

# Option 1: Tag the entire describe block
RSpec.describe 'Billing feature', billing: true do
  before do
    # Setup test plans
    setup_test_plan({
      plan_id: 'free',
      name: 'Free',
      tier: 1,
      interval: 'month',
      region: 'us',
      entitlements: ['create_secrets'],
      limits: { 'teams.max' => '0' }
    })
  end

  it 'checks entitlements against plan' do
    org = Onetime::Organization.new(planid: 'free')

    expect(org.can?('create_secrets')).to be true
    expect(org.can?('custom_domains')).to be false
  end
end

# Option 2: Use helper for specific tests
RSpec.describe 'Mixed billing tests' do
  it 'uses standalone mode by default' do
    org = Onetime::Organization.new(planid: 'free')
    # Billing disabled, so gets standalone entitlements
    expect(org.can?('create_secrets')).to be true
  end

  it 'can enable billing for specific test' do
    with_billing_enabled(plans: [{
      plan_id: 'free',
      name: 'Free',
      tier: 1,
      interval: 'month',
      region: 'us',
      entitlements: ['create_secrets'],
      limits: {}
    }]) do
      org = Onetime::Organization.new(planid: 'free')
      # Now using actual plan entitlements
      expect(org.can?('create_secrets')).to be true
    end
  end
end
```

## Test Isolation Guarantees

### What's Guaranteed

1. **Billing disabled by default**: No test inherits enabled billing from previous tests
2. **Clean plan cache**: Each test starts with empty Redis plan cache
3. **No config leakage**: Test billing config never loads production billing.yaml
4. **Thread isolation**: Thread.current[:entitlement_test_planid] is cleared between tests
5. **Proper cleanup**: `with_billing_enabled` ensures cleanup even on exceptions

### What to Verify

Your tests should verify:

```ruby
# Before any billing operations
Onetime::BillingConfig.path
#=> '/nonexistent/billing_disabled_for_tests.yaml'

Billing::Plan.all.empty?
#=> true

# After with_billing_enabled block
Billing::Plan.all.empty?
#=> true

Onetime::BillingConfig.instance.enabled?
#=> false
```

## BillingTestHelpers API

### Methods

**`disable_billing!`**
- Sets billing config path to non-existent file
- Resets billing singleton
- Called automatically at test suite startup

**`restore_billing!`**
- Restores original billing config path
- Use for tests that need real billing config
- Automatically restored by `with_billing_enabled`

**`clear_plan_cache!`**
- Clears all plans from Redis cache
- Safe to call even with empty cache
- Called automatically by `cleanup_billing_state!`

**`cleanup_billing_state!`**
- Clears plan cache + disables billing
- Full state reset
- Called automatically after `with_billing_enabled`

**`with_billing_enabled(plans: [])`**
- Enables billing for block duration
- Optionally populates test plans
- Guarantees cleanup on success or exception
- Returns block result

**`populate_test_plans(plans)`**
- Populates Redis plan cache with test data
- Requires array of plan hashes with:
  - `plan_id`, `name`, `tier`, `interval`, `region`
  - `entitlements` (array)
  - `limits` (hash)

**`ensure_familia_configured!`**
- Ensures Familia uses test Redis (port 2121)
- Idempotent - safe to call multiple times
- Called automatically by other helpers

## Common Patterns

### Testing Entitlement Checks

```ruby
## Test that feature requires specific entitlement
with_billing_enabled(plans: [{
  plan_id: 'free',
  entitlements: ['basic_feature']
}]) do
  org = Onetime::Organization.new(planid: 'free')
  org.can?('basic_feature')  #=> true
  org.can?('premium_feature')  #=> false
end
```

### Testing Plan Upgrades

```ruby
## Test upgrade path for features
plans = [
  { plan_id: 'free', tier: 1, entitlements: ['basic'] },
  { plan_id: 'premium', tier: 2, entitlements: ['basic', 'advanced'] }
]

with_billing_enabled(plans: plans) do
  free_org = Onetime::Organization.new(planid: 'free')
  premium_org = Onetime::Organization.new(planid: 'premium')

  free_org.can?('advanced')  #=> false
  premium_org.can?('advanced')  #=> true
end
```

### Testing Limits

```ruby
## Test that limits are enforced
with_billing_enabled(plans: [{
  plan_id: 'free',
  limits: { 'teams.max' => '1' }
}]) do
  org = Onetime::Organization.new(planid: 'free')
  org.at_limit?('teams', 0)  #=> false (0 < 1)
  org.at_limit?('teams', 1)  #=> true (1 = 1)
  org.at_limit?('teams', 2)  #=> true (2 > 1)
end
```

## Debugging Tips

### Check Billing State

```ruby
# Is billing enabled?
Onetime::BillingConfig.instance.enabled?

# What's the config path?
Onetime::BillingConfig.path

# What plans are in cache?
Billing::Plan.all

# Is Familia using test Redis?
Familia.uri.to_s.include?('2121')
```

### Common Issues

**Problem**: Test fails with "plan not found"
**Solution**: You forgot to populate plans. Use `with_billing_enabled(plans: [...])`

**Problem**: Tests pass individually but fail in suite
**Solution**: Plan cache isn't being cleared. Verify `BillingTestHelpers.cleanup_billing_state!` is called

**Problem**: Entitlement check returns unexpected result
**Solution**: Billing might be disabled. Check `Onetime::BillingConfig.instance.enabled?`

**Problem**: Can't connect to Redis
**Solution**: Test database not running. Run `pnpm run test:database:start`

## Verification Tests

See `try/features/billing_isolation_verification_try.rb` for comprehensive verification tests that validate:

1. Billing is disabled by default
2. Plan cache starts empty
3. `with_billing_enabled` works correctly
4. Plan cache is cleared after blocks
5. Multiple sequential blocks maintain isolation
6. Familia is configured with test Redis

Run verification:

```bash
pnpm run test:tryouts:agent -- try/features/billing_isolation_verification_try.rb
```

## Migration Guide

### Updating Existing Tests

**Before (tests might fail in suite):**
```ruby
## Test organization features
org = create_organization_with_plan('premium')
org.can?('advanced_feature')
#=> true
```

**After (isolated):**
```ruby
## Test organization features
with_billing_enabled(plans: [{
  plan_id: 'premium',
  entitlements: ['advanced_feature']
}]) do
  org = create_organization_with_plan('premium')
  org.can?('advanced_feature')
end
#=> true
```

### Test Suite Checklist

- [ ] All tests pass individually
- [ ] All tests pass in full suite run
- [ ] Tests don't depend on billing.yaml existence
- [ ] Tests that enable billing use `with_billing_enabled`
- [ ] Plan cache is cleared between test files
- [ ] No hardcoded Redis URIs (use ENV vars)
- [ ] Verification tests pass

## Related Files

- `try/support/billing_helpers.rb` - Core isolation helpers
- `try/support/test_helpers.rb` - Tryouts setup
- `spec/support/billing_isolation.rb` - RSpec hooks
- `try/features/billing_isolation_verification_try.rb` - Verification tests
- `spec/integration/api/colonel/entitlement_test_spec.rb` - Entitlement test mode tests
- `spec/unit/models/features/with_entitlements_test_mode_spec.rb` - WithEntitlements tests

## See Also

- Issue #2228: Billing/Entitlement Test Isolation
- Issue #2244: Plan Test Mode for Colonel
