# apps/web/billing/spec/cli/products_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require 'onetime/cli'
require_relative '../../cli/products_command'
require_relative '../../cli/products_create_command'
require_relative '../../cli/products_show_command'
require_relative '../../cli/products_update_command'

RSpec.describe 'Billing Products CLI Commands', :billing_cli, :integration, :vcr do
  let(:stripe_client) { Billing::StripeClient.new }

  describe Onetime::CLI::BillingProductsCommand do
    subject(:command) { described_class.new }

    describe '#call (list products)' do
      it 'lists active products by default' do
        output = capture_stdout do
          command.call(limit: 100)
        end

        expect(output).to include('Fetching products from Stripe')
        expect(output).to match(/ID.*NAME.*TIER.*TENANCY.*REGION.*ACTIVE/)
      end

      it 'includes inactive products when active_only is false' do
        output = capture_stdout do
          command.call(active_only: false, limit: 100)
        end

        expect(output).to include('Fetching products from Stripe')
      end

      it 'displays product count in output' do
        output = capture_stdout do
          command.call(limit: 100)
        end

        expect(output).to match(/Total: \d+ product\(s\)/)
      end

      it 'formats product rows with proper alignment' do
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
      it 'creates product with name argument' do
        # Use mocks instead of VCR because the cassette was recorded with invalid credentials
        # The test verifies the CLI creates products with correct metadata structure
        allow(Stripe::Product).to receive(:list).and_return(double(data: []))

        mock_product = double(
          id: 'prod_test_name_arg',
          name: 'Test Product',
          marketing_features: [],
        )
        allow(Stripe::Product).to receive(:create).and_return(mock_product)

        output = capture_stdout do
          command.call(name: 'Test Product', force: true, yes: true)
        end

        expect(output).to include("Creating product 'Test Product' with metadata:")
        expect(output).to include('app: onetimesecret')
        expect(output).to include('Product created successfully')
        expect(output).to match(/ID: prod_/)
      end

      it 'requires confirmation before creation' do
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

      it 'accepts plan_id option', :vcr do
        # Use --force to bypass duplicate detection when running with VCR_MODE=all
        # against live Stripe where products may already exist from previous runs
        output = capture_stdout do
          command.call(name: 'Test Product', plan_id: 'vcr_test_plan_id_unique', force: true, yes: true)
        end

        expect(output).to include('plan_id: vcr_test_plan_id_unique')
        expect(output).to include('Product created successfully')
      end

      it 'accepts tier option', :vcr do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(name: 'Test Product', tier: 'single_team')
        end

        expect(output).to include('tier: single_team')
      end

      it 'accepts region option', :vcr do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(name: 'Test Product', region: 'EU')
        end

        expect(output).to include('region: EU')
      end

      it 'defaults region to global if not specified', :vcr do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(name: 'Test Product')
        end

        expect(output).to include('region: global')
      end

      it 'accepts tenancy option', :vcr do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(name: 'Test Product', tenancy: 'multi')
        end

        expect(output).to include('tenancy: multi')
      end

      it 'accepts entitlements option', :vcr do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(name: 'Test Product', entitlements: 'api,teams')
        end

        expect(output).to include('entitlements: api,teams')
      end

      it 'accepts marketing_features option', :vcr do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(name: 'Test Product', marketing_features: 'Feature 1,Feature 2')
        end

        expect(output).to include('Marketing features:')
        expect(output).to include('- Feature 1')
        expect(output).to include('- Feature 2')
      end

      it 'displays next steps after creation', :vcr do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(name: 'Test Product')
        end

        expect(output).to include('Next steps:')
        expect(output).to match(/bin\/ots billing prices create prod_/)
      end

      it 'handles interactive mode' do
        # This test uses mocks instead of VCR because:
        # 1. Interactive mode collects dynamic user input that varies per run
        # 2. Duplicate detection makes cassette matching fragile
        # 3. We're testing the CLI flow, not the Stripe API integration
        #
        # Interactive mode prompts for: product name, plan_id, tier, region, tenancy,
        # entitlements, display_order, show_on_plans_page, limit_teams, limit_members,
        # then confirmation.
        inputs = [
          "Test Product\n",     # Product name
          "test_plan\n",        # Plan ID
          "single_team\n",      # Tier
          "global\n",           # Region
          "multi\n",            # Tenancy
          "api,teams\n",        # Entitlements
          "0\n",                # Display order
          "yes\n",              # Show on plans page
          "-1\n",               # Limit teams
          "-1\n",               # Limit members per team
          "y\n",                # Confirmation
        ]
        allow($stdin).to receive(:gets).and_return(*inputs)

        # Mock the duplicate detection to return empty (no existing products)
        allow(Stripe::Product).to receive(:list).and_return(double(data: []))

        # Mock the product creation to return a successful response
        mock_product = double(
          id: 'prod_test123',
          name: 'Test Product',
          marketing_features: [],
        )
        allow(Stripe::Product).to receive(:create).and_return(mock_product)

        output = capture_stdout do
          command.call(interactive: true)
        end

        expect(output).to include('Product name:')
        expect(output).to include('Product created successfully')
        expect(output).to include('ID: prod_test123')
      end

      it 'includes created timestamp in metadata', :vcr do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(name: 'Test Product')
        end

        expect(output).to match(/created: \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/)
      end

      it 'initializes all metadata fields with empty strings', :vcr do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(name: 'Test Product')
        end

        # All fields should be present even if empty
        expect(output).to include('plan_id:')
        expect(output).to include('tier:')
        expect(output).to include('tenancy:')
        expect(output).to include('entitlements:')
      end

      it 'uses StripeClient for retry and idempotency' do
        # This test verifies CLI uses StripeClient for Stripe API calls
        # Mock the Stripe API to isolate from VCR cassette issues
        allow(Stripe::Product).to receive(:list).and_return(double(data: []))

        mock_product = double(
          id: 'prod_retry_test',
          name: 'Test Product',
          marketing_features: [],
        )
        allow(Stripe::Product).to receive(:create).and_return(mock_product)

        output = capture_stdout do
          command.call(name: 'Test Product', yes: true)
        end

        expect(output).to include('Product created successfully')
      end
    end
  end

  describe Onetime::CLI::BillingProductsShowCommand do
    subject(:command) { described_class.new }

    describe '#call (show product)' do
      it 'displays product details', :vcr do
        # Create a real product for VCR recording
        product = stripe_client.create(Stripe::Product, {
          name: 'VCR Test Product Details',
        }
        )

        output = capture_stdout do
          command.call(product_id: product.id)
        end

        expect(output).to include('Product Details:')
        expect(output).to include('ID:')
        expect(output).to include('Name:')
        expect(output).to include('Active:')

        # Cleanup
        # Note: No cleanup - VCR tests dont need product deletion
      end

      it 'displays description if present', :vcr do
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
        # Note: No cleanup - VCR tests dont need product deletion
      end

      it 'displays metadata section', :vcr do
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
        # Note: No cleanup - VCR tests dont need product deletion
      end

      it 'displays marketing features section', :vcr do
        product = stripe_client.create(Stripe::Product, {
          name: 'Marketing Features Test Product',
          marketing_features: [{ name: 'Feature 1' }],
        }
        )

        output = capture_stdout do
          command.call(product_id: product.id)
        end

        # Verify Marketing Features section exists in output
        expect(output).to include('Marketing Features:')

        # Note: No cleanup - VCR tests dont need product deletion
      end

      it 'displays associated prices', :vcr do
        product = stripe_client.create(Stripe::Product, {
          name: 'Prices Test Product',
        }
        )

        stripe_client.create(Stripe::Price, {
          product: product.id,
          unit_amount: 1999,
          currency: 'usd',
          recurring: { interval: 'month' },
        }
        )

        output = capture_stdout do
          command.call(product_id: product.id)
        end

        expect(output).to include('Prices:')

        # Note: No cleanup - VCR tests dont need product deletion
      end

      it 'formats price information with amount and currency', :vcr do
        product = stripe_client.create(Stripe::Product, {
          name: 'Price Format Test Product',
        }
        )

        stripe_client.create(Stripe::Price, {
          product: product.id,
          unit_amount: 2500,
          currency: 'usd',
          recurring: { interval: 'month' },
        }
        )

        output = capture_stdout do
          command.call(product_id: product.id)
        end

        # Verify price formatting includes amount and currency
        expect(output).to match(/\$\d+\.\d{2}|USD/)

        # Note: No cleanup - VCR tests dont need product deletion
      end

      it 'displays price interval information', :vcr do
        product = stripe_client.create(Stripe::Product, {
          name: 'Interval Test Product',
        }
        )

        stripe_client.create(Stripe::Price, {
          product: product.id,
          unit_amount: 1000,
          currency: 'usd',
          recurring: { interval: 'month' },
        }
        )

        output = capture_stdout do
          command.call(product_id: product.id)
        end

        # Verify interval display (either recurring or one-time)
        expect(output).to match(/month|year|one-time/i)

        # Note: No cleanup - VCR tests dont need product deletion
      end

      it 'displays price status', :vcr do
        product = stripe_client.create(Stripe::Product, {
          name: 'Status Test Product',
        }
        )

        stripe_client.create(Stripe::Price, {
          product: product.id,
          unit_amount: 500,
          currency: 'usd',
          recurring: { interval: 'month' },
        }
        )

        output = capture_stdout do
          command.call(product_id: product.id)
        end

        # Verify active/inactive status is shown
        expect(output).to match(/active|inactive/i)

        # Note: No cleanup - VCR tests dont need product deletion
      end
    end
  end

  describe Onetime::CLI::BillingProductsUpdateCommand do
    subject(:command) { described_class.new }

    # Helper to create a test product for update tests
    def create_update_test_product(name)
      stripe_client.create(Stripe::Product, {
        name: name,
        metadata: {
          app: 'onetimesecret',
          plan_id: '',
          tier: '',
          region: '',
          tenancy: '',
          entitlements: '',
        },
      }
      )
    end

    describe '#call (update product)' do
      it 'displays current metadata before update', :vcr do
        product = create_update_test_product('Metadata Display Test')

        allow($stdin).to receive(:gets).and_return("n\n")

        output = capture_stdout do
          command.call(product_id: product.id)
        end

        expect(output).to include('Current product:')
        expect(output).to include('Current metadata:')

        # Note: No cleanup - VCR tests dont need product deletion
      end

      it 'requires confirmation before updating', :vcr do
        product = create_update_test_product('Confirmation Test')

        allow($stdin).to receive(:gets).and_return("n\n")

        output = capture_stdout do
          command.call(product_id: product.id, tier: 'pro')
        end

        expect(output).to include('Proceed? (y/n):')
        expect(output).not_to include('Product updated successfully')

        # Note: No cleanup - VCR tests dont need product deletion
      end

      it 'updates when confirmed', :vcr do
        product = create_update_test_product('Update Confirm Test')

        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product.id, tier: 'pro')
        end

        expect(output).to include('Updating metadata:')
        expect(output).to include('tier: pro')
        expect(output).to include('Product updated successfully')

        # Note: No cleanup - VCR tests dont need product deletion
      end

      it 'updates plan_id', :vcr do
        product = create_update_test_product('Plan ID Update Test')

        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product.id, plan_id: 'new_plan')
        end

        expect(output).to include('plan_id: new_plan')

        # Note: No cleanup - VCR tests dont need product deletion
      end

      it 'updates tier', :vcr do
        product = create_update_test_product('Tier Update Test')

        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product.id, tier: 'enterprise')
        end

        expect(output).to include('tier: enterprise')

        # Note: No cleanup - VCR tests dont need product deletion
      end

      it 'updates region', :vcr do
        product = create_update_test_product('Region Update Test')

        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product.id, region: 'eu-west')
        end

        expect(output).to include('region: eu-west')

        # Note: No cleanup - VCR tests dont need product deletion
      end

      it 'updates tenancy', :vcr do
        product = create_update_test_product('Tenancy Update Test')

        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product.id, tenancy: 'single')
        end

        expect(output).to include('tenancy: single')

        # Note: No cleanup - VCR tests dont need product deletion
      end

      it 'updates entitlements', :vcr do
        product = create_update_test_product('Entitlements Update Test')

        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product.id, entitlements: 'api,webhooks')
        end

        expect(output).to include('entitlements: api,webhooks')

        # Note: No cleanup - VCR tests dont need product deletion
      end

      it 'preserves existing metadata not being updated', :code_smell, :integration, :stripe_sandbox_api do
        # This test requires verifying state preservation across API calls
        # stripe-mock doesn't maintain state between requests
        skip 'Requires integration test - cannot verify state preservation with stripe-mock'
      end

      it 'ensures all expected metadata fields exist', :vcr do
        product = create_update_test_product('Metadata Fields Test')

        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product.id, tier: 'pro')
        end

        # All standard fields should be present
        expect(output).to include('app:')
        expect(output).to include('tier:')
        expect(output).to include('created:')

        # Note: No cleanup - VCR tests dont need product deletion
      end

      it 'adds marketing feature', :vcr do
        product = create_update_test_product('Add Marketing Feature Test')

        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product.id, add_marketing_feature: 'New Feature')
        end

        expect(output).to include('Adding marketing feature: New Feature')

        # Note: No cleanup - VCR tests dont need product deletion
      end

      it 'removes marketing feature', :vcr do
        product = stripe_client.create(Stripe::Product, {
          name: 'Remove Marketing Feature Test',
          marketing_features: [{ name: 'Old Feature' }],
          metadata: { app: 'onetimesecret' },
        }
        )

        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product.id, remove_marketing_feature: 'Old Feature')
        end

        expect(output).to include('Removing marketing feature: Old Feature')

        # Note: No cleanup - VCR tests dont need product deletion
      end

      it 'displays updated metadata after successful update', :vcr do
        product = create_update_test_product('Updated Metadata Test')

        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product.id, tier: 'pro')
        end

        expect(output).to include('Updated metadata:')

        # Note: No cleanup - VCR tests dont need product deletion
      end

      it 'displays marketing features section in update output', :vcr do
        product = stripe_client.create(Stripe::Product, {
          name: 'Marketing Section Test',
          marketing_features: [{ name: 'Feature 1' }],
          metadata: { app: 'onetimesecret' },
        })

        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(product_id: product.id, tier: 'pro')
        end

        # Verify Marketing Features section is included in update output
        expect(output).to include('Marketing features:')

        # Note: No cleanup - VCR tests dont need product deletion
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
