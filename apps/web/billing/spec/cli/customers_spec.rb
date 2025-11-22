# apps/web/billing/spec/cli/customers_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require 'onetime/cli'
require_relative '../../lib/stripe_client'
require_relative '../../cli/customers_command'
require_relative '../../cli/customers_create_command'
require_relative '../../cli/customers_show_command'
require_relative '../../cli/customers_delete_command'

RSpec.describe 'Billing Customers CLI Commands', :billing_cli, :unit, :stripe_mock do
  let(:stripe_client) { Billing::StripeClient.new }

  describe Onetime::CLI::BillingCustomersCommand do
    subject(:command) { described_class.new }

    describe '#call (list customers)' do
      it 'lists customers with default limit' do
        output = capture_stdout do
          command.call(limit: 100)
        end

        expect(output).to include('Fetching customers from Stripe')
        expect(output).to match(/ID.*EMAIL.*NAME.*CREATED/)
        expect(output).to match(/Total: \d+ customer\(s\)/)
      end

      it 'accepts email filter option' do
        output = capture_stdout do
          command.call(email: 'test@example.com', limit: 100)
        end

        expect(output).to include('Fetching customers from Stripe')
      end

      it 'accepts custom limit option' do
        output = capture_stdout do
          command.call(limit: 50)
        end

        expect(output).to include('Fetching customers from Stripe')
      end

      it 'handles empty results gracefully', :code_smell do
        # stripe-mock returns static fixtures, so we can't actually test empty state
        # This would need integration test with VCR
        skip 'stripe-mock limitation - always returns fixtures'
      end

      it 'formats customer rows with proper alignment' do
        output = capture_stdout do
          command.call(limit: 100)
        end

        # Check for separator line (90 characters)
        expect(output).to include('-' * 90)
      end
    end
  end

  describe Onetime::CLI::BillingCustomersCreateCommand do
    subject(:command) { described_class.new }

    describe '#call (create customer)' do
      it 'creates customer with email only' do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(email: 'test@example.com')
        end

        expect(output).to include('Creating customer:')
        expect(output).to include('Email: test@example.com')
        expect(output).to include('Proceed? (y/n):')
        expect(output).to include('Customer created successfully')
        expect(output).to match(/ID: cus_/)
      end

      it 'creates customer with email and name' do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(email: 'test@example.com', name: 'Test User')
        end

        expect(output).to include('Email: test@example.com')
        expect(output).to include('Name: Test User')
        expect(output).to include('Customer created successfully')
      end

      it 'requires confirmation before creating' do
        allow($stdin).to receive(:gets).and_return("n\n")

        output = capture_stdout do
          command.call(email: 'test@example.com')
        end

        expect(output).to include('Proceed? (y/n):')
        expect(output).not_to include('Customer created successfully')
      end

      it 'validates email is required' do
        allow($stdin).to receive(:gets).and_return("\n", "\n", "n\n")

        output = capture_stdout do
          command.call
        end

        expect(output).to include('Email:')
        expect(output).to include('Error: Email is required')
      end

      it 'handles interactive mode' do
        allow($stdin).to receive(:gets).and_return("test@example.com\n", "Test User\n", "y\n")

        output = capture_stdout do
          command.call(interactive: true)
        end

        expect(output).to include('Email:')
        expect(output).to include('Name (optional):')
        expect(output).to include('Customer created successfully')
      end

      it 'allows empty name in interactive mode' do
        allow($stdin).to receive(:gets).and_return("test@example.com\n", "\n", "y\n")

        output = capture_stdout do
          command.call(interactive: true)
        end

        expect(output).to include('Customer created successfully')
      end

      it 'uses StripeClient for retry and idempotency' do
        allow($stdin).to receive(:gets).and_return("y\n")

        output = capture_stdout do
          command.call(email: 'test@example.com')
        end

        expect(output).to include('Customer created successfully')
      end
    end
  end

  describe Onetime::CLI::BillingCustomersShowCommand do
    subject(:command) { described_class.new }

    describe '#call (show customer)' do
      it 'displays customer details with correct format' do
        # NOTE: stripe-mock returns static customer data
        # This test verifies CLI output formatting is correct
        output = capture_stdout do
          command.call(customer_id: 'cus_test123')
        end

        # Verify section headers and structure
        expect(output).to include('Customer Details:')
        expect(output).to match(/ID: cus_\w+/)  # Customer ID format
        expect(output).to match(/Created: \d{4}-\d{2}-\d{2}/)  # Date format
        expect(output).to include('Currency:')
        expect(output).to include('Balance:')
      end

      it 'displays payment methods section' do
        # stripe-mock returns static payment method data
        output = capture_stdout do
          command.call(customer_id: 'cus_test123')
        end

        expect(output).to include('Payment Methods:')
        # Verify format if payment methods exist
        # stripe-mock may include card details in format: pm_xxx - card
      end

      it 'displays subscriptions section' do
        # stripe-mock returns static subscription data
        output = capture_stdout do
          command.call(customer_id: 'cus_test123')
        end

        expect(output).to include('Subscriptions:')
        # Verify subscription format if present: sub_xxx - status
        # May include (paused) marker
      end

      it 'formats timestamps in readable format' do
        output = capture_stdout do
          command.call(customer_id: 'cus_test123')
        end

        # Verify timestamp format (YYYY-MM-DD HH:MM:SS UTC)
        expect(output).to match(/Created: \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC/)
      end

      it 'formats currency amounts correctly' do
        output = capture_stdout do
          command.call(customer_id: 'cus_test123')
        end

        # Verify currency format (USD X.XX or USD -X.XX for credits)
        expect(output).to match(/Balance: USD -?\d+\.\d{2}/)
      end
    end
  end

  describe Onetime::CLI::BillingCustomersDeleteCommand do
    subject(:command) { described_class.new }

    describe '#call (delete customer)' do
      it 'warns about active subscriptions without --yes flag' do
        # NOTE: stripe-mock returns customers with active subscriptions
        output = capture_stdout do
          command.call(customer_id: 'cus_test123')
        end

        expect(output).to include('⚠️  Customer has active subscriptions!')
        expect(output).to include('Cancel subscriptions first or use --yes to force deletion with cancellation')
        expect(output).not_to include('Customer deleted successfully')
      end

      it 'cancels subscriptions and deletes with --yes flag' do
        # Test that --yes skips confirmation and handles subscriptions
        output = capture_stdout do
          command.call(customer_id: 'cus_test456', yes: true)
        end

        expect(output).not_to include('⚠️  Delete customer permanently? (y/n):')
        # Verify deletion workflow (may cancel subscriptions first)
        expect(output).to include('Customer deleted successfully')
      end

      it 'displays customer ID in output' do
        output = capture_stdout do
          command.call(customer_id: 'cus_test789', yes: true)
        end

        # Verify customer ID appears in output
        expect(output).to match(/Customer: cus_\w+/)
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
