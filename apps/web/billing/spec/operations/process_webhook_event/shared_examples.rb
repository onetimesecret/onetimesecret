# apps/web/billing/spec/operations/process_webhook_event/shared_examples.rb
#
# frozen_string_literal: true

# Shared helpers and examples for ProcessWebhookEvent specs.
# Provides Stripe object builders and common test patterns.

module ProcessWebhookEventHelpers
  # Build a Stripe::Event for testing
  def build_stripe_event(type:, data_object:, id: nil)
    Stripe::Event.construct_from({
      id: id || "evt_test_#{SecureRandom.hex(8)}",
      object: 'event',
      type: type,
      created: Time.now.to_i,
      livemode: false,
      data: { object: data_object },
    })
  end

  # Build a Stripe::Subscription for testing
  #
  # @param id [String] Subscription ID
  # @param customer [String] Customer ID
  # @param status [String] Subscription status
  # @param metadata [Hash] Subscription-level metadata (e.g., customer_extid, plan_id)
  # @param price_metadata [Hash] Price-level metadata (fallback for plan_id)
  # @param current_period_end [Integer] Unix timestamp
  def build_stripe_subscription(id:, customer:, status:, metadata: {}, price_metadata: {}, current_period_end: nil)
    period_end = current_period_end || (Time.now + 30 * 24 * 60 * 60).to_i
    Stripe::Subscription.construct_from({
      id: id,
      object: 'subscription',
      customer: customer,
      status: status,
      metadata: metadata,
      current_period_end: period_end,
      items: {
        data: [{
          price: {
            id: 'price_test',
            product: 'prod_test',
            metadata: price_metadata,
          },
          # current_period_end on items (Stripe API 2025-11-17 structure)
          current_period_end: period_end,
        }],
      },
    })
  end

  # Build a Stripe::Checkout::Session for testing
  def build_stripe_session(id:, customer:, subscription: nil, mode: 'subscription')
    Stripe::Checkout::Session.construct_from({
      id: id,
      object: 'checkout.session',
      customer: customer,
      subscription: subscription,
      mode: mode,
    })
  end

  # Build a Stripe::Product for testing
  def build_stripe_product(id:, name: 'Test Product', metadata: {})
    Stripe::Product.construct_from({
      id: id,
      object: 'product',
      name: name,
      metadata: metadata,
    })
  end

  # Build a Stripe::Price for testing
  def build_stripe_price(id:, product:, unit_amount: 1999, currency: 'usd')
    Stripe::Price.construct_from({
      id: id,
      object: 'price',
      unit_amount: unit_amount,
      currency: currency,
      product: product,
    })
  end

  # Create test customer and track for cleanup
  def create_test_customer(email:)
    cust = Onetime::Customer.create!(email)
    created_customers << cust
    cust
  end

  # Create test organization and track for cleanup
  def create_test_organization(customer:, name: nil, default: true)
    org = Onetime::Organization.create!(
      name || "#{customer.email}'s Workspace",
      customer,
      customer.email,
    )
    org.is_default = default
    org.save
    created_organizations << org
    org
  end
end

# Shared example: event returns :success (handled)
RSpec.shared_examples 'handles event successfully' do
  it 'returns :success indicating event was handled' do
    expect(operation.call).to eq(:success)
  end
end

# Shared example: event returns :unhandled
RSpec.shared_examples 'ignores unhandled event' do
  it 'returns :unhandled for unhandled event type' do
    expect(operation.call).to eq(:unhandled)
  end

  it 'does not raise an error' do
    expect { operation.call }.not_to raise_error
  end
end

# Shared example: logs warning for missing organization
RSpec.shared_examples 'logs warning for missing organization' do
  it 'returns :not_found when organization is not found' do
    expect(operation.call).to eq(:not_found)
  end
end

RSpec.configure do |config|
  config.include ProcessWebhookEventHelpers, :process_webhook_event
end
