# apps/web/billing/spec/support/stripe_mock_factory.rb
#
# frozen_string_literal: true

# Factory methods for creating Stripe API mock objects in tests.
# Uses Stripe::*.construct_from() which is the official pattern for creating
# test fixtures that behave like real Stripe API objects.
module StripeMockFactory
  module_function

  # Deep merge helper since ActiveSupport may not be available
  def deep_merge_hashes(base, overrides)
    result = base.dup
    overrides.each do |key, value|
      if result.key?(key) && result[key].is_a?(Hash) && value.is_a?(Hash)
        result[key] = deep_merge_hashes(result[key], value)
      else
        result[key] = value
      end
    end
    result
  end

  def build_checkout_session(overrides = {})
    defaults = {
      'id' => "cs_test_#{SecureRandom.hex(8)}",
      'object' => 'checkout.session',
      'url' => "https://checkout.stripe.com/c/pay/cs_test_#{SecureRandom.hex(12)}",
      'customer' => nil,
      'mode' => 'subscription',
      'status' => 'open',
      'payment_status' => 'unpaid',
      'currency' => 'cad',
      'amount_total' => 1900,
      'amount_subtotal' => 1900,
      'created' => Time.now.to_i,
      'expires_at' => (Time.now + 24 * 60 * 60).to_i,
      'livemode' => false,
      'success_url' => 'https://example.com/success?session_id={CHECKOUT_SESSION_ID}',
      'cancel_url' => 'https://example.com/cancel',
      'subscription' => nil,
      'automatic_tax' => { 'enabled' => true, 'liability' => { 'type' => 'self' }, 'status' => nil },
      'metadata' => {},
      'customer_details' => nil,
      'client_reference_id' => nil
    }
    Stripe::Checkout::Session.construct_from(deep_merge_hashes(defaults, overrides))
  end

  def build_customer(overrides = {})
    defaults = {
      'id' => "cus_test_#{SecureRandom.hex(8)}",
      'object' => 'customer',
      'email' => 'test@example.com',
      'name' => nil,
      'metadata' => {},
      'created' => Time.now.to_i,
      'livemode' => false
    }
    Stripe::Customer.construct_from(deep_merge_hashes(defaults, overrides))
  end

  def build_subscription(overrides = {})
    # Extract items_data before merging (special handling)
    overrides = overrides.dup
    items_data = overrides.delete('items_data') || [build_subscription_item_hash]

    defaults = {
      'id' => "sub_test_#{SecureRandom.hex(8)}",
      'object' => 'subscription',
      'status' => 'active',
      'current_period_start' => Time.now.to_i,
      'current_period_end' => (Time.now + 30 * 24 * 60 * 60).to_i,
      'cancel_at_period_end' => false,
      'canceled_at' => nil,
      'items' => { 'object' => 'list', 'data' => items_data, 'has_more' => false },
      'metadata' => {},
      'livemode' => false
    }
    Stripe::Subscription.construct_from(deep_merge_hashes(defaults, overrides))
  end

  def build_subscription_item_hash(overrides = {})
    overrides = overrides.dup
    price_id = overrides.delete('price_id') || 'price_test_mock'

    defaults = {
      'id' => "si_test_#{SecureRandom.hex(4)}",
      'object' => 'subscription_item',
      'price' => {
        'id' => price_id,
        'object' => 'price',
        'unit_amount' => 1900,
        'currency' => 'cad'
      },
      'quantity' => 1
    }
    deep_merge_hashes(defaults, overrides)
  end

  def build_invoice(overrides = {})
    defaults = {
      'id' => "in_test_#{SecureRandom.hex(8)}",
      'object' => 'invoice',
      'number' => "INV-#{rand(1000..9999)}",
      'customer' => 'cus_test_default',
      'amount_due' => 1900,
      'amount_paid' => 1900,
      'currency' => 'cad',
      'status' => 'paid',
      'created' => Time.now.to_i,
      'invoice_pdf' => 'https://pay.stripe.com/invoice/pdf/test',
      'hosted_invoice_url' => 'https://invoice.stripe.com/i/test',
      'livemode' => false
    }
    Stripe::Invoice.construct_from(deep_merge_hashes(defaults, overrides))
  end

  def build_invoice_list(invoices = [], has_more: false)
    Stripe::ListObject.construct_from({
      'object' => 'list',
      'url' => '/v1/invoices',
      'has_more' => has_more,
      'data' => invoices.map { |inv| inv.is_a?(Hash) ? inv : inv.to_hash }
    })
  end

  def build_upcoming_invoice(overrides = {})
    defaults = {
      'object' => 'invoice',
      'amount_due' => 1900,
      'amount_remaining' => 1900,
      'currency' => 'cad',
      'created' => Time.now.to_i,
      'period_start' => Time.now.to_i,
      'period_end' => (Time.now + 30 * 24 * 60 * 60).to_i,
      'lines' => { 'object' => 'list', 'data' => [], 'has_more' => false },
      'livemode' => false
    }
    Stripe::Invoice.construct_from(deep_merge_hashes(defaults, overrides))
  end

  def build_price(overrides = {})
    defaults = {
      'id' => "price_test_#{SecureRandom.hex(8)}",
      'object' => 'price',
      'active' => true,
      'currency' => 'cad',
      'unit_amount' => 1900,
      'recurring' => { 'interval' => 'month', 'interval_count' => 1 },
      'product' => 'prod_test_default',
      'livemode' => false
    }
    Stripe::Price.construct_from(deep_merge_hashes(defaults, overrides))
  end
end
