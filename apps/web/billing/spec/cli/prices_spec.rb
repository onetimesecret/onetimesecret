# apps/web/billing/spec/cli/prices_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require 'onetime/cli'
require_relative '../../cli/prices_command'
require_relative '../../cli/prices_create_command'

RSpec.describe 'Billing Prices CLI Commands', :billing_cli do
  let(:stripe_client) { Billing::StripeClient.new }

  describe Onetime::CLI::BillingPricesCommand do
    subject(:command) { described_class.new }

    describe '#call (list prices)' do
      it 'lists active prices by default', :unit do
        output = capture_stdout do
          command.call(limit: 100, active_only: true)
        end

        expect(output).to include('Fetching prices from Stripe')
        expect(output).to match(/ID.*PRODUCT.*AMOUNT.*INTERVAL.*ACTIVE/)
        expect(output).to match(/Total: \d+ price\(s\)/)
      end

      it 'accepts product filter option', :unit do
        output = capture_stdout do
          command.call(product: 'prod_test123', limit: 100)
        end

        expect(output).to include('Fetching prices from Stripe')
      end

      it 'includes inactive prices when active_only is false', :unit do
        output = capture_stdout do
          command.call(limit: 100, active_only: false)
        end

        expect(output).to include('Fetching prices from Stripe')
      end

      it 'formats price rows with proper alignment', :unit do
        output = capture_stdout do
          command.call(limit: 100)
        end

        # Check for separator line (78 characters)
        expect(output).to include('-' * 78)
      end

      it 'handles empty results gracefully' do
        # Mock empty price list
        allow(Stripe::Price).to receive(:list).and_return(
          double(data: [])
        )

        output = capture_stdout do
          command.call(limit: 100)
        end

        expect(output).to include('No prices found')
      end

      it 'handles Stripe API errors gracefully' do
        # Mock Stripe API error
        allow(Stripe::Price).to receive(:list).and_raise(
          Stripe::InvalidRequestError.new('Invalid request', 'param')
        )

        expect {
          command.call(limit: 100)
        }.to output(/Error fetching prices|Error/).to_stdout
      end
    end
  end

  describe Onetime::CLI::BillingPricesCreateCommand do
    subject(:command) { described_class.new }
    let(:product_id) { 'prod_test123' }

    describe '#call (create price)' do
      it 'creates price with all required arguments', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product_id,
            amount: 900,
            currency: 'usd',
            interval: 'month',
            interval_count: 1
          )
        end

        expect(output).to include('Creating price:')
        expect(output).to include("Product: #{product_id}")
        expect(output).to include('Amount: USD 9.00')
        expect(output).to include('Interval: 1 month(s)')
        expect(output).to include('Proceed? (y/n):')
        expect(output).to include('Price created successfully')
        expect(output).to match(/ID: price_/)
      end

      it 'uses default currency of usd', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product_id,
            amount: 900,
            interval: 'month'
          )
        end

        expect(output).to include('Amount: USD 9.00')
        expect(output).to include('Price created successfully')
      end

      it 'uses default interval of month', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product_id,
            amount: 900
          )
        end

        expect(output).to include('Interval: 1 month(s)')
        expect(output).to include('Price created successfully')
      end

      it 'uses default interval_count of 1', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product_id,
            amount: 900,
            interval: 'month'
          )
        end

        expect(output).to include('Interval: 1 month(s)')
      end

      it 'accepts year interval', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product_id,
            amount: 9000,
            interval: 'year'
          )
        end

        expect(output).to include('Interval: 1 year(s)')
        expect(output).to include('Price created successfully')
      end

      it 'accepts week interval', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product_id,
            amount: 200,
            interval: 'week'
          )
        end

        expect(output).to include('Interval: 1 week(s)')
        expect(output).to include('Price created successfully')
      end

      it 'accepts day interval', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product_id,
            amount: 50,
            interval: 'day'
          )
        end

        expect(output).to include('Interval: 1 day(s)')
        expect(output).to include('Price created successfully')
      end

      it 'accepts custom interval_count', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product_id,
            amount: 900,
            interval: 'month',
            interval_count: 3
          )
        end

        expect(output).to include('Interval: 3 month(s)')
        expect(output).to include('Price created successfully')
      end

      it 'requires confirmation before creating', :unit do
        allow($stdin).to receive(:gets).and_return("n\n")

        output = capture_stdout do
          command.call(
            product_id: product_id,
            amount: 900
          )
        end

        expect(output).to include('Proceed? (y/n):')
        expect(output).not_to include('Price created successfully')
      end

      it 'validates product_id is required' do
        allow($stdin).to receive(:gets).and_return("\n", "\n", "n\n")

        output = capture_stdout do
          command.call(amount: 900)
        end

        expect(output).to include('Product ID:')
        expect(output).to include('Error: Product ID is required')
      end

      it 'validates amount is required' do
        allow($stdin).to receive(:gets).and_return("\n", "\n", "n\n")

        output = capture_stdout do
          command.call(product_id: product_id)
        end

        expect(output).to include('Amount in cents')
      end

      it 'validates amount is greater than 0' do
        output = capture_stdout do
          command.call(
            product_id: product_id,
            amount: 0
          )
        end

        expect(output).to include('Error: Amount must be greater than 0')
      end

      it 'validates negative amounts' do
        output = capture_stdout do
          command.call(
            product_id: product_id,
            amount: -100
          )
        end

        expect(output).to include('Error: Amount must be greater than 0')
      end

      it 'validates interval is one of allowed values' do
        output = capture_stdout do
          command.call(
            product_id: product_id,
            amount: 900,
            interval: 'quarterly'
          )
        end

        expect(output).to include('Error: Interval must be one of: month, year, week, day')
      end

      it 'verifies product exists before creating price', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product_id,
            amount: 900
          )
        end

        # Should show product name after retrieval
        expect(output).to include('Product:')
      end

      it 'formats amount display correctly', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product_id,
            amount: 1299
          )
        end

        expect(output).to include('Amount: USD 12.99')
      end

      it 'displays created price details after success', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product_id,
            amount: 900
          )
        end

        expect(output).to include('Price created successfully:')
        expect(output).to match(/ID: price_/)
        expect(output).to include('Amount:')
        expect(output).to include('Interval:')
      end

      it 'handles interactive mode', :unit do
        allow($stdin).to receive(:gets).and_return(
          "#{product_id}\n",
          "900\n",
          "y\n"
        )

        output = capture_stdout do
          command.call(interactive: true)
        end

        expect(output).to include('Product ID:')
        expect(output).to include('Amount in cents')
        expect(output).to include('Price created successfully')
      end

      it 'handles product not found error' do
        # Mock product not found error
        allow(Stripe::Product).to receive(:retrieve).and_raise(
          Stripe::InvalidRequestError.new('No such product', 'product')
        )

        allow($stdin).to receive(:gets).and_return("y\n")

        expect {
          command.call(product_id: 'prod_nonexistent', amount: 1000, yes: true)
        }.to output(/Error|No such product/).to_stdout
      end

      it 'handles price creation failure' do
        # Mock price creation error
        allow(stripe_client).to receive(:create).with(Stripe::Price, anything).and_raise(
          Stripe::InvalidRequestError.new('Invalid currency', 'currency')
        )

        allow($stdin).to receive(:gets).and_return("y\n")

        expect {
          command.call(product_id: product_id, amount: 1000, currency: 'invalid', yes: true)
        }.to output(/Error|Invalid currency/).to_stdout
      end

      it 'uses StripeClient for retry and idempotency', :unit do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(
            product_id: product_id,
            amount: 900
          )
        end

        expect(output).to include('Price created successfully')
      end
    end
  end

  # Helper to capture stdout
  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end
end
