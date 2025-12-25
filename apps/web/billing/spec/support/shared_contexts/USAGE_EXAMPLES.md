# Shared Context Usage Examples

Practical examples showing how to use the billing test shared contexts.

## Overview

Four shared contexts for different testing scenarios:

| Context | Purpose | Use Case |
|---------|---------|----------|
| `with_test_plans` | Load plans from YAML | Unit tests without Stripe API |
| `with_authenticated_customer` | Authenticated user session | Tests requiring auth |
| `with_organization` | Organization with owner | Tests requiring org access |
| `with_stripe_vcr` | Stripe API integration | Tests making real Stripe calls |

## Quick Reference

### Unit Test (No Stripe)
```ruby
include_context 'with_test_plans'
include_context 'with_authenticated_customer'
include_context 'with_organization'
```

### Integration Test (With Stripe)
```ruby
include_context 'with_stripe_vcr'
include_context 'with_authenticated_customer'
include_context 'with_organization'
```

## Example 1: Simple Unit Test (No Authentication)

Test that doesn't require user authentication.

```ruby
RSpec.describe 'BillingController' do
  include Rack::Test::Methods
  include_context 'with_test_plans'

  def app
    Rack::URLMap.new('/billing' => Billing::Application.new)
  end

  describe 'GET /billing/api/plans' do
    it 'returns list of available plans' do
      get '/billing/api/plans'

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')

      data = JSON.parse(last_response.body)
      expect(data['plans']).to be_an(Array)

      # Verify test plans loaded
      expect(test_plan_exists?('single_team')).to be true
      expect(test_plan_exists?('free')).to be true
    end

    it 'does not require authentication' do
      # No authentication context needed
      get '/billing/api/plans'

      expect(last_response.status).to eq(200)
    end
  end
end
```

## Example 2: Unit Test with Authentication

Test requiring authenticated customer but no organization.

```ruby
RSpec.describe 'BillingController' do
  include Rack::Test::Methods
  include_context 'with_test_plans'
  include_context 'with_authenticated_customer'

  def app
    Rack::URLMap.new('/billing' => Billing::Application.new)
  end

  describe 'GET /billing/api/customer/subscriptions' do
    it 'returns customer subscriptions' do
      get "/billing/api/customer/#{customer.extid}/subscriptions"

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')
    end

    it 'requires authentication' do
      clear_authentication

      get "/billing/api/customer/#{customer.extid}/subscriptions"

      expect(last_response.status).to eq(401)
    end

    it 'prevents access to other customers' do
      other_customer = create_other_customer

      get "/billing/api/customer/#{other_customer.extid}/subscriptions"

      expect(last_response.status).to eq(403)
    end
  end
end
```

## Example 3: Unit Test with Organization

Test requiring authenticated customer and organization.

```ruby
RSpec.describe 'BillingController' do
  include Rack::Test::Methods
  include_context 'with_test_plans'
  include_context 'with_authenticated_customer'
  include_context 'with_organization'

  def app
    Rack::URLMap.new('/billing' => Billing::Application.new)
  end

  describe 'GET /billing/api/org/:extid' do
    it 'returns billing overview for organization' do
      get "/billing/api/org/#{organization.extid}"

      expect(last_response.status).to eq(200)

      data = JSON.parse(last_response.body)
      expect(data['organization']['id']).to eq(organization.extid)
      expect(data['subscription']).to be_nil  # No Stripe subscription
      expect(data['usage']).to have_key('members')
    end

    it 'returns 403 when customer is not organization member' do
      other_customer = create_other_customer
      authenticate_as(other_customer)

      get "/billing/api/org/#{organization.extid}"

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Access denied')
    end

    it 'returns 403 when organization does not exist' do
      get '/billing/api/org/nonexistent_org_id'

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Organization not found')
    end

    it 'requires authentication' do
      clear_authentication

      get "/billing/api/org/#{organization.extid}"

      expect(last_response.status).to eq(401)
    end
  end
end
```

## Example 4: Unit Test with Validation

Test validating request parameters without Stripe.

```ruby
RSpec.describe 'BillingController' do
  include Rack::Test::Methods
  include_context 'with_test_plans'
  include_context 'with_authenticated_customer'
  include_context 'with_organization'

  def app
    Rack::URLMap.new('/billing' => Billing::Application.new)
  end

  describe 'POST /billing/api/org/:extid/checkout' do
    let(:valid_params) do
      {
        tier: 'single_team',
        billing_cycle: 'monthly'
      }
    end

    it 'returns 400 when tier is missing' do
      post "/billing/api/org/#{organization.extid}/checkout",
           valid_params.except(:tier).to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(400)
      expect(last_response.body).to include('Missing tier or billing_cycle')
    end

    it 'returns 400 when billing_cycle is missing' do
      post "/billing/api/org/#{organization.extid}/checkout",
           valid_params.except(:billing_cycle).to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(400)
      expect(last_response.body).to include('Missing tier or billing_cycle')
    end

    it 'returns 404 when plan is not found' do
      post "/billing/api/org/#{organization.extid}/checkout", {
        tier: 'nonexistent_tier',
        billing_cycle: 'monthly'
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(404)
      expect(last_response.body).to include('Plan not found')
    end

    it 'returns 403 when customer is not owner' do
      member = create_organization_member
      authenticate_as(member)

      post "/billing/api/org/#{organization.extid}/checkout",
           valid_params.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Owner access required')
    end
  end
end
```

## Example 5: Integration Test with Stripe

Test creating real Stripe resources via VCR.

```ruby
RSpec.describe 'BillingController', :integration do
  include Rack::Test::Methods
  include_context 'with_stripe_vcr'
  include_context 'with_authenticated_customer'
  include_context 'with_organization'

  def app
    Rack::URLMap.new('/billing' => Billing::Application.new)
  end

  describe 'POST /billing/api/org/:extid/checkout' do
    it 'creates Stripe checkout session', :vcr do
      post "/billing/api/org/#{organization.extid}/checkout", {
        tier: 'single_team',
        billing_cycle: 'monthly'
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)

      data = JSON.parse(last_response.body)
      expect(data['checkout_url']).to match(%r{\Ahttps://checkout\.stripe\.com/})
      expect(data['session_id']).to start_with('cs_test_')
    end

    it 'uses existing Stripe customer if available', :vcr do
      # Create real Stripe customer (VCR records this)
      stripe_customer = Stripe::Customer.create(email: organization.billing_email)
      set_stripe_customer(stripe_customer.id)

      post "/billing/api/org/#{organization.extid}/checkout", {
        tier: 'single_team',
        billing_cycle: 'monthly'
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)

      # Verify checkout session used existing customer
      data = JSON.parse(last_response.body)
      session = Stripe::Checkout::Session.retrieve(data['session_id'])
      expect(session.customer).to eq(stripe_customer.id)
    end
  end
end
```

## Example 6: Integration Test with Subscription

Test with active Stripe subscription.

```ruby
RSpec.describe 'BillingController', :integration do
  include Rack::Test::Methods
  include_context 'with_stripe_vcr'
  include_context 'with_authenticated_customer'
  include_context 'with_organization'

  def app
    Rack::URLMap.new('/billing' => Billing::Application.new)
  end

  describe 'GET /billing/api/org/:extid' do
    it 'returns subscription data when active subscription', :vcr do
      # Create Stripe customer with payment method
      stripe_customer = Stripe::Customer.create(email: customer.email)
      payment_method = Stripe::PaymentMethod.create(
        type: 'card',
        card: { token: 'tok_visa' }
      )
      Stripe::PaymentMethod.attach(payment_method.id, { customer: stripe_customer.id })
      Stripe::Customer.update(stripe_customer.id, {
        invoice_settings: { default_payment_method: payment_method.id }
      })

      # Get Stripe price ID from cached plan
      price_id = stripe_price_id_for('single_team', 'monthly')

      # Create subscription
      subscription = Stripe::Subscription.create(
        customer: stripe_customer.id,
        items: [{ price: price_id }]
      )

      # Update organization
      update_from_subscription(subscription)

      # Test endpoint
      get "/billing/api/org/#{organization.extid}"

      expect(last_response.status).to eq(200)

      data = JSON.parse(last_response.body)
      expect(data['subscription']['id']).to eq(subscription.id)
      expect(data['subscription']['status']).to match(/active|trialing/)
    end
  end
end
```

## Example 7: Test Plan Helpers

Using test plan helpers for assertions.

```ruby
RSpec.describe 'Plan Lookup' do
  include_context 'with_test_plans'

  it 'loads test plans from config' do
    # Check plan exists
    expect(test_plan_exists?('single_team')).to be true
    expect(test_plan_exists?('free')).to be true
    expect(test_plan_exists?('nonexistent')).to be false

    # Get plan details
    plan = test_plan('single_team')
    expect(plan[:name]).to eq('Identity Plus')
    expect(plan[:tier]).to eq('single_team')
    expect(plan[:region]).to eq('EU')

    # Check entitlements
    expect(plan[:entitlements]).to include('create_secrets', 'custom_domains')

    # Check limits
    expect(plan[:limits]['members_per_team.max']).to eq('10')
    expect(plan[:limits]['custom_domains.max']).to eq('unlimited')
  end

  it 'loads test entitlements' do
    entitlements = test_entitlements

    expect(entitlements).to have_key('create_secrets')
    expect(entitlements['create_secrets']['category']).to eq('core')
    expect(entitlements['custom_domains']['category']).to eq('infrastructure')
  end
end
```

## Example 8: Organization Member Tests

Testing member vs owner access.

```ruby
RSpec.describe 'Organization Access Control' do
  include Rack::Test::Methods
  include_context 'with_test_plans'
  include_context 'with_authenticated_customer'
  include_context 'with_organization'

  def app
    Rack::URLMap.new('/billing' => Billing::Application.new)
  end

  describe 'owner vs member access' do
    let(:member) { create_organization_member }

    it 'allows owner to access billing' do
      get "/billing/api/org/#{organization.extid}"

      expect(last_response.status).to eq(200)
    end

    it 'allows member to view billing (read-only)' do
      authenticate_as(member)

      get "/billing/api/org/#{organization.extid}"

      expect(last_response.status).to eq(200)
    end

    it 'prevents member from modifying billing' do
      authenticate_as(member)

      post "/billing/api/org/#{organization.extid}/checkout", {
        tier: 'single_team',
        billing_cycle: 'monthly'
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Owner access required')
    end
  end
end
```

## Best Practices

### 1. Choose the Right Context

**Unit Test (Fast)**:
```ruby
include_context 'with_test_plans'
```

**Integration Test (Slow)**:
```ruby
include_context 'with_stripe_vcr'
```

### 2. Layer Contexts Appropriately

Most common combinations:

```ruby
# Basic unit test
include_context 'with_test_plans'

# Authenticated unit test
include_context 'with_test_plans'
include_context 'with_authenticated_customer'

# Organization unit test
include_context 'with_test_plans'
include_context 'with_authenticated_customer'
include_context 'with_organization'

# Stripe integration test
include_context 'with_stripe_vcr'
include_context 'with_authenticated_customer'
include_context 'with_organization'
```

### 3. Use Helpers for Common Operations

```ruby
# Authentication helpers
clear_authentication          # Remove session
authenticate_as(customer)     # Switch user
create_other_customer         # Create non-auth customer

# Organization helpers
create_organization_member    # Add non-owner member
create_other_organization     # Create second org
set_stripe_customer(id)       # Associate Stripe customer

# Plan helpers
test_plan('single_team')      # Get plan from config
test_plan_exists?('free')     # Check plan exists
test_entitlements             # Load entitlements

# Stripe helpers (integration only)
cached_stripe_plan('single_team')  # Get from Redis
stripe_price_id_for('single_team') # Get Stripe price ID
```

### 4. Tag Integration Tests

Always tag integration tests with `:vcr`:

```ruby
it 'creates checkout session', :vcr do
  # Stripe API call here
end
```

### 5. Keep Unit Tests Simple

Avoid:
```ruby
# DON'T: Calling Stripe in unit test
include_context 'with_test_plans'

it 'creates subscription' do
  Stripe::Subscription.create(...)  # Wrong!
end
```

Do:
```ruby
# DO: Mock Stripe or move to integration test
include_context 'with_stripe_vcr'

it 'creates subscription', :vcr do
  Stripe::Subscription.create(...)  # Correct!
end
```

## Common Patterns

### Pattern 1: Test Both Auth and Unauth

```ruby
describe 'GET /endpoint' do
  context 'when authenticated' do
    include_context 'with_authenticated_customer'

    it 'allows access' do
      get '/endpoint'
      expect(last_response.status).to eq(200)
    end
  end

  context 'when not authenticated' do
    it 'denies access' do
      get '/endpoint'
      expect(last_response.status).to eq(401)
    end
  end
end
```

### Pattern 2: Test Owner vs Member

```ruby
describe 'POST /org/:id/checkout' do
  include_context 'with_authenticated_customer'
  include_context 'with_organization'

  context 'as owner' do
    it 'allows checkout' do
      post "/org/#{organization.extid}/checkout"
      expect(last_response.status).to eq(200)
    end
  end

  context 'as member' do
    before { authenticate_as(create_organization_member) }

    it 'denies checkout' do
      post "/org/#{organization.extid}/checkout"
      expect(last_response.status).to eq(403)
    end
  end
end
```

### Pattern 3: Validation Then Integration

```ruby
describe 'POST /checkout' do
  # Unit tests first (validation)
  describe 'validation', unit: true do
    include_context 'with_test_plans'

    it 'requires tier' do
      post '/checkout', { billing_cycle: 'monthly' }.to_json
      expect(last_response.status).to eq(400)
    end
  end

  # Integration tests last (Stripe)
  describe 'Stripe integration', :integration do
    include_context 'with_stripe_vcr'

    it 'creates session', :vcr do
      post '/checkout', { tier: 'single_team', billing_cycle: 'monthly' }.to_json
      expect(last_response.status).to eq(200)
    end
  end
end
```

## Troubleshooting

### "Plan not found" Error

**Problem**: Test looks for plan but gets nil.

**Solution**: Verify region matches:
```ruby
# In test file
before { mock_region!('EU') }

# In billing.test.yaml
plans:
  identity_plus_v1:
    region: EU  # Must match!
```

### "Stripe API key not set" Error

**Problem**: Integration test runs without VCR cassette.

**Solution**: Tag test with `:vcr`:
```ruby
it 'creates subscription', :vcr do  # Add :vcr tag
  # ...
end
```

### "Customer not authenticated" Error

**Problem**: Forgot to include auth context.

**Solution**:
```ruby
# Add authentication context
include_context 'with_authenticated_customer'
```

### "Organization not found" Error

**Problem**: Forgot to include organization context.

**Solution**:
```ruby
# Add organization context
include_context 'with_organization'
```
