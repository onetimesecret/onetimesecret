# Timecop Integration for Billing Tests

This document explains how to use Timecop for time manipulation and sleep mocking in billing tests.

## Overview

Timecop is integrated globally in `spec/spec_helper.rb` and provides additional billing-specific helpers in `billing_spec_helper.rb`.

## Automatic Setup

For all billing tests (`:billing`, `:cli` types), the following is automatically configured:

1. **Sleep is mocked** - `Billing::StripeClient#sleep` calls are intercepted and tracked
2. **Delays are tracked** - Access via `sleep_delays` helper
3. **Timecop is reset** - After each test, time returns to normal automatically

## Basic Time Manipulation

### Freeze Time

```ruby
it "generates timestamp-based keys" do
  freeze_time(Time.parse("2024-01-15 10:00:00 UTC"))

  key = client.send(:generate_idempotency_key)

  expect(key).to start_with("1705312800-") # Frozen timestamp
end
```

### Travel to Specific Time

```ruby
it "validates event timestamps" do
  event_time = Time.parse("2024-01-15 10:00:00 UTC")
  travel_to(event_time)

  # Event is exactly 4 minutes old
  travel(4.minutes)

  expect { validator.verify_timestamp!(event) }.not_to raise_error
end
```

### Travel Forward/Backward

```ruby
it "expires after 5 minutes" do
  freeze_time

  create_event(id: "evt_123")

  # Jump forward 6 minutes
  travel(6.minutes)

  expect(event_expired?("evt_123")).to be true
end
```

## Retry Testing with Sleep Mocking

### Track Sleep Delays

```ruby
it "retries with linear backoff" do
  allow(Stripe::Customer).to receive(:create) do
    raise Stripe::APIConnectionError.new("Network error")
  end.exactly(3).times

  begin
    client.create(Stripe::Customer, email: "test@example.com")
  rescue Stripe::APIConnectionError
    # Expected after retries
  end

  # Verify delays were tracked
  expect(sleep_delays).to eq([2, 4, 6])
end
```

### Use Helper Assertions

```ruby
it "retries with exponential backoff" do
  # ... trigger retries ...

  # Verify exponential pattern: 4s, 8s, 16s (base=2, exponent)
  expect_exponential_backoff(base: 2, count: 3)
end

it "retries with linear backoff" do
  # ... trigger retries ...

  # Verify linear pattern: 2s, 4s, 6s (base=2, multiplier)
  expect_linear_backoff(base: 2, count: 3)
end

it "uses custom retry delays" do
  # ... trigger retries ...

  # Verify exact delays
  expect_retry_delays(1, 2, 4, 8)
end
```

## Combining Timecop with Sleep Mocking

Test retry logic WITHOUT actual delays:

```ruby
it "retries 3 times with delays" do
  call_count = 0
  start_time = Time.now

  freeze_time(start_time)

  allow(Stripe::Customer).to receive(:create) do
    call_count += 1

    # Simulate time passing during retry
    travel(sleep_delays.last || 2) if call_count > 1

    raise Stripe::RateLimitError.new("Rate limit") if call_count < 3
    mock_stripe_customer
  end

  result = client.create(Stripe::Customer, email: "test@example.com")

  # Verify retries happened
  expect(call_count).to eq(3)

  # Verify correct delays
  expect_exponential_backoff(base: 2, count: 2)

  # Time has advanced but test ran instantly
  expect(Time.now - start_time).to be > 0
end
```

## Testing Webhook Timestamp Validation

```ruby
describe "timestamp validation" do
  let(:payload) { '{"type":"customer.created"}' }
  let(:webhook_secret) { "whsec_test" }

  it "accepts recent events" do
    freeze_time

    signature =
      generate_stripe_signature(payload: payload, secret: webhook_secret, timestamp: Time.now.to_i)

    expect { validator.construct_event(payload, signature) }.not_to raise_error
  end

  it "rejects old events (replay attack)" do
    freeze_time

    # Create signature for event 6 minutes ago
    old_timestamp = (Time.now - 6.minutes).to_i
    signature =
      generate_stripe_signature(payload: payload, secret: webhook_secret, timestamp: old_timestamp)

    expect { validator.construct_event(payload, signature) }.to raise_error(
      SecurityError,
      /too old/,
    )
  end

  it "rejects future events" do
    freeze_time

    # Create signature for event 2 minutes in future
    future_timestamp = (Time.now + 2.minutes).to_i
    signature =
      generate_stripe_signature(
        payload: payload,
        secret: webhook_secret,
        timestamp: future_timestamp,
      )

    expect { validator.construct_event(payload, signature) }.to raise_error(
      SecurityError,
      /timestamp in future/,
    )
  end
end
```

## Available Helpers

### Time Manipulation

- `freeze_time(time = Time.now)` - Freeze time at specific moment
- `travel_to(time)` - Jump to specific time
- `travel(duration)` - Move forward/backward by duration

### Sleep Tracking

- `sleep_delays` - Array of tracked sleep durations
- `expect_retry_delays(*delays)` - Assert exact delay pattern
- `expect_exponential_backoff(base:, count:)` - Assert exponential pattern
- `expect_linear_backoff(base:, count:)` - Assert linear pattern

## Best Practices

1. **Always use helpers** - Don't call `Timecop.freeze` directly, use `freeze_time`
2. **No manual cleanup needed** - `Timecop.return` is called automatically after each test
3. **Verify delays, not actual time** - Use `sleep_delays` instead of measuring elapsed time
4. **Test retry logic fast** - Sleep is mocked, so retries happen instantly
5. **Combine for complex scenarios** - Use both time travel and sleep tracking together

## Performance Impact

**Before Timecop integration:**

- Rate limit tests took 30+ seconds (actual 4s, 8s, 16s delays)
- Network retry tests took 12+ seconds (2s, 4s, 6s delays)

**After Timecop integration:**

- All retry tests run instantly (sleep is mocked)
- Time-based tests are deterministic and fast
- Full billing test suite runs in seconds, not minutes

## Examples in Test Suite

See these files for real-world usage:

- `spec/lib/stripe_client_spec.rb` - Retry testing with sleep mocking
- `spec/lib/webhook_validator_spec.rb` - Timestamp validation with time travel
- `spec/cli/integration_spec.rb` - Complex workflows with time manipulation
