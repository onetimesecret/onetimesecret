# Stripe Testing Guide

This billing test suite uses a combination of **stripe-mock** (official Stripe mock server) and **VCR** (HTTP interaction recording) for comprehensive, reliable testing.

## Philosophy

We do not trust third-party mock libraries to stay up-to-date with Stripe's API. Instead, we use:

1. **stripe-mock**: Official Stripe mock server written in Go - **UNIT TESTS ONLY**
2. **VCR**: Record real Stripe test API interactions for playback - **INTEGRATION TESTS**

This dual approach ensures:

- Fast unit tests validating request construction (stripe-mock)
- Realistic integration tests capturing actual API behavior (VCR + Stripe test mode)
- No dependency on third-party mocks staying current

### Critical Distinction

**stripe-mock is for unit tests only.** It returns static fixtures that validate request structure but do not reflect real API behavior (state persistence, validation, error handling). Use VCR + Stripe test mode for integration tests that verify actual API interactions.

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

## RSpec Tag-Based Test Organization

### Key Principles

1. **Unit tests** (stripe-mock): Fast, no network, validate request construction
2. **Integration tests** (VCR + test mode): Capture real behavior, replay for speed
3. **Separate clearly**: Use directory structure, tags, or both
4. **Filter secrets**: Always scrub API keys from cassettes
5. **Re-record periodically**: Catch API changes by refreshing cassettes

### Approach 1 (Preferred): Shared Examples for Both Test Types

DRY approach for testing same behavior at different levels:

```ruby
# spec/support/shared_examples/stripe_charges.rb
RSpec.shared_examples 'charge creation' do
  it 'creates a charge with correct amount' do
    charge = create_charge(amount: 1000)
    expect(charge.amount).to eq(1000)
  end
end

# Unit test
RSpec.describe ChargeService, :unit, :stripe_mock do
  include_examples 'charge creation'
end

# Integration test
RSpec.describe ChargeService, :integration, :stripe_sandbox_api, :vcr, :slow do
  include_examples 'charge creation'

  it 'persists charge on Stripe servers' do
    # Additional integration-specific assertions
  end
end
```

### Approach 2 (Default): Metadata Tags

Use RSpec's built-in metadata system to tag tests without separate directories:

```ruby
# spec/spec_helper.rb
RSpec.configure do |config|
  # Tag-based filtering
  config.filter_run_excluding :integration unless ENV['INTEGRATION']

  # Configure based on test type
  config.before(:each, :integration) do
    # Use real Stripe test keys
    Stripe.api_key = ENV['STRIPE_KEY']
    WebMock.allow_net_connect!
  end

  config.before(:each) do |example|
    unless example.metadata[:integration]
      # Unit tests: point to stripe-mock
      Stripe.api_key = 'sk_test_mock'
      Stripe.api_base = 'http://localhost:12111'
      WebMock.disable_net_connect!(allow_localhost: true)
    end
  end
end
```

```ruby
# spec/support/vcr.rb
require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Filter sensitive data
  config.filter_sensitive_data('<STRIPE_KEY>') { ENV['STRIPE_KEY'] }

  # Only record for integration tests
  config.ignore_localhost = true
  config.ignore_hosts 'localhost', '127.0.0.1'
end
```

### Test Tags Reference

#### Test Type Tags

**`:unit` - Unit tests (fast, no external dependencies)**
- Tests CLI parameter parsing, error handling, output formatting
- Validates request construction with stripe-mock
- No network calls

**`:integration` - Integration tests (requires Stripe API)**
- Tests actual Stripe API behavior (state persistence, filtering, validation)
- Requires Stripe sandbox account or test API key
- **NOT compatible with stripe-mock** (it returns static fixtures)

#### Infrastructure Tags

**`:stripe_mock` - Uses stripe-mock server (unit tests only)**

```ruby
RSpec.describe "Price formatting", :stripe_mock do
  it "sends correct parameters to Stripe API" do
    # stripe-mock validates request structure but returns static fixture
    price = Stripe::Price.create(currency: "usd", unit_amount: 1000, recurring: { interval: "month" })
    expect(price.recurring.interval).to eq("month")
  end
end
```

**`:stripe_sandbox_api` - Requires Stripe sandbox/test API (integration tests)**

```ruby
RSpec.describe "Refund state persistence", :integration, :stripe_sandbox_api, :vcr do
  it "prevents double refunds on same charge" do
    # This REQUIRES real Stripe API - stripe-mock doesn't maintain state
    charge = Stripe::Charge.create(amount: 1000, currency: 'usd', source: 'tok_visa')
    Stripe::Refund.create(charge: charge.id)

    # Second refund should fail
    expect {
      Stripe::Refund.create(charge: charge.id)
    }.to raise_error(Stripe::InvalidRequestError, /already been refunded/)
  end
end
```

**`:vcr` - Records/replays real API calls**

Used with `:integration` and `:stripe_sandbox_api` to capture and replay real Stripe API responses.

#### Code Quality Tags

**`:code_smell` - Test needs refactoring**

Indicates tests that:
- Try to do integration testing with stripe-mock (wrong tool)
- Have excessive mocking that hides the actual behavior being tested
- Should be rewritten as proper unit or integration tests

### Running Tests by Tag

**Unit tests only (default, no API required):**

```bash
bundle exec rspec
```

**Integration tests only (requires Stripe test API):**

```bash
INTEGRATION=true bundle exec rspec --tag integration
```

**All tests (unit + integration):**

```bash
INTEGRATION=true bundle exec rspec
```

**Specific tag:**

```bash
bundle exec rspec --tag vcr
```

**Skip tests that need refactoring:**

```bash
bundle exec rspec --tag '~code_smell'
```

**Force re-record VCR cassettes:**

```bash
INTEGRATION=true bundle exec rspec --tag integration
# Then delete and re-run specific tests to re-record
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

### 1. Use stripe-mock for Unit Tests Only

Fast, isolated tests that validate request construction:

```ruby
RSpec.describe BillingFormatter, :stripe_mock do
  it "sends correct parameters for subscription interval" do
    # stripe-mock validates request structure but returns static fixture
    price = Stripe::Price.create(
      currency: "usd",
      unit_amount: 1000,
      recurring: { interval: "month" }
    )

    expect(price.recurring.interval).to eq("month")
  end
end
```

### 2. Use VCR + Stripe Test Mode for Integration Tests

Tests that need real API behavior:

```ruby
RSpec.describe "Stripe webhook handling", :integration, :stripe_sandbox_api, :vcr do
  it "processes subscription created events" do
    # This hits the real test API (first run)
    # Then replays from cassette (subsequent runs)
    subscription = Stripe::Subscription.create(
      customer: "cus_test123",
      items: [{ price: "price_test123" }]
    )

    expect(subscription.status).to eq("active")
  end
end
```

### 3. Naming Conventions

**Tag Naming:**
- `:integration` - Full external API tests
- `:vcr` - Tests that record/replay HTTP
- `:stripe_mock` - Tests using stripe-mock server
- `:stripe_sandbox_api` - Tests hitting Stripe test mode
- `:slow` - Long-running tests to skip in CI

**Test Descriptions:**
- Auto-generate cassette names
- Keep descriptions concise and unique
- Avoid special characters

**Good:**

```ruby
it "creates customer with email" do
  # Cassette: billing_creates_customer_with_email.yml
end
```

**Bad:**

```ruby
it "creates customer with email (special: test@example.com)" do
  # Cassette: billing_creates_customer_with_email_special_testexamplecom.yml
end
```

### 4. VCR Management

**Configure VCR properly:**

```ruby
VCR.configure do |config|
  config.default_cassette_options = {
    record: :once,  # or :new_episodes for updates
    match_requests_on: [:method, :uri, :body]
  }

  # Auto-name cassettes from test description
  config.configure_rspec_metadata!
end
```

**Per-test cassette control:**

```ruby
it 'handles updated API response', vcr: { record: :new_episodes } do
  # Forces re-recording to catch API changes
end
```

**Re-record when Stripe API changes:**

```bash
# Delete old cassette
rm spec/fixtures/vcr_cassettes/specific_test.yml

# Re-record with real API
INTEGRATION=true STRIPE_KEY=sk_test_xxx bundle exec rspec spec/path/to/spec.rb:42
```

### 5. CI Configuration

**Separate unit and integration test runs:**

```yaml
# .github/workflows/test.yml
- name: Unit tests
  run: bundle exec rspec --tag ~integration

- name: Integration tests
  run: INTEGRATION=true bundle exec rspec --tag integration
  env:
    STRIPE_KEY: ${{ secrets.STRIPE_KEY }}
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

| Variable           | Purpose                          | Example               |
| ------------------ | -------------------------------- | --------------------- |
| `INTEGRATION`      | Enable integration tests         | `true` / `false`      |
| `STRIPE_KEY`       | Real test API key for VCR        | `sk_test_xxx`         |
| `STRIPE_API_KEY`   | Legacy - use `STRIPE_KEY`        | `sk_test_xxx`         |
| `STRIPE_MOCK_PORT` | Custom mock server port          | `12111` (default)     |
| `VCR_MODE`         | Force cassette re-recording      | `all`, `once`, `none` |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        RSpec Test Suite                      │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           │
         ┌─────────────────┴──────────────────┐
         │                                    │
         │ UNIT TESTS                         │ INTEGRATION TESTS
         │ (:unit, :stripe_mock)                     │ (:integration, :stripe_sandbox_api, :vcr)
         │                                    │
         ▼                                    ▼
   stripe-mock                          VCR Cassette
   (localhost:12111)                          │
         │                                    │
         ▼                                    ├─exists───► Replay recorded response
   Static fixtures                            │
   (validates request structure)              └─missing──► Record from real API
                                                                │
                                                                ▼
                                                          api.stripe.com
                                                          (test/sandbox mode)
```

## Summary

**Key Takeaways:**

1. **stripe-mock is for unit tests ONLY** - validates request construction, returns static fixtures
2. **VCR + Stripe test mode for integration tests** - captures real API behavior for reliable testing
3. **Tag-based organization** - use `:stripe_mock`, `:integration`, `:stripe_sandbox_api`, `:vcr` tags
4. **Shared examples when possible** - DRY approach for testing same behavior at both levels
5. **Always scrub sensitive data** - filter API keys from VCR cassettes
6. **Re-record periodically** - refresh cassettes to catch API changes

This tag-based approach keeps all tests in standard locations while providing flexible execution control.

## Reference

- **stripe-mock**: https://github.com/stripe/stripe-mock
- **VCR**: https://github.com/vcr/vcr
- **Stripe Testing**: https://stripe.com/docs/testing
