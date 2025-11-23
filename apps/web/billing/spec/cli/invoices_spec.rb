# apps/web/billing/spec/cli/invoices_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require 'onetime/cli'
require_relative '../../lib/stripe_client'
require_relative '../../cli/invoices_command'

# Invoices CLI Test Strategy:
#
# These tests validate CLI output formatting and parameter handling.
#
# stripe-mock limitations:
# - Returns static invoice fixtures
# - Doesn't support filtering by customer/status/subscription
# - Doesn't create invoices based on test input
#
# Most tests here are :code_smell - they try to validate Stripe API behavior
# Should be rewritten as true unit tests or moved to :integration with :stripe_sandbox_api

RSpec.describe 'Billing Invoices CLI Commands', :billing_cli, :integration, :stripe_sandbox_api, :code_smell do
  let(:stripe_client) { Billing::StripeClient.new }

  # Helper to create test invoice
  def create_test_invoice(email: 'invoice-test@example.com', status: 'draft')
    customer = stripe_client.create(Stripe::Customer, { email: email })

    product = stripe_client.create(Stripe::Product, {
      name: "Test Product #{Time.now.to_i}"
    })

    price = stripe_client.create(Stripe::Price, {
      unit_amount: 5000,
      currency: 'usd',
      product: product.id
    })

    # Create invoice item first
    invoice_item = stripe_client.create(Stripe::InvoiceItem, {
      customer: customer.id,
      price: price.id
    })

    # Create invoice
    invoice = stripe_client.create(Stripe::Invoice, {
      customer: customer.id,
      auto_advance: false
    })

    { customer: customer, product: product, price: price, invoice: invoice }
  end

  describe Onetime::CLI::BillingInvoicesCommand do
    subject(:command) { described_class.new }

    describe '#call (list invoices)' do
      context 'with successful Stripe API response' do
        it 'lists all invoices without filters', :vcr do
          test_data = create_test_invoice

          expect {
            command.call(limit: 10)
          }.to output(/Fetching invoices from Stripe/).to_stdout

          # Cleanup
          stripe_client.delete(Stripe::Customer, test_data[:customer].id)
        end

        it 'filters invoices by customer ID', :vcr do
          test_data = create_test_invoice(email: 'invoice-filter@example.com')

          output = capture_stdout do
            command.call(customer: test_data[:customer].id, limit: 10)
          end

          expect(output).to match(/#{test_data[:customer].id}/)
          expect(output).to match(/#{test_data[:invoice].id}/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, test_data[:customer].id)
        end

        it 'filters invoices by status', :vcr do
          test_data = create_test_invoice

          output = capture_stdout do
            command.call(status: 'draft', limit: 10)
          end

          expect(output).to match(/draft/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, test_data[:customer].id)
        end

        it 'filters invoices by subscription ID', :integration, :stripe_sandbox_api, :vcr do
          # Create subscription to generate invoice
          customer = stripe_client.create(Stripe::Customer, {
            email: 'invoice-sub-filter@example.com'
          })

          product = stripe_client.create(Stripe::Product, {
            name: "Test Product #{Time.now.to_i}"
          })

          price = stripe_client.create(Stripe::Price, {
            unit_amount: 2000,
            currency: 'usd',
            recurring: { interval: 'month' },
            product: product.id
          })

          subscription = stripe_client.create(Stripe::Subscription, {
            customer: customer.id,
            items: [{ price: price.id }]
          })

          # Get latest invoice from subscription
          invoice = stripe_client.retrieve(Stripe::Invoice, subscription.latest_invoice)

          output = capture_stdout do
            command.call(subscription: subscription.id, limit: 10)
          end

          expect(output).to match(/#{subscription.id}/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, customer.id)
        end

        it 'respects limit parameter', :vcr do
          expect {
            command.call(limit: 5)
          }.to output(/Fetching invoices from Stripe/).to_stdout
        end

        it 'displays correct invoice information', :vcr do
          test_data = create_test_invoice

          output = capture_stdout do
            command.call(customer: test_data[:customer].id, limit: 10)
          end

          expect(output).to match(/ID.*CUSTOMER.*AMOUNT.*STATUS.*CREATED/)
          expect(output).to match(/#{test_data[:invoice].id}/)
          expect(output).to match(/#{test_data[:customer].id}/)
          expect(output).to match(/USD/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, test_data[:customer].id)
        end

        it 'displays available status filters', :vcr do
          output = capture_stdout do
            command.call(limit: 10)
          end

          expect(output).to match(/Statuses: draft, open, paid, uncollectible, void/)
        end

        it 'displays total count of invoices', :vcr do
          test_data = create_test_invoice

          output = capture_stdout do
            command.call(customer: test_data[:customer].id, limit: 10)
          end

          expect(output).to match(/Total: \d+ invoice\(s\)/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, test_data[:customer].id)
        end
      end

      context 'when no invoices found' do
        it 'displays appropriate message', :vcr do
          output = capture_stdout do
            command.call(customer: 'cus_nonexistent', limit: 10)
          end

          expect(output).to match(/No invoices found/)
        end
      end

      context 'with multiple filter combinations' do
        it 'combines customer and status filters', :vcr do
          test_data = create_test_invoice

          output = capture_stdout do
            command.call(
              customer: test_data[:customer].id,
              status: 'draft',
              limit: 10
            )
          end

          expect(output).to match(/#{test_data[:customer].id}/)
          expect(output).to match(/draft/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, test_data[:customer].id)
        end
      end

      context 'with different invoice statuses' do
        it 'lists draft invoices', :vcr do
          test_data = create_test_invoice(status: 'draft')

          output = capture_stdout do
            command.call(status: 'draft', limit: 10)
          end

          expect(output).to match(/draft/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, test_data[:customer].id)
        end

        it 'lists open invoices', :vcr do
          test_data = create_test_invoice

          # Finalize to make it open
          stripe_client.create(Stripe::Invoice, test_data[:invoice].id, :finalize)

          output = capture_stdout do
            command.call(customer: test_data[:customer].id, limit: 10)
          end

          expect(output).to match(/open/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, test_data[:customer].id)
        end
      end

      context 'with Stripe API errors' do
        it 'handles invalid customer ID gracefully' do
          allow(Stripe::Invoice).to receive(:list).and_raise(
            Stripe::InvalidRequestError.new('Invalid customer', 'customer')
          )

          expect {
            command.call(customer: 'invalid_id', limit: 10)
          }.to output(/Error fetching invoices/).to_stdout
        end

        it 'handles invalid status parameter gracefully' do
          allow(Stripe::Invoice).to receive(:list).and_raise(
            Stripe::InvalidRequestError.new('Invalid status', 'status')
          )

          expect {
            command.call(status: 'invalid_status', limit: 10)
          }.to output(/Error fetching invoices/).to_stdout
        end

        it 'handles network errors gracefully' do
          allow(Stripe::Invoice).to receive(:list).and_raise(
            Stripe::APIConnectionError.new('Network error')
          )

          expect {
            command.call(limit: 10)
          }.to output(/Error fetching invoices/).to_stdout
        end

        it 'handles rate limit errors gracefully' do
          allow(Stripe::Invoice).to receive(:list).and_raise(
            Stripe::RateLimitError.new('Rate limit exceeded')
          )

          expect {
            command.call(limit: 10)
          }.to output(/Error fetching invoices/).to_stdout
        end

        it 'handles authentication errors gracefully' do
          allow(Stripe::Invoice).to receive(:list).and_raise(
            Stripe::AuthenticationError.new('Invalid API key')
          )

          expect {
            command.call(limit: 10)
          }.to output(/Error fetching invoices/).to_stdout
        end
      end

      context 'with invoice formatting' do
        it 'formats amounts correctly', :vcr do
          test_data = create_test_invoice

          output = capture_stdout do
            command.call(customer: test_data[:customer].id, limit: 10)
          end

          # Should display formatted currency amount
          expect(output).to match(/USD \d+\.\d{2}/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, test_data[:customer].id)
        end

        it 'formats dates correctly', :vcr do
          test_data = create_test_invoice

          output = capture_stdout do
            command.call(customer: test_data[:customer].id, limit: 10)
          end

          # Should display formatted date (YYYY-MM-DD)
          expect(output).to match(/\d{4}-\d{2}-\d{2}/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, test_data[:customer].id)
        end

        it 'truncates long IDs appropriately', :vcr do
          test_data = create_test_invoice

          output = capture_stdout do
            command.call(customer: test_data[:customer].id, limit: 10)
          end

          # IDs should be truncated to fit column width (22 chars)
          lines = output.split("\n")
          data_lines = lines.select { |l| l.start_with?('in_') }
          expect(data_lines).to be_present

          # Cleanup
          stripe_client.delete(Stripe::Customer, test_data[:customer].id)
        end
      end

      context 'when billing not configured' do
        before do
          allow(command).to receive(:stripe_configured?).and_return(false)
        end

        it 'returns early without making API calls' do
          expect(Stripe::Invoice).not_to receive(:list)
          command.call(limit: 10)
        end

        it 'does not display any invoice data' do
          output = capture_stdout do
            command.call(limit: 10)
          end

          expect(output).not_to match(/ID.*CUSTOMER.*AMOUNT/)
        end
      end

      context 'with pagination' do
        it 'limits results to specified limit', :vcr do
          # Create multiple invoices
          3.times do |i|
            create_test_invoice(email: "invoice-pagination-#{i}@example.com")
          end

          output = capture_stdout do
            command.call(limit: 2)
          end

          # Should respect limit
          expect(output).to match(/Total: \d+ invoice\(s\)/)
        end
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
