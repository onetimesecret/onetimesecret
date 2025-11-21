# frozen_string_literal: true

# apps/web/billing/spec/support/fixtures/webhook_events.rb
#
# Fixture data for Stripe webhook events

module WebhookEventFixtures
  include StripeFixtures

  # Base event structure
  def event_fixture(type:, data_object:, **overrides)
    {
      id: "evt_#{SecureRandom.hex(12)}",
      object: 'event',
      api_version: '2023-10-16',
      created: Time.now.to_i,
      data: {
        object: data_object,
        previous_attributes: overrides[:previous_attributes]
      }.compact,
      livemode: false,
      pending_webhooks: 1,
      request: {
        id: "req_#{SecureRandom.hex(8)}",
        idempotency_key: SecureRandom.uuid
      },
      type: type
    }.merge(overrides.except(:previous_attributes))
  end

  # Checkout session completed event
  def checkout_session_completed_event(session: nil)
    session ||= checkout_session_fixture
    event_fixture(
      type: 'checkout.session.completed',
      data_object: session
    )
  end

  # Customer subscription created event
  def customer_subscription_created_event(subscription: nil)
    subscription ||= subscription_fixture
    event_fixture(
      type: 'customer.subscription.created',
      data_object: subscription
    )
  end

  # Customer subscription updated event
  def customer_subscription_updated_event(subscription: nil, previous_attributes: {})
    subscription ||= subscription_fixture
    event_fixture(
      type: 'customer.subscription.updated',
      data_object: subscription,
      previous_attributes: previous_attributes
    )
  end

  # Customer subscription deleted event
  def customer_subscription_deleted_event(subscription: nil)
    subscription ||= subscription_fixture(
      status: 'canceled',
      canceled_at: Time.now.to_i,
      ended_at: Time.now.to_i
    )
    event_fixture(
      type: 'customer.subscription.deleted',
      data_object: subscription
    )
  end

  # Invoice paid event
  def invoice_paid_event(invoice: nil)
    invoice ||= invoice_fixture(status: 'paid', paid: true)
    event_fixture(
      type: 'invoice.paid',
      data_object: invoice
    )
  end

  # Invoice payment failed event
  def invoice_payment_failed_event(invoice: nil, attempt_count: 1)
    invoice ||= invoice_fixture(
      status: 'open',
      paid: false,
      attempt_count: attempt_count,
      next_payment_attempt: (Time.now + 1.day).to_i
    )
    event_fixture(
      type: 'invoice.payment_failed',
      data_object: invoice
    )
  end

  # Invoice finalized event
  def invoice_finalized_event(invoice: nil)
    invoice ||= invoice_fixture(
      status: 'open',
      status_transitions: {
        finalized_at: Time.now.to_i,
        paid_at: nil
      }
    )
    event_fixture(
      type: 'invoice.finalized',
      data_object: invoice
    )
  end

  # Payment intent succeeded event
  def payment_intent_succeeded_event(payment_intent: nil)
    payment_intent ||= {
      id: 'pi_test123',
      object: 'payment_intent',
      amount: 2900,
      currency: 'usd',
      customer: 'cus_test123',
      invoice: 'in_test123',
      status: 'succeeded',
      created: Time.now.to_i
    }
    event_fixture(
      type: 'payment_intent.succeeded',
      data_object: payment_intent
    )
  end

  # Payment intent payment failed event
  def payment_intent_payment_failed_event(payment_intent: nil, error_code: 'card_declined')
    payment_intent ||= {
      id: 'pi_test123',
      object: 'payment_intent',
      amount: 2900,
      currency: 'usd',
      customer: 'cus_test123',
      invoice: 'in_test123',
      status: 'requires_payment_method',
      last_payment_error: {
        code: error_code,
        message: 'Your card was declined',
        type: 'card_error'
      },
      created: Time.now.to_i
    }
    event_fixture(
      type: 'payment_intent.payment_failed',
      data_object: payment_intent
    )
  end

  # Product updated event
  def product_updated_event(product: nil, previous_attributes: {})
    product ||= product_fixture
    event_fixture(
      type: 'product.updated',
      data_object: product,
      previous_attributes: previous_attributes
    )
  end

  # Price updated event
  def price_updated_event(price: nil, previous_attributes: {})
    price ||= price_fixture
    event_fixture(
      type: 'price.updated',
      data_object: price,
      previous_attributes: previous_attributes
    )
  end

  # Customer updated event
  def customer_updated_event(customer: nil, previous_attributes: {})
    customer ||= customer_fixture
    event_fixture(
      type: 'customer.updated',
      data_object: customer,
      previous_attributes: previous_attributes
    )
  end

  # Customer deleted event
  def customer_deleted_event(customer: nil)
    customer ||= customer_fixture(deleted: true)
    event_fixture(
      type: 'customer.deleted',
      data_object: customer
    )
  end

  # Payment method attached event
  def payment_method_attached_event(payment_method: nil)
    payment_method ||= payment_method_fixture
    event_fixture(
      type: 'payment_method.attached',
      data_object: payment_method
    )
  end

  # Payment method detached event
  def payment_method_detached_event(payment_method: nil)
    payment_method ||= payment_method_fixture(customer: nil)
    event_fixture(
      type: 'payment_method.detached',
      data_object: payment_method
    )
  end

  # Subscription trial will end event
  def customer_subscription_trial_will_end_event(subscription: nil, days_until_end: 3)
    subscription ||= subscription_fixture(
      status: 'trialing',
      trial_start: (Time.now - 27.days).to_i,
      trial_end: (Time.now + days_until_end.days).to_i
    )
    event_fixture(
      type: 'customer.subscription.trial_will_end',
      data_object: subscription
    )
  end

  # Subscription paused event
  def customer_subscription_paused_event(subscription: nil)
    subscription ||= subscription_fixture(
      status: 'paused',
      pause_collection: {
        behavior: 'void',
        resumes_at: (Time.now + 3.months).to_i
      }
    )
    event_fixture(
      type: 'customer.subscription.paused',
      data_object: subscription
    )
  end

  # Subscription resumed event
  def customer_subscription_resumed_event(subscription: nil)
    subscription ||= subscription_fixture(
      status: 'active',
      pause_collection: nil
    )
    event_fixture(
      type: 'customer.subscription.resumed',
      data_object: subscription
    )
  end

  # Charge refunded event
  def charge_refunded_event(charge: nil, refund: nil)
    refund ||= refund_fixture
    charge ||= {
      id: 'ch_test123',
      object: 'charge',
      amount: 2900,
      amount_refunded: refund[:amount],
      currency: 'usd',
      customer: 'cus_test123',
      invoice: 'in_test123',
      refunded: true,
      refunds: {
        data: [refund]
      },
      status: 'succeeded'
    }
    event_fixture(
      type: 'charge.refunded',
      data_object: charge
    )
  end

  # Helper to generate event JSON payload
  def event_json_payload(event)
    JSON.generate(event)
  end

  # Helper to generate signed webhook payload
  def signed_webhook_payload(event:, secret: 'whsec_test_secret', timestamp: Time.now.to_i)
    payload = event_json_payload(event)
    signature = generate_stripe_signature(payload: payload, secret: secret, timestamp: timestamp)

    {
      payload: payload,
      signature: signature,
      timestamp: timestamp
    }
  end
end
