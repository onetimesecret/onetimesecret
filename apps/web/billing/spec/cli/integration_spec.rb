# frozen_string_literal: true

require 'spec_helper'
require 'cli/cli_spec_helper'
require_relative '../support/billing_spec_helper'

RSpec.describe 'Billing CLI integration workflows', type: :cli do
  let(:customer_id) { 'cus_integration_test' }
  let(:subscription_id) { 'sub_integration_test' }
  let(:product_id) { 'prod_integration_test' }
  let(:price_id) { 'price_integration_test' }
  let(:charge_id) { 'ch_integration_test' }
  let(:refund_id) { 'ref_integration_test' }
  let(:link_id) { 'plink_integration_test' }

  let(:customer) { mock_stripe_customer(id: customer_id, email: 'integration@example.com') }
  let(:subscription) { mock_stripe_subscription(id: subscription_id, customer: customer_id, status: 'active') }
  let(:product) { mock_stripe_product(id: product_id, name: 'Integration Product') }
  let(:price) { mock_stripe_price(id: price_id, product: product_id, unit_amount: 1000) }
  let(:charge) { mock_stripe_charge(id: charge_id, customer: customer_id, amount: 5000) }
  let(:refund) { mock_stripe_refund(id: refund_id, charge: charge_id, amount: 5000) }

  before do
    # Mock billing configuration
    billing_config = double('BillingConfig',
      enabled?: true,
      stripe_key: 'sk_test_123456'
    )
    allow(OT).to receive(:billing_config).and_return(billing_config)

    # Set Stripe API key
    Stripe.api_key = 'sk_test_123456'

    # Mock confirmation prompts
    allow($stdin).to receive(:gets).and_return("y\n")
  end

  describe 'Customer lifecycle workflow' do
    it 'creates customer, adds subscription, then cancels subscription' do
      # Step 1: Create customer
      allow(Stripe::Customer).to receive(:create).and_return(customer)

      output1 = run_cli_command_quietly('billing', 'customers', 'create',
        '--email', 'integration@example.com')

      expect(output1[:stdout]).to include('Customer created successfully')
      expect(output1[:stdout]).to include(customer_id)

      # Step 2: Create subscription
      allow(Stripe::Customer).to receive(:retrieve).and_return(customer)
      allow(Stripe::Subscription).to receive(:create).and_return(subscription)
      allow(Stripe::Price).to receive(:retrieve).and_return(price)

      output2 = run_cli_command_quietly('billing', 'subscriptions', 'create',
        '--customer', customer_id, '--price', price_id)

      expect(output2[:stdout]).to include('Subscription created successfully')
      expect(output2[:stdout]).to include(subscription_id)

      # Step 3: Cancel subscription
      canceled_sub = mock_stripe_subscription(id: subscription_id, status: 'canceled')
      allow(Stripe::Subscription).to receive(:retrieve).and_return(subscription)
      allow(Stripe::Subscription).to receive(:cancel).and_return(canceled_sub)

      output3 = run_cli_command_quietly('billing', 'subscriptions', 'cancel', subscription_id)

      expect(output3[:stdout]).to include('canceled')
      expect(last_exit_code).to eq(0)
    end

    it 'handles full customer deletion workflow' do
      # Create customer
      allow(Stripe::Customer).to receive(:create).and_return(customer)

      output1 = run_cli_command_quietly('billing', 'customers', 'create',
        '--email', 'integration@example.com')

      expect(output1[:stdout]).to include(customer_id)

      # Delete customer
      allow(Stripe::Customer).to receive(:retrieve).and_return(customer)
      allow(Stripe::Customer).to receive(:delete).and_return(
        double('DeletedCustomer', id: customer_id, deleted: true)
      )

      output2 = run_cli_command_quietly('billing', 'customers', 'delete', customer_id)

      expect(output2[:stdout]).to include('deleted successfully')
    end
  end

  describe 'Payment link workflow' do
    let(:payment_link) do
      double('PaymentLink',
        id: link_id,
        url: 'https://buy.stripe.com/test',
        active: true,
        line_items: double('ListObject', data: [])
      )
    end

    it 'creates, updates, and archives payment link' do
      # Step 1: Create payment link
      allow(Stripe::Price).to receive(:retrieve).and_return(price)
      allow(Stripe::Product).to receive(:retrieve).and_return(product)
      allow(Stripe::PaymentLink).to receive(:create).and_return(payment_link)

      output1 = run_cli_command_quietly('billing', 'payment-links', 'create', '--price', price_id)

      expect(output1[:stdout]).to include('Payment link created successfully')
      expect(output1[:stdout]).to include(link_id)

      # Step 2: Update payment link
      updated_link = double('PaymentLink', id: link_id, active: true,
        metadata: { 'campaign' => 'test' })
      allow(Stripe::PaymentLink).to receive(:retrieve).and_return(payment_link)
      allow(Stripe::PaymentLink).to receive(:update).and_return(updated_link)

      output2 = run_cli_command_quietly('billing', 'payment-links', 'update', link_id,
        '--metadata', 'campaign=test')

      expect(output2[:stdout]).to include('updated successfully')

      # Step 3: Archive payment link
      archived_link = double('PaymentLink', id: link_id, active: false)
      allow(Stripe::PaymentLink).to receive(:update).and_return(archived_link)

      output3 = run_cli_command_quietly('billing', 'payment-links', 'archive', link_id)

      expect(output3[:stdout]).to include('archived successfully')
      expect(last_exit_code).to eq(0)
    end
  end

  describe 'Product catalog workflow' do
    it 'creates product, adds prices, then syncs to cache' do
      # Step 1: Create product
      allow(Stripe::Product).to receive(:create).and_return(product)

      output1 = run_cli_command_quietly('billing', 'products', 'create',
        '--name', 'Integration Product', '--app', 'web', '--tier', 'personal', '--region', 'US')

      expect(output1[:stdout]).to include('Product created successfully')

      # Step 2: Create price
      allow(Stripe::Price).to receive(:create).and_return(price)

      output2 = run_cli_command_quietly('billing', 'prices', 'create',
        '--product', product_id, '--amount', '1000', '--currency', 'usd', '--interval', 'month')

      expect(output2[:stdout]).to include('Price created successfully')

      # Step 3: Sync to cache
      allow(Billing::Plan).to receive(:refresh_from_stripe).and_return(1)

      output3 = run_cli_command_quietly('billing', 'sync')

      expect(output3[:stdout]).to include('Successfully synced')
      expect(last_exit_code).to eq(0)
    end

    it 'validates product metadata after creation' do
      # Create product
      allow(Stripe::Product).to receive(:create).and_return(product)

      run_cli_command_quietly('billing', 'products', 'create',
        '--name', 'Test', '--app', 'web', '--tier', 'personal', '--region', 'US')

      # Validate
      products = double('ListObject', data: [product])
      allow(Stripe::Product).to receive(:list).and_return(products)

      output = run_cli_command_quietly('billing', 'validate')

      expect(output[:stdout]).to match(/valid metadata|no.*errors/i)
    end
  end

  describe 'Refund workflow' do
    it 'processes full refund for a charge' do
      # Setup charge
      allow(Stripe::Charge).to receive(:retrieve).and_return(charge)

      # Create full refund
      allow(Stripe::Refund).to receive(:create).and_return(refund)

      output = run_cli_command_quietly('billing', 'refunds', 'create', '--charge', charge_id)

      expect(output[:stdout]).to include('Refund created successfully')
      expect(output[:stdout]).to include(refund_id)
      expect(last_exit_code).to eq(0)
    end

    it 'processes partial refund for a charge' do
      # Setup charge
      allow(Stripe::Charge).to receive(:retrieve).and_return(charge)

      # Create partial refund
      partial_refund = mock_stripe_refund(id: 'ref_partial', charge: charge_id, amount: 2500)
      allow(Stripe::Refund).to receive(:create).and_return(partial_refund)

      output = run_cli_command_quietly('billing', 'refunds', 'create',
        '--charge', charge_id, '--amount', '2500')

      expect(output[:stdout]).to include('Refund amount: USD 25.00')
      expect(output[:stdout]).to include('Refund created successfully')
    end
  end

  describe 'Subscription upgrade workflow' do
    let(:basic_price) { mock_stripe_price(id: 'price_basic', unit_amount: 1000) }
    let(:premium_price) { mock_stripe_price(id: 'price_premium', unit_amount: 2000) }

    it 'upgrades subscription from basic to premium tier' do
      # Create basic subscription
      basic_sub = mock_stripe_subscription(id: subscription_id, customer: customer_id, status: 'active')
      allow(Stripe::Customer).to receive(:retrieve).and_return(customer)
      allow(Stripe::Subscription).to receive(:create).and_return(basic_sub)
      allow(Stripe::Price).to receive(:retrieve).with('price_basic').and_return(basic_price)

      output1 = run_cli_command_quietly('billing', 'subscriptions', 'create',
        '--customer', customer_id, '--price', 'price_basic')

      expect(output1[:stdout]).to include('Subscription created successfully')

      # Upgrade to premium
      upgraded_sub = mock_stripe_subscription(id: subscription_id, status: 'active')
      allow(Stripe::Subscription).to receive(:retrieve).and_return(basic_sub)
      allow(Stripe::Subscription).to receive(:update).and_return(upgraded_sub)
      allow(Stripe::Price).to receive(:retrieve).with('price_premium').and_return(premium_price)

      output2 = run_cli_command_quietly('billing', 'subscriptions', 'update', subscription_id,
        '--price', 'price_premium')

      expect(output2[:stdout]).to include('updated successfully')
      expect(last_exit_code).to eq(0)
    end
  end

  describe 'Event monitoring workflow' do
    it 'views events after customer operations' do
      # Perform customer operation
      allow(Stripe::Customer).to receive(:create).and_return(customer)

      run_cli_command_quietly('billing', 'customers', 'create', '--email', 'test@example.com')

      # Check events
      event = double('Event',
        id: 'evt_test',
        type: 'customer.created',
        created: Time.now.to_i
      )
      events = double('ListObject', data: [event])
      allow(Stripe::Event).to receive(:list).and_return(events)

      output = run_cli_command_quietly('billing', 'events', '--type', 'customer.created')

      expect(output[:stdout]).to include('customer.created')
      expect(last_exit_code).to eq(0)
    end
  end

  describe 'Error recovery workflows' do
    it 'handles network errors with appropriate messages' do
      allow(Stripe::Customer).to receive(:list).and_raise(
        Stripe::APIConnectionError.new('Network error')
      )

      output = run_cli_command_quietly('billing', 'customers')

      expect(output[:stdout]).to include('Error fetching customers')
      expect(output[:stdout]).to include('Network error')
    end

    it 'handles authentication errors gracefully' do
      allow(Stripe::Customer).to receive(:list).and_raise(
        Stripe::AuthenticationError.new('Invalid API key')
      )

      output = run_cli_command_quietly('billing', 'customers')

      expect(output[:stdout]).to include('Error fetching customers')
      expect(output[:stdout]).to include('Invalid API key')
    end
  end

  describe 'Data consistency checks' do
    it 'verifies customer data after creation' do
      allow(Stripe::Customer).to receive(:create).and_return(customer)

      # Create customer
      output1 = run_cli_command_quietly('billing', 'customers', 'create',
        '--email', 'verify@example.com')

      expect(output1[:stdout]).to include(customer_id)

      # Verify by listing
      customers = double('ListObject', data: [customer])
      allow(Stripe::Customer).to receive(:list).and_return(customers)

      output2 = run_cli_command_quietly('billing', 'customers')

      expect(output2[:stdout]).to include(customer_id)
      expect(output2[:stdout]).to include('verify@example.com')
    end

    it 'ensures price data integrity in product creation flow' do
      allow(Stripe::Product).to receive(:create).and_return(product)
      allow(Stripe::Price).to receive(:create).and_return(price)

      # Create product and price
      run_cli_command_quietly('billing', 'products', 'create',
        '--name', 'Test', '--app', 'web', '--tier', 'personal', '--region', 'US')

      output = run_cli_command_quietly('billing', 'prices', 'create',
        '--product', product_id, '--amount', '1000', '--currency', 'usd', '--interval', 'month')

      expect(output[:stdout]).to include('USD 10.00')
      expect(output[:stdout]).to include('month')
    end
  end
end
