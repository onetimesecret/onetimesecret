# Billing Controller Test Categorization

Detailed breakdown of all 18 tests from `billing_controller_spec.rb` categorized as unit or integration tests.

## Summary

| Category | Count | Needs Stripe | Uses VCR | Data Source | Speed |
|----------|-------|--------------|----------|-------------|-------|
| Unit | 11 | No | No | billing.test.yaml | Fast (~100ms) |
| Integration | 7 | Yes | Yes | Stripe API | Slow (~2s) |

## Unit Tests (11 tests)

Tests that validate business logic, authorization, and error handling without Stripe API.

### GET /billing/api/plans (2 tests)

1. **returns list of available plans**
   - **Current**: Uses VCR, calls `Billing::Plan.refresh_from_stripe`
   - **Refactored**: Uses `Billing::Plan.list_plans_from_config` from test YAML
   - **Assertions**: Plan structure (id, name, tier, interval, amount, features, limits)
   - **Context**: `with_test_plans`

2. **does not require authentication**
   - **Current**: Uses VCR, clears session
   - **Refactored**: Uses `clear_authentication` helper, no VCR
   - **Assertions**: 200 status without session
   - **Context**: `with_test_plans`

### GET /billing/api/org/:extid (4 tests)

3. **returns billing overview for organization**
   - **Current**: Uses VCR, full organization data
   - **Refactored**: Tests structure only (no Stripe subscription)
   - **Assertions**: organization, subscription (nil), plan (nil), usage
   - **Context**: `with_test_plans`, `with_authenticated_customer`, `with_organization`

4. **returns nil subscription when organization has no subscription**
   - **Current**: Uses VCR
   - **Refactored**: Simple structure test, no VCR
   - **Assertions**: subscription is nil
   - **Context**: `with_test_plans`, `with_authenticated_customer`, `with_organization`

5. **returns 403 when customer is not organization member**
   - **Current**: Uses VCR, creates other customer
   - **Refactored**: Uses `create_other_customer` and `authenticate_as` helpers
   - **Assertions**: 403 status, "Access denied"
   - **Context**: `with_test_plans`, `with_authenticated_customer`, `with_organization`

6. **returns 403 when organization does not exist**
   - **Current**: Uses VCR, fake org ID
   - **Refactored**: No VCR needed (no Stripe call)
   - **Assertions**: 403 status, "Organization not found"
   - **Context**: `with_test_plans`, `with_authenticated_customer`

7. **requires authentication**
   - **Current**: Uses VCR, clears session
   - **Refactored**: Uses `clear_authentication` helper
   - **Assertions**: 401 status
   - **Context**: `with_test_plans`, `with_authenticated_customer`, `with_organization`

### POST /billing/api/org/:extid/checkout (3 tests)

8. **returns 400 when tier is missing**
   - **Current**: Uses VCR, sends request without tier
   - **Refactored**: No VCR (validation fails before Stripe call)
   - **Assertions**: 400 status, "Missing tier or billing_cycle"
   - **Context**: `with_test_plans`, `with_authenticated_customer`, `with_organization`

9. **returns 400 when billing_cycle is missing**
   - **Current**: Uses VCR, sends request without billing_cycle
   - **Refactored**: No VCR (validation fails before Stripe call)
   - **Assertions**: 400 status, "Missing tier or billing_cycle"
   - **Context**: `with_test_plans`, `with_authenticated_customer`, `with_organization`

10. **returns 404 when plan is not found**
    - **Current**: Uses VCR, tries 'nonexistent_tier'
    - **Refactored**: Tests plan lookup against test config (no Stripe)
    - **Assertions**: 404 status, "Plan not found"
    - **Context**: `with_test_plans`, `with_authenticated_customer`, `with_organization`

11. **returns 403 when customer is not organization owner**
    - **Current**: Uses VCR, creates member customer
    - **Refactored**: Uses `create_organization_member` helper
    - **Assertions**: 403 status, "Owner access required"
    - **Context**: `with_test_plans`, `with_authenticated_customer`, `with_organization`

12. **requires authentication**
    - **Current**: Uses VCR, clears session
    - **Refactored**: Uses `clear_authentication` helper
    - **Assertions**: 401 status
    - **Context**: `with_test_plans`, `with_authenticated_customer`, `with_organization`

### GET /billing/api/org/:extid/invoices (2 tests)

13. **returns empty list when organization has no Stripe customer**
    - **Current**: Uses VCR
    - **Refactored**: Simple structure test, no VCR
    - **Assertions**: 200 status, invoices: []
    - **Context**: `with_test_plans`, `with_authenticated_customer`, `with_organization`

14. **returns 403 when customer is not organization member**
    - **Current**: Uses VCR, creates other customer
    - **Refactored**: Uses `create_other_customer` and `authenticate_as` helpers
    - **Assertions**: 403 status
    - **Context**: `with_test_plans`, `with_authenticated_customer`, `with_organization`

15. **requires authentication**
    - **Current**: Uses VCR, clears session
    - **Refactored**: Uses `clear_authentication` helper
    - **Assertions**: 401 status
    - **Context**: `with_test_plans`, `with_authenticated_customer`, `with_organization`

## Integration Tests (7 tests)

Tests that interact with real Stripe API via VCR cassettes.

### GET /billing/api/plans (1 test)

1. **handles plan cache refresh failures gracefully**
   - **Reason for Integration**: Tests Stripe API error handling
   - **Setup**: Mocks `Billing::Plan.list_plans` to raise `Stripe::StripeError`
   - **Assertions**: 500 status, "Failed to list plans"
   - **Context**: `with_stripe_vcr`, `with_authenticated_customer`
   - **VCR Cassette**: Yes

### GET /billing/api/org/:extid (1 test)

2. **returns subscription data when organization has active subscription**
   - **Reason for Integration**: Creates real Stripe customer, payment method, subscription
   - **Setup**:
     - `Stripe::Customer.create`
     - `Stripe::PaymentMethod.create` + attach
     - `Stripe::Subscription.create`
     - `organization.update_from_stripe_subscription`
   - **Assertions**: subscription.id, subscription.status (active/trialing)
   - **Context**: `with_stripe_vcr`, `with_authenticated_customer`, `with_organization`
   - **VCR Cassette**: Yes

### POST /billing/api/org/:extid/checkout (4 tests)

3. **creates Stripe checkout session**
   - **Reason for Integration**: Creates real Stripe Checkout.Session
   - **Setup**: `Billing::Plan.refresh_from_stripe`, `mock_region!('EU')`
   - **Assertions**: 200 status, checkout_url, session_id (Stripe checkout URL)
   - **Context**: `with_stripe_vcr`, `with_authenticated_customer`, `with_organization`
   - **VCR Cassette**: Yes

4. **uses existing Stripe customer if organization has one**
   - **Reason for Integration**: Creates Stripe customer, verifies checkout uses it
   - **Setup**: `Stripe::Customer.create`, `organization.stripe_customer_id = ...`
   - **Assertions**: Checkout session uses existing customer ID
   - **Context**: `with_stripe_vcr`, `with_authenticated_customer`, `with_organization`
   - **VCR Cassette**: Yes

5. **includes metadata in subscription**
   - **Reason for Integration**: Creates checkout session, verifies metadata
   - **Setup**: Creates checkout session
   - **Assertions**: `Stripe::Checkout::Session.retrieve` includes metadata (orgid, tier, external_id)
   - **Context**: `with_stripe_vcr`, `with_authenticated_customer`, `with_organization`
   - **VCR Cassette**: Yes

6. **uses idempotency key to prevent duplicates**
   - **Reason for Integration**: Tests Stripe idempotency behavior
   - **Setup**: Makes 2 identical requests
   - **Assertions**: Both requests succeed (Stripe dedupes)
   - **Context**: `with_stripe_vcr`, `with_authenticated_customer`, `with_organization`
   - **VCR Cassette**: Yes

### GET /billing/api/org/:extid/invoices (2 tests)

7. **returns list of invoices for organization**
   - **Reason for Integration**: Creates real Stripe customer and invoice
   - **Setup**:
     - `Stripe::Customer.create`
     - `Stripe::Invoice.create`
   - **Assertions**: invoices array, invoice structure (id, number, amount, status, pdf URL)
   - **Context**: `with_stripe_vcr`, `with_authenticated_customer`, `with_organization`
   - **VCR Cassette**: Yes

8. **handles Stripe errors gracefully**
   - **Reason for Integration**: Tests Stripe API error with invalid customer ID
   - **Setup**: `organization.stripe_customer_id = 'cus_invalid'`
   - **Assertions**: 500 status, "Failed to retrieve invoices"
   - **Context**: `with_stripe_vcr`, `with_authenticated_customer`, `with_organization`
   - **VCR Cassette**: Yes

## Skipped Tests (1 test)

### GET /billing/api/org/:extid/invoices

1. **limits invoices to 12**
   - **Status**: Skipped (requires creating 13+ invoices, time-intensive)
   - **Reason**: VCR cassette recording would be very slow
   - **Future**: Could be re-enabled as integration test with pre-recorded cassette

## Context Usage Summary

### Unit Tests
- All use: `with_test_plans`
- Most use: `with_authenticated_customer`, `with_organization`
- None use: `with_stripe_vcr`

### Integration Tests
- All use: `with_stripe_vcr`, `with_authenticated_customer`
- Most use: `with_organization`
- None use: `with_test_plans`

## Migration Checklist

### Pre-migration
- [x] Create `spec/billing.test.yaml`
- [x] Create `spec/support/shared_contexts/with_test_plans.rb`
- [x] Create `spec/support/shared_contexts/with_authenticated_customer.rb`
- [x] Create `spec/support/shared_contexts/with_organization.rb`
- [x] Create `spec/support/shared_contexts/with_stripe_vcr.rb`

### Migration
- [ ] Update `Billing::Config.config_path` to use ConfigResolver
- [ ] Load shared contexts in `billing_spec_helper.rb`
- [ ] Create `billing_controller_unit_spec.rb` (11 tests)
- [ ] Create `billing_controller_integration_spec.rb` (7 tests)

### Post-migration
- [ ] Run unit tests (verify no VCR usage)
- [ ] Run integration tests (verify VCR cassettes work)
- [ ] Archive original `billing_controller_spec.rb`
- [ ] Update CI configuration if needed
- [ ] Document new test structure

## Expected Performance Improvement

### Before
- All 18 tests use VCR
- Total runtime: ~5-10 seconds (VCR overhead + Redis)
- Cassette maintenance: 18 cassettes

### After
- 11 unit tests (no VCR): ~100-200ms
- 7 integration tests (VCR): ~3-5 seconds
- Total runtime: ~3-6 seconds (40-50% faster)
- Cassette maintenance: 7 cassettes (61% reduction)

### Benefits Beyond Speed
- Unit tests work without Stripe API credentials
- Easier to debug (less moving parts)
- Clearer test intent (filename indicates type)
- Reduced VCR maintenance burden
- Better isolation (unit tests fully deterministic)
