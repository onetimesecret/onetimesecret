# frozen_string_literal: true

require 'spec_helper'
require 'cli/cli_spec_helper'
require_relative '../support/billing_spec_helper'
require_relative '../support/stripe_test_data'

RSpec.describe 'Billing Products CLI Commands', type: :cli do
  let(:billing_config) { double('BillingConfig', enabled?: true, stripe_key: 'sk_test_123') }

  before do
    allow(OT).to receive(:billing_config).and_return(billing_config)
    allow(Stripe).to receive(:api_key=)
  end

  describe 'billing products (list)' do
    let(:product1) do
      mock_stripe_product(
        id: 'prod_test1',
        name: 'Personal Plan',
        metadata: { 'tier' => 'personal', 'tenancy' => 'single', 'region' => 'us-east' },
        active: true
      )
    end
    let(:product2) do
      mock_stripe_product(
        id: 'prod_test2',
        name: 'Professional Plan',
        metadata: { 'tier' => 'professional', 'tenancy' => 'multi', 'region' => 'global' },
        active: true
      )
    end
    let(:products_list) { double('ListObject', data: [product1, product2]) }

    context 'with valid configuration' do
      it 'lists all active products' do
        expect(Stripe::Product).to receive(:list).with(hash_including(active: true, limit: 100)).and_return(products_list)

        output = run_cli_command_quietly('billing', 'products')

        expect(output[:stdout]).to include('prod_test1')
        expect(output[:stdout]).to include('Personal Plan')
        expect(output[:stdout]).to include('prod_test2')
        expect(output[:stdout]).to include('Professional Plan')
        expect(output[:stdout]).to include('Total: 2 product(s)')
        expect(last_exit_code).to eq(0)
      end

      it 'displays formatted table header' do
        allow(Stripe::Product).to receive(:list).and_return(products_list)

        output = run_cli_command_quietly('billing', 'products')

        expect(output[:stdout]).to match(/ID.*NAME.*TIER.*TENANCY.*REGION.*ACTIVE/)
      end

      it 'displays product metadata' do
        allow(Stripe::Product).to receive(:list).and_return(products_list)

        output = run_cli_command_quietly('billing', 'products')

        expect(output[:stdout]).to include('personal')
        expect(output[:stdout]).to include('professional')
        expect(output[:stdout]).to include('single')
        expect(output[:stdout]).to include('multi')
      end
    end

    context 'with --active-only flag set to false' do
      let(:inactive_product) { mock_stripe_product(id: 'prod_inactive', name: 'Inactive Plan', active: false) }
      let(:all_products) { double('ListObject', data: [product1, inactive_product]) }

      it 'includes inactive products' do
        expect(Stripe::Product).to receive(:list).with(hash_including(active: false)).and_return(all_products)

        output = run_cli_command_quietly('billing', 'products', '--no-active-only')

        expect(output[:stdout]).to include('prod_inactive')
      end
    end

    context 'when no products found' do
      it 'displays appropriate message' do
        empty_list = double('ListObject', data: [])
        allow(Stripe::Product).to receive(:list).and_return(empty_list)

        output = run_cli_command_quietly('billing', 'products')

        expect(output[:stdout]).to include('No products found')
        expect(last_exit_code).to eq(0)
      end
    end

    context 'when billing not configured' do
      let(:billing_config) { double('BillingConfig', enabled?: false) }

      it 'exits with configuration error' do
        output = run_cli_command_quietly('billing', 'products')

        expect(output[:stdout]).to match(/billing not enabled/i)
      end
    end
  end

  describe 'billing products create' do
    let(:product) { mock_stripe_product(name: 'New Product') }

    before do
      allow($stdin).to receive(:gets).and_return("y\n")
    end

    context 'with valid name parameter' do
      it 'creates a product with metadata' do
        expect(Stripe::Product).to receive(:create).with(
          hash_including(
            name: 'Test Product',
            metadata: hash_including('app' => 'onetimesecret')
          )
        ).and_return(product)

        output = run_cli_command_quietly('billing', 'products', 'create', 'Test Product')

        expect(output[:stdout]).to include('Product created successfully')
        expect(last_exit_code).to eq(0)
      end

      it 'displays product details after creation' do
        allow(Stripe::Product).to receive(:create).and_return(product)

        output = run_cli_command_quietly('billing', 'products', 'create', 'Test Product')

        expect(output[:stdout]).to include('ID:')
        expect(output[:stdout]).to include('Name:')
      end

      it 'suggests next steps' do
        allow(Stripe::Product).to receive(:create).and_return(product)

        output = run_cli_command_quietly('billing', 'products', 'create', 'Test Product')

        expect(output[:stdout]).to match(/next steps/i)
        expect(output[:stdout]).to include('billing prices create')
      end
    end

    context 'with tier and region options' do
      it 'includes metadata in creation' do
        expect(Stripe::Product).to receive(:create).with(
          hash_including(
            name: 'Enterprise Plan',
            metadata: hash_including('tier' => 'enterprise', 'region' => 'eu-west')
          )
        ).and_return(product)

        run_cli_command_quietly('billing', 'products', 'create', 'Enterprise Plan', '--tier', 'enterprise', '--region', 'eu-west')

        expect(last_exit_code).to eq(0)
      end
    end

    context 'with plan_id option' do
      it 'includes plan_id in metadata' do
        expect(Stripe::Product).to receive(:create).with(
          hash_including(
            metadata: hash_including('plan_id' => 'identity_v1')
          )
        ).and_return(product)

        run_cli_command_quietly('billing', 'products', 'create', 'Identity Plan', '--plan-id', 'identity_v1')
      end
    end

    context 'with capabilities option' do
      it 'includes capabilities in metadata' do
        expect(Stripe::Product).to receive(:create).with(
          hash_including(
            metadata: hash_including('capabilities' => 'create_secrets,api_access')
          )
        ).and_return(product)

        run_cli_command_quietly('billing', 'products', 'create', 'Pro Plan', '--capabilities', 'create_secrets,api_access')
      end
    end

    context 'with marketing features' do
      it 'adds marketing features to product' do
        expect(Stripe::Product).to receive(:create).with(
          hash_including(
            marketing_features: [
              { name: 'Unlimited secrets' },
              { name: 'Priority support' }
            ]
          )
        ).and_return(product)

        output = run_cli_command_quietly(
          'billing', 'products', 'create', 'Premium Plan',
          '--marketing-features', 'Unlimited secrets,Priority support'
        )

        expect(output[:stdout]).to match(/marketing features/i)
      end
    end

    context 'without name parameter (interactive mode)' do
      before do
        allow($stdin).to receive(:gets).and_return("Interactive Product\n", "y\n")
      end

      it 'prompts for product name' do
        allow(Stripe::Product).to receive(:create).and_return(product)

        output = run_cli_command_quietly('billing', 'products', 'create')

        expect(output[:stdout]).to include('Product name:')
      end
    end

    context 'with empty name' do
      before do
        allow($stdin).to receive(:gets).and_return("\n")
      end

      it 'displays validation error' do
        output = run_cli_command_quietly('billing', 'products', 'create', '')

        expect(output[:stdout]).to match(/error.*product name.*required/i)
      end
    end

    context 'when user declines confirmation' do
      before do
        allow($stdin).to receive(:gets).and_return("n\n")
      end

      it 'does not create product' do
        expect(Stripe::Product).not_to receive(:create)

        run_cli_command_quietly('billing', 'products', 'create', 'Test Product')
      end
    end

    context 'when Stripe API fails' do
      it 'displays error message' do
        allow(Stripe::Product).to receive(:create).and_raise(
          Stripe::InvalidRequestError.new('Invalid product', 'product', http_status: 400)
        )

        output = run_cli_command_quietly('billing', 'products', 'create', 'Test Product')

        expect(output[:stdout]).to match(/error creating product/i)
      end
    end

    context 'with all metadata fields' do
      it 'creates product with complete metadata' do
        expect(Stripe::Product).to receive(:create).with(
          hash_including(
            metadata: hash_including(
              'app' => 'onetimesecret',
              'plan_id' => 'full_v1',
              'tier' => 'enterprise',
              'region' => 'global',
              'tenancy' => 'multi',
              'capabilities' => 'all_features'
            )
          )
        ).and_return(product)

        run_cli_command_quietly(
          'billing', 'products', 'create', 'Complete Plan',
          '--plan-id', 'full_v1',
          '--tier', 'enterprise',
          '--region', 'global',
          '--tenancy', 'multi',
          '--capabilities', 'all_features'
        )
      end
    end
  end

  describe 'billing products show' do
    let(:product) do
      mock_stripe_product(
        id: 'prod_test123',
        name: 'Professional Plan',
        description: 'For professional use',
        metadata: { 'tier' => 'professional', 'region' => 'us-east' },
        active: true,
        marketing_features: [
          double('MarketingFeature', name: 'Unlimited secrets', id: 'feat_1'),
          double('MarketingFeature', name: 'Priority support', id: 'feat_2')
        ]
      )
    end
    let(:prices) do
      double('ListObject', data: [
        mock_stripe_price(id: 'price_monthly', unit_amount: 1000, recurring: { interval: 'month' }),
        mock_stripe_price(id: 'price_annual', unit_amount: 10000, recurring: { interval: 'year' })
      ])
    end

    before do
      allow(Stripe::Product).to receive(:retrieve).with('prod_test123').and_return(product)
      allow(Stripe::Price).to receive(:list).with(hash_including(product: 'prod_test123')).and_return(prices)
    end

    context 'with valid product ID' do
      it 'displays product details' do
        output = run_cli_command_quietly('billing', 'products', 'show', 'prod_test123')

        expect(output[:stdout]).to include('Product Details:')
        expect(output[:stdout]).to include('prod_test123')
        expect(output[:stdout]).to include('Professional Plan')
        expect(output[:stdout]).to include('For professional use')
        expect(last_exit_code).to eq(0)
      end

      it 'displays product metadata' do
        output = run_cli_command_quietly('billing', 'products', 'show', 'prod_test123')

        expect(output[:stdout]).to include('Metadata:')
        expect(output[:stdout]).to include('tier: professional')
        expect(output[:stdout]).to include('region: us-east')
      end

      it 'displays marketing features' do
        output = run_cli_command_quietly('billing', 'products', 'show', 'prod_test123')

        expect(output[:stdout]).to include('Marketing Features:')
        expect(output[:stdout]).to include('Unlimited secrets')
        expect(output[:stdout]).to include('Priority support')
      end

      it 'displays associated prices' do
        output = run_cli_command_quietly('billing', 'products', 'show', 'prod_test123')

        expect(output[:stdout]).to include('Prices:')
        expect(output[:stdout]).to include('price_monthly')
        expect(output[:stdout]).to include('price_annual')
        expect(output[:stdout]).to match(/USD.*10\.00.*month/i)
      end

      it 'displays active status' do
        output = run_cli_command_quietly('billing', 'products', 'show', 'prod_test123')

        expect(output[:stdout]).to match(/active:.*yes/i)
      end
    end

    context 'when product has no prices' do
      let(:prices) { double('ListObject', data: []) }

      it 'displays none message' do
        output = run_cli_command_quietly('billing', 'products', 'show', 'prod_test123')

        expect(output[:stdout]).to match(/prices:.*\(none\)/im)
      end
    end

    context 'when product has no metadata' do
      let(:product) { mock_stripe_product(id: 'prod_test123', metadata: {}) }

      it 'does not display metadata section' do
        allow(product).to receive(:metadata).and_return({})
        allow(product.metadata).to receive(:any?).and_return(false)

        output = run_cli_command_quietly('billing', 'products', 'show', 'prod_test123')

        expect(output[:stdout]).not_to match(/metadata:/i)
      end
    end

    context 'with invalid product ID' do
      it 'displays error message' do
        allow(Stripe::Product).to receive(:retrieve).and_raise(
          Stripe::InvalidRequestError.new('No such product', 'product', http_status: 404)
        )

        output = run_cli_command_quietly('billing', 'products', 'show', 'prod_invalid')

        expect(output[:stdout]).to match(/error retrieving product/i)
      end
    end
  end

  describe 'billing products update' do
    let(:product) do
      mock_stripe_product(
        id: 'prod_test123',
        name: 'Existing Product',
        metadata: { 'tier' => 'personal', 'region' => 'us-east', 'app' => 'onetimesecret' }
      )
    end

    before do
      allow(Stripe::Product).to receive(:retrieve).with('prod_test123').and_return(product)
      allow($stdin).to receive(:gets).and_return("y\n")
    end

    context 'with valid product ID and metadata' do
      it 'updates product metadata' do
        expect(Stripe::Product).to receive(:update).with(
          'prod_test123',
          hash_including(
            metadata: hash_including('tier' => 'professional')
          )
        ).and_return(product)

        output = run_cli_command_quietly('billing', 'products', 'update', 'prod_test123', '--tier', 'professional')

        expect(output[:stdout]).to include('Product updated successfully')
        expect(last_exit_code).to eq(0)
      end

      it 'displays current metadata before update' do
        allow(Stripe::Product).to receive(:update).and_return(product)

        output = run_cli_command_quietly('billing', 'products', 'update', 'prod_test123', '--tier', 'professional')

        expect(output[:stdout]).to include('Current product:')
        expect(output[:stdout]).to include('Current metadata:')
      end

      it 'displays updated metadata after update' do
        updated_product = mock_stripe_product(
          id: 'prod_test123',
          metadata: { 'tier' => 'professional', 'region' => 'us-east' }
        )
        allow(Stripe::Product).to receive(:update).and_return(updated_product)

        output = run_cli_command_quietly('billing', 'products', 'update', 'prod_test123', '--tier', 'professional')

        expect(output[:stdout]).to include('Updated metadata:')
        expect(output[:stdout]).to include('tier: professional')
      end
    end

    context 'updating multiple metadata fields' do
      it 'updates all specified fields' do
        expect(Stripe::Product).to receive(:update).with(
          'prod_test123',
          hash_including(
            metadata: hash_including(
              'tier' => 'enterprise',
              'region' => 'global',
              'capabilities' => 'all_features'
            )
          )
        ).and_return(product)

        run_cli_command_quietly(
          'billing', 'products', 'update', 'prod_test123',
          '--tier', 'enterprise',
          '--region', 'global',
          '--capabilities', 'all_features'
        )
      end
    end

    context 'adding marketing features' do
      it 'adds new marketing feature' do
        expect(Stripe::Product).to receive(:update).with(
          'prod_test123',
          hash_including(
            marketing_features: array_including(hash_including(name: 'New Feature'))
          )
        ).and_return(product)

        output = run_cli_command_quietly(
          'billing', 'products', 'update', 'prod_test123',
          '--add-marketing-feature', 'New Feature'
        )

        expect(output[:stdout]).to include('Adding marketing feature: New Feature')
      end
    end

    context 'removing marketing features' do
      let(:product_with_features) do
        mock_stripe_product(
          id: 'prod_test123',
          marketing_features: [
            { 'name' => 'Feature 1' },
            { 'name' => 'Feature 2' }
          ]
        )
      end

      it 'removes existing marketing feature' do
        allow(Stripe::Product).to receive(:retrieve).and_return(product_with_features)
        expect(Stripe::Product).to receive(:update).with(
          'prod_test123',
          hash_including(marketing_features: [{ 'name' => 'Feature 1' }])
        ).and_return(product_with_features)

        output = run_cli_command_quietly(
          'billing', 'products', 'update', 'prod_test123',
          '--remove-marketing-feature', 'Feature 2'
        )

        expect(output[:stdout]).to include('Removing marketing feature: Feature 2')
      end
    end

    context 'when user declines confirmation' do
      before do
        allow($stdin).to receive(:gets).and_return("n\n")
      end

      it 'does not update product' do
        expect(Stripe::Product).not_to receive(:update)

        run_cli_command_quietly('billing', 'products', 'update', 'prod_test123', '--tier', 'professional')
      end
    end

    context 'with invalid product ID' do
      it 'displays error message' do
        allow(Stripe::Product).to receive(:retrieve).and_raise(
          Stripe::InvalidRequestError.new('No such product', 'product', http_status: 404)
        )

        output = run_cli_command_quietly('billing', 'products', 'update', 'prod_invalid', '--tier', 'pro')

        expect(output[:stdout]).to match(/error updating product/i)
      end
    end

    context 'preserving existing metadata' do
      it 'maintains unchanged fields' do
        expect(Stripe::Product).to receive(:update).with(
          'prod_test123',
          hash_including(
            metadata: hash_including(
              'tier' => 'professional',
              'region' => 'us-east',  # Preserved from original
              'app' => 'onetimesecret' # Always set
            )
          )
        ).and_return(product)

        run_cli_command_quietly('billing', 'products', 'update', 'prod_test123', '--tier', 'professional')
      end
    end
  end

  describe 'integration scenarios' do
    it 'create, show, and update product workflow' do
      product = mock_stripe_product(id: 'prod_workflow', name: 'Workflow Product')
      allow($stdin).to receive(:gets).and_return("y\n")

      # Create
      allow(Stripe::Product).to receive(:create).and_return(product)
      output = run_cli_command_quietly('billing', 'products', 'create', 'Workflow Product')
      expect(output[:stdout]).to include('Product created successfully')

      # Show
      allow(Stripe::Product).to receive(:retrieve).and_return(product)
      allow(Stripe::Price).to receive(:list).and_return(double(data: []))

      output = run_cli_command_quietly('billing', 'products', 'show', 'prod_workflow')
      expect(output[:stdout]).to include('Workflow Product')

      # Update
      allow(Stripe::Product).to receive(:update).and_return(product)

      output = run_cli_command_quietly('billing', 'products', 'update', 'prod_workflow', '--tier', 'premium')
      expect(output[:stdout]).to include('Product updated successfully')
    end
  end
end
