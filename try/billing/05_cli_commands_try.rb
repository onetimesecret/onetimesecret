# try/billing/05_cli_commands_try.rb
#
# frozen_string_literal: true

require_relative '../support/test_helpers'

# Billing CLI Commands tests
#
# Tests billing CLI commands for subscription management, customer creation,
# and test helpers. Requires STRIPE_KEY environment variable set to a test key.
#
# Run with:
#   STRIPE_KEY=sk_test_xxx bundle exec try --agent try/billing/05_cli_commands_try.rb

## Setup: Skip if no Stripe test key
unless ENV['STRIPE_KEY']&.start_with?('sk_test_')
  puts 'Skipping: Requires STRIPE_KEY=sk_test_... for Stripe API access'
  exit 0
end

## Load Stripe and configure
require 'stripe'
Stripe.api_key = ENV['STRIPE_KEY']

## Test: Create test customer via CLI works
`bin/ots billing test create-customer` =~ /Customer created:/
#=> 0

## Test: Extract customer ID from output
@output = `bin/ots billing test create-customer`
@customer_id = @output.match(/ID: (cus_\w+)/)[1]
@customer_id.start_with?('cus_')
#=> true

## Test: Verify customer exists in Stripe
@customer = Stripe::Customer.retrieve(@customer_id)
@customer.email.start_with?('test-')
#=> true

## Test: Customer has test card attached
@payment_methods = Stripe::PaymentMethod.list({ customer: @customer_id })
@payment_methods.data.size
#=> 1

## Test: Card is Visa test card
@pm = @payment_methods.data.first
@pm.card.last4
#=> '4242'

## Test: Create customer via CLI with email
`bin/ots billing customers create --email test-cli@example.com --name "CLI Test" <<< 'y'` =~ /Customer created successfully/
#=> 0

## Test: List customers includes our test customer
`bin/ots billing customers --email test-cli@example.com` =~ /test-cli@example.com/
#=> 0

## Setup: Create a subscription for testing cancellation
# First get an active price
@prices = Stripe::Price.list({ active: true, limit: 1 })
if @prices.data.empty?
  # Create a product and price for testing
  @product = Stripe::Product.create({
    name: 'Test Product',
    metadata: {
      app: 'onetimesecret',
      plan_id: 'test_v1',
      tier: 'test',
      region: 'global',
      capabilities: 'test'
    }
  })
  @price = Stripe::Price.create({
    product: @product.id,
    unit_amount: 900,
    currency: 'usd',
    recurring: { interval: 'month' }
  })
else
  @price = @prices.data.first
end

## Create test subscription
@subscription = Stripe::Subscription.create({
  customer: @customer_id,
  items: [{ price: @price.id }],
  payment_behavior: 'default_incomplete'
})
@subscription.status
#=~ /incomplete|active|trialing/

## Test: Cancel subscription at period end via CLI
`bin/ots billing subscriptions cancel #{@subscription.id} --force` =~ /Subscription canceled successfully/
#=> 0

## Test: Verify subscription marked for cancellation
@canceled_sub = Stripe::Subscription.retrieve(@subscription.id)
@canceled_sub.cancel_at_period_end
#=> true

## Setup: Create another subscription for immediate cancellation
@subscription2 = Stripe::Subscription.create({
  customer: @customer_id,
  items: [{ price: @price.id }],
  payment_behavior: 'default_incomplete'
})

## Test: Cancel subscription immediately via CLI
`bin/ots billing subscriptions cancel #{@subscription2.id} --immediately --force` =~ /Subscription canceled successfully/
#=> 0

## Test: Verify subscription is canceled
@canceled_sub2 = Stripe::Subscription.retrieve(@subscription2.id)
@canceled_sub2.status
#=> 'canceled'

## Teardown: Clean up test resources
Stripe::Customer.delete(@customer_id)
Stripe::Product.delete(@product.id) if defined?(@product) && @product

## Test: Cleanup successful
true
#=> true
