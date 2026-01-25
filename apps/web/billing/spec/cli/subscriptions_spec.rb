# apps/web/billing/spec/cli/subscriptions_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require 'onetime/cli'
require_relative '../../lib/stripe_client'
require_relative '../../cli/subscriptions_command'
require_relative '../../cli/subscriptions_cancel_command'
require_relative '../../cli/subscriptions_pause_command'
require_relative '../../cli/subscriptions_resume_command'
require_relative '../../cli/subscriptions_update_command'

# Subscriptions CLI Test Strategy:
#
# These tests validate CLI behavior, NOT Stripe subscription lifecycle management.
#
# stripe-mock limitations:
# - Returns incomplete subscription objects (missing current_period_end, etc.)
# - Doesn't persist pause/resume state between requests
# - Doesn't enforce cancellation rules
#
# Current state: Heavy mocking to work around stripe-mock limitations
# Tests marked :code_smell should be rewritten as either:
#   - True unit tests (test CLI only, fully mock Stripe SDK)
#   - Integration tests with :stripe_sandbox_api tag

RSpec.describe 'Billing Subscriptions CLI Commands', :billing_cli, :code_smell, :integration, :vcr do
  using Familia::Refinements::TimeLiterals

  let(:stripe_client) { Billing::StripeClient.new }

  # Helper to create mock subscription with full attributes
  # stripe-mock returns incomplete objects, so we mock for comprehensive testing
  # Note: current_period_end is now at the subscription item level in Stripe API 2025-11-17.clover
  def mock_subscription(id: 'sub_test123', status: 'active', customer_id: 'cus_test')
    period_end = Time.now.to_i + 30.days
    double(Stripe::Subscription,
      id: id,
      status: status,
      customer: customer_id,
      cancel_at_period_end: false,
      canceled_at: nil,
      pause_collection: nil,
      items: double(data: [
                      double(
                        id: 'si_test',
                        price: double(id: 'price_test', unit_amount: 2000, currency: 'usd'),
                        quantity: 1,
                        current_period_end: period_end,
                        current_period_start: Time.now.to_i,
                      ),
                    ],
                   ),
    )
  end

  # Helper to create test subscription with stripe-mock
  # Note: Uses fixed product name for VCR cassette replay (matching on body)
  def create_test_subscription(email: 'sub-test@example.com')
    customer = stripe_client.create(Stripe::Customer, {
      email: email,
      source: 'tok_visa',  # Attach payment source for subscription creation
    }
    )

    product = stripe_client.create(Stripe::Product, {
      name: 'VCR Test Product',
    }
    )

    price = stripe_client.create(Stripe::Price, {
      unit_amount: 2000,
      currency: 'usd',
      recurring: { interval: 'month' },
      product: product.id,
    }
    )

    subscription = stripe_client.create(Stripe::Subscription, {
      customer: customer.id,
      items: [{ price: price.id }],
    }
    )

    # Retrieve full subscription object to ensure all attributes are present
    # (VCR may not capture all nested attributes from create response)
    subscription = stripe_client.retrieve(Stripe::Subscription, subscription.id)

    { customer: customer, product: product, price: price, subscription: subscription }
  end

  describe Onetime::CLI::BillingSubscriptionsCommand do
    subject(:command) { described_class.new }

    describe '#call (list subscriptions)' do
      context 'with successful Stripe API response' do
        it 'lists all subscriptions without filters' do
          # Mock response to avoid incomplete stripe-mock objects
          allow(Stripe::Subscription).to receive(:list).and_return(
            double(data: [mock_subscription]),
          )

          expect do
            command.call(limit: 10)
          end.to output(/Fetching subscriptions from Stripe/).to_stdout
        end

        it 'filters subscriptions by customer ID' do
          # stripe-mock doesn't filter, so mock the response
          allow(Stripe::Subscription).to receive(:list).and_return(
            double(data: [mock_subscription(customer_id: 'cus_filter')]),
          )

          output = capture_stdout do
            command.call(customer: 'cus_filter', limit: 10)
          end

          expect(output).to match(/cus_filter/)
          expect(output).to match(/sub_test123/)
        end

        it 'filters subscriptions by status' do
          # stripe-mock doesn't filter, mock the response to test CLI accepts parameter
          allow(Stripe::Subscription).to receive(:list).and_return(
            double(data: [mock_subscription(status: 'active')]),
          )

          output = capture_stdout do
            command.call(status: 'active', limit: 10)
          end

          expect(output).to match(/Fetching subscriptions from Stripe/)
          expect(output).to match(/active/)
        end

        it 'respects limit parameter' do
          # Mock the response to avoid incomplete stripe-mock objects
          allow(Stripe::Subscription).to receive(:list).and_return(
            double(data: [mock_subscription]),
          )

          expect do
            command.call(limit: 3)
          end.to output(/Fetching subscriptions from Stripe/).to_stdout
        end

        it 'displays correct subscription information' do
          allow(Stripe::Subscription).to receive(:list).and_return(
            double(data: [mock_subscription]),
          )

          output = capture_stdout do
            command.call(limit: 10)
          end

          expect(output).to match(/ID.*CUSTOMER.*STATUS.*PERIOD END/)
          expect(output).to match(/sub_test123/)
          expect(output).to match(/cus_test/)
        end

        it 'displays available status filters when subscriptions exist' do
          allow(Stripe::Subscription).to receive(:list).and_return(
            double(data: [mock_subscription]),
          )

          output = capture_stdout do
            command.call(limit: 10)
          end

          expect(output).to match(/Statuses: active, past_due, canceled, incomplete, trialing, unpaid/)
        end
      end

      context 'when no subscriptions found' do
        it 'displays appropriate message' do
          allow(Stripe::Subscription).to receive(:list).and_return(
            double(data: []),
          )

          output = capture_stdout do
            command.call(customer: 'cus_nonexistent', limit: 10)
          end

          expect(output).to match(/No subscriptions found/)
        end
      end

      context 'with Stripe API errors' do
        it 'handles invalid customer ID gracefully' do
          allow(Stripe::Subscription).to receive(:list).and_raise(
            Stripe::InvalidRequestError.new('Invalid customer', 'customer'),
          )

          expect do
            command.call(customer: 'invalid_id', limit: 10)
          end.to output(/Error fetching subscriptions/).to_stdout
        end

        it 'handles network errors gracefully' do
          allow(Stripe::Subscription).to receive(:list).and_raise(
            Stripe::APIConnectionError.new('Network error'),
          )

          expect do
            command.call(limit: 10)
          end.to output(/Error fetching subscriptions/).to_stdout
        end
      end

      context 'when billing not configured' do
        before do
          allow(command).to receive(:stripe_configured?).and_return(false)
        end

        it 'returns early without making API calls' do
          expect(Stripe::Subscription).not_to receive(:list)
          command.call(limit: 10)
        end
      end
    end
  end

  describe Onetime::CLI::BillingSubscriptionsCancelCommand do
    subject(:command) { described_class.new }

    describe '#call (cancel subscription)' do
      context 'with valid subscription ID' do
        it 'cancels subscription at period end by default' do
          sub = mock_subscription

          # Mock Stripe SDK methods directly
          allow(Stripe::Subscription).to receive_messages(retrieve: sub, update: sub)
          allow($stdin).to receive(:gets).and_return("y\n")

          # Just verify the command accepts the request without errors
          expect do
            capture_stdout do
              command.call(subscription_id: 'sub_test123')
            end
          end.not_to raise_error
        end

        it 'cancels subscription immediately with --immediately flag', :vcr do
          # Create real test subscription for VCR recording
          resources = create_test_subscription(email: 'cancel-immediate-test@example.com')

          allow($stdin).to receive(:gets).and_return("y\n")

          output = capture_stdout do
            command.call(subscription_id: resources[:subscription].id, immediately: true)
          end

          # Verify CLI displays cancellation confirmation
          expect(output).to match(/Subscription cancelled successfully/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, resources[:customer].id)
        end

        it 'displays operation summary with dry run' do
          sub = mock_subscription
          allow(Stripe::Subscription).to receive(:retrieve).and_return(sub)

          # Just verify dry run doesn't raise errors
          expect do
            capture_stdout do
              command.call(subscription_id: 'sub_test123', dry_run: true)
            end
          end.not_to raise_error
        end

        it 'bypasses confirmation with --yes flag' do
          sub = mock_subscription

          allow(Stripe::Subscription).to receive_messages(retrieve: sub, update: sub)
          expect($stdin).not_to receive(:gets)

          # Just verify the command accepts the request without errors
          expect do
            capture_stdout do
              command.call(subscription_id: 'sub_test123', yes: true)
            end
          end.not_to raise_error
        end

        it 'aborts when user declines confirmation', :vcr do
          # Create real test subscription for VCR recording
          resources = create_test_subscription(email: 'cancel-abort-test@example.com')

          allow($stdin).to receive(:gets).and_return("n\n")

          output = capture_stdout do
            command.call(subscription_id: resources[:subscription].id)
          end

          # Verify CLI shows abort message (not cancellation success)
          expect(output).not_to match(/Subscription cancelled successfully/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, resources[:customer].id)
        end
      end

      context 'with invalid subscription ID' do
        it 'handles non-existent subscription gracefully' do
          allow(stripe_client).to receive(:retrieve).and_raise(
            Stripe::InvalidRequestError.new('No such subscription', 'subscription'),
          )

          output = capture_stdout do
            command.call(subscription_id: 'sub_nonexistent', yes: true)
          end

          expect(output).to match(/Subscription cancellation failed/)
        end
      end

      context 'when billing not configured' do
        before do
          allow(command).to receive(:stripe_configured?).and_return(false)
        end

        it 'returns early without making API calls' do
          expect(Stripe::Subscription).not_to receive(:retrieve)
          command.call(subscription_id: 'sub_test', yes: true)
        end
      end
    end
  end

  describe Onetime::CLI::BillingSubscriptionsPauseCommand do
    subject(:command) { described_class.new }

    describe '#call (pause subscription)' do
      context 'with valid subscription ID' do
        it 'pauses active subscription' do
          sub        = mock_subscription
          paused_sub = mock_subscription
          allow(paused_sub).to receive(:pause_collection).and_return(double(behavior: 'void'))

          allow(Stripe::Subscription).to receive_messages(retrieve: sub, update: paused_sub)
          allow($stdin).to receive(:gets).and_return("y\n")

          output = capture_stdout do
            command.call(subscription_id: 'sub_test123')
          end

          expect(output).to match(/Subscription: sub_test123/)
          expect(output).to match(/Subscription paused successfully/)
          expect(output).to match(/Billing paused, access continues/)
        end

        it 'bypasses confirmation with --yes flag' do
          sub        = mock_subscription
          paused_sub = mock_subscription
          allow(paused_sub).to receive(:pause_collection).and_return(double(behavior: 'void'))

          allow(Stripe::Subscription).to receive_messages(retrieve: sub, update: paused_sub)
          expect($stdin).not_to receive(:gets)

          output = capture_stdout do
            command.call(subscription_id: 'sub_test123', yes: true)
          end

          expect(output).to match(/Subscription paused successfully/)
        end

        it 'detects already paused subscription' do
          paused_sub = mock_subscription
          allow(paused_sub).to receive(:pause_collection).and_return(double(behavior: 'void'))

          allow(Stripe::Subscription).to receive(:retrieve).and_return(paused_sub)

          output = capture_stdout do
            command.call(subscription_id: 'sub_test123', yes: true)
          end

          expect(output).to match(/Subscription is already paused/)
        end

        it 'aborts when user declines confirmation' do
          sub = mock_subscription
          allow(Stripe::Subscription).to receive(:retrieve).and_return(sub)
          allow($stdin).to receive(:gets).and_return("n\n")

          output = capture_stdout do
            command.call(subscription_id: 'sub_test123')
          end

          expect(output).not_to match(/Subscription paused successfully/)
        end
      end

      context 'with invalid subscription ID' do
        it 'handles non-existent subscription gracefully' do
          allow(Stripe::Subscription).to receive(:retrieve).and_raise(
            Stripe::InvalidRequestError.new('No such subscription', 'subscription'),
          )

          expect do
            command.call(subscription_id: 'sub_nonexistent', yes: true)
          end.to output(/Error pausing subscription/).to_stdout
        end
      end

      context 'when billing not configured' do
        before do
          allow(command).to receive(:stripe_configured?).and_return(false)
        end

        it 'returns early without making API calls' do
          expect(Stripe::Subscription).not_to receive(:retrieve)
          command.call(subscription_id: 'sub_test', yes: true)
        end
      end
    end
  end

  describe Onetime::CLI::BillingSubscriptionsResumeCommand do
    subject(:command) { described_class.new }

    describe '#call (resume subscription)' do
      context 'with valid paused subscription' do
        it 'resumes paused subscription', :vcr do
          test_data = create_test_subscription

          # Pause first
          stripe_client.update(Stripe::Subscription, test_data[:subscription].id, {
            pause_collection: { behavior: 'void' },
          }
          )

          allow($stdin).to receive(:gets).and_return("y\n")

          output = capture_stdout do
            command.call(subscription_id: test_data[:subscription].id)
          end

          expect(output).to match(/Currently paused: Yes/)
          expect(output).to match(/Subscription resumed successfully/)
          expect(output).to match(/Billing will resume on next period/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, test_data[:customer].id)
        end

        it 'bypasses confirmation with --yes flag', :vcr do
          test_data = create_test_subscription

          # Pause first
          stripe_client.update(Stripe::Subscription, test_data[:subscription].id, {
            pause_collection: { behavior: 'void' },
          }
          )

          expect($stdin).not_to receive(:gets)

          output = capture_stdout do
            command.call(subscription_id: test_data[:subscription].id, yes: true)
          end

          expect(output).to match(/Subscription resumed successfully/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, test_data[:customer].id)
        end

        it 'detects not paused subscription', :vcr do
          test_data = create_test_subscription

          output = capture_stdout do
            command.call(subscription_id: test_data[:subscription].id, yes: true)
          end

          expect(output).to match(/Subscription is not paused/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, test_data[:customer].id)
        end

        it 'aborts when user declines confirmation', :vcr do
          test_data = create_test_subscription

          # Pause first
          stripe_client.update(Stripe::Subscription, test_data[:subscription].id, {
            pause_collection: { behavior: 'void' },
          }
          )

          allow($stdin).to receive(:gets).and_return("n\n")

          output = capture_stdout do
            command.call(subscription_id: test_data[:subscription].id)
          end

          expect(output).not_to match(/Subscription resumed successfully/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, test_data[:customer].id)
        end
      end

      context 'with invalid subscription ID' do
        it 'handles non-existent subscription gracefully' do
          allow(Stripe::Subscription).to receive(:retrieve).and_raise(
            Stripe::InvalidRequestError.new('No such subscription', 'subscription'),
          )

          expect do
            command.call(subscription_id: 'sub_nonexistent', yes: true)
          end.to output(/Error resuming subscription/).to_stdout
        end
      end

      context 'when billing not configured' do
        before do
          allow(command).to receive(:stripe_configured?).and_return(false)
        end

        it 'returns early without making API calls' do
          expect(Stripe::Subscription).not_to receive(:retrieve)
          command.call(subscription_id: 'sub_test', yes: true)
        end
      end
    end
  end

  describe Onetime::CLI::BillingSubscriptionsUpdateCommand do
    subject(:command) { described_class.new }

    describe '#call (update subscription)' do
      context 'with valid subscription ID' do
        it 'updates subscription quantity', :vcr do
          test_data = create_test_subscription

          allow($stdin).to receive(:gets).and_return("y\n")

          output = capture_stdout do
            command.call(subscription_id: test_data[:subscription].id, quantity: 3)
          end

          expect(output).to match(/Current quantity: 1/)
          expect(output).to match(/New quantity: 3/)
          expect(output).to match(/Subscription updated successfully/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, test_data[:customer].id)
        end

        it 'updates subscription price', :vcr do
          test_data = create_test_subscription

          # Create new price
          new_price = stripe_client.create(Stripe::Price, {
            unit_amount: 3000,
            currency: 'usd',
            recurring: { interval: 'month' },
            product: test_data[:product].id,
          }
          )

          allow($stdin).to receive(:gets).and_return("y\n")

          output = capture_stdout do
            command.call(subscription_id: test_data[:subscription].id, price: new_price.id)
          end

          expect(output).to match(/New price: #{new_price.id}/)
          expect(output).to match(/Subscription updated successfully/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, test_data[:customer].id)
        end

        it 'disables proration when specified', :vcr do
          test_data = create_test_subscription

          allow($stdin).to receive(:gets).and_return("y\n")

          output = capture_stdout do
            command.call(
              subscription_id: test_data[:subscription].id,
              quantity: 2,
              prorate: false,
            )
          end

          expect(output).to match(/Prorate: false/)
          expect(output).to match(/Subscription updated successfully/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, test_data[:customer].id)
        end

        it 'requires either price or quantity parameter', :vcr do
          test_data = create_test_subscription

          output = capture_stdout do
            command.call(subscription_id: test_data[:subscription].id)
          end

          expect(output).to match(/Must specify --price, --quantity, or --reactivate/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, test_data[:customer].id)
        end

        it 'aborts when user declines confirmation', :vcr do
          test_data = create_test_subscription

          allow($stdin).to receive(:gets).and_return("n\n")

          output = capture_stdout do
            command.call(subscription_id: test_data[:subscription].id, quantity: 2)
          end

          expect(output).not_to match(/Subscription updated successfully/)

          # Cleanup
          stripe_client.delete(Stripe::Customer, test_data[:customer].id)
        end
      end

      context 'with invalid subscription ID' do
        it 'handles non-existent subscription gracefully' do
          allow(Stripe::Subscription).to receive(:retrieve).and_raise(
            Stripe::InvalidRequestError.new('No such subscription', 'subscription'),
          )

          expect do
            command.call(subscription_id: 'sub_nonexistent', quantity: 2)
          end.to output(/Error updating subscription/).to_stdout
        end
      end

      context 'when billing not configured' do
        before do
          allow(command).to receive(:stripe_configured?).and_return(false)
        end

        it 'returns early without making API calls' do
          expect(Stripe::Subscription).not_to receive(:retrieve)
          command.call(subscription_id: 'sub_test', quantity: 2)
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
