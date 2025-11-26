# apps/web/billing/try/05_cli_commands_try.rb
#
# frozen_string_literal: true

require_relative '../../../../try/support/test_helpers'

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
      capabilities: 'test',
      tenancy: 'single',
      created: Time.now.utc.iso8601
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
`bin/ots billing subscriptions cancel #{@subscription.id} --yes` =~ /Subscription canceled successfully/
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
`bin/ots billing subscriptions cancel #{@subscription2.id} --immediately --yes` =~ /Subscription canceled successfully/
#=> 0

## Test: Verify subscription is canceled
@canceled_sub2 = Stripe::Subscription.retrieve(@subscription2.id)
@canceled_sub2.status
#=> 'canceled'

## Sprint 2 Tests: Subscription Pause/Resume and Customer Show

## Setup: Create another subscription for pause/resume testing
@subscription3 = Stripe::Subscription.create({
  customer: @customer_id,
  items: [{ price: @price.id }],
  payment_behavior: 'default_incomplete'
})

## Test: Pause subscription via CLI
`bin/ots billing subscriptions pause #{@subscription3.id} --yes` =~ /Subscription paused successfully/
#=> 0

## Test: Verify subscription is paused in Stripe
@paused_sub = Stripe::Subscription.retrieve(@subscription3.id)
@paused_sub.pause_collection.present?
#=> true

## Test: Resume paused subscription via CLI
`bin/ots billing subscriptions resume #{@subscription3.id} --yes` =~ /Subscription resumed successfully/
#=> 0

## Test: Verify subscription is no longer paused
@resumed_sub = Stripe::Subscription.retrieve(@subscription3.id)
@resumed_sub.pause_collection.nil?
#=> true

## Test: Show customer details via CLI includes email
`bin/ots billing customers show #{@customer_id}` =~ /Email: #{Regexp.escape(@customer.email)}/
#=> 0

## Test: Show customer details includes payment methods
@show_output = `bin/ots billing customers show #{@customer_id}`
@show_output.include?('Payment Methods:') && @show_output.include?('****4242')
#=> true

## Test: Show customer details includes subscriptions
@show_output.include?('Subscriptions:') && @show_output.include?(@subscription3.id)
#=> true

## Sprint 3 Tests: Subscription Update, Customer Delete, Payment Method Default

## Setup: Create another subscription for update testing
@subscription4 = Stripe::Subscription.create({
  customer: @customer_id,
  items: [{ price: @price.id }],
  payment_behavior: 'default_incomplete'
})

## Test: Update subscription quantity via CLI
`bin/ots billing subscriptions update #{@subscription4.id} --quantity 2 <<< 'y'` =~ /Subscription updated successfully/
#=> 0

## Test: Verify subscription quantity updated in Stripe
@updated_sub = Stripe::Subscription.retrieve(@subscription4.id)
@updated_sub.items.data.first.quantity
#=> 2

## Setup: Get another active price for price update test
@prices2 = Stripe::Price.list({ active: true, limit: 2 })
if @prices2.data.size >= 2
  @new_price = @prices2.data.find { |p| p.id != @price.id }
else
  # Create another price for testing
  @new_price = Stripe::Price.create({
    product: @product.id,
    unit_amount: 1900,
    currency: 'usd',
    recurring: { interval: 'month' }
  })
end

## Test: Update subscription price via CLI
`bin/ots billing subscriptions update #{@subscription4.id} --price #{@new_price.id} <<< 'y'` =~ /Subscription updated successfully/
#=> 0

## Test: Verify subscription price updated in Stripe
@updated_sub2 = Stripe::Subscription.retrieve(@subscription4.id)
@updated_sub2.items.data.first.price.id
#=> @new_price.id

## Test: Update subscription with no-prorate option
`bin/ots billing subscriptions update #{@subscription4.id} --quantity 3 --no-prorate <<< 'y'` =~ /Subscription updated successfully/
#=> 0

## Test: Verify quantity updated to 3
@updated_sub3 = Stripe::Subscription.retrieve(@subscription4.id)
@updated_sub3.items.data.first.quantity
#=> 3

## Test: Set default payment method via CLI
`bin/ots billing payment-methods set-default #{@pm.id} --customer #{@customer_id} <<< 'y'` =~ /Default payment method updated successfully/
#=> 0

## Test: Verify default payment method set in Stripe
@customer_updated = Stripe::Customer.retrieve(@customer_id)
@customer_updated.invoice_settings.default_payment_method
#=> @pm.id

## Test: Customer delete blocked with active subscription
@delete_output = `bin/ots billing customers delete #{@customer_id} 2>&1`
@delete_output.include?('Customer has active subscriptions')
#=> true

## Setup: Cancel all subscriptions for customer
[@subscription, @subscription2, @subscription3, @subscription4].each do |sub|
  begin
    Stripe::Subscription.update(sub.id, { cancel_at_period_end: true })
  rescue Stripe::InvalidRequestError
    # Already canceled
  end
end

## Test: Customer delete with force flag works even with subscriptions
`bin/ots billing customers delete #{@customer_id} --yes` =~ /Customer deleted successfully/
#=> 0

## Test: Verify customer deleted in Stripe
begin
  Stripe::Customer.retrieve(@customer_id)
  false
rescue Stripe::InvalidRequestError => e
  e.message.include?('No such customer')
end
#=> true

## Teardown: Clean up test resources
Stripe::Product.delete(@product.id) if defined?(@product) && @product

## Sprint 4 Tests: Refunds and Webhook Testing

## Setup: Create new customer for refund tests
@refund_customer = Stripe::Customer.create({
  email: "refund-test-#{SecureRandom.hex(4)}@example.com",
  name: "Refund Test Customer"
})

## Setup: Attach payment method
@refund_pm = Stripe::PaymentMethod.create({
  type: 'card',
  card: {
    number: '4242424242424242',
    exp_month: 12,
    exp_year: Time.now.year + 2,
    cvc: '123'
  }
})
Stripe::PaymentMethod.attach(@refund_pm.id, { customer: @refund_customer.id })
Stripe::Customer.update(@refund_customer.id, {
  invoice_settings: { default_payment_method: @refund_pm.id }
})

## Setup: Create a charge for refund testing
@payment_intent = Stripe::PaymentIntent.create({
  amount: 1000,
  currency: 'usd',
  customer: @refund_customer.id,
  payment_method: @refund_pm.id,
  confirm: true,
  automatic_payment_methods: { enabled: true, allow_redirects: 'never' }
})

## Test: Payment intent has a charge
@charge_id = @payment_intent.charges.data.first&.id
@charge_id.to_s.start_with?('ch_')
#=> true

## Test: Create refund via CLI
`bin/ots billing refunds create --charge #{@charge_id} --reason requested_by_customer --yes` =~ /Refund created successfully/
#=> 0

## Test: Verify refund exists in Stripe
@refund_list = Stripe::Refund.list({ charge: @charge_id, limit: 1 })
@refund_list.data.size
#=> 1

## Test: Refund has correct amount (full refund)
@refund = @refund_list.data.first
@refund.amount
#=> 1000

## Test: Refund has correct reason
@refund.reason
#=> 'requested_by_customer'

## Test: List refunds via CLI includes our refund
`bin/ots billing refunds --charge #{@charge_id}` =~ /#{@refund.id}/
#=> 0

## Test: Trigger webhook command shows appropriate message
@webhook_output = `bin/ots billing test trigger-webhook customer.created 2>&1`
# Will either trigger successfully or show "Stripe CLI not found"
@webhook_output.include?('Triggering test webhook') || @webhook_output.include?('Stripe CLI not found')
#=> true

## Teardown: Clean up refund test resources
Stripe::Customer.delete(@refund_customer.id)

## Sprint 5 Tests: Products Update Command

## Setup: Create test product for update testing
@update_product = Stripe::Product.create({
  name: 'Update Test Product',
  metadata: {
    app: 'onetimesecret',
    plan_id: 'update_test_v1',
    tier: 'single_team',
    region: 'us-east',
    tenancy: 'single',
    capabilities: 'create_secrets,basic_sharing',
    created: Time.now.utc.iso8601,
    limit_teams: '1',
    limit_members_per_team: '10'
  }
})

## Test: Product created with correct metadata
@update_product.metadata['plan_id']
#=> 'update_test_v1'

## Test: Update single field (tier) preserves other metadata
`bin/ots billing products update #{@update_product.id} --tier multi_team <<< 'y'` =~ /Product updated successfully/
#=> 0

## Test: Verify tier was updated
@updated_product = Stripe::Product.retrieve(@update_product.id)
@updated_product.metadata['tier']
#=> 'multi_team'

## Test: Verify other fields were preserved (not set to empty)
@updated_product.metadata['plan_id']
#=> 'update_test_v1'

## Test: Verify capabilities were preserved
@updated_product.metadata['capabilities']
#=> 'create_secrets,basic_sharing'

## Test: Verify limits were preserved
@updated_product.metadata['limit_teams']
#=> '1'

## Test: Update multiple fields at once
`bin/ots billing products update #{@update_product.id} --tier enterprise --capabilities "create_secrets,basic_sharing,api_access,audit_logs" <<< 'y'` =~ /Product updated successfully/
#=> 0

## Test: Verify both fields updated
@multi_updated = Stripe::Product.retrieve(@update_product.id)
@multi_updated.metadata['tier']
#=> 'enterprise'

## Test: Verify capabilities updated
@multi_updated.metadata['capabilities']
#=> 'create_secrets,basic_sharing,api_access,audit_logs'

## Test: Verify unrelated fields still preserved
@multi_updated.metadata['region']
#=> 'us-east'

## Teardown: Clean up test product
Stripe::Product.delete(@update_product.id)

## Test: Cleanup successful
true
#=> true
