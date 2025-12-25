# apps/web/billing/cli/subscriptions_cancel_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require_relative 'safety_helpers'
require_relative '../lib/stripe_client'

module Onetime
  module CLI
    # Cancel subscription
    class BillingSubscriptionsCancelCommand < Command
      include BillingHelpers
      include SafetyHelpers

      desc 'Cancel a subscription'

      argument :subscription_id, required: true, desc: 'Subscription ID (sub_xyz)'

      option :immediately, type: :boolean, default: false,
        desc: 'Cancel immediately instead of at period end'
      option :yes, type: :boolean, default: false,
        desc: 'Assume yes to prompts'
      option :dry_run, type: :boolean, default: false,
        desc: 'Preview operation without making changes'

      def call(subscription_id:, immediately: false, yes: false, dry_run: false, **)
        boot_application!

        return unless stripe_configured?

        # Use StripeClient for all Stripe API calls (includes retry logic)
        stripe_client = Billing::StripeClient.new

        # Retrieve subscription to show current state
        subscription = stripe_client.retrieve(Stripe::Subscription, subscription_id)

        # Display operation summary
        # Note: current_period_end is now at the subscription item level in Stripe API 2025-11-17.clover
        period_end = subscription.items&.data&.first&.current_period_end
        display_operation_summary(
          'Cancel subscription',
          {
            subscription_id: subscription.id,
            customer_id: subscription.customer,
            current_status: subscription.status,
            period_end: period_end ? format_timestamp(period_end) : 'N/A',
            cancel_mode: immediately ? 'IMMEDIATE' : 'At period end',
          },
          dry_run: dry_run,
        )

        # Return early if dry run
        return if dry_run

        # Confirm destructive operation
        confirmation_msg = immediately ? 'Cancel subscription IMMEDIATELY?' : 'Cancel subscription at period end?'
        return unless confirm_operation(confirmation_msg, auto_yes: yes)

        # Cancel subscription

        canceled = if immediately
          stripe_client.delete(Stripe::Subscription, subscription_id)
        else
          stripe_client.update(Stripe::Subscription, subscription_id, {
            cancel_at_period_end: true,
          }
          )
        end

        # Display success with details
        details               = {
          subscription_id: canceled.id,
          status: canceled.status,
        }
        details[:canceled_at] = format_timestamp(canceled.canceled_at) if canceled.canceled_at
        # NOTE: current_period_end is now at the subscription item level in Stripe API 2025-11-17.clover
        if canceled.cancel_at_period_end
          item_period_end       = canceled.items&.data&.first&.current_period_end
          details[:will_end_at] = format_timestamp(item_period_end) if item_period_end
        end

        display_success('Subscription cancelled successfully', details)
      rescue Stripe::StripeError => ex
        display_error(
          format_stripe_error('Subscription cancellation failed', ex),
          [
            'Verify subscription ID is correct',
            'Check subscription is not already canceled',
            'Review Stripe dashboard for details',
          ],
        )
      end
    end
  end
end

Onetime::CLI.register 'billing subscriptions cancel', Onetime::CLI::BillingSubscriptionsCancelCommand
