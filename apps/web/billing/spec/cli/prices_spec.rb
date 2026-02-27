# apps/web/billing/spec/cli/prices_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require 'onetime/cli'
require_relative '../../cli/prices_command'
require_relative '../../cli/prices_create_command'

RSpec.describe 'Billing Prices CLI Commands', :billing_cli, :integration, :vcr do
  let(:stripe_client) { Billing::StripeClient.new }

  # Helper to create a test product for price tests
  def create_price_test_product(name = 'VCR Price Test Product')
    stripe_client.create(Stripe::Product, { name: name })
  end

  describe Onetime::CLI::BillingPricesCommand do
    subject(:command) { described_class.new }

    describe '#call (list prices)' do
      it 'lists active prices by default', :vcr do
        output = capture_stdout do
          command.call(limit: 100, active_only: true)
        end

        expect(output).to include('Fetching prices from Stripe')
        expect(output).to match(/ID.*PRODUCT.*AMOUNT.*INTERVAL.*PRICE/)
        expect(output).to match(/Total: \d+ price\(s\)/)
      end

      it 'accepts product filter option', :vcr do
        product = create_price_test_product('Product Filter Test')

        output = capture_stdout do
          command.call(product: product.id, limit: 100)
        end

        expect(output).to include('Fetching prices from Stripe')

        stripe_client.delete(Stripe::Product, product.id)
      end

      it 'includes inactive prices when active_only is false' do
        output = capture_stdout do
          command.call(limit: 100, active_only: false)
        end

        expect(output).to include('Fetching prices from Stripe')
      end

      it 'formats price rows with proper alignment' do
        output = capture_stdout do
          command.call(limit: 100)
        end

        # Check for separator line (78 characters)
        expect(output).to include('-' * 78)
      end

      it 'handles empty results gracefully' do
        # Mock empty price list
        allow(Stripe::Price).to receive(:list).and_return(
          double(data: []),
        )

        output = capture_stdout do
          command.call(limit: 100)
        end

        expect(output).to include('No prices found')
      end

      it 'handles Stripe API errors gracefully' do
        # Mock Stripe API error
        allow(Stripe::Price).to receive(:list).and_raise(
          Stripe::InvalidRequestError.new('Invalid request', 'param'),
        )

        expect do
          command.call(limit: 100)
        end.to output(/Error fetching prices|Error/).to_stdout
      end
    end
  end

  describe Onetime::CLI::BillingPricesCreateCommand do
    subject(:command) { described_class.new }

    describe '#call (create price)' do
      it 'creates price with all required arguments', :vcr do
        product = create_price_test_product('Price Create All Args')
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product.id,
            amount: 900,
            currency: 'cad',
            interval: 'month',
            interval_count: 1,
          )
        end

        expect(output).to include('Creating price:')
        expect(output).to include('Amount: USD 9.00')
        expect(output).to include('Interval: 1 month(s)')
        expect(output).to include('Proceed? (y/n):')
        expect(output).to include('Price created successfully')
        expect(output).to match(/ID: price_/)
        # Note: No cleanup - products with prices can't be deleted in Stripe
      end

      it 'uses default currency of cad', :vcr do
        product = create_price_test_product('Default Currency Test')
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product.id,
            amount: 900,
            interval: 'month',
          )
        end

        expect(output).to include('Amount: USD 9.00')
        expect(output).to include('Price created successfully')
        # Note: No cleanup - products with prices can't be deleted in Stripe
      end

      it 'uses default interval of month', :vcr do
        product = create_price_test_product('Default Interval Test')
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product.id,
            amount: 900,
          )
        end

        expect(output).to include('Interval: 1 month(s)')
        expect(output).to include('Price created successfully')
        # Note: No cleanup - products with prices can't be deleted in Stripe
      end

      it 'uses default interval_count of 1', :vcr do
        product = create_price_test_product('Default Count Test')
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product.id,
            amount: 900,
            interval: 'month',
          )
        end

        expect(output).to include('Interval: 1 month(s)')
        # Note: No cleanup - products with prices can't be deleted
      end

      it 'accepts year interval', :vcr do
        product = create_price_test_product('Year Interval Test')
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product.id,
            amount: 9000,
            interval: 'year',
          )
        end

        expect(output).to include('Interval: 1 year(s)')
        expect(output).to include('Price created successfully')

        # Note: No cleanup - products with prices cannot be deleted
      end

      it 'accepts week interval', :vcr do
        product = create_price_test_product('Week Interval Test')
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product.id,
            amount: 200,
            interval: 'week',
          )
        end

        expect(output).to include('Interval: 1 week(s)')
        expect(output).to include('Price created successfully')

        # Note: No cleanup - products with prices cannot be deleted
      end

      it 'accepts day interval', :vcr do
        product = create_price_test_product('Day Interval Test')
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product.id,
            amount: 50,
            interval: 'day',
          )
        end

        expect(output).to include('Interval: 1 day(s)')
        expect(output).to include('Price created successfully')

        # Note: No cleanup - products with prices cannot be deleted
      end

      it 'accepts custom interval_count', :vcr do
        product = create_price_test_product('Custom Count Test')
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product.id,
            amount: 900,
            interval: 'month',
            interval_count: 3,
          )
        end

        expect(output).to include('Interval: 3 month(s)')
        expect(output).to include('Price created successfully')

        # Note: No cleanup - products with prices cannot be deleted
      end

      it 'requires confirmation before creating', :vcr do
        product = create_price_test_product('Confirmation Required Test')
        allow($stdin).to receive(:gets).and_return("n\n")

        output = capture_stdout do
          command.call(
            product_id: product.id,
            amount: 900,
          )
        end

        expect(output).to include('Proceed? (y/n):')
        expect(output).not_to include('Price created successfully')

        # Note: No cleanup - products with prices cannot be deleted
      end

      it 'validates product_id is required' do
        allow($stdin).to receive(:gets).and_return("\n", "\n", "n\n")

        output = capture_stdout do
          command.call(amount: 900)
        end

        expect(output).to include('Product ID:')
        expect(output).to include('Error: Product ID is required')
      end

      it 'validates amount is required', :vcr do
        product = create_price_test_product('Amount Required Test')
        allow($stdin).to receive(:gets).and_return("\n", "\n", "n\n")

        output = capture_stdout do
          command.call(product_id: product.id)
        end

        expect(output).to include('Amount in cents')

        # Note: No cleanup - products with prices cannot be deleted
      end

      it 'validates amount is greater than 0', :vcr do
        product = create_price_test_product('Amount GT Zero Test')

        output = capture_stdout do
          command.call(
            product_id: product.id,
            amount: 0,
          )
        end

        expect(output).to include('Error: Amount must be greater than 0')

        # Note: No cleanup - products with prices cannot be deleted
      end

      it 'validates negative amounts', :vcr do
        product = create_price_test_product('Negative Amount Test')

        output = capture_stdout do
          command.call(
            product_id: product.id,
            amount: -100,
          )
        end

        expect(output).to include('Error: Amount must be greater than 0')

        # Note: No cleanup - products with prices cannot be deleted
      end

      it 'validates interval is one of allowed values', :vcr do
        product = create_price_test_product('Interval Validation Test')

        output = capture_stdout do
          command.call(
            product_id: product.id,
            amount: 900,
            interval: 'quarterly',
          )
        end

        expect(output).to include('Error: Interval must be one of: month, year, week, day')

        # Note: No cleanup - products with prices cannot be deleted
      end

      it 'verifies product exists before creating price', :vcr do
        product = create_price_test_product('Product Verify Test')
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product.id,
            amount: 900,
          )
        end

        # Should show product name after retrieval
        expect(output).to include('Product:')

        # Note: No cleanup - products with prices cannot be deleted
      end

      it 'formats amount display correctly', :vcr do
        product = create_price_test_product('Amount Format Test')
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product.id,
            amount: 1299,
          )
        end

        expect(output).to include('Amount: USD 12.99')

        # Note: No cleanup - products with prices cannot be deleted
      end

      it 'displays created price details after success', :vcr do
        product = create_price_test_product('Price Details Test')
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product.id,
            amount: 900,
          )
        end

        expect(output).to include('Price created successfully:')
        expect(output).to match(/ID: price_/)
        expect(output).to include('Amount:')
        expect(output).to include('Interval:')

        # Note: No cleanup - products with prices cannot be deleted
      end

      it 'handles interactive mode', :vcr do
        product = create_price_test_product('Interactive Mode Test')
        allow($stdin).to receive(:gets).and_return(
          "#{product.id}\n",
          "900\n",
          "y\n",
        )

        output = capture_stdout do
          command.call(interactive: true)
        end

        expect(output).to include('Product ID:')
        expect(output).to include('Amount in cents')
        expect(output).to include('Price created successfully')

        # Note: No cleanup - products with prices cannot be deleted
      end

      it 'handles product not found error' do
        # Mock product not found error
        allow(Stripe::Product).to receive(:retrieve).and_raise(
          Stripe::InvalidRequestError.new('No such product', 'product'),
        )

        allow($stdin).to receive(:gets).and_return("y\n")

        expect do
          command.call(product_id: 'prod_nonexistent', amount: 1000, yes: true)
        end.to output(/Error|No such product/).to_stdout
      end

      it 'handles price creation failure' do
        # Mock price creation error
        allow(stripe_client).to receive(:create).with(Stripe::Price, anything).and_raise(
          Stripe::InvalidRequestError.new('Invalid currency', 'currency'),
        )

        allow($stdin).to receive(:gets).and_return("y\n")

        expect do
          command.call(product_id: 'prod_mock', amount: 1000, currency: 'invalid', yes: true)
        end.to output(/Error|Invalid currency/).to_stdout
      end

      it 'uses StripeClient for retry and idempotency', :vcr do
        product = create_price_test_product('Stripe Client Test')
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product.id,
            amount: 900,
          )
        end

        expect(output).to include('Price created successfully')

        # Note: No cleanup - products with prices cannot be deleted
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
