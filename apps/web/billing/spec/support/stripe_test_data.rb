# frozen_string_literal: true

# apps/web/billing/spec/support/stripe_test_data.rb
#
# Constants for Stripe integration tests.
# Official test data from Stripe documentation.
#
# Actual Stripe objects will be created via stripe-mock server + VCR.

module StripeTestData
  # Test card numbers from Stripe's testing documentation
  # https://stripe.com/docs/testing#cards
  CARDS = {
    visa_success: '4242424242424242',
    visa_decline: '4000000000000002',
    visa_insufficient_funds: '4000000000009995',
    visa_lost_card: '4000000000009987',
    visa_stolen_card: '4000000000009979',
    visa_expired: '4000000000000069',
    visa_cvc_fail: '4000000000000127',
    visa_processing_error: '4000000000000119',
    visa_3ds_required: '4000002500003155',
    mastercard_success: '5555555555554444',
    amex_success: '378282246310005',
    discover_success: '6011111111111117',
    diners_success: '3056930009020004',
    jcb_success: '3566002020360505'
  }.freeze

  # Test error codes from Stripe
  ERROR_CODES = {
    card_declined: 'card_declined',
    expired_card: 'expired_card',
    incorrect_cvc: 'incorrect_cvc',
    processing_error: 'processing_error',
    incorrect_number: 'incorrect_number',
    invalid_expiry_month: 'invalid_expiry_month',
    invalid_expiry_year: 'invalid_expiry_year',
    insufficient_funds: 'insufficient_funds'
  }.freeze

  # Webhook event types handled by the system
  WEBHOOK_EVENTS = {
    checkout_completed: 'checkout.session.completed',
    subscription_created: 'customer.subscription.created',
    subscription_updated: 'customer.subscription.updated',
    subscription_deleted: 'customer.subscription.deleted',
    invoice_paid: 'invoice.paid',
    invoice_payment_failed: 'invoice.payment_failed',
    payment_intent_succeeded: 'payment_intent.succeeded',
    payment_intent_failed: 'payment_intent.payment_failed',
    product_updated: 'product.updated',
    price_updated: 'price.updated',
    customer_updated: 'customer.updated',
    customer_deleted: 'customer.deleted'
  }.freeze
end
