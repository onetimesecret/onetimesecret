# apps/web/billing/spec/cli/refunds_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require 'onetime/cli'
require_relative '../../lib/stripe_client'
require_relative '../../cli/refunds_command'
require_relative '../../cli/refunds_create_command'

# Refunds CLI Test Strategy:
#
# These tests validate CLI behavior (parameter passing, error handling, output formatting),
# NOT Stripe API behavior (state persistence, amount calculations, filtering).
#
# stripe-mock limitations addressed:
# - Returns static fixture data ($1.00) regardless of input amounts
# - Doesn't maintain state between requests (can't test double-refund prevention)
# - Doesn't support filtering (charge parameter accepted but not filtered)
#
# Tests marked :code_smell need rewriting:
# - Some try to validate Stripe API behavior with stripe-mock (impossible)
# - Should either become true unit tests (CLI only) or :integration tests (require sandbox)

RSpec.describe 'Billing Refunds CLI Commands', :billing_cli, :integration, :vcr do
  let(:stripe_client) { Billing::StripeClient.new }

  describe Onetime::CLI::BillingRefundsCommand do
    subject(:command) { described_class.new }

    describe '#call (list refunds)' do
      context 'with successful Stripe API response' do
        it 'lists all refunds without filters', :vcr do
          # Create test charge first
          customer = stripe_client.create(Stripe::Customer, {
            email: 'refund-test@example.com',
            name: 'Refund Test User',
            source: 'tok_visa',  # Attach payment source at customer creation
          }
          )

          charge = stripe_client.create(Stripe::Charge, {
            amount: 5000,
            currency: 'cad',
            customer: customer.id,
            # Uses customer's attached payment source
          }
          )

          # Create refund
          stripe_client.create(Stripe::Refund, {
            charge: charge.id,
          }
          )

          expect do
            command.call(limit: 10)
          end.to output(/Fetching refunds from Stripe/).to_stdout

          # Cleanup
          stripe_client.delete(Stripe::Customer, customer.id)
        end

        it 'filters refunds by charge ID' do
          # NOTE: Real Stripe API validates charge ID, so we mock the response
          # This test verifies the CLI accepts the charge filter parameter and formats output
          allow(Stripe::Refund).to receive(:list).and_return(
            double(data: [
                     double(
                       id: 're_test123',
                       charge: 'ch_test_filter',
                       amount: 5000,
                       currency: 'cad',
                       status: 'succeeded',
                       created: Time.now.to_i,
                     ),
                   ]),
          )

          output = capture_stdout do
            command.call(charge: 'ch_test_filter', limit: 10)
          end

          # Verify CLI displays refund list format correctly
          expect(output).to match(/ID.*CHARGE.*AMOUNT.*STATUS.*CREATED/)
          expect(output).to match(/Total: \d+ refund\(s\)/)
        end

        it 'respects limit parameter' do
          # List with limit
          expect do
            command.call(limit: 5)
          end.to output(/Fetching refunds from Stripe/).to_stdout
        end

        it 'displays correct refund information' do
          # NOTE: stripe-mock returns static refund data
          # This test verifies CLI output formatting is correct
          output = capture_stdout do
            command.call(limit: 10)
          end

          # Verify header row
          expect(output).to match(/ID.*CHARGE.*AMOUNT.*STATUS.*CREATED/)

          # Verify data formatting (stripe-mock returns consistent test data)
          expect(output).to match(/re_\w+/)  # Refund ID format
          expect(output).to match(/ch_\w+/)  # Charge ID format
          expect(output).to match(/USD \d+\.\d{2}/)  # Currency format
          expect(output).to match(/succeeded/)  # Status
          expect(output).to match(/\d{4}-\d{2}-\d{2}/)  # Date format
        end
      end

      context 'when no refunds found' do
        it 'displays appropriate message' do
          # Mock empty refund list (stripe-mock always returns data)
          allow(Stripe::Refund).to receive(:list).and_return(
            double(data: []),
          )

          output = capture_stdout do
            command.call(charge: 'ch_nonexistent', limit: 10)
          end

          expect(output).to match(/No refunds found/)
        end
      end

      context 'with Stripe API errors' do
        it 'handles invalid charge ID gracefully' do
          allow(Stripe::Refund).to receive(:list).and_raise(
            Stripe::InvalidRequestError.new('Invalid charge', 'charge'),
          )

          expect do
            command.call(charge: 'invalid_id', limit: 10)
          end.to output(/Error fetching refunds/).to_stdout
        end

        it 'handles network errors gracefully' do
          allow(Stripe::Refund).to receive(:list).and_raise(
            Stripe::APIConnectionError.new('Network error'),
          )

          expect do
            command.call(limit: 10)
          end.to output(/Error fetching refunds/).to_stdout
        end
      end

      context 'when billing not configured' do
        before do
          allow(command).to receive(:stripe_configured?).and_return(false)
        end

        it 'returns early without making API calls' do
          expect(Stripe::Refund).not_to receive(:list)
          command.call(limit: 10)
        end
      end
    end
  end

  describe Onetime::CLI::BillingRefundsCreateCommand do
    subject(:command) { described_class.new }

    describe '#call (create refund)' do
      context 'with valid charge ID' do
        it 'creates full refund with confirmation', :vcr do
          # Create test charge with real Stripe API (VCR records the interaction)
          customer = stripe_client.create(Stripe::Customer, {
            email: 'refund-create-test@example.com',
            source: 'tok_visa',  # Attach payment source at customer creation
          }
          )

          charge = stripe_client.create(Stripe::Charge, {
            amount: 5000,  # $50.00
            currency: 'cad',
            customer: customer.id,
            # Uses customer's attached payment source
          }
          )

          # Simulate user confirmation
          allow($stdin).to receive(:gets).and_return("y\n")

          output = capture_stdout do
            command.call(charge: charge.id)
          end

          expect(output).to match(/Charge: #{charge.id}/)
          expect(output).to match(/Amount: USD 50\.00/)  # Real API returns actual amount
          expect(output).to match(/Refund amount: USD 50\.00/)
          expect(output).to match(/Refund created successfully/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, customer.id)
        end

        it 'creates partial refund', :vcr do
          customer = stripe_client.create(Stripe::Customer, {
            email: 'partial-refund-test@example.com',
            source: 'tok_visa',  # Attach payment source at customer creation
          }
          )

          charge = stripe_client.create(Stripe::Charge, {
            amount: 10_000,
            currency: 'cad',
            customer: customer.id,
            # Uses customer's attached payment source
          }
          )

          allow($stdin).to receive(:gets).and_return("y\n")

          output = capture_stdout do
            command.call(charge: charge.id, amount: 5000)
          end

          expect(output).to match(/Refund amount: USD 50\.00/)
          expect(output).to match(/Refund created successfully/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, customer.id)
        end

        it 'includes reason when provided', :vcr do
          customer = stripe_client.create(Stripe::Customer, {
            email: 'refund-reason-test@example.com',
            source: 'tok_visa',  # Attach payment source at customer creation
          }
          )

          charge = stripe_client.create(Stripe::Charge, {
            amount: 3000,
            currency: 'cad',
            customer: customer.id,
            # Uses customer's attached payment source
          }
          )

          allow($stdin).to receive(:gets).and_return("y\n")

          output = capture_stdout do
            command.call(charge: charge.id, reason: 'requested_by_customer')
          end

          expect(output).to match(/Reason: requested_by_customer/)
          expect(output).to match(/Refund created successfully/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, customer.id)
        end

        it 'bypasses confirmation with --yes flag', :vcr do
          customer = stripe_client.create(Stripe::Customer, {
            email: 'refund-yes-test@example.com',
            source: 'tok_visa',  # Attach payment source at customer creation
          }
          )

          charge = stripe_client.create(Stripe::Charge, {
            amount: 2000,
            currency: 'cad',
            customer: customer.id,
            # Uses customer's attached payment source
          }
          )

          # Should not prompt for confirmation
          expect($stdin).not_to receive(:gets)

          output = capture_stdout do
            command.call(charge: charge.id, yes: true)
          end

          expect(output).to match(/Refund created successfully/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, customer.id)
        end

        it 'aborts when user declines confirmation', :vcr do
          customer = stripe_client.create(Stripe::Customer, {
            email: 'refund-decline-test@example.com',
            source: 'tok_visa',  # Attach payment source at customer creation
          }
          )

          charge = stripe_client.create(Stripe::Charge, {
            amount: 1000,
            currency: 'cad',
            customer: customer.id,
            # Uses customer's attached payment source
          }
          )

          allow($stdin).to receive(:gets).and_return("n\n")

          output = capture_stdout do
            command.call(charge: charge.id)
          end

          expect(output).not_to match(/Refund created successfully/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, customer.id)
        end
      end

      context 'with invalid charge ID' do
        it 'handles non-existent charge gracefully' do
          allow(Stripe::Charge).to receive(:retrieve).and_raise(
            Stripe::InvalidRequestError.new('No such charge', 'charge'),
          )

          expect do
            command.call(charge: 'ch_nonexistent', yes: true)
          end.to output(/Error creating refund/).to_stdout
        end

        it 'handles already refunded charge' do
          # Mock the scenario where charge is already fully refunded
          # stripe-mock doesn't enforce this constraint
          allow(Stripe::Charge).to receive(:retrieve).and_return(
            double(
              id: 'ch_already_refunded',
              amount: 1000,
              currency: 'cad',
              customer: 'cus_test',
            ),
          )

          allow(Stripe::Refund).to receive(:create).and_raise(
            Stripe::InvalidRequestError.new(
              'Charge ch_already_refunded has already been refunded',
              'charge',
            ),
          )

          expect do
            command.call(charge: 'ch_already_refunded', yes: true)
          end.to output(/Error creating refund/).to_stdout
        end
      end

      context 'with Stripe API errors' do
        it 'handles network errors gracefully' do
          allow(Stripe::Charge).to receive(:retrieve).and_raise(
            Stripe::APIConnectionError.new('Network error'),
          )

          expect do
            command.call(charge: 'ch_test', yes: true)
          end.to output(/Error creating refund/).to_stdout
        end

        it 'handles authentication errors' do
          allow(Stripe::Charge).to receive(:retrieve).and_raise(
            Stripe::AuthenticationError.new('Invalid API key'),
          )

          expect do
            command.call(charge: 'ch_test', yes: true)
          end.to output(/Error creating refund/).to_stdout
        end
      end

      context 'when billing not configured' do
        before do
          allow(command).to receive(:stripe_configured?).and_return(false)
        end

        it 'returns early without making API calls' do
          expect(Stripe::Charge).not_to receive(:retrieve)
          command.call(charge: 'ch_test', yes: true)
        end
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
