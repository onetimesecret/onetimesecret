# frozen_string_literal: true

# Stripe Test Data Factory
#
# Factory methods for creating real Stripe objects through stripe-mock.
# These methods create actual Stripe objects with proper nesting and behavior,
# unlike RSpec doubles which return Hashes for nested attributes.
#
# Usage:
#   customer = create_stripe_customer(email: 'test@example.com')
#   price = create_stripe_price(recurring: { interval: 'month' })
#   price.recurring.interval  # => "month" (works correctly!)
#
# All factory methods return real Stripe objects that behave identically
# to objects returned from the Stripe API, supporting:
#   - Method-style access (price.recurring.interval)
#   - Hash-style access (price['recurring']['interval'])
#   - Proper type coercion and validation
#   - Nested object structures (ListObjects, StripeObjects)

require 'stripe_mock'

module StripeTestData
  # Create a Stripe Customer with proper object structure
  # @param [String] id Customer ID (default: auto-generated)
  # @param [Hash] attrs Additional attributes
  # @return [Stripe::Customer]
  def create_stripe_customer(id: nil, **attrs)
    defaults = {
      email: attrs[:email] || 'test@example.com',
      name: attrs[:name] || 'Test Customer',
      metadata: attrs[:metadata] || {},
      description: attrs[:description] || 'Test customer for specs'
    }

    # Let stripe-mock generate the ID if not provided
    params = id ? defaults.merge(attrs).merge(id: id) : defaults.merge(attrs)

    # Create via stripe-mock server (returns real Stripe::Customer)
    Stripe::Customer.create(params)
  rescue Stripe::InvalidRequestError => e
    # If customer exists, retrieve it
    if e.message.include?('already exists')
      Stripe::Customer.retrieve(id)
    else
      raise
    end
  end

  # Create a Stripe Product
  # @param [String] id Product ID (default: auto-generated)
  # @param [Hash] attrs Additional attributes
  # @return [Stripe::Product]
  def create_stripe_product(id: nil, **attrs)
    defaults = {
      name: attrs[:name] || 'Test Product',
      description: attrs[:description] || 'Test product description',
      metadata: attrs[:metadata] || {},
      active: attrs.fetch(:active, true)
    }

    params = id ? defaults.merge(attrs).merge(id: id) : defaults.merge(attrs)

    Stripe::Product.create(params)
  rescue Stripe::InvalidRequestError => e
    if e.message.include?('already exists')
      Stripe::Product.retrieve(id)
    else
      raise
    end
  end

  # Create a Stripe Price with proper recurring object structure
  # @param [String] id Price ID (default: auto-generated)
  # @param [Hash] attrs Additional attributes
  # @return [Stripe::Price]
  def create_stripe_price(id: nil, **attrs)
    # Create product first if not specified
    product = if attrs[:product]
                attrs[:product]
              elsif attrs[:product_id]
                attrs.delete(:product_id)
              else
                create_stripe_product.id
              end

    defaults = {
      product: product,
      unit_amount: attrs[:unit_amount] || 1000,
      currency: attrs[:currency] || 'usd',
      metadata: attrs[:metadata] || {}
    }

    # Handle recurring pricing
    if attrs[:recurring]
      defaults[:recurring] = {
        interval: attrs[:recurring][:interval] || 'month',
        interval_count: attrs[:recurring][:interval_count] || 1
      }.merge(attrs[:recurring])
    end

    params = id ? defaults.merge(attrs).merge(id: id) : defaults.merge(attrs)
    params.delete(:product_id) # Remove if present as we use :product

    Stripe::Price.create(params)
  rescue Stripe::InvalidRequestError => e
    if e.message.include?('already exists')
      Stripe::Price.retrieve(id)
    else
      raise
    end
  end

  # Create a Stripe Subscription with proper items structure
  # @param [String] id Subscription ID (default: auto-generated)
  # @param [Hash] attrs Additional attributes
  # @return [Stripe::Subscription]
  def create_stripe_subscription(id: nil, **attrs)
    # Create customer if not provided
    customer = attrs[:customer] || create_stripe_customer.id

    # Create price if not provided
    price = attrs[:price] || create_stripe_price(recurring: { interval: 'month' }).id

    defaults = {
      customer: customer,
      items: [{ price: price }],
      metadata: attrs[:metadata] || {}
    }

    # Remove price from attrs since we use items
    attrs.delete(:price)

    params = id ? defaults.merge(attrs).merge(id: id) : defaults.merge(attrs)

    Stripe::Subscription.create(params)
  rescue Stripe::InvalidRequestError => e
    if e.message.include?('already exists')
      Stripe::Subscription.retrieve(id)
    else
      raise
    end
  end

  # Create a Stripe Invoice
  # @param [String] id Invoice ID (default: auto-generated)
  # @param [Hash] attrs Additional attributes
  # @return [Stripe::Invoice]
  def create_stripe_invoice(id: nil, **attrs)
    customer = attrs[:customer] || create_stripe_customer.id

    defaults = {
      customer: customer,
      auto_advance: attrs.fetch(:auto_advance, false),
      collection_method: attrs[:collection_method] || 'charge_automatically',
      metadata: attrs[:metadata] || {}
    }

    params = id ? defaults.merge(attrs).merge(id: id) : defaults.merge(attrs)

    invoice = Stripe::Invoice.create(params)

    # Add line items if needed
    if attrs[:line_items]
      attrs[:line_items].each do |item|
        Stripe::InvoiceItem.create(
          customer: customer,
          invoice: invoice.id,
          amount: item[:amount] || 1000,
          currency: item[:currency] || 'usd',
          description: item[:description] || 'Test line item'
        )
      end
      # Refresh to get line items
      invoice = Stripe::Invoice.retrieve(invoice.id)
    end

    invoice
  rescue Stripe::InvalidRequestError => e
    if e.message.include?('already exists')
      Stripe::Invoice.retrieve(id)
    else
      raise
    end
  end

  # Create a Stripe PaymentIntent
  # @param [String] id PaymentIntent ID (default: auto-generated)
  # @param [Hash] attrs Additional attributes
  # @return [Stripe::PaymentIntent]
  def create_stripe_payment_intent(id: nil, **attrs)
    defaults = {
      amount: attrs[:amount] || 1000,
      currency: attrs[:currency] || 'usd',
      metadata: attrs[:metadata] || {}
    }

    # Add customer if provided
    defaults[:customer] = attrs[:customer] if attrs[:customer]

    params = id ? defaults.merge(attrs).merge(id: id) : defaults.merge(attrs)

    Stripe::PaymentIntent.create(params)
  rescue Stripe::InvalidRequestError => e
    if e.message.include?('already exists')
      Stripe::PaymentIntent.retrieve(id)
    else
      raise
    end
  end

  # Create a Stripe Charge
  # @param [String] id Charge ID (default: auto-generated)
  # @param [Hash] attrs Additional attributes
  # @return [Stripe::Charge]
  def create_stripe_charge(id: nil, **attrs)
    customer = attrs[:customer] || create_stripe_customer.id

    defaults = {
      amount: attrs[:amount] || 1000,
      currency: attrs[:currency] || 'usd',
      customer: customer,
      description: attrs[:description] || 'Test charge',
      metadata: attrs[:metadata] || {}
    }

    params = id ? defaults.merge(attrs).merge(id: id) : defaults.merge(attrs)

    Stripe::Charge.create(params)
  rescue Stripe::InvalidRequestError => e
    if e.message.include?('already exists')
      Stripe::Charge.retrieve(id)
    else
      raise
    end
  end

  # Create a Stripe Refund
  # @param [String] charge_id Charge to refund
  # @param [Hash] attrs Additional attributes
  # @return [Stripe::Refund]
  def create_stripe_refund(charge_id: nil, **attrs)
    # Create a charge first if not provided
    charge_id ||= create_stripe_charge.id

    defaults = {
      charge: charge_id,
      amount: attrs[:amount], # nil means full refund
      reason: attrs[:reason] || 'requested_by_customer',
      metadata: attrs[:metadata] || {}
    }

    Stripe::Refund.create(defaults.merge(attrs))
  end

  # Create a Stripe PaymentMethod
  # @param [String] id PaymentMethod ID (default: auto-generated)
  # @param [Hash] attrs Additional attributes
  # @return [Stripe::PaymentMethod]
  def create_stripe_payment_method(id: nil, **attrs)
    defaults = {
      type: 'card',
      card: {
        number: '4242424242424242',
        exp_month: 12,
        exp_year: Time.now.year + 2,
        cvc: '123'
      },
      metadata: attrs[:metadata] || {}
    }

    # stripe-mock might not fully support payment method creation,
    # so we'll use the test helper's card tokens
    if attrs[:customer]
      defaults[:customer] = attrs[:customer]
    end

    params = id ? defaults.merge(attrs).merge(id: id) : defaults.merge(attrs)

    # Use test token for card payment methods
    if params[:type] == 'card'
      token = StripeMock.generate_card_token
      customer = params[:customer] || create_stripe_customer.id

      # Attach the card to the customer
      customer_obj = Stripe::Customer.retrieve(customer)
      customer_obj.sources.create(source: token)

      # Return the first payment method
      customer_obj.sources.data.first
    else
      Stripe::PaymentMethod.create(params)
    end
  rescue Stripe::InvalidRequestError => e
    if e.message.include?('already exists')
      Stripe::PaymentMethod.retrieve(id)
    else
      raise
    end
  end

  # Create a Stripe PaymentLink
  # @param [String] id PaymentLink ID (default: auto-generated)
  # @param [Hash] attrs Additional attributes
  # @return [Stripe::PaymentLink]
  def create_stripe_payment_link(id: nil, **attrs)
    # Create price if not provided
    price = attrs[:price] || create_stripe_price.id

    defaults = {
      line_items: [
        {
          price: price,
          quantity: attrs[:quantity] || 1
        }
      ],
      metadata: attrs[:metadata] || {}
    }

    attrs.delete(:price) # Remove since we use line_items
    params = id ? defaults.merge(attrs).merge(id: id) : defaults.merge(attrs)

    # stripe-mock may not fully support PaymentLink,
    # so we'll create a mock object with proper structure
    StripeMock.mock_stripe_object(
      :payment_link,
      params.merge(
        id: id || "plink_#{SecureRandom.hex(12)}",
        url: "https://stripe.com/payment/#{SecureRandom.hex(12)}",
        active: true,
        created: Time.now.to_i
      )
    )
  end

  # Create a Stripe Checkout Session
  # @param [String] id Session ID (default: auto-generated)
  # @param [Hash] attrs Additional attributes
  # @return [Stripe::Checkout::Session]
  def create_stripe_checkout_session(id: nil, **attrs)
    customer = attrs[:customer] || create_stripe_customer.id

    defaults = {
      customer: customer,
      mode: attrs[:mode] || 'payment',
      success_url: attrs[:success_url] || 'https://example.com/success',
      cancel_url: attrs[:cancel_url] || 'https://example.com/cancel',
      line_items: attrs[:line_items] || [
        {
          price: create_stripe_price.id,
          quantity: 1
        }
      ],
      metadata: attrs[:metadata] || {}
    }

    params = id ? defaults.merge(attrs).merge(id: id) : defaults.merge(attrs)

    Stripe::Checkout::Session.create(params)
  rescue Stripe::InvalidRequestError => e
    if e.message.include?('already exists')
      Stripe::Checkout::Session.retrieve(id)
    else
      raise
    end
  end

  # Create a Stripe Event (webhooks)
  # @param [String] type Event type (e.g., 'customer.created')
  # @param [Hash] data_object The object associated with the event
  # @param [Hash] attrs Additional attributes
  # @return [Stripe::Event]
  def create_stripe_event(type:, data_object: nil, **attrs)
    # Create a default object if not provided
    data_object ||= case type
                    when /^customer\./
                      create_stripe_customer
                    when /^subscription\./
                      create_stripe_subscription
                    when /^invoice\./
                      create_stripe_invoice
                    when /^charge\./
                      create_stripe_charge
                    when /^price\./
                      create_stripe_price
                    when /^product\./
                      create_stripe_product
                    else
                      create_stripe_customer
                    end

    # stripe-mock creates events automatically for operations,
    # but we can also construct them manually
    event_data = {
      id: attrs[:id] || "evt_#{SecureRandom.hex(12)}",
      type: type,
      data: {
        object: data_object
      },
      created: attrs[:created] || Time.now.to_i,
      livemode: attrs.fetch(:livemode, false),
      api_version: attrs[:api_version] || '2023-10-16'
    }

    Stripe::Event.construct_from(event_data.merge(attrs))
  end

  # Generate a valid Stripe webhook signature
  # @param [String] payload The webhook payload
  # @param [String] secret The webhook secret
  # @param [Integer] timestamp The timestamp (default: now)
  # @return [String] The webhook signature header value
  def generate_stripe_signature(payload:, secret:, timestamp: Time.now.to_i)
    signed_payload = "#{timestamp}.#{payload}"
    signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), secret, signed_payload)
    "t=#{timestamp},v1=#{signature}"
  end

  # Helper to clear all stripe-mock data
  def reset_stripe_data!
    StripeMockServer.reset!
  end
end

# Include in RSpec automatically for billing tests
RSpec.configure do |config|
  config.include StripeTestData, :stripe
  config.include StripeTestData, type: :billing
  config.include StripeTestData, type: :controller
  config.include StripeTestData, type: :integration
  config.include StripeTestData, type: :cli
end
