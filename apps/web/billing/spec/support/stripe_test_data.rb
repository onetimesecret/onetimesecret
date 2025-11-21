# frozen_string_literal: true

# apps/web/billing/spec/support/stripe_test_data.rb
#
# Test data and constants for Stripe integration tests

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

  # Sample customer data
  CUSTOMERS = {
    basic: {
      email: 'customer@example.com',
      name: 'Test Customer',
      metadata: { user_id: 'test_user_123' }
    },
    with_payment: {
      email: 'paying@example.com',
      name: 'Paying Customer',
      payment_method: 'pm_card_visa',
      invoice_settings: { default_payment_method: 'pm_card_visa' },
      metadata: { user_id: 'paying_user_456' }
    },
    enterprise: {
      email: 'enterprise@example.com',
      name: 'Enterprise Customer',
      metadata: {
        user_id: 'enterprise_789',
        tier: 'enterprise',
        organization_id: 'org_abc123'
      }
    }
  }.freeze

  # Sample subscription data
  SUBSCRIPTIONS = {
    monthly_personal: {
      items: [{ price: 'price_personal_monthly_us' }],
      metadata: { tier: 'personal', interval: 'month', region: 'US' }
    },
    annual_professional: {
      items: [{ price: 'price_professional_annual_us' }],
      metadata: { tier: 'professional', interval: 'year', region: 'US' }
    },
    enterprise_custom: {
      items: [{ price: 'price_enterprise_custom' }],
      metadata: { tier: 'enterprise', interval: 'month', region: 'US', contract_term: '12' }
    }
  }.freeze

  # Sample product metadata for plan identification
  PRODUCT_METADATA = {
    personal: {
      tier: 'personal',
      features: 'basic_sharing,email_support',
      max_secrets: '100',
      max_views: '10'
    },
    professional: {
      tier: 'professional',
      features: 'advanced_sharing,priority_support,custom_branding',
      max_secrets: '1000',
      max_views: '100'
    },
    agency: {
      tier: 'agency',
      features: 'team_management,api_access,priority_support,custom_branding',
      max_secrets: '10000',
      max_views: '1000'
    },
    enterprise: {
      tier: 'enterprise',
      features: 'unlimited_sharing,dedicated_support,sla,custom_integration',
      max_secrets: 'unlimited',
      max_views: 'unlimited'
    }
  }.freeze

  # Sample price metadata
  PRICE_METADATA = {
    monthly_us: {
      interval: 'month',
      region: 'US',
      currency: 'usd'
    },
    annual_us: {
      interval: 'year',
      region: 'US',
      currency: 'usd',
      discount_percent: '20'
    },
    monthly_eu: {
      interval: 'month',
      region: 'EU',
      currency: 'eur'
    }
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

  # Sample webhook payloads
  def self.webhook_payload(event_type, data_object)
    {
      id: "evt_#{SecureRandom.hex(12)}",
      type: event_type,
      data: { object: data_object },
      created: Time.now.to_i,
      livemode: false,
      api_version: '2023-10-16',
      request: { id: "req_#{SecureRandom.hex(8)}", idempotency_key: nil }
    }
  end

  # Generate a checkout session completed payload
  def self.checkout_session_payload(customer_id: 'cus_test', subscription_id: 'sub_test')
    webhook_payload(WEBHOOK_EVENTS[:checkout_completed], {
      id: "cs_#{SecureRandom.hex(12)}",
      customer: customer_id,
      subscription: subscription_id,
      mode: 'subscription',
      status: 'complete',
      payment_status: 'paid',
      metadata: { user_id: 'test_user_123' }
    })
  end

  # Generate a subscription updated payload
  def self.subscription_updated_payload(subscription_id: 'sub_test', status: 'active')
    webhook_payload(WEBHOOK_EVENTS[:subscription_updated], {
      id: subscription_id,
      customer: 'cus_test',
      status: status,
      current_period_start: Time.now.to_i,
      current_period_end: (Time.now + 30.days).to_i,
      items: {
        data: [{
          id: 'si_test',
          price: {
            id: 'price_test',
            product: 'prod_test',
            unit_amount: 1000,
            currency: 'usd',
            recurring: { interval: 'month' }
          }
        }]
      },
      metadata: { tier: 'professional' }
    })
  end

  # Generate an invoice payment failed payload
  def self.invoice_payment_failed_payload(invoice_id: 'in_test', attempt_count: 1)
    webhook_payload(WEBHOOK_EVENTS[:invoice_payment_failed], {
      id: invoice_id,
      customer: 'cus_test',
      subscription: 'sub_test',
      status: 'open',
      attempt_count: attempt_count,
      amount_due: 1000,
      amount_paid: 0,
      currency: 'usd',
      next_payment_attempt: (Time.now + 1.day).to_i
    })
  end
end
