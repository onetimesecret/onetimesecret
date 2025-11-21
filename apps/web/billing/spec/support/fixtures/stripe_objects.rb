# frozen_string_literal: true

# apps/web/billing/spec/support/fixtures/stripe_objects.rb
#
# Fixture data for Stripe API objects

module StripeFixtures
  # Complete customer fixture with all fields
  def customer_fixture(overrides = {})
    {
      id: 'cus_test123',
      object: 'customer',
      address: nil,
      balance: 0,
      created: 1_609_459_200,
      currency: 'usd',
      default_source: nil,
      delinquent: false,
      description: 'Test customer for Onetime Secret',
      discount: nil,
      email: 'customer@example.com',
      invoice_prefix: 'ABC123',
      invoice_settings: {
        custom_fields: nil,
        default_payment_method: 'pm_test123',
        footer: nil
      },
      livemode: false,
      metadata: {
        user_id: 'test_user_123',
        organization_id: 'org_test_456'
      },
      name: 'Test Customer',
      phone: nil,
      preferred_locales: ['en'],
      shipping: nil,
      tax_exempt: 'none'
    }.merge(overrides)
  end

  # Complete subscription fixture
  def subscription_fixture(overrides = {})
    {
      id: 'sub_test123',
      object: 'subscription',
      application_fee_percent: nil,
      automatic_tax: { enabled: false },
      billing_cycle_anchor: 1_609_459_200,
      billing_thresholds: nil,
      cancel_at: nil,
      cancel_at_period_end: false,
      canceled_at: nil,
      collection_method: 'charge_automatically',
      created: 1_609_459_200,
      current_period_end: 1_612_137_600,
      current_period_start: 1_609_459_200,
      customer: 'cus_test123',
      days_until_due: nil,
      default_payment_method: 'pm_test123',
      default_source: nil,
      default_tax_rates: [],
      discount: nil,
      ended_at: nil,
      items: {
        object: 'list',
        data: [subscription_item_fixture],
        has_more: false,
        total_count: 1,
        url: '/v1/subscription_items?subscription=sub_test123'
      },
      latest_invoice: 'in_test123',
      livemode: false,
      metadata: {
        tier: 'professional',
        interval: 'month',
        region: 'US'
      },
      next_pending_invoice_item_invoice: nil,
      pause_collection: nil,
      payment_settings: {
        payment_method_options: nil,
        payment_method_types: nil
      },
      pending_invoice_item_interval: nil,
      pending_setup_intent: nil,
      pending_update: nil,
      schedule: nil,
      start_date: 1_609_459_200,
      status: 'active',
      test_clock: nil,
      transfer_data: nil,
      trial_end: nil,
      trial_start: nil
    }.merge(overrides)
  end

  # Subscription item fixture
  def subscription_item_fixture(overrides = {})
    {
      id: 'si_test123',
      object: 'subscription_item',
      billing_thresholds: nil,
      created: 1_609_459_200,
      metadata: {},
      price: price_fixture,
      quantity: 1,
      subscription: 'sub_test123',
      tax_rates: []
    }.merge(overrides)
  end

  # Price fixture
  def price_fixture(overrides = {})
    {
      id: 'price_test123',
      object: 'price',
      active: true,
      billing_scheme: 'per_unit',
      created: 1_609_459_200,
      currency: 'usd',
      livemode: false,
      lookup_key: nil,
      metadata: {
        interval: 'month',
        region: 'US',
        tier: 'professional'
      },
      nickname: 'Professional Monthly US',
      product: 'prod_test123',
      recurring: {
        aggregate_usage: nil,
        interval: 'month',
        interval_count: 1,
        trial_period_days: nil,
        usage_type: 'licensed'
      },
      tax_behavior: 'unspecified',
      tiers_mode: nil,
      transform_quantity: nil,
      type: 'recurring',
      unit_amount: 2900,
      unit_amount_decimal: '2900'
    }.merge(overrides)
  end

  # Product fixture
  def product_fixture(overrides = {})
    {
      id: 'prod_test123',
      object: 'product',
      active: true,
      attributes: [],
      created: 1_609_459_200,
      default_price: 'price_test123',
      description: 'Professional plan for teams and businesses',
      images: [],
      livemode: false,
      metadata: {
        tier: 'professional',
        features: 'advanced_sharing,priority_support,custom_branding',
        max_secrets: '1000',
        max_views: '100',
        limits: '{"secrets":1000,"views":100,"ttl":2592000}'
      },
      name: 'Professional',
      package_dimensions: nil,
      shippable: nil,
      statement_descriptor: nil,
      tax_code: nil,
      type: 'service',
      unit_label: nil,
      updated: 1_609_459_200,
      url: nil
    }.merge(overrides)
  end

  # Invoice fixture
  def invoice_fixture(overrides = {})
    {
      id: 'in_test123',
      object: 'invoice',
      account_country: 'US',
      account_name: 'Onetime Secret',
      account_tax_ids: nil,
      amount_due: 2900,
      amount_paid: 2900,
      amount_remaining: 0,
      application_fee_amount: nil,
      attempt_count: 1,
      attempted: true,
      auto_advance: true,
      automatic_tax: { enabled: false, status: nil },
      billing_reason: 'subscription_cycle',
      charge: 'ch_test123',
      collection_method: 'charge_automatically',
      created: 1_609_459_200,
      currency: 'usd',
      custom_fields: nil,
      customer: 'cus_test123',
      customer_address: nil,
      customer_email: 'customer@example.com',
      customer_name: 'Test Customer',
      customer_phone: nil,
      customer_shipping: nil,
      customer_tax_exempt: 'none',
      customer_tax_ids: [],
      default_payment_method: 'pm_test123',
      default_source: nil,
      default_tax_rates: [],
      description: nil,
      discount: nil,
      discounts: [],
      due_date: nil,
      ending_balance: 0,
      footer: nil,
      hosted_invoice_url: 'https://invoice.stripe.com/i/test',
      invoice_pdf: 'https://pay.stripe.com/invoice/test/pdf',
      lines: {
        object: 'list',
        data: [invoice_line_item_fixture],
        has_more: false,
        total_count: 1,
        url: '/v1/invoices/in_test123/lines'
      },
      livemode: false,
      metadata: {},
      next_payment_attempt: nil,
      number: 'ABC123-0001',
      paid: true,
      paid_out_of_band: false,
      payment_intent: 'pi_test123',
      payment_settings: {
        payment_method_options: nil,
        payment_method_types: nil
      },
      period_end: 1_612_137_600,
      period_start: 1_609_459_200,
      post_payment_credit_notes_amount: 0,
      pre_payment_credit_notes_amount: 0,
      receipt_number: nil,
      starting_balance: 0,
      statement_descriptor: nil,
      status: 'paid',
      status_transitions: {
        finalized_at: 1_609_459_200,
        marked_uncollectible_at: nil,
        paid_at: 1_609_459_200,
        voided_at: nil
      },
      subscription: 'sub_test123',
      subtotal: 2900,
      tax: nil,
      test_clock: nil,
      total: 2900,
      total_discount_amounts: [],
      total_tax_amounts: [],
      transfer_data: nil,
      webhooks_delivered_at: 1_609_459_200
    }.merge(overrides)
  end

  # Invoice line item fixture
  def invoice_line_item_fixture(overrides = {})
    {
      id: 'il_test123',
      object: 'line_item',
      amount: 2900,
      currency: 'usd',
      description: 'Professional × 1',
      discount_amounts: [],
      discountable: true,
      discounts: [],
      livemode: false,
      metadata: {},
      period: {
        end: 1_612_137_600,
        start: 1_609_459_200
      },
      price: price_fixture,
      proration: false,
      quantity: 1,
      subscription: 'sub_test123',
      subscription_item: 'si_test123',
      tax_amounts: [],
      tax_rates: [],
      type: 'subscription'
    }.merge(overrides)
  end

  # Refund fixture
  def refund_fixture(overrides = {})
    {
      id: 'ref_test123',
      object: 'refund',
      amount: 2900,
      balance_transaction: 'txn_test123',
      charge: 'ch_test123',
      created: 1_609_459_200,
      currency: 'usd',
      metadata: {},
      payment_intent: 'pi_test123',
      reason: nil,
      receipt_number: nil,
      source_transfer_reversal: nil,
      status: 'succeeded',
      transfer_reversal: nil
    }.merge(overrides)
  end

  # Payment method fixture
  def payment_method_fixture(overrides = {})
    {
      id: 'pm_test123',
      object: 'payment_method',
      billing_details: {
        address: {
          city: nil,
          country: nil,
          line1: nil,
          line2: nil,
          postal_code: nil,
          state: nil
        },
        email: 'customer@example.com',
        name: 'Test Customer',
        phone: nil
      },
      card: {
        brand: 'visa',
        checks: {
          address_line1_check: nil,
          address_postal_code_check: nil,
          cvc_check: 'pass'
        },
        country: 'US',
        exp_month: 12,
        exp_year: 2025,
        fingerprint: 'test_fingerprint',
        funding: 'credit',
        generated_from: nil,
        last4: '4242',
        networks: {
          available: ['visa'],
          preferred: nil
        },
        three_d_secure_usage: { supported: true },
        wallet: nil
      },
      created: 1_609_459_200,
      customer: 'cus_test123',
      livemode: false,
      metadata: {},
      type: 'card'
    }.merge(overrides)
  end

  # Checkout session fixture
  def checkout_session_fixture(overrides = {})
    {
      id: 'cs_test123',
      object: 'checkout.session',
      after_expiration: nil,
      allow_promotion_codes: nil,
      amount_subtotal: 2900,
      amount_total: 2900,
      automatic_tax: { enabled: false, status: nil },
      billing_address_collection: nil,
      cancel_url: 'https://example.com/cancel',
      client_reference_id: nil,
      consent: nil,
      consent_collection: nil,
      created: 1_609_459_200,
      currency: 'usd',
      customer: 'cus_test123',
      customer_creation: nil,
      customer_details: {
        email: 'customer@example.com',
        phone: nil,
        tax_exempt: 'none',
        tax_ids: []
      },
      customer_email: nil,
      expires_at: 1_609_545_600,
      livemode: false,
      locale: nil,
      metadata: {
        user_id: 'test_user_123'
      },
      mode: 'subscription',
      payment_intent: nil,
      payment_link: nil,
      payment_method_options: {},
      payment_method_types: ['card'],
      payment_status: 'paid',
      phone_number_collection: { enabled: false },
      recovered_from: nil,
      setup_intent: nil,
      shipping: nil,
      shipping_address_collection: nil,
      shipping_options: [],
      shipping_rate: nil,
      status: 'complete',
      submit_type: nil,
      subscription: 'sub_test123',
      success_url: 'https://example.com/success',
      total_details: {
        amount_discount: 0,
        amount_shipping: 0,
        amount_tax: 0
      },
      url: nil
    }.merge(overrides)
  end
end
