# frozen_string_literal: true

require 'spec_helper'
require 'cli/cli_spec_helper'
require_relative '../support/billing_spec_helper'
require_relative '../support/stripe_test_data'

RSpec.describe 'Billing Customers CLI Commands', type: :cli do
  let(:billing_config) { double('BillingConfig', enabled?: true, stripe_key: 'sk_test_123') }

  before do
    allow(OT).to receive(:billing_config).and_return(billing_config)
    allow(Stripe).to receive(:api_key=)
  end

  describe 'billing customers (list)' do
    let(:customer1) { mock_stripe_customer(id: 'cus_test1', email: 'user1@example.com', name: 'User One') }
    let(:customer2) { mock_stripe_customer(id: 'cus_test2', email: 'user2@example.com', name: 'User Two') }
    let(:customers_list) { double('ListObject', data: [customer1, customer2]) }

    context 'with valid configuration' do
      it 'lists all customers' do
        allow(Stripe::Customer).to receive(:list).and_return(customers_list)

        output = run_cli_command_quietly('billing', 'customers')

        expect(output[:stdout]).to include('cus_test1')
        expect(output[:stdout]).to include('user1@example.com')
        expect(output[:stdout]).to include('User One')
        expect(output[:stdout]).to include('Total: 2 customer(s)')
        expect(last_exit_code).to eq(0)
      end

      it 'displays formatted table header' do
        allow(Stripe::Customer).to receive(:list).and_return(customers_list)

        output = run_cli_command_quietly('billing', 'customers')

        expect(output[:stdout]).to match(/ID.*EMAIL.*NAME.*CREATED/)
      end
    end

    context 'with email filter' do
      it 'filters customers by email' do
        filtered_list = double('ListObject', data: [customer1])
        expect(Stripe::Customer).to receive(:list).with(hash_including(email: 'user1@example.com')).and_return(filtered_list)

        output = run_cli_command_quietly('billing', 'customers', '--email', 'user1@example.com')

        expect(output[:stdout]).to include('user1@example.com')
        expect(last_exit_code).to eq(0)
      end
    end

    context 'with limit option' do
      it 'respects the limit parameter' do
        expect(Stripe::Customer).to receive(:list).with(hash_including(limit: 50)).and_return(customers_list)

        run_cli_command_quietly('billing', 'customers', '--limit', '50')

        expect(last_exit_code).to eq(0)
      end
    end

    context 'when no customers found' do
      it 'displays appropriate message' do
        empty_list = double('ListObject', data: [])
        allow(Stripe::Customer).to receive(:list).and_return(empty_list)

        output = run_cli_command_quietly('billing', 'customers')

        expect(output[:stdout]).to include('No customers found')
        expect(last_exit_code).to eq(0)
      end
    end

    context 'when Stripe API fails' do
      it 'displays error message' do
        allow(Stripe::Customer).to receive(:list).and_raise(Stripe::APIConnectionError.new('Network error'))

        output = run_cli_command_quietly('billing', 'customers')

        expect(output[:stdout]).to match(/error.*fetching customers/i)
      end
    end

    context 'when billing not configured' do
      let(:billing_config) { double('BillingConfig', enabled?: false) }

      it 'exits with configuration error' do
        output = run_cli_command_quietly('billing', 'customers')

        expect(output[:stdout]).to match(/billing not enabled/i)
      end
    end
  end

  describe 'billing customers create' do
    let(:customer) { mock_stripe_customer(email: 'new@example.com', name: 'New Customer') }
    let(:stripe_client) { instance_double('Billing::StripeClient') }

    before do
      allow(Billing::StripeClient).to receive(:new).and_return(stripe_client)
      # Mock stdin for confirmation prompt
      allow($stdin).to receive(:gets).and_return("y\n")
    end

    context 'with valid email parameter' do
      it 'creates a customer' do
        expect(stripe_client).to receive(:create).with(
          Stripe::Customer,
          hash_including(email: 'new@example.com')
        ).and_return(customer)

        output = run_cli_command_quietly('billing', 'customers', 'create', '--email', 'new@example.com')

        expect(output[:stdout]).to include('Customer created successfully')
        expect(output[:stdout]).to include('new@example.com')
        expect(last_exit_code).to eq(0)
      end

      it 'displays customer details after creation' do
        expect(stripe_client).to receive(:create).and_return(customer)

        output = run_cli_command_quietly('billing', 'customers', 'create', '--email', 'new@example.com')

        expect(output[:stdout]).to include('ID:')
        expect(output[:stdout]).to include('Email:')
      end
    end

    context 'with email and name parameters' do
      it 'creates customer with name' do
        expect(stripe_client).to receive(:create).with(
          Stripe::Customer,
          hash_including(email: 'new@example.com', name: 'Test User')
        ).and_return(customer)

        run_cli_command_quietly('billing', 'customers', 'create', '--email', 'new@example.com', '--name', 'Test User')

        expect(last_exit_code).to eq(0)
      end
    end

    context 'without email parameter (interactive mode)' do
      before do
        # Mock interactive input
        allow($stdin).to receive(:gets).and_return("interactive@example.com\n", "Interactive Name\n", "y\n")
      end

      it 'prompts for email and name' do
        expect(stripe_client).to receive(:create).and_return(customer)

        output = run_cli_command_quietly('billing', 'customers', 'create')

        expect(output[:stdout]).to include('Email:')
        expect(output[:stdout]).to include('Name (optional):')
      end
    end

    context 'with empty email' do
      before do
        allow($stdin).to receive(:gets).and_return("\n", "\n", "n\n")
      end

      it 'displays validation error' do
        output = run_cli_command_quietly('billing', 'customers', 'create', '--email', '')

        expect(output[:stdout]).to match(/error.*email.*required/i)
      end
    end

    context 'when user declines confirmation' do
      before do
        allow($stdin).to receive(:gets).and_return("n\n")
      end

      it 'does not create customer' do
        expect(stripe_client).not_to receive(:create)

        run_cli_command_quietly('billing', 'customers', 'create', '--email', 'test@example.com')
      end
    end

    context 'when Stripe API fails' do
      it 'displays formatted error message' do
        allow(stripe_client).to receive(:create).and_raise(
          Stripe::InvalidRequestError.new('Email already exists', 'email', http_status: 400)
        )

        output = run_cli_command_quietly('billing', 'customers', 'create', '--email', 'duplicate@example.com')

        expect(output[:stdout]).to match(/failed to create customer/i)
      end
    end

    context 'when authentication fails' do
      it 'displays authentication error' do
        allow(stripe_client).to receive(:create).and_raise(
          Stripe::AuthenticationError.new('Invalid API key', http_status: 401)
        )

        output = run_cli_command_quietly('billing', 'customers', 'create', '--email', 'test@example.com')

        expect(output[:stdout]).to match(/authentication failed/i)
      end
    end
  end

  describe 'billing customers show' do
    let(:customer) { mock_stripe_customer(id: 'cus_test123', email: 'show@example.com', name: 'Show User', currency: 'usd', balance: -500) }
    let(:payment_methods) { double('ListObject', data: [mock_stripe_payment_method]) }
    let(:subscriptions) { double('ListObject', data: [mock_stripe_subscription]) }

    before do
      allow(Stripe::Customer).to receive(:retrieve).with('cus_test123').and_return(customer)
      allow(Stripe::PaymentMethod).to receive(:list).and_return(payment_methods)
      allow(Stripe::Subscription).to receive(:list).and_return(subscriptions)
    end

    context 'with valid customer ID' do
      it 'displays customer details' do
        output = run_cli_command_quietly('billing', 'customers', 'show', 'cus_test123')

        expect(output[:stdout]).to include('Customer Details:')
        expect(output[:stdout]).to include('cus_test123')
        expect(output[:stdout]).to include('show@example.com')
        expect(output[:stdout]).to include('Show User')
        expect(last_exit_code).to eq(0)
      end

      it 'displays payment methods' do
        output = run_cli_command_quietly('billing', 'customers', 'show', 'cus_test123')

        expect(output[:stdout]).to include('Payment Methods:')
        expect(output[:stdout]).to include('pm_test123')
      end

      it 'displays subscriptions' do
        output = run_cli_command_quietly('billing', 'customers', 'show', 'cus_test123')

        expect(output[:stdout]).to include('Subscriptions:')
        expect(output[:stdout]).to include('sub_test123')
      end

      it 'displays customer balance' do
        output = run_cli_command_quietly('billing', 'customers', 'show', 'cus_test123')

        expect(output[:stdout]).to match(/balance/i)
      end
    end

    context 'when customer has no payment methods' do
      let(:payment_methods) { double('ListObject', data: []) }

      it 'displays none message' do
        output = run_cli_command_quietly('billing', 'customers', 'show', 'cus_test123')

        expect(output[:stdout]).to match(/payment methods:.*none/im)
      end
    end

    context 'when customer has no subscriptions' do
      let(:subscriptions) { double('ListObject', data: []) }

      it 'displays none message' do
        output = run_cli_command_quietly('billing', 'customers', 'show', 'cus_test123')

        expect(output[:stdout]).to match(/subscriptions:.*none/im)
      end
    end

    context 'with invalid customer ID' do
      it 'displays error message' do
        allow(Stripe::Customer).to receive(:retrieve).and_raise(
          Stripe::InvalidRequestError.new('No such customer', 'customer', http_status: 404)
        )

        output = run_cli_command_quietly('billing', 'customers', 'show', 'cus_invalid')

        expect(output[:stdout]).to match(/error retrieving customer/i)
      end
    end

    context 'when displaying default payment method' do
      let(:customer) do
        mock_stripe_customer(
          id: 'cus_test123',
          invoice_settings: double('InvoiceSettings', default_payment_method: 'pm_test123')
        )
      end

      it 'marks default payment method' do
        output = run_cli_command_quietly('billing', 'customers', 'show', 'cus_test123')

        expect(output[:stdout]).to match(/pm_test123.*\(default\)/i)
      end
    end
  end

  describe 'billing customers delete' do
    let(:customer) { mock_stripe_customer(id: 'cus_test123', email: 'delete@example.com') }
    let(:deleted_response) { double('DeletedObject', deleted: true) }
    let(:active_subscriptions) { double('ListObject', data: []) }

    before do
      allow(Stripe::Customer).to receive(:retrieve).with('cus_test123').and_return(customer)
      allow(Stripe::Subscription).to receive(:list).with(hash_including(customer: 'cus_test123', status: 'active')).and_return(active_subscriptions)
      allow($stdin).to receive(:gets).and_return("y\n")
    end

    context 'with valid customer ID' do
      it 'deletes the customer after confirmation' do
        expect(Stripe::Customer).to receive(:delete).with('cus_test123').and_return(deleted_response)

        output = run_cli_command_quietly('billing', 'customers', 'delete', 'cus_test123')

        expect(output[:stdout]).to include('Customer deleted successfully')
        expect(last_exit_code).to eq(0)
      end

      it 'displays customer information before deletion' do
        allow(Stripe::Customer).to receive(:delete).and_return(deleted_response)

        output = run_cli_command_quietly('billing', 'customers', 'delete', 'cus_test123')

        expect(output[:stdout]).to include('cus_test123')
        expect(output[:stdout]).to include('delete@example.com')
      end

      it 'prompts for confirmation' do
        allow(Stripe::Customer).to receive(:delete).and_return(deleted_response)

        output = run_cli_command_quietly('billing', 'customers', 'delete', 'cus_test123')

        expect(output[:stdout]).to match(/delete customer permanently/i)
      end
    end

    context 'when user declines confirmation' do
      before do
        allow($stdin).to receive(:gets).and_return("n\n")
      end

      it 'does not delete customer' do
        expect(Stripe::Customer).not_to receive(:delete)

        run_cli_command_quietly('billing', 'customers', 'delete', 'cus_test123')
      end
    end

    context 'with --yes flag' do
      it 'skips confirmation prompt' do
        expect($stdin).not_to receive(:gets)
        expect(Stripe::Customer).to receive(:delete).with('cus_test123').and_return(deleted_response)

        run_cli_command_quietly('billing', 'customers', 'delete', 'cus_test123', '--yes')

        expect(last_exit_code).to eq(0)
      end
    end

    context 'when customer has active subscriptions' do
      let(:active_subscription) { mock_stripe_subscription(id: 'sub_active', status: 'active') }
      let(:active_subscriptions) { double('ListObject', data: [active_subscription], auto_paging_each: [active_subscription]) }

      context 'without --yes flag' do
        before do
          allow($stdin).to receive(:gets).and_return("n\n")
        end

        it 'warns about active subscriptions' do
          output = run_cli_command_quietly('billing', 'customers', 'delete', 'cus_test123')

          expect(output[:stdout]).to match(/customer has active subscriptions/i)
          expect(output[:stdout]).to match(/cancel subscriptions first/i)
        end

        it 'does not delete customer' do
          expect(Stripe::Customer).not_to receive(:delete)

          run_cli_command_quietly('billing', 'customers', 'delete', 'cus_test123')
        end
      end

      context 'with --yes flag' do
        it 'cancels subscriptions before deleting' do
          allow(active_subscriptions).to receive(:auto_paging_each).and_yield(active_subscription)
          expect(Stripe::Subscription).to receive(:update).with('sub_active', hash_including(cancel_at_period_end: false))
          expect(Stripe::Subscription).to receive(:delete).with('sub_active')
          expect(Stripe::Customer).to receive(:delete).with('cus_test123').and_return(deleted_response)

          output = run_cli_command_quietly('billing', 'customers', 'delete', 'cus_test123', '--yes')

          expect(output[:stdout]).to include('Cancelling all active subscriptions')
          expect(output[:stdout]).to include('Cancelled subscription sub_active')
        end
      end
    end

    context 'when deletion fails' do
      let(:deleted_response) { double('DeletedObject', deleted: false) }

      it 'displays failure message' do
        allow(Stripe::Customer).to receive(:delete).and_return(deleted_response)

        output = run_cli_command_quietly('billing', 'customers', 'delete', 'cus_test123')

        expect(output[:stdout]).to include('Failed to delete customer')
      end
    end

    context 'with invalid customer ID' do
      it 'displays error message' do
        allow(Stripe::Customer).to receive(:retrieve).and_raise(
          Stripe::InvalidRequestError.new('No such customer', 'customer', http_status: 404)
        )

        output = run_cli_command_quietly('billing', 'customers', 'delete', 'cus_invalid')

        expect(output[:stdout]).to match(/error deleting customer/i)
      end
    end

    context 'when subscription cancellation fails' do
      let(:active_subscription) { mock_stripe_subscription(id: 'sub_active', status: 'active') }
      let(:active_subscriptions) { double('ListObject', data: [active_subscription]) }

      it 'reports the error but continues' do
        allow(active_subscriptions).to receive(:auto_paging_each).and_yield(active_subscription)
        allow(Stripe::Subscription).to receive(:update).and_raise(Stripe::InvalidRequestError.new('Cannot cancel', 'subscription'))

        output = run_cli_command_quietly('billing', 'customers', 'delete', 'cus_test123', '--yes')

        expect(output[:stdout]).to match(/failed to cancel subscription/i)
      end
    end
  end

  describe 'integration scenarios' do
    it 'create, show, and delete customer workflow' do
      customer = mock_stripe_customer(id: 'cus_workflow', email: 'workflow@example.com')
      stripe_client = instance_double('Billing::StripeClient')
      allow(Billing::StripeClient).to receive(:new).and_return(stripe_client)
      allow(stripe_client).to receive(:create).and_return(customer)
      allow($stdin).to receive(:gets).and_return("y\n")

      # Create
      output = run_cli_command_quietly('billing', 'customers', 'create', '--email', 'workflow@example.com')
      expect(output[:stdout]).to include('Customer created successfully')

      # Show
      allow(Stripe::Customer).to receive(:retrieve).and_return(customer)
      allow(Stripe::PaymentMethod).to receive(:list).and_return(double(data: []))
      allow(Stripe::Subscription).to receive(:list).and_return(double(data: []))

      output = run_cli_command_quietly('billing', 'customers', 'show', 'cus_workflow')
      expect(output[:stdout]).to include('workflow@example.com')

      # Delete
      allow(Stripe::Customer).to receive(:delete).and_return(double(deleted: true))

      output = run_cli_command_quietly('billing', 'customers', 'delete', 'cus_workflow', '--yes')
      expect(output[:stdout]).to include('Customer deleted successfully')
    end
  end
end
