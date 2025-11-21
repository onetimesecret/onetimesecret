# frozen_string_literal: true

require 'spec_helper'
require 'cli/cli_spec_helper'
require_relative '../../support/billing_spec_helper'
require_relative '../../support/shared_examples/cli_safety'

# NOTE: This spec currently uses mock_stripe_* helpers that return RSpec doubles
# with Hash attributes for nested objects. This causes failures when production
# code uses method chaining like price.recurring.interval (NoMethodError).
#
# See billing_spec_helper.rb for the StripeObject vs Hash gotcha and proper
# fix using Stripe::Price.construct_from() or stripe-ruby-mock gem.
#
RSpec.describe 'Billing payment links CLI commands', type: :cli do
  let(:price_id) { 'price_test123' }
  let(:product_id) { 'prod_test123' }
  let(:link_id) { 'plink_test123' }

  let(:product) do
    mock_stripe_product(id: product_id, name: 'Test Product')
  end

  let(:price) do
    mock_stripe_price(
      id: price_id,
      product: product_id,
      unit_amount: 1000,
      currency: 'usd',
      recurring: { interval: 'month', interval_count: 1 }
    )
  end

  let(:payment_link) do
    double('PaymentLink',
      id: link_id,
      url: 'https://buy.stripe.com/test_xyz',
      active: true,
      line_items: double('ListObject', data: [
        double('LineItem',
          price: price_id,
          quantity: 1
        )
      ])
    )
  end

  let(:payment_link_expanded) do
    double('PaymentLink',
      id: link_id,
      url: 'https://buy.stripe.com/test_xyz',
      active: true,
      line_items: double('ListObject', data: [
        double('LineItem',
          price: price,
          quantity: 1
        )
      ])
    )
  end

  before do
    # Mock billing configuration
    billing_config = double('BillingConfig',
      enabled?: true,
      stripe_key: 'sk_test_123456'
    )
    allow(OT).to receive(:billing_config).and_return(billing_config)

    # Set Stripe API key
    Stripe.api_key = 'sk_test_123456'
  end

  describe 'billing payment-links' do
    context 'when listing payment links' do
      let(:links) do
        double('ListObject', data: [
          double('PaymentLink',
            id: 'plink_001',
            active: true,
            line_items: double('ListObject', data: [])
          ),
          double('PaymentLink',
            id: 'plink_002',
            active: false,
            line_items: double('ListObject', data: [])
          )
        ])
      end

      before do
        allow(Stripe::PaymentLink).to receive(:list).and_return(links)
        allow(Stripe::PaymentLink).to receive(:retrieve).and_return(payment_link_expanded)
        allow(Stripe::Price).to receive(:retrieve).and_return(price)
        allow(Stripe::Product).to receive(:retrieve).and_return(product)
      end

      it 'lists all active payment links by default' do
        expect(Stripe::PaymentLink).to receive(:list).with(hash_including(
          active: true,
          limit: 100
        )).and_return(links)

        output = run_cli_command_quietly('billing', 'payment-links')

        expect(output[:stdout]).to include('plink_001')
        expect(output[:stdout]).to include('Total: 2 payment link(s)')
        expect(last_exit_code).to eq(0)
      end

      it 'displays payment links in formatted table' do
        output = run_cli_command_quietly('billing', 'payment-links')

        expect(output[:stdout]).to match(/ID.*PRODUCT\/PRICE.*AMOUNT.*INTERVAL.*ACTIVE/)
      end

      it 'respects limit parameter' do
        expect(Stripe::PaymentLink).to receive(:list).with(hash_including(
          limit: 50
        )).and_return(links)

        run_cli_command_quietly('billing', 'payment-links', '--limit', '50')
      end

      it 'shows inactive links when active-only is false' do
        expect(Stripe::PaymentLink).to receive(:list).with(hash_not_including(
          :active
        )).and_return(links)

        output = run_cli_command_quietly('billing', 'payment-links', '--no-active-only')

        expect(last_exit_code).to eq(0)
      end

      it 'displays product name and amount' do
        output = run_cli_command_quietly('billing', 'payment-links')

        expect(output[:stdout]).to include('Test Product')
        expect(output[:stdout]).to include('USD 10.00')
      end

      it 'displays subscription interval' do
        output = run_cli_command_quietly('billing', 'payment-links')

        expect(output[:stdout]).to include('month')
      end

      it 'shows usage hint at the end' do
        output = run_cli_command_quietly('billing', 'payment-links')

        expect(output[:stdout]).to include("Use 'bin/ots billing payment-links show")
      end

      context 'when no payment links exist' do
        let(:empty_list) { double('ListObject', data: []) }

        before do
          allow(Stripe::PaymentLink).to receive(:list).and_return(empty_list)
        end

        it 'displays no payment links message' do
          output = run_cli_command_quietly('billing', 'payment-links')

          expect(output[:stdout]).to include('No payment links found')
          expect(last_exit_code).to eq(0)
        end
      end

      context 'when Stripe API fails' do
        before do
          allow(Stripe::PaymentLink).to receive(:list).and_raise(
            Stripe::APIConnectionError.new('Network error')
          )
        end

        it 'handles connection errors' do
          output = run_cli_command_quietly('billing', 'payment-links')

          expect(output[:stdout]).to include('Error fetching payment links')
          expect(output[:stdout]).to include('Network error')
        end
      end

      context 'with retrieval errors for individual links' do
        before do
          allow(Stripe::PaymentLink).to receive(:retrieve).and_raise(
            Stripe::InvalidRequestError.new('Invalid link', 'id')
          )
        end

        it 'continues with N/A values when retrieval fails' do
          output = run_cli_command_quietly('billing', 'payment-links')

          expect(output[:stdout]).to include('N/A')
          expect(last_exit_code).to eq(0)
        end

        it 'logs warning for retrieval errors' do
          expect(OT.logger).to receive(:warn)

          run_cli_command_quietly('billing', 'payment-links')
        end
      end

      context 'with pagination' do
        it 'allows custom limits for pagination' do
          expect(Stripe::PaymentLink).to receive(:list).with(hash_including(
            limit: 25
          )).and_return(links)

          run_cli_command_quietly('billing', 'payment-links', '--limit', '25')
        end

        it 'handles large result sets with default limit' do
          large_links = double('ListObject', data: Array.new(100) do |i|
            double('PaymentLink',
              id: "plink_#{i}",
              active: true,
              line_items: double('ListObject', data: [])
            )
          end)

          allow(Stripe::PaymentLink).to receive(:list).and_return(large_links)

          output = run_cli_command_quietly('billing', 'payment-links')

          expect(output[:stdout]).to include('Total: 100 payment link(s)')
        end
      end
    end
  end

  describe 'billing payment-links create' do
    before do
      allow(Stripe::Price).to receive(:retrieve).and_return(price)
      allow(Stripe::Product).to receive(:retrieve).and_return(product)
    end

    context 'with valid parameters' do
      before do
        allow(Stripe::PaymentLink).to receive(:create).and_return(payment_link)
      end

      it 'creates a payment link with required price' do
        expect(Stripe::PaymentLink).to receive(:create).with(hash_including(
          line_items: array_including(hash_including(
            price: price_id,
            quantity: 1
          ))
        )).and_return(payment_link)

        output = run_cli_command_quietly('billing', 'payment-links', 'create', '--price', price_id)

        expect(output[:stdout]).to include('Payment link created successfully')
        expect(output[:stdout]).to include(link_id)
        expect(output[:stdout]).to include('https://buy.stripe.com/test_xyz')
        expect(last_exit_code).to eq(0)
      end

      it 'displays price and product details before creating' do
        output = run_cli_command_quietly('billing', 'payment-links', 'create', '--price', price_id)

        expect(output[:stdout]).to include("Price: #{price_id}")
        expect(output[:stdout]).to include('Product: Test Product')
        expect(output[:stdout]).to include('Amount: USD 10.00/month')
      end

      it 'creates link with custom quantity' do
        expect(Stripe::PaymentLink).to receive(:create).with(hash_including(
          line_items: array_including(hash_including(
            quantity: 5
          ))
        )).and_return(payment_link)

        run_cli_command_quietly('billing', 'payment-links', 'create',
          '--price', price_id, '--quantity', '5')
      end

      it 'enables adjustable quantity when specified' do
        expect(Stripe::PaymentLink).to receive(:create).with(hash_including(
          line_items: array_including(hash_including(
            adjustable_quantity: { enabled: true }
          ))
        )).and_return(payment_link)

        run_cli_command_quietly('billing', 'payment-links', 'create',
          '--price', price_id, '--allow-quantity')
      end

      it 'adds after_completion redirect URL when specified' do
        redirect_url = 'https://example.com/thank-you'

        expect(Stripe::PaymentLink).to receive(:create).with(hash_including(
          after_completion: {
            type: 'redirect',
            redirect: { url: redirect_url }
          }
        )).and_return(payment_link)

        run_cli_command_quietly('billing', 'payment-links', 'create',
          '--price', price_id, '--after-completion', redirect_url)
      end

      it 'displays shareable URL in output' do
        output = run_cli_command_quietly('billing', 'payment-links', 'create', '--price', price_id)

        expect(output[:stdout]).to include('Share this link with customers!')
        expect(output[:stdout]).to include('URL: https://buy.stripe.com/test_xyz')
      end
    end

    context 'with missing required parameters' do
      it 'requires price parameter' do
        output = run_cli_command_quietly('billing', 'payment-links', 'create')

        required_message = output[:stderr].to_s + output[:stdout].to_s
        expect(required_message).to include('required')
      end
    end

    context 'with invalid price ID' do
      before do
        allow(Stripe::Price).to receive(:retrieve).and_raise(
          Stripe::InvalidRequestError.new('No such price', 'price')
        )
      end

      it 'displays error for non-existent price' do
        output = run_cli_command_quietly('billing', 'payment-links', 'create', '--price', 'invalid_price')

        expect(output[:stdout]).to include('Error creating payment link')
        expect(output[:stdout]).to include('No such price')
      end
    end

    context 'when Stripe API fails' do
      before do
        allow(Stripe::PaymentLink).to receive(:create).and_raise(
          Stripe::APIConnectionError.new('Network error')
        )
      end

      it 'handles connection errors' do
        output = run_cli_command_quietly('billing', 'payment-links', 'create', '--price', price_id)

        expect(output[:stdout]).to include('Error creating payment link')
        expect(output[:stdout]).to include('Network error')
      end
    end

    context 'with one-time price' do
      let(:one_time_price) do
        mock_stripe_price(
          id: 'price_onetime',
          product: product_id,
          unit_amount: 5000,
          currency: 'usd',
          recurring: nil
        )
      end

      before do
        allow(Stripe::Price).to receive(:retrieve).and_return(one_time_price)
      end

      it 'displays one-time for non-recurring prices' do
        output = run_cli_command_quietly('billing', 'payment-links', 'create', '--price', 'price_onetime')

        expect(output[:stdout]).to include('Amount: USD 50.00/one-time')
      end
    end
  end

  describe 'billing payment-links show' do
    let(:detailed_link) do
      double('PaymentLink',
        id: link_id,
        url: 'https://buy.stripe.com/test_xyz',
        active: true,
        metadata: { 'campaign' => 'summer2024' },
        line_items: double('ListObject', data: [
          double('LineItem',
            price: price,
            quantity: 1
          )
        ])
      )
    end

    before do
      allow(Stripe::PaymentLink).to receive(:retrieve).and_return(detailed_link)
      allow(Stripe::Price).to receive(:retrieve).and_return(price)
      allow(Stripe::Product).to receive(:retrieve).and_return(product)
    end

    context 'with valid payment link ID' do
      it 'displays full payment link details' do
        output = run_cli_command_quietly('billing', 'payment-links', 'show', link_id)

        expect(output[:stdout]).to include('Payment Link Details')
        expect(output[:stdout]).to include("ID: #{link_id}")
        expect(output[:stdout]).to include('URL: https://buy.stripe.com/test_xyz')
        expect(last_exit_code).to eq(0)
      end

      it 'displays product information' do
        output = run_cli_command_quietly('billing', 'payment-links', 'show', link_id)

        expect(output[:stdout]).to include('Product: Test Product')
        expect(output[:stdout]).to include('Amount: USD 10.00')
      end

      it 'displays active status' do
        output = run_cli_command_quietly('billing', 'payment-links', 'show', link_id)

        expect(output[:stdout]).to include('Active: yes')
      end

      it 'displays metadata if present' do
        output = run_cli_command_quietly('billing', 'payment-links', 'show', link_id)

        expect(output[:stdout]).to include('campaign: summer2024')
      end
    end

    context 'with inactive payment link' do
      let(:inactive_link) do
        double('PaymentLink',
          id: link_id,
          url: 'https://buy.stripe.com/test_xyz',
          active: false,
          metadata: {},
          line_items: double('ListObject', data: [])
        )
      end

      before do
        allow(Stripe::PaymentLink).to receive(:retrieve).and_return(inactive_link)
      end

      it 'displays inactive status' do
        output = run_cli_command_quietly('billing', 'payment-links', 'show', link_id)

        expect(output[:stdout]).to include('Active: no')
      end
    end

    context 'with non-existent payment link' do
      before do
        allow(Stripe::PaymentLink).to receive(:retrieve).and_raise(
          Stripe::InvalidRequestError.new('No such payment link', 'id')
        )
      end

      it 'displays error for invalid ID' do
        output = run_cli_command_quietly('billing', 'payment-links', 'show', 'invalid_id')

        expect(output[:stdout]).to include('Error fetching payment link')
        expect(output[:stdout]).to include('No such payment link')
      end
    end

    context 'when Stripe API fails' do
      before do
        allow(Stripe::PaymentLink).to receive(:retrieve).and_raise(
          Stripe::APIConnectionError.new('Network error')
        )
      end

      it 'handles connection errors' do
        output = run_cli_command_quietly('billing', 'payment-links', 'show', link_id)

        expect(output[:stdout]).to include('Error fetching payment link')
        expect(output[:stdout]).to include('Network error')
      end
    end
  end

  describe 'billing payment-links update' do
    let(:updated_link) do
      double('PaymentLink',
        id: link_id,
        url: 'https://buy.stripe.com/test_xyz',
        active: true,
        metadata: { 'campaign' => 'fall2024' }
      )
    end

    before do
      allow(Stripe::PaymentLink).to receive(:retrieve).and_return(payment_link)
      allow($stdin).to receive(:gets).and_return("y\n")
    end

    context 'with valid parameters' do
      before do
        allow(Stripe::PaymentLink).to receive(:update).and_return(updated_link)
      end

      it 'updates payment link metadata' do
        expect(Stripe::PaymentLink).to receive(:update).with(
          link_id,
          hash_including(metadata: { 'campaign' => 'fall2024' })
        ).and_return(updated_link)

        output = run_cli_command_quietly('billing', 'payment-links', 'update', link_id,
          '--metadata', 'campaign=fall2024')

        expect(output[:stdout]).to include('Payment link updated successfully')
        expect(last_exit_code).to eq(0)
      end

      it 'displays updated metadata' do
        output = run_cli_command_quietly('billing', 'payment-links', 'update', link_id,
          '--metadata', 'campaign=fall2024')

        expect(output[:stdout]).to include('campaign: fall2024')
      end

      it 'can activate an inactive link' do
        expect(Stripe::PaymentLink).to receive(:update).with(
          link_id,
          hash_including(active: true)
        ).and_return(updated_link)

        run_cli_command_quietly('billing', 'payment-links', 'update', link_id, '--active')
      end

      it 'can deactivate an active link' do
        expect(Stripe::PaymentLink).to receive(:update).with(
          link_id,
          hash_including(active: false)
        ).and_return(updated_link)

        run_cli_command_quietly('billing', 'payment-links', 'update', link_id, '--no-active')
      end
    end

    context 'with non-existent payment link' do
      before do
        allow(Stripe::PaymentLink).to receive(:retrieve).and_raise(
          Stripe::InvalidRequestError.new('No such payment link', 'id')
        )
      end

      it 'displays error for invalid ID' do
        output = run_cli_command_quietly('billing', 'payment-links', 'update', 'invalid_id',
          '--metadata', 'key=value')

        expect(output[:stdout]).to include('Error updating payment link')
        expect(output[:stdout]).to include('No such payment link')
      end
    end

    context 'when Stripe API fails' do
      before do
        allow(Stripe::PaymentLink).to receive(:update).and_raise(
          Stripe::APIConnectionError.new('Network error')
        )
      end

      it 'handles connection errors' do
        output = run_cli_command_quietly('billing', 'payment-links', 'update', link_id,
          '--metadata', 'key=value')

        expect(output[:stdout]).to include('Error updating payment link')
        expect(output[:stdout]).to include('Network error')
      end
    end
  end

  describe 'billing payment-links archive' do
    let(:archived_link) do
      double('PaymentLink',
        id: link_id,
        url: 'https://buy.stripe.com/test_xyz',
        active: false
      )
    end

    before do
      allow(Stripe::PaymentLink).to receive(:retrieve).and_return(payment_link)
      allow($stdin).to receive(:gets).and_return("y\n")
    end

    context 'with confirmation' do
      before do
        allow(Stripe::PaymentLink).to receive(:update).and_return(archived_link)
      end

      it 'archives payment link after confirmation' do
        expect(Stripe::PaymentLink).to receive(:update).with(
          link_id,
          { active: false }
        ).and_return(archived_link)

        output = run_cli_command_quietly('billing', 'payment-links', 'archive', link_id)

        expect(output[:stdout]).to include('Payment link archived successfully')
        expect(last_exit_code).to eq(0)
      end

      it 'displays warning about permanent action' do
        output = run_cli_command_quietly('billing', 'payment-links', 'archive', link_id)

        expect(output[:stdout]).to match(/archiv/i)
        expect(output[:stdout]).to include(link_id)
      end
    end

    context 'without confirmation' do
      before do
        allow($stdin).to receive(:gets).and_return("n\n")
      end

      it 'cancels archive operation' do
        expect(Stripe::PaymentLink).not_to receive(:update)

        output = run_cli_command_quietly('billing', 'payment-links', 'archive', link_id)

        expect(output[:stdout]).to match(/cancel/i)
      end
    end

    context 'with non-existent payment link' do
      before do
        allow(Stripe::PaymentLink).to receive(:retrieve).and_raise(
          Stripe::InvalidRequestError.new('No such payment link', 'id')
        )
      end

      it 'displays error for invalid ID' do
        output = run_cli_command_quietly('billing', 'payment-links', 'archive', 'invalid_id')

        expect(output[:stdout]).to include('Error archiving payment link')
        expect(output[:stdout]).to include('No such payment link')
      end
    end

    context 'when Stripe API fails' do
      before do
        allow(Stripe::PaymentLink).to receive(:update).and_raise(
          Stripe::APIConnectionError.new('Network error')
        )
      end

      it 'handles connection errors' do
        output = run_cli_command_quietly('billing', 'payment-links', 'archive', link_id)

        expect(output[:stdout]).to include('Error archiving payment link')
        expect(output[:stdout]).to include('Network error')
      end
    end
  end

  context 'when billing not configured' do
    before do
      allow(OT).to receive(:billing_config).and_return(
        double('BillingConfig', enabled?: false)
      )
    end

    it 'exits early with error message for list command' do
      output = run_cli_command_quietly('billing', 'payment-links')

      expect(output[:stdout]).to include('Billing not enabled in etc/billing.yaml')
    end

    it 'exits early with error message for create command' do
      output = run_cli_command_quietly('billing', 'payment-links', 'create', '--price', price_id)

      expect(output[:stdout]).to include('Billing not enabled in etc/billing.yaml')
    end
  end

  context 'when Stripe key not configured' do
    before do
      allow(OT).to receive(:billing_config).and_return(
        double('BillingConfig', enabled?: true, stripe_key: nil)
      )
    end

    it 'exits early with error message' do
      output = run_cli_command_quietly('billing', 'payment-links')

      expect(output[:stdout]).to include('STRIPE_KEY environment variable not set or billing.yaml has no valid key')
    end
  end

  describe 'parameter validation' do
    context 'quantity validation' do
      it 'accepts positive quantities' do
        allow(Stripe::PaymentLink).to receive(:create).and_return(payment_link)

        run_cli_command_quietly('billing', 'payment-links', 'create',
          '--price', price_id, '--quantity', '10')

        expect(last_exit_code).to eq(0)
      end
    end

    context 'after_completion URL validation' do
      it 'accepts valid HTTPS URLs' do
        allow(Stripe::PaymentLink).to receive(:create).and_return(payment_link)

        run_cli_command_quietly('billing', 'payment-links', 'create',
          '--price', price_id, '--after-completion', 'https://example.com/success')

        expect(last_exit_code).to eq(0)
      end
    end
  end
end
