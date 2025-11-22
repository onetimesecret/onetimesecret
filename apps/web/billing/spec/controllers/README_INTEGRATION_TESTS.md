# Controller Integration Tests - Setup Required

## Current Status

The controller integration tests in this directory are designed to test against the **real Stripe Test API** using VCR for recording/replaying HTTP interactions.

These tests currently fail because they require Stripe Test API infrastructure that is not yet configured.

## Required Setup

### 1. Stripe Test Account Configuration

You need a Stripe Test account with the following resources created:

#### Products

Create test products in Stripe Dashboard (Test Mode):
- Product: "Single Team Plan" (for tier: 'single_team')
- Product: "Multi Team Plan" (for tier: 'multi_team')
- Product: "Identity Plan" (for tier: 'identity')

#### Prices

For each product, create monthly and yearly prices:
- Monthly: `interval: 'month'`, `interval_count: 1`
- Yearly: `interval: 'year'`, `interval_count: 1`

Add metadata to prices:
```
tier: single_team|multi_team|identity
region: us-east
billing_cycle: monthly|yearly
```

### 2. Environment Variables

```bash
export STRIPE_KEY='sk_test_YOUR_STRIPE_TEST_KEY'
export STRIPE_WEBHOOK_SECRET='whsec_YOUR_WEBHOOK_SECRET'
export STRIPE_TEST_PRICE_ID='price_YOUR_TEST_PRICE_ID'
```

### 3. VCR Cassette Recording

Once Stripe is configured, record VCR cassettes:

```bash
# Delete existing cassettes
rm -rf apps/web/billing/spec/fixtures/vcr_cassettes/

# Re-record with real Stripe Test API
VCR_MODE=all STRIPE_KEY=sk_test_xxx bundle exec rspec apps/web/billing/spec/controllers
```

### 4. Running Tests

After setup:

```bash
# Use recorded cassettes (no API calls)
bundle exec rspec apps/web/billing/spec/controllers

# Re-record cassettes
VCR_MODE=all STRIPE_KEY=sk_test_xxx bundle exec rspec apps/web/billing/spec/controllers
```

## Alternative: Mock-Based Testing

If you want to run tests without Stripe infrastructure, you can modify the tests to mock `Billing::Plan.get_plan`:

```ruby
before do
  allow(::Billing::Plan).to receive(:get_plan).and_return(
    double(
      plan_id: 'test_plan_v1',
      stripe_price_id: 'price_test',
      name: 'Test Plan',
      tier: 'single_team',
      interval: 'month'
    )
  )
end
```

However, this defeats the purpose of integration tests which are meant to verify real Stripe API behavior.

## Test Categories

### Currently Passing
- `smoke_spec.rb` - Basic application bootstrap tests

### Require Stripe Setup
- `plans_controller_spec.rb` - Plan selection and checkout flows
- `billing_controller_spec.rb` - Billing API endpoints (some tests)
- `webhooks_controller_spec.rb` - Webhook processing
- `capabilities_controller_spec.rb` - Capability checking

## Recommended Approach

1. **For Development**: Use stripe-mock for unit tests (already configured)
2. **For CI/CD**: Set up Stripe Test account + VCR cassettes for integration tests
3. **For Production**: Never use production Stripe keys in tests

## See Also

- `apps/web/billing/spec/STRIPE_TESTING_GUIDE.md` - Comprehensive testing strategy
- `apps/web/billing/spec/controllers/PHASE_5_SUMMARY.md` - Phase 5 completion summary
