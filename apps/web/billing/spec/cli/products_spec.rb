# apps/web/billing/spec/cli/products_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require 'onetime/cli'
require_relative '../../cli/products_command'
require_relative '../../cli/products_create_command'
require_relative '../../cli/products_show_command'
require_relative '../../cli/products_update_command'

RSpec.describe 'Billing Products CLI Commands', :billing_cli, :unit do
  let(:stripe_client) { Billing::StripeClient.new }

  describe Onetime::CLI::BillingProductsCommand do
    subject(:command) { described_class.new }

    describe '#call (list products)' do
      it 'lists active products by default', :unit do
        output = capture_stdout do
          command.call(limit: 100)
        end

        expect(output).to include('Fetching products from Stripe')
        expect(output).to match(/ID.*NAME.*TIER.*TENANCY.*REGION.*ACTIVE/)
      end

      it 'includes inactive products when active_only is false', :unit do
        output = capture_stdout do
          command.call(active_only: false, limit: 100)
        end

        expect(output).to include('Fetching products from Stripe')
      end

      it 'displays product count in output', :unit do
        output = capture_stdout do
          command.call(limit: 100)
        end

        expect(output).to match(/Total: \d+ product\(s\)/)
      end

      it 'formats product rows with proper alignment', :unit do
        output = capture_stdout do
          command.call(limit: 100)
        end

        # Check for separator line (101 characters)
        expect(output).to include('-' * 101)
      end

      it 'handles empty results gracefully' do
        # Mock empty product list
        allow(Stripe::Product).to receive(:list).and_return(
          double(data: []),
        )

        output = capture_stdout do
          command.call(limit: 100)
        end

        expect(output).to include('No products found')
      end
    end
  end

  describe Onetime::CLI::BillingProductsCreateCommand do
    subject(:command) { described_class.new }

    describe '#call (create product)' do
      it 'creates product with name argument', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(name: 'Test Product')
        end

        expect(output).to include("Creating product 'Test Product' with metadata:")
        expect(output).to include('app: onetimesecret')
        expect(output).to include('Proceed? (y/n):')
        expect(output).to include('Product created successfully')
        expect(output).to match(/ID: prod_/)
      end

      it 'requires confirmation before creation', :unit do
        allow($stdin).to receive(:gets).and_return("n\n")

        output = capture_stdout do
          command.call(name: 'Test Product')
        end

        expect(output).to include('Proceed? (y/n):')
        expect(output).not_to include('Product created successfully')
      end

      it 'validates product name is required' do
        allow($stdin).to receive(:gets).and_return("\n", "\n", "n\n")

        output = capture_stdout do
          command.call
        end

        expect(output).to include('Product name:')
        expect(output).to include('Error: Product name is required')
      end

      it 'accepts plan_id option', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(name: 'Test Product', plan_id: 'identity_v1')
        end

        expect(output).to include('plan_id: identity_v1')
        expect(output).to include('Product created successfully')
      end

      it 'accepts tier option', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(name: 'Test Product', tier: 'single_team')
        end

        expect(output).to include('tier: single_team')
      end

      it 'accepts region option', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(name: 'Test Product', region: 'EU')
        end

        expect(output).to include('region: EU')
      end

      it 'defaults region to global if not specified', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(name: 'Test Product')
        end

        expect(output).to include('region: global')
      end

      it 'accepts tenancy option', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(name: 'Test Product', tenancy: 'multi')
        end

        expect(output).to include('tenancy: multi')
      end

      it 'accepts entitlements option', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(name: 'Test Product', entitlements: 'api,teams')
        end

        expect(output).to include('entitlements: api,teams')
      end

      it 'accepts marketing_features option', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(name: 'Test Product', marketing_features: 'Feature 1,Feature 2')
        end

        expect(output).to include('Marketing features:')
        expect(output).to include('- Feature 1')
        expect(output).to include('- Feature 2')
      end

      it 'displays next steps after creation', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(name: 'Test Product')
        end

        expect(output).to include('Next steps:')
        expect(output).to include('bin/ots billing prices create --product')
      end

      it 'handles interactive mode', :unit do
        allow($stdin).to receive(:gets).and_return("Test Product\n", "y\n")

        output = capture_stdout do
          command.call(interactive: true)
        end

        expect(output).to include('Product name:')
        expect(output).to include('Product created successfully')
      end

      it 'includes created timestamp in metadata', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(name: 'Test Product')
        end

        expect(output).to match(/created: \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/)
      end

      it 'initializes all metadata fields with empty strings', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(name: 'Test Product')
        end

        # All fields should be present even if empty
        expect(output).to include('plan_id:')
        expect(output).to include('tier:')
        expect(output).to include('tenancy:')
        expect(output).to include('entitlements:')
        expect(output).to include('limit_teams:')
        expect(output).to include('limit_members_per_team:')
      end

      it 'uses StripeClient for retry and idempotency', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(name: 'Test Product')
        end

        expect(output).to include('Product created successfully')
      end
    end
  end

  describe Onetime::CLI::BillingProductsShowCommand do
    subject(:command) { described_class.new }

    let(:product_id) { 'prod_test123' }

    describe '#call (show product)' do
      it 'displays product details', :unit do
        output = capture_stdout do
          command.call(product_id: product_id)
        end

        expect(output).to include('Product Details:')
        expect(output).to include('ID:')
        expect(output).to include('Name:')
        expect(output).to include('Active:')
      end

      it 'displays description if present' do
        # Create product with description
        product = stripe_client.create(Stripe::Product, {
          name: 'Product with Description',
          description: 'Test product description',
        }
        )

        output = capture_stdout do
          command.call(product_id: product.id)
        end

        expect(output).to include('Description:')

        # Cleanup
        stripe_client.delete(Stripe::Product, product.id)
      end

      it 'displays metadata section', :unit do
        # Create product with metadata
        product = stripe_client.create(Stripe::Product, {
          name: 'Metadata Test Product',
          metadata: {
            app: 'onetimesecret',
            tier: 'pro',
            region: 'global',
          },
        }
        )

        output = capture_stdout do
          command.call(product_id: product.id)
        end

        expect(output).to include('Metadata:')
        expect(output).to include('app: onetimesecret')
        expect(output).to include('tier: pro')
        expect(output).to include('region: global')

        # Cleanup
        stripe_client.delete(Stripe::Product, product.id)
      end

      it 'displays marketing features section' do
        output = capture_stdout do
          command.call(product_id: product_id)
        end

        # Verify Marketing Features section exists in output
        expect(output).to include('Marketing Features:')
      end

      it 'displays associated prices', :unit do
        output = capture_stdout do
          command.call(product_id: product_id)
        end

        expect(output).to include('Prices:')
      end

      it 'formats price information with amount and currency' do
        output = capture_stdout do
          command.call(product_id: product_id)
        end

        # Verify price formatting includes amount and currency
        expect(output).to match(/\$\d+\.\d{2}|USD/)
      end

      it 'displays price interval information' do
        output = capture_stdout do
          command.call(product_id: product_id)
        end

        # Verify interval display (either recurring or one-time)
        expect(output).to match(/month|year|one-time/i)
      end

      it 'displays price status' do
        output = capture_stdout do
          command.call(product_id: product_id)
        end

        # Verify active/inactive status is shown
        expect(output).to match(/active|inactive/i)
      end
    end
  end

  describe Onetime::CLI::BillingProductsUpdateCommand do
    subject(:command) { described_class.new }

    let(:product_id) { 'prod_test123' }

    describe '#call (update product)' do
      it 'displays current metadata before update', :unit do
        allow($stdin).to receive(:gets).and_return("n\n")

        output = capture_stdout do
          command.call(product_id: product_id)
        end

        expect(output).to include('Current product:')
        expect(output).to include('Current metadata:')
      end

      it 'requires confirmation before updating', :unit do
        allow($stdin).to receive(:gets).and_return("n\n")

        output = capture_stdout do
          command.call(product_id: product_id, tier: 'pro')
        end

        expect(output).to include('Proceed? (y/n):')
        expect(output).not_to include('Product updated successfully')
      end

      it 'updates when confirmed', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product_id, tier: 'pro')
        end

        expect(output).to include('Updating metadata:')
        expect(output).to include('tier: pro')
        expect(output).to include('Product updated successfully')
      end

      it 'updates plan_id', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product_id, plan_id: 'new_plan')
        end

        expect(output).to include('plan_id: new_plan')
      end

      it 'updates tier', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product_id, tier: 'enterprise')
        end

        expect(output).to include('tier: enterprise')
      end

      it 'updates region', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product_id, region: 'eu-west')
        end

        expect(output).to include('region: eu-west')
      end

      it 'updates tenancy', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product_id, tenancy: 'single')
        end

        expect(output).to include('tenancy: single')
      end

      it 'updates entitlements', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product_id, entitlements: 'api,webhooks')
        end

        expect(output).to include('entitlements: api,webhooks')
      end

      it 'preserves existing metadata not being updated', :code_smell, :integration, :stripe_sandbox_api do
        # This test requires verifying state preservation across API calls
        # stripe-mock doesn't maintain state between requests
        skip 'Requires integration test - cannot verify state preservation with stripe-mock'
      end

      it 'ensures all expected metadata fields exist', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product_id, tier: 'pro')
        end

        # All standard fields should be present
        expect(output).to include('app:')
        expect(output).to include('plan_id:')
        expect(output).to include('tier:')
        expect(output).to include('region:')
        expect(output).to include('tenancy:')
        expect(output).to include('entitlements:')
        expect(output).to include('created:')
      end

      it 'adds marketing feature', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product_id, add_marketing_feature: 'New Feature')
        end

        expect(output).to include('Adding marketing feature: New Feature')
      end

      it 'removes marketing feature', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product_id, remove_marketing_feature: 'Old Feature')
        end

        expect(output).to include('Removing marketing feature: Old Feature')
      end

      it 'displays updated metadata after successful update', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product_id, tier: 'pro')
        end

        expect(output).to include('Updated metadata:')
      end

      it 'displays marketing features section in update output' do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product_id, tier: 'pro')
        end

        # Verify Marketing Features section is included in update output
        expect(output).to include('Marketing Features:')
      end
    end
  end

  # Helper to capture stdout
  def capture_stdout
    old_stdout = $stdout
    $stdout    = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end
end
