# frozen_string_literal: true

require 'spec_helper'
require 'cli/cli_spec_helper'
require_relative '../../support/billing_spec_helper'
require_relative '../../support/shared_examples/cli_safety'

RSpec.describe 'Billing subscriptions CLI commands', type: :cli do
  let(:subscription_id) { 'sub_test123' }
  let(:subscription) { mock_stripe_subscription(id: subscription_id) }

  before do
    # Mock billing configuration
    billing_config = double('BillingConfig',
      enabled?: true,
      stripe_key: 'sk_test_123456'
    )
    allow(OT).to receive(:billing_config).and_return(billing_config)

    # Set Stripe API key
    Stripe.api_key = 'sk_test_123456'
  end

  describe 'billing subscriptions' do
    context 'when listing subscriptions' do
      let(:subscriptions) { double('ListObject', data: [
        mock_stripe_subscription(id: 'sub_001', customer: 'cus_001', status: 'active'),
        mock_stripe_subscription(id: 'sub_002', customer: 'cus_002', status: 'past_due'),
        mock_stripe_subscription(id: 'sub_003', customer: 'cus_003', status: 'canceled')
      ]) }

      before do
        allow(Stripe::Subscription).to receive(:list).and_return(subscriptions)
      end

      it 'lists all subscriptions' do
        output = run_cli_command_quietly('billing', 'subscriptions')

        expect(output[:stdout]).to include('sub_001')
        expect(output[:stdout]).to include('sub_002')
        expect(output[:stdout]).to include('sub_003')
        expect(output[:stdout]).to include('Total: 3 subscription(s)')
        expect(last_exit_code).to eq(0)
      end

      it 'displays subscription details in formatted table' do
        output = run_cli_command_quietly('billing', 'subscriptions')

        expect(output[:stdout]).to match(/ID.*CUSTOMER.*STATUS.*PERIOD END/)
        expect(output[:stdout]).to include('active')
        expect(output[:stdout]).to include('past_due')
        expect(output[:stdout]).to include('canceled')
      end

      it 'shows available statuses in output' do
        output = run_cli_command_quietly('billing', 'subscriptions')

        expect(output[:stdout]).to include('Statuses: active, past_due, canceled, incomplete, trialing, unpaid')
      end

      it 'filters by status' do
        expect(Stripe::Subscription).to receive(:list).with(hash_including(
          status: 'active',
          limit: 100
        )).and_return(subscriptions)

        run_cli_command_quietly('billing', 'subscriptions', '--status', 'active')
      end

      it 'filters by customer' do
        expect(Stripe::Subscription).to receive(:list).with(hash_including(
          customer: 'cus_001',
          limit: 100
        )).and_return(subscriptions)

        run_cli_command_quietly('billing', 'subscriptions', '--customer', 'cus_001')
      end

      it 'respects limit parameter' do
        expect(Stripe::Subscription).to receive(:list).with(hash_including(
          limit: 50
        )).and_return(subscriptions)

        run_cli_command_quietly('billing', 'subscriptions', '--limit', '50')
      end

      context 'when no subscriptions exist' do
        let(:empty_list) { double('ListObject', data: []) }

        before do
          allow(Stripe::Subscription).to receive(:list).and_return(empty_list)
        end

        it 'displays no subscriptions message' do
          output = run_cli_command_quietly('billing', 'subscriptions')

          expect(output[:stdout]).to include('No subscriptions found')
          expect(last_exit_code).to eq(0)
        end
      end

      context 'when Stripe API fails' do
        before do
          allow(Stripe::Subscription).to receive(:list).and_raise(
            Stripe::APIConnectionError.new('Network error')
          )
        end

        it 'displays error message' do
          output = run_cli_command_quietly('billing', 'subscriptions')

          expect(output[:stdout]).to include('Error fetching subscriptions')
          expect(output[:stdout]).to include('Network error')
        end
      end
    end
  end

  describe 'billing subscriptions cancel' do
    before do
      allow(Stripe::Subscription).to receive(:retrieve).and_return(subscription)

      # Mock StripeClient
      stripe_client = instance_double('Billing::StripeClient')
      allow(Billing::StripeClient).to receive(:new).and_return(stripe_client)
      allow(stripe_client).to receive(:retrieve).and_return(subscription)
      allow(stripe_client).to receive(:update).and_return(subscription)
      allow(stripe_client).to receive(:delete).and_return(subscription)
    end

    context 'canceling at period end (default)' do
      before do
        allow($stdin).to receive(:gets).and_return("y\n")
      end

      it 'displays subscription details' do
        output = run_cli_command_quietly('billing', 'subscriptions', 'cancel', subscription_id)

        expect(output[:stdout]).to include('Cancel subscription')
        expect(output[:stdout]).to include(subscription_id)
        expect(output[:stdout]).to include(subscription.customer)
        expect(output[:stdout]).to include(subscription.status)
      end

      it 'shows cancel mode as "At period end"' do
        output = run_cli_command_quietly('billing', 'subscriptions', 'cancel', subscription_id)

        expect(output[:stdout]).to include('Cancel mode: At period end')
      end

      it 'prompts for confirmation' do
        output = run_cli_command_quietly('billing', 'subscriptions', 'cancel', subscription_id)

        expect(output[:stdout]).to include('Cancel subscription at period end? (y/n):')
      end

      it 'cancels subscription at period end when confirmed' do
        canceled_sub = mock_stripe_subscription(
          id: subscription_id,
          cancel_at_period_end: true,
          status: 'active'
        )

        stripe_client = Billing::StripeClient.new
        expect(stripe_client).to receive(:update).with(
          Stripe::Subscription,
          subscription_id,
          hash_including(cancel_at_period_end: true)
        ).and_return(canceled_sub)

        output = run_cli_command_quietly('billing', 'subscriptions', 'cancel', subscription_id)

        expect(output[:stdout]).to include('Subscription canceled successfully')
        expect(last_exit_code).to eq(0)
      end

      it 'aborts when user declines' do
        allow($stdin).to receive(:gets).and_return("n\n")

        stripe_client = Billing::StripeClient.new
        expect(stripe_client).not_to receive(:update)
        expect(stripe_client).not_to receive(:delete)

        output = run_cli_command_quietly('billing', 'subscriptions', 'cancel', subscription_id)

        expect(output[:stdout]).not_to include('Subscription canceled successfully')
      end

      it 'skips confirmation with --yes flag' do
        expect($stdin).not_to receive(:gets)

        output = run_cli_command_quietly('billing', 'subscriptions', 'cancel',
          subscription_id, '--yes')

        expect(output[:stdout]).to include('Subscription canceled successfully')
      end
    end

    context 'canceling immediately' do
      before do
        allow($stdin).to receive(:gets).and_return("y\n")
      end

      it 'shows cancel mode as "IMMEDIATE"' do
        output = run_cli_command_quietly('billing', 'subscriptions', 'cancel',
          subscription_id, '--immediately')

        expect(output[:stdout]).to include('Cancel mode: IMMEDIATE')
      end

      it 'prompts for immediate cancellation confirmation' do
        output = run_cli_command_quietly('billing', 'subscriptions', 'cancel',
          subscription_id, '--immediately')

        expect(output[:stdout]).to include('Cancel subscription IMMEDIATELY? (y/n):')
      end

      it 'deletes subscription immediately when confirmed' do
        canceled_sub = mock_stripe_subscription(
          id: subscription_id,
          status: 'canceled',
          canceled_at: Time.now.to_i
        )

        stripe_client = Billing::StripeClient.new
        expect(stripe_client).to receive(:delete).with(
          Stripe::Subscription,
          subscription_id
        ).and_return(canceled_sub)

        output = run_cli_command_quietly('billing', 'subscriptions', 'cancel',
          subscription_id, '--immediately')

        expect(output[:stdout]).to include('Subscription canceled successfully')
        expect(output[:stdout]).to include('status: canceled')
      end
    end

    context 'with dry-run mode' do
      it 'shows what would happen without executing' do
        expect($stdin).not_to receive(:gets)

        stripe_client = Billing::StripeClient.new
        expect(stripe_client).not_to receive(:update)
        expect(stripe_client).not_to receive(:delete)

        output = run_cli_command_quietly('billing', 'subscriptions', 'cancel',
          subscription_id, '--dry-run')

        expect(output[:stdout]).to include('[DRY RUN]')
        expect(output[:stdout]).to include('Cancel subscription')
        expect(last_exit_code).to eq(0)
      end

      it 'shows immediate cancellation in dry-run' do
        output = run_cli_command_quietly('billing', 'subscriptions', 'cancel',
          subscription_id, '--immediately', '--dry-run')

        expect(output[:stdout]).to include('[DRY RUN]')
        expect(output[:stdout]).to include('IMMEDIATE')
      end
    end

    context 'with error scenarios' do
      before do
        allow($stdin).to receive(:gets).and_return("y\n")
      end

      it 'handles subscription not found' do
        stripe_client = Billing::StripeClient.new
        allow(stripe_client).to receive(:retrieve).and_raise(
          Stripe::InvalidRequestError.new('No such subscription', 'subscription')
        )

        output = run_cli_command_quietly('billing', 'subscriptions', 'cancel', 'sub_invalid')

        expect(output[:stdout]).to include('Error')
        expect(output[:stdout]).to include('No such subscription')
      end

      it 'handles already canceled subscription' do
        stripe_client = Billing::StripeClient.new
        allow(stripe_client).to receive(:update).and_raise(
          Stripe::InvalidRequestError.new('Subscription already canceled', 'subscription')
        )

        output = run_cli_command_quietly('billing', 'subscriptions', 'cancel', subscription_id)

        expect(output[:stdout]).to include('Subscription cancellation failed')
        expect(output[:stdout]).to include('already canceled')
      end

      it 'handles network errors' do
        stripe_client = Billing::StripeClient.new
        allow(stripe_client).to receive(:update).and_raise(
          Stripe::APIConnectionError.new('Connection failed')
        )

        output = run_cli_command_quietly('billing', 'subscriptions', 'cancel', subscription_id)

        expect(output[:stdout]).to include('Error')
      end

      it 'provides helpful error messages and suggestions' do
        stripe_client = Billing::StripeClient.new
        allow(stripe_client).to receive(:update).and_raise(
          Stripe::InvalidRequestError.new('Invalid subscription', 'subscription')
        )

        output = run_cli_command_quietly('billing', 'subscriptions', 'cancel', subscription_id)

        expect(output[:stdout]).to include('Verify subscription ID is correct')
        expect(output[:stdout]).to include('Review Stripe dashboard')
      end
    end
  end

  describe 'billing subscriptions pause' do
    before do
      allow(Stripe::Subscription).to receive(:retrieve).and_return(subscription)
      allow(Stripe::Subscription).to receive(:update).and_return(subscription)
    end

    context 'with active subscription' do
      let(:active_sub) { mock_stripe_subscription(id: subscription_id, pause_collection: nil) }

      before do
        allow(Stripe::Subscription).to receive(:retrieve).and_return(active_sub)
        allow($stdin).to receive(:gets).and_return("y\n")
      end

      it 'displays subscription details' do
        output = run_cli_command_quietly('billing', 'subscriptions', 'pause', subscription_id)

        expect(output[:stdout]).to include("Subscription: #{subscription_id}")
        expect(output[:stdout]).to include(active_sub.customer)
        expect(output[:stdout]).to include(active_sub.status)
      end

      it 'prompts for confirmation' do
        output = run_cli_command_quietly('billing', 'subscriptions', 'pause', subscription_id)

        expect(output[:stdout]).to include('Pause subscription? (y/n):')
      end

      it 'pauses subscription when confirmed' do
        paused_sub = mock_stripe_subscription(
          id: subscription_id,
          pause_collection: { behavior: 'void' },
          status: 'active'
        )

        expect(Stripe::Subscription).to receive(:update).with(
          subscription_id,
          hash_including(pause_collection: { behavior: 'void' })
        ).and_return(paused_sub)

        output = run_cli_command_quietly('billing', 'subscriptions', 'pause', subscription_id)

        expect(output[:stdout]).to include('Subscription paused successfully')
        expect(output[:stdout]).to include('Billing paused, access continues')
        expect(last_exit_code).to eq(0)
      end

      it 'skips confirmation with --yes flag' do
        expect($stdin).not_to receive(:gets)

        output = run_cli_command_quietly('billing', 'subscriptions', 'pause',
          subscription_id, '--yes')

        expect(output[:stdout]).to include('Subscription paused successfully')
      end
    end

    context 'with already paused subscription' do
      let(:paused_sub) do
        mock_stripe_subscription(
          id: subscription_id,
          pause_collection: { behavior: 'void' }
        )
      end

      before do
        allow(Stripe::Subscription).to receive(:retrieve).and_return(paused_sub)
      end

      it 'exits early with message' do
        expect(Stripe::Subscription).not_to receive(:update)

        output = run_cli_command_quietly('billing', 'subscriptions', 'pause', subscription_id)

        expect(output[:stdout]).to include('already paused')
      end
    end

    context 'with error scenarios' do
      before do
        allow($stdin).to receive(:gets).and_return("y\n")
      end

      it 'handles subscription not found' do
        allow(Stripe::Subscription).to receive(:retrieve).and_raise(
          Stripe::InvalidRequestError.new('No such subscription', 'subscription')
        )

        output = run_cli_command_quietly('billing', 'subscriptions', 'pause', 'sub_invalid')

        expect(output[:stdout]).to include('Error pausing subscription')
      end

      it 'handles API errors' do
        allow(Stripe::Subscription).to receive(:update).and_raise(
          Stripe::APIConnectionError.new('Network error')
        )

        output = run_cli_command_quietly('billing', 'subscriptions', 'pause', subscription_id)

        expect(output[:stdout]).to include('Error pausing subscription')
      end
    end
  end

  describe 'billing subscriptions resume' do
    before do
      allow(Stripe::Subscription).to receive(:retrieve).and_return(subscription)
      allow(Stripe::Subscription).to receive(:update).and_return(subscription)
    end

    context 'with paused subscription' do
      let(:paused_sub) do
        mock_stripe_subscription(
          id: subscription_id,
          pause_collection: { behavior: 'void' }
        )
      end

      before do
        allow(Stripe::Subscription).to receive(:retrieve).and_return(paused_sub)
        allow($stdin).to receive(:gets).and_return("y\n")
      end

      it 'displays subscription details including paused status' do
        output = run_cli_command_quietly('billing', 'subscriptions', 'resume', subscription_id)

        expect(output[:stdout]).to include("Subscription: #{subscription_id}")
        expect(output[:stdout]).to include('Currently paused: Yes')
      end

      it 'prompts for confirmation' do
        output = run_cli_command_quietly('billing', 'subscriptions', 'resume', subscription_id)

        expect(output[:stdout]).to include('Resume subscription? (y/n):')
      end

      it 'resumes subscription when confirmed' do
        resumed_sub = mock_stripe_subscription(id: subscription_id, pause_collection: nil)

        expect(Stripe::Subscription).to receive(:update).with(
          subscription_id,
          hash_including(pause_collection: nil)
        ).and_return(resumed_sub)

        output = run_cli_command_quietly('billing', 'subscriptions', 'resume', subscription_id)

        expect(output[:stdout]).to include('Subscription resumed successfully')
        expect(output[:stdout]).to include('Billing will resume on next period')
        expect(last_exit_code).to eq(0)
      end

      it 'skips confirmation with --yes flag' do
        expect($stdin).not_to receive(:gets)

        output = run_cli_command_quietly('billing', 'subscriptions', 'resume',
          subscription_id, '--yes')

        expect(output[:stdout]).to include('Subscription resumed successfully')
      end
    end

    context 'with active subscription' do
      let(:active_sub) { mock_stripe_subscription(id: subscription_id, pause_collection: nil) }

      before do
        allow(Stripe::Subscription).to receive(:retrieve).and_return(active_sub)
      end

      it 'exits early with message' do
        expect(Stripe::Subscription).not_to receive(:update)

        output = run_cli_command_quietly('billing', 'subscriptions', 'resume', subscription_id)

        expect(output[:stdout]).to include('not paused')
      end
    end

    context 'with error scenarios' do
      before do
        allow($stdin).to receive(:gets).and_return("y\n")
      end

      it 'handles subscription not found' do
        allow(Stripe::Subscription).to receive(:retrieve).and_raise(
          Stripe::InvalidRequestError.new('No such subscription', 'subscription')
        )

        output = run_cli_command_quietly('billing', 'subscriptions', 'resume', 'sub_invalid')

        expect(output[:stdout]).to include('Error resuming subscription')
      end

      it 'handles API errors' do
        paused_sub = mock_stripe_subscription(
          id: subscription_id,
          pause_collection: { behavior: 'void' }
        )
        allow(Stripe::Subscription).to receive(:retrieve).and_return(paused_sub)
        allow(Stripe::Subscription).to receive(:update).and_raise(
          Stripe::APIConnectionError.new('Network error')
        )

        output = run_cli_command_quietly('billing', 'subscriptions', 'resume', subscription_id)

        expect(output[:stdout]).to include('Error resuming subscription')
      end
    end
  end

  describe 'billing subscriptions update' do
    before do
      allow(Stripe::Subscription).to receive(:retrieve).and_return(subscription)
      allow(Stripe::Subscription).to receive(:update).and_return(subscription)
      allow($stdin).to receive(:gets).and_return("y\n")
    end

    context 'updating price' do
      it 'displays current and new configuration' do
        output = run_cli_command_quietly('billing', 'subscriptions', 'update',
          subscription_id, '--price', 'price_new123')

        expect(output[:stdout]).to include('Current subscription:')
        expect(output[:stdout]).to include('Current price:')
        expect(output[:stdout]).to include('New configuration:')
        expect(output[:stdout]).to include('New price: price_new123')
      end

      it 'updates subscription price with proration by default' do
        expect(Stripe::Subscription).to receive(:update).with(
          subscription_id,
          hash_including(
            items: array_including(hash_including(price: 'price_new123')),
            proration_behavior: 'create_prorations'
          )
        )

        run_cli_command_quietly('billing', 'subscriptions', 'update',
          subscription_id, '--price', 'price_new123')
      end

      it 'supports disabling proration' do
        expect(Stripe::Subscription).to receive(:update).with(
          subscription_id,
          hash_including(proration_behavior: 'none')
        )

        run_cli_command_quietly('billing', 'subscriptions', 'update',
          subscription_id, '--price', 'price_new123', '--no-prorate')
      end
    end

    context 'updating quantity' do
      it 'displays current and new quantity' do
        output = run_cli_command_quietly('billing', 'subscriptions', 'update',
          subscription_id, '--quantity', '5')

        expect(output[:stdout]).to include('Current quantity:')
        expect(output[:stdout]).to include('New quantity: 5')
      end

      it 'updates subscription quantity' do
        expect(Stripe::Subscription).to receive(:update).with(
          subscription_id,
          hash_including(
            items: array_including(hash_including(quantity: 5))
          )
        )

        run_cli_command_quietly('billing', 'subscriptions', 'update',
          subscription_id, '--quantity', '5')
      end
    end

    context 'updating both price and quantity' do
      it 'updates both values' do
        expect(Stripe::Subscription).to receive(:update).with(
          subscription_id,
          hash_including(
            items: array_including(hash_including(
              price: 'price_new123',
              quantity: 10
            ))
          )
        )

        run_cli_command_quietly('billing', 'subscriptions', 'update',
          subscription_id, '--price', 'price_new123', '--quantity', '10')
      end
    end

    context 'with confirmation prompt' do
      it 'prompts before updating' do
        output = run_cli_command_quietly('billing', 'subscriptions', 'update',
          subscription_id, '--price', 'price_new123')

        expect(output[:stdout]).to include('Proceed? (y/n):')
      end

      it 'aborts when user declines' do
        allow($stdin).to receive(:gets).and_return("n\n")

        expect(Stripe::Subscription).not_to receive(:update)

        run_cli_command_quietly('billing', 'subscriptions', 'update',
          subscription_id, '--price', 'price_new123')
      end
    end

    context 'with validation' do
      it 'requires at least one parameter' do
        output = run_cli_command_quietly('billing', 'subscriptions', 'update', subscription_id)

        expect(output[:stdout]).to include('Must specify --price or --quantity')
      end
    end

    context 'with error scenarios' do
      it 'handles subscription not found' do
        allow(Stripe::Subscription).to receive(:retrieve).and_raise(
          Stripe::InvalidRequestError.new('No such subscription', 'subscription')
        )

        output = run_cli_command_quietly('billing', 'subscriptions', 'update',
          subscription_id, '--price', 'price_new123')

        expect(output[:stdout]).to include('Error updating subscription')
      end

      it 'handles invalid price ID' do
        allow(Stripe::Subscription).to receive(:update).and_raise(
          Stripe::InvalidRequestError.new('No such price', 'price')
        )

        output = run_cli_command_quietly('billing', 'subscriptions', 'update',
          subscription_id, '--price', 'price_invalid')

        expect(output[:stdout]).to include('Error updating subscription')
      end

      it 'handles invalid quantity' do
        allow(Stripe::Subscription).to receive(:update).and_raise(
          Stripe::InvalidRequestError.new('Quantity must be positive', 'quantity')
        )

        output = run_cli_command_quietly('billing', 'subscriptions', 'update',
          subscription_id, '--quantity', '-1')

        expect(output[:stdout]).to include('Error updating subscription')
      end
    end

    context 'with successful update' do
      it 'displays success message with status' do
        output = run_cli_command_quietly('billing', 'subscriptions', 'update',
          subscription_id, '--price', 'price_new123')

        expect(output[:stdout]).to include('Subscription updated successfully')
        expect(output[:stdout]).to include("Status: #{subscription.status}")
      end
    end
  end
end
