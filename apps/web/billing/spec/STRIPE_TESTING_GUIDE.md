# Stripe VCR Testing Guide

## Self-Check Protocol

| Trigger | Action |
|---------|--------|
| Before recording | Run `/vcr-preflight` - blocks until checks pass |
| After 2 failures | Run `/step-back` - forces pattern analysis |
| Still stuck | Invoke `second-opinion` agent |

**Red flags** (STOP and use `/step-back`):
- Running same spec 3+ times
- Failure count not decreasing
- Fixing same issue type repeatedly

## Pre-Recording Checklist

Before recording VCR cassettes, Claude must complete these checks:

### 1. Scan for Dynamic Values
```bash
grep -rn "Time.now\|SecureRandom\|rand(\|\.to_i}" apps/web/billing/spec/cli/
```
**Fix:** Replace with deterministic values (e.g., `'VCR Test Product'` not `"Test #{Time.now.to_i}"`)

### 2. Scan for Stripe API Compatibility
```bash
grep -rn "current_period_end\|\.delete(Stripe::Subscription" apps/web/billing/cli/
```
**Known issues (API 2025-11-17.clover):**
- `subscription.current_period_end` → `subscription.items.data.first.current_period_end`
- `Stripe::Subscription.delete` → `Stripe::Subscription.cancel`
- `InvoiceItem.create(price:)` → `InvoiceItem.create(pricing: { price: })`

### 3. Verify VCR Matching Strategy
```ruby
# In vcr_setup.rb - body matching requires deterministic data
match_requests_on: [:method, :uri, :body]
```

## Recording Workflow

### Step 1: Batch Fix All Issues
Fix ALL identified issues across ALL specs before recording.

### Step 2: Delete Old Cassettes
```bash
rm -rf apps/web/billing/spec/fixtures/vcr_cassettes/Onetime_CLI_*
```

### Step 3: Record All Cassettes
```bash
source .env.billing && VCR_MODE=all RACK_ENV=test bundle exec rspec apps/web/billing/spec/cli/
```

### Step 4: Verify Replay
```bash
RACK_ENV=test bundle exec rspec apps/web/billing/spec/cli/
```

## Test Categories

| Tag | Purpose | Stripe API | VCR |
|-----|---------|------------|-----|
| `:vcr` | Real API behavior | Yes (recorded) | Yes |
| `:stripe_mock` | Request validation | No (static) | No |
| Mocked | CLI formatting/errors | No (allow/double) | No |

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `STRIPE_API_KEY` | Real test key for recording |
| `VCR_MODE=all` | Force re-record all cassettes |
| `VCR_MODE=none` | Fail if cassette missing |

## Gotchas

1. **VCR playback tries real API**: If cassette body doesn't match, VCR falls through to real API with `sk_test_mock` (fails)
2. **Each test = own cassette**: Named by test description, so unique emails per test are OK
3. **Cassettes record errors**: If test fails during recording, cassette saves error response
4. **Payment source required**: Subscriptions need `source: 'tok_visa'` on customer

## Reference
- [stripe-mock](https://github.com/stripe/stripe-mock)
- [VCR](https://github.com/vcr/vcr)
- [Stripe Testing](https://stripe.com/docs/testing)
