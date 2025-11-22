# Stripe Testing Guide

This billing test suite uses a combination of **stripe-mock** (official Stripe mock server) and **VCR** (HTTP interaction recording) for comprehensive, reliable testing.

## Philosophy

We do not trust third-party mock libraries to stay up-to-date with Stripe's API. Instead, we use:

1. **stripe-mock**: Official Stripe mock server written in Go
2. **VCR**: Record real Stripe test API interactions for playback

This dual approach ensures:
- Fast tests (stripe-mock)
- Realistic responses (VCR recordings from real API)
- No dependency on third-party mocks staying current

## Prerequisites

### Install stripe-mock

**macOS (Homebrew):**
```bash
brew install stripe/stripe-mock/stripe-mock
```

**Via Go:**
```bash
go install github.com/stripe/stripe-mock@latest
```

**Verify installation:**
```bash
stripe-mock --version
```

### Install Ruby gems

```bash
bundle install
```

This installs:
- `vcr` - HTTP interaction recording
- `webmock` - HTTP request stubbing
- `stripe` - Stripe Ruby SDK

## Usage

### Running Tests

**Default mode (uses stripe-mock + existing VCR cassettes):**
```bash
bundle exec rspec spec/billing
```

**Record new cassettes (uses REAL Stripe test API):**
```bash
STRIPE_API_KEY=sk_test_xxx bundle exec rspec spec/billing
```

**Force re-record all cassettes:**
```bash
VCR_MODE=all STRIPE_API_KEY=sk_test_xxx bundle exec rspec spec/billing
```

### Test Tags

**`:stripe` - Uses stripe-mock server:**
```ruby
RSpec.describe 'Price formatting', :stripe do
  it 'formats monthly intervals correctly' do
    price = Stripe::Price.create(
      currency: 'usd',
      unit_amount: 1000,
      recurring: { interval: 'month' }
    )

    expect(price.recurring.interval).to eq('month')
  end
end
```

**`:vcr` - Records/replays real API calls:**
```ruby
RSpec.describe 'Customer creation', :stripe, :vcr do
  it 'creates a customer successfully' do
    customer = Stripe::Customer.create(
      email: 'test@example.com',
      metadata: { source: 'test' }
    )

    expect(customer.email).to eq('test@example.com')
  end
end
```

## How It Works

### stripe-mock Server

- Runs on `localhost:12111` (default port)
- Started automatically before test suite
- Stopped automatically after test suite
- Reset between tests tagged with `:stripe`

**What it provides:**
- Fast, deterministic responses
- Realistic Stripe object structures
- No network latency
- No API rate limits

### VCR Cassettes

- Stored in `spec/fixtures/vcr_cassettes/`
- Generated from test descriptions
- Checked into git for consistency
- Filter sensitive data (API keys)

**What they provide:**
- Exact real API responses
- Full Stripe object structures
- Real validation behavior
- Confidence in production compatibility

## Best Practices

### 1. Use stripe-mock for Unit Tests

Fast, isolated tests that don't need exact API responses:

```ruby
RSpec.describe BillingFormatter, :stripe do
  it 'formats subscription intervals' do
    price = Stripe::Price.construct_from(
      recurring: { interval: 'month' }
    )

    expect(BillingFormatter.interval(price)).to eq('monthly')
  end
end
```

### 2. Use VCR for Integration Tests

Tests that need real API behavior:

```ruby
RSpec.describe 'Stripe webhook handling', :stripe, :vcr do
  it 'processes subscription created events' do
    # This hits the real test API (first run)
    # Then replays from cassette (subsequent runs)
    subscription = Stripe::Subscription.create(
      customer: 'cus_test123',
      items: [{ price: 'price_test123' }]
    )

    expect(subscription.status).to eq('active')
  end
end
```

### 3. Naming Conventions

- Test descriptions auto-generate cassette names
- Keep descriptions concise and unique
- Avoid special characters

**Good:**
```ruby
it 'creates customer with email' do
  # Cassette: billing_creates_customer_with_email.yml
end
```

**Bad:**
```ruby
it 'creates customer with email (special: test@example.com)' do
  # Cassette: billing_creates_customer_with_email_special_testexamplecom.yml
end
```

### 4. Re-recording Cassettes

When Stripe API changes:

```bash
# Delete old cassette
rm spec/fixtures/vcr_cassettes/specific_test.yml

# Re-record with real API
STRIPE_API_KEY=sk_test_xxx bundle exec rspec spec/path/to/spec.rb:42
```

## Troubleshooting

### stripe-mock not found

```
Error: stripe-mock is not installed
```

**Solution:** Install stripe-mock (see Prerequisites)

### VCR can't find cassette

```
VCR::Errors::UnhandledHTTPRequestError
```

**Solution:** Record the cassette with `STRIPE_API_KEY=sk_test_xxx`

### Cassette has wrong data

**Solution:** Delete cassette and re-record with `VCR_MODE=all`

### Tests fail with "Connection refused"

**Solution:** Ensure stripe-mock is running:

```bash
stripe-mock -port 12111
```

Then run tests in another terminal.

## Environment Variables

| Variable | Purpose | Example |
|----------|---------|---------|
| `STRIPE_API_KEY` | Real test API key for recording | `sk_test_xxx` |
| `STRIPE_MOCK_PORT` | Custom mock server port | `12111` (default) |
| `VCR_MODE` | Force cassette re-recording | `all`, `once`, `none` |

## Architecture

```
┌─────────────────┐
│   RSpec Test    │
└────────┬────────┘
         │
         ├──:stripe──────► stripe-mock (localhost:12111)
         │                      │
         │                      ▼
         │                 StripeObject responses
         │
         └──:vcr─────────► VCR Cassette
                                │
                                ├─exists───► Replay recorded response
                                │
                                └─missing──► Record from real API
                                                 │
                                                 ▼
                                           api.stripe.com (test mode)
```

## Reference

- **stripe-mock**: https://github.com/stripe/stripe-mock
- **VCR**: https://github.com/vcr/vcr
- **Stripe Testing**: https://stripe.com/docs/testing
