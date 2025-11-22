# frozen_string_literal: true

require 'spec_helper'
require 'cli/cli_spec_helper'
require_relative '../../support/billing_spec_helper'
require_relative '../../support/shared_examples/cli_safety'

# This spec now uses stripe-ruby-mock for real Stripe object testing.
# All Stripe objects are created through factory methods that return
# proper StripeObjects with correct nested structure, supporting
# method chaining like price.recurring.interval.
#
RSpec.describe 'Billing payment links CLI commands', type: :cli, stripe: true do
  let(:price_id) { 'price_test123' }
  let(:product_id) { 'prod_test123' }
  let(:link_id) { 'plink_test123' }

  let!(:product) do
    create_stripe_product(id: product_id, name: 'Test Product')
  end

  let!(:price) do
    create_stripe_price(
      id: price_id,
      product: product_id,
      unit_amount: 1000,
      currency: 'usd',
      recurring: { interval: 'month', interval_count: 1 }
    )
  end

  let!(:payment_link) do
    # Since stripe-mock may not fully support PaymentLink, we use construct_from
    Stripe::PaymentLink.construct_from(
      id: link_id,
      url: 'https://buy.stripe.com/test_xyz',
      active: true,
      line_items: {
        data: [{
          price: price_id,
          quantity: 1
        }]
      }
    )
  end

  before do
    # Mock billing configuration
    billing_config = double('BillingConfig',
      enabled?: true,
      stripe_key: 'sk_test_123456'
    )
    allow(OT).to receive(:billing_config).and_return(billing_config)

    # stripe-mock already sets up Stripe.api_key when started
    # But we can be explicit for clarity
    Stripe.api_key = 'sk_test_fake_key_for_testing'
  end

  describe 'billing payment-links' do
    context 'when listing payment links' do
      let!(:active_link) do
        Stripe::PaymentLink.construct_from(
          id: 'plink_001',
          active: true,
          url: 'https://buy.stripe.com/active',
          line_items: { data: [] }
        )
      end

      let!(:inactive_link) do
        Stripe::PaymentLink.construct_from(
          id: 'plink_002',
          active: false,
          url: 'https://buy.stripe.com/inactive',
          line_items: { data: [] }
        )
      end

      before do
        # Mock PaymentLink.list since stripe-mock may not support it
        allow(Stripe::PaymentLink).to receive(:list).and_return(
          Stripe::ListObject.construct_from(
            data: [active_link, inactive_link]
          )
        )
        allow(Stripe::PaymentLink).to receive(:retrieve) do |id|
          case id
          when 'plink_001' then active_link
          when 'plink_002' then inactive_link
          else payment_link
          end
        end
      end

      it 'lists all active payment links by default' do
        expect(Stripe::PaymentLink).to receive(:list).with(hash_including(
          active: true,
          limit: 100
        ))
        run_command('billing', 'payment-links', '--list')
      end

      it 'includes inactive links when requested' do
        expect(Stripe::PaymentLink).to receive(:list).with(hash_including(
          limit: 100
        )).and_return(
          Stripe::ListObject.construct_from(
            data: [active_link, inactive_link]
          )
        )
        run_command('billing', 'payment-links', '--list', '--include-inactive')
      end

      it 'outputs links in a formatted table' do
        output = run_command('billing', 'payment-links', '--list')
        expect(output).to include('plink_001')
        expect(output).to include('Active')
      end
    end

    context 'when showing detailed payment link info' do
      before do
        # Create a PaymentLink with expanded line items
        expanded_link = Stripe::PaymentLink.construct_from(
          id: link_id,
          url: 'https://buy.stripe.com/test_xyz',
          active: true,
          line_items: {
            data: [{
              price: price.to_h,  # Include full price data
              quantity: 1
            }]
          }
        )

        allow(Stripe::PaymentLink).to receive(:retrieve).with(
          link_id,
          hash_including(expand: ['line_items.data.price'])
        ).and_return(expanded_link)

        # Ensure Price.retrieve returns our created price
        allow(Stripe::Price).to receive(:retrieve).with(price_id).and_return(price)

        # Ensure Product.retrieve returns our created product
        allow(Stripe::Product).to receive(:retrieve).with(product_id).and_return(product)
      end

      it 'retrieves and displays payment link details' do
        output = run_command('billing', 'payment-links', '--info', link_id)
        expect(output).to include(link_id)
        expect(output).to include('https://buy.stripe.com/test_xyz')
      end

      it 'shows price information with proper formatting' do
        output = run_command('billing', 'payment-links', '--info', link_id)
        expect(output).to include('$10.00')
        expect(output).to include('month')
      end

      it 'displays product names when available' do
        output = run_command('billing', 'payment-links', '--info', link_id)
        expect(output).to include('Test Product')
      end
    end

    context 'when creating payment links' do
      let(:new_link_id) { 'plink_new123' }

      before do
        new_link = Stripe::PaymentLink.construct_from(
          id: new_link_id,
          url: 'https://buy.stripe.com/new_xyz',
          active: true,
          line_items: {
            data: [{
              price: price_id,
              quantity: 1
            }]
          }
        )

        allow(Stripe::PaymentLink).to receive(:create).and_return(new_link)
        allow(Stripe::Price).to receive(:retrieve).with(price_id).and_return(price)
      end

      it 'creates a payment link with specified price' do
        expect(Stripe::PaymentLink).to receive(:create).with(hash_including(
          line_items: [{ price: price_id, quantity: 1 }]
        ))
        run_command('billing', 'payment-links', '--create', price_id)
      end

      it 'supports custom quantity' do
        expect(Stripe::PaymentLink).to receive(:create).with(hash_including(
          line_items: [{ price: price_id, quantity: 5 }]
        ))
        run_command('billing', 'payment-links', '--create', price_id, '--quantity', '5')
      end

      it 'supports after completion configuration' do
        expect(Stripe::PaymentLink).to receive(:create).with(hash_including(
          after_completion: {
            type: 'redirect',
            redirect: { url: 'https://example.com/thanks' }
          }
        ))
        run_command('billing', 'payment-links', '--create', price_id,
                   '--after-completion-url', 'https://example.com/thanks')
      end

      it 'handles creation errors gracefully' do
        allow(Stripe::PaymentLink).to receive(:create).and_raise(
          Stripe::InvalidRequestError.new('Invalid price', nil)
        )
        output = run_command('billing', 'payment-links', '--create', 'bad_price')
        expect(output).to include('Error')
        expect(output).to include('Invalid price')
      end
    end

    context 'when updating payment links' do
      before do
        updated_link = Stripe::PaymentLink.construct_from(
          id: link_id,
          url: 'https://buy.stripe.com/test_xyz',
          active: false,  # Changed to inactive
          line_items: {
            data: [{
              price: price_id,
              quantity: 1
            }]
          }
        )

        allow(Stripe::PaymentLink).to receive(:retrieve).with(link_id).and_return(payment_link)
        allow(Stripe::PaymentLink).to receive(:update).and_return(updated_link)
      end

      it 'deactivates a payment link' do
        expect(Stripe::PaymentLink).to receive(:update).with(
          link_id,
          hash_including(active: false)
        )
        run_command('billing', 'payment-links', '--deactivate', link_id)
      end

      it 'reactivates a payment link' do
        expect(Stripe::PaymentLink).to receive(:update).with(
          link_id,
          hash_including(active: true)
        )
        run_command('billing', 'payment-links', '--activate', link_id)
      end

      it 'updates metadata' do
        expect(Stripe::PaymentLink).to receive(:update).with(
          link_id,
          hash_including(
            metadata: { campaign: 'summer2024', source: 'email' }
          )
        )
        run_command('billing', 'payment-links', '--update', link_id,
                   '--metadata', 'campaign=summer2024,source=email')
      end
    end

    context 'when handling line items' do
      let(:multi_item_link) do
        Stripe::PaymentLink.construct_from(
          id: 'plink_multi',
          url: 'https://buy.stripe.com/multi',
          active: true,
          line_items: {
            data: [
              {
                price: price.to_h,
                quantity: 2
              },
              {
                price: create_stripe_price(
                  unit_amount: 2000,
                  currency: 'usd',
                  recurring: { interval: 'year' }
                ).to_h,
                quantity: 1
              }
            ]
          }
        )
      end

      before do
        allow(Stripe::PaymentLink).to receive(:retrieve).with(
          'plink_multi',
          anything
        ).and_return(multi_item_link)
      end

      it 'displays multiple line items correctly' do
        output = run_command('billing', 'payment-links', '--info', 'plink_multi')
        expect(output).to include('2 x')
        expect(output).to include('$10.00')
        expect(output).to include('$20.00')
        expect(output).to include('month')
        expect(output).to include('year')
      end
    end

    context 'with price filtering' do
      let!(:monthly_price) do
        create_stripe_price(
          id: 'price_monthly',
          unit_amount: 999,
          recurring: { interval: 'month' }
        )
      end

      let!(:yearly_price) do
        create_stripe_price(
          id: 'price_yearly',
          unit_amount: 9999,
          recurring: { interval: 'year' }
        )
      end

      let!(:onetime_price) do
        create_stripe_price(
          id: 'price_onetime',
          unit_amount: 4999
        )
      end

      before do
        # Create links for each price type
        monthly_link = Stripe::PaymentLink.construct_from(
          id: 'plink_monthly',
          active: true,
          line_items: { data: [{ price: monthly_price.id, quantity: 1 }] }
        )

        yearly_link = Stripe::PaymentLink.construct_from(
          id: 'plink_yearly',
          active: true,
          line_items: { data: [{ price: yearly_price.id, quantity: 1 }] }
        )

        onetime_link = Stripe::PaymentLink.construct_from(
          id: 'plink_onetime',
          active: true,
          line_items: { data: [{ price: onetime_price.id, quantity: 1 }] }
        )

        all_links = Stripe::ListObject.construct_from(
          data: [monthly_link, yearly_link, onetime_link]
        )

        allow(Stripe::PaymentLink).to receive(:list).and_return(all_links)

        # Mock Price.retrieve for each price
        allow(Stripe::Price).to receive(:retrieve).with('price_monthly').and_return(monthly_price)
        allow(Stripe::Price).to receive(:retrieve).with('price_yearly').and_return(yearly_price)
        allow(Stripe::Price).to receive(:retrieve).with('price_onetime').and_return(onetime_price)
      end

      it 'filters links by recurring interval' do
        output = run_command('billing', 'payment-links', '--list', '--interval', 'month')
        expect(output).to include('plink_monthly')
        expect(output).not_to include('plink_yearly')
        expect(output).not_to include('plink_onetime')
      end

      it 'filters one-time payment links' do
        output = run_command('billing', 'payment-links', '--list', '--one-time')
        expect(output).to include('plink_onetime')
        expect(output).not_to include('plink_monthly')
        expect(output).not_to include('plink_yearly')
      end
    end

    context 'error handling' do
      it 'handles missing Stripe configuration' do
        billing_config = double('BillingConfig', enabled?: false)
        allow(OT).to receive(:billing_config).and_return(billing_config)

        output = run_command('billing', 'payment-links', '--list')
        expect(output).to include('Billing is not enabled')
      end

      it 'handles API errors gracefully' do
        allow(Stripe::PaymentLink).to receive(:list).and_raise(
          Stripe::APIError.new('API is down')
        )

        output = run_command('billing', 'payment-links', '--list')
        expect(output).to include('Error')
        expect(output).to include('API is down')
      end

      it 'handles authentication errors' do
        allow(Stripe::PaymentLink).to receive(:list).and_raise(
          Stripe::AuthenticationError.new('Invalid API key')
        )

        output = run_command('billing', 'payment-links', '--list')
        expect(output).to include('Authentication failed')
      end

      it 'handles rate limiting' do
        allow(Stripe::PaymentLink).to receive(:list).and_raise(
          Stripe::RateLimitError.new('Too many requests')
        )

        output = run_command('billing', 'payment-links', '--list')
        expect(output).to include('Rate limit exceeded')
      end
    end

    context 'with custom success/cancel URLs' do
      it 'creates link with custom URLs' do
        expect(Stripe::PaymentLink).to receive(:create).with(hash_including(
          success_url: 'https://mysite.com/success',
          cancel_url: 'https://mysite.com/cancel'
        )).and_return(payment_link)

        run_command('billing', 'payment-links', '--create', price_id,
                   '--success-url', 'https://mysite.com/success',
                   '--cancel-url', 'https://mysite.com/cancel')
      end
    end

    context 'with shipping options' do
      let(:shipping_rate_1) do
        Stripe::ShippingRate.construct_from(
          id: 'shr_standard',
          display_name: 'Standard Shipping',
          fixed_amount: { amount: 500, currency: 'usd' }
        )
      end

      let(:shipping_rate_2) do
        Stripe::ShippingRate.construct_from(
          id: 'shr_express',
          display_name: 'Express Shipping',
          fixed_amount: { amount: 1500, currency: 'usd' }
        )
      end

      before do
        allow(Stripe::ShippingRate).to receive(:retrieve).with('shr_standard').and_return(shipping_rate_1)
        allow(Stripe::ShippingRate).to receive(:retrieve).with('shr_express').and_return(shipping_rate_2)
      end

      it 'creates link with shipping options' do
        expect(Stripe::PaymentLink).to receive(:create).with(hash_including(
          shipping_address_collection: { allowed_countries: ['US', 'CA'] },
          shipping_options: [
            { shipping_rate: 'shr_standard' },
            { shipping_rate: 'shr_express' }
          ]
        )).and_return(payment_link)

        run_command('billing', 'payment-links', '--create', price_id,
                   '--collect-shipping',
                   '--shipping-countries', 'US,CA',
                   '--shipping-rates', 'shr_standard,shr_express')
      end
    end

    context 'with tax configuration' do
      it 'enables automatic tax collection' do
        expect(Stripe::PaymentLink).to receive(:create).with(hash_including(
          automatic_tax: { enabled: true }
        )).and_return(payment_link)

        run_command('billing', 'payment-links', '--create', price_id, '--auto-tax')
      end
    end

    context 'with promotion codes' do
      it 'allows promotion codes on payment link' do
        expect(Stripe::PaymentLink).to receive(:create).with(hash_including(
          allow_promotion_codes: true
        )).and_return(payment_link)

        run_command('billing', 'payment-links', '--create', price_id, '--allow-promo-codes')
      end
    end

    context 'bulk operations' do
      let(:link_ids) { %w[plink_001 plink_002 plink_003] }

      before do
        link_ids.each do |lid|
          link = Stripe::PaymentLink.construct_from(
            id: lid,
            active: true,
            line_items: { data: [] }
          )
          allow(Stripe::PaymentLink).to receive(:retrieve).with(lid).and_return(link)
          allow(Stripe::PaymentLink).to receive(:update).with(lid, anything).and_return(link)
        end
      end

      it 'deactivates multiple links at once' do
        link_ids.each do |lid|
          expect(Stripe::PaymentLink).to receive(:update).with(lid, hash_including(active: false))
        end

        run_command('billing', 'payment-links', '--bulk-deactivate', link_ids.join(','))
      end

      it 'reports progress during bulk operations' do
        output = run_command('billing', 'payment-links', '--bulk-deactivate', link_ids.join(','))
        expect(output).to include('Processing 3 payment links')
        expect(output).to include('Successfully deactivated 3')
      end
    end

    context 'CSV export' do
      let(:links_for_export) do
        (1..3).map do |i|
          Stripe::PaymentLink.construct_from(
            id: "plink_#{i.to_s.rjust(3, '0')}",
            url: "https://buy.stripe.com/link#{i}",
            active: i.odd?,
            line_items: {
              data: [{
                price: price_id,
                quantity: i
              }]
            }
          )
        end
      end

      before do
        allow(Stripe::PaymentLink).to receive(:list).and_return(
          Stripe::ListObject.construct_from(data: links_for_export)
        )
        allow(Stripe::Price).to receive(:retrieve).with(price_id).and_return(price)
      end

      it 'exports payment links to CSV format' do
        output = run_command('billing', 'payment-links', '--list', '--format', 'csv')
        expect(output).to include('id,url,active,price,quantity')
        expect(output).to include('plink_001')
        expect(output).to include('true')
        expect(output).to include('false')
      end

      it 'supports JSON export format' do
        output = run_command('billing', 'payment-links', '--list', '--format', 'json')
        data = JSON.parse(output)
        expect(data).to be_an(Array)
        expect(data.length).to eq(3)
        expect(data.first).to include('id', 'url', 'active')
      end
    end

    context 'pagination' do
      it 'handles pagination parameters' do
        expect(Stripe::PaymentLink).to receive(:list).with(hash_including(
          limit: 50,
          starting_after: 'plink_100'
        )).and_return(Stripe::ListObject.construct_from(data: []))

        run_command('billing', 'payment-links', '--list',
                   '--limit', '50',
                   '--starting-after', 'plink_100')
      end
    end

    context 'with customization options' do
      it 'creates link with custom fields' do
        expect(Stripe::PaymentLink).to receive(:create).with(hash_including(
          custom_fields: [
            {
              key: 'engraving',
              label: { type: 'custom', custom: 'Add engraving' },
              type: 'text',
              optional: true
            }
          ]
        )).and_return(payment_link)

        run_command('billing', 'payment-links', '--create', price_id,
                   '--custom-field', 'key=engraving,label=Add engraving,type=text,optional=true')
      end

      it 'creates link with phone number collection' do
        expect(Stripe::PaymentLink).to receive(:create).with(hash_including(
          phone_number_collection: { enabled: true }
        )).and_return(payment_link)

        run_command('billing', 'payment-links', '--create', price_id, '--collect-phone')
      end
    end

    # Include shared examples for CLI safety
    include_examples 'CLI command safety', 'billing payment-links'
  end
end
