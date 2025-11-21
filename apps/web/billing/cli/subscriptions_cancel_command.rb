# apps/web/billing/cli/subscriptions_cancel_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require_relative 'safety_helpers'

module Onetime
  module CLI
    # Cancel subscription
    class BillingSubscriptionsCancelCommand < Command
      include BillingHelpers
      include SafetyHelpers

      desc 'Cancel a subscription'

      argument :subscription_id, required: true, desc: 'Subscription ID (sub_xxx)'

      option :immediately, type: :boolean, default: false,
        desc: 'Cancel immediately instead of at period end'
      option :yes, type: :boolean, default: false,
        desc: 'Assume yes to prompts'
      option :dry_run, type: :boolean, default: false,
        desc: 'Preview operation without making changes'

      def call(subscription_id:, immediately: false, yes: false, dry_run: false, **)
        boot_application!

        return unless stripe_configured?

        # Retrieve subscription to show current state
        subscription = Stripe::Subscription.retrieve(subscription_id)

        # Display operation summary
        display_operation_summary(
          'Cancel subscription',
          {
            subscription_id: subscription.id,
            customer_id: subscription.customer,
            current_status: subscription.status,
            period_end: format_timestamp(subscription.current_period_end),
            cancel_mode: immediately ? 'IMMEDIATE' : 'At period end'
          },
          dry_run: dry_run
        )

        # Return early if dry run
        return if dry_run

        # Confirm destructive operation
        confirmation_msg = immediately ? 'Cancel subscription IMMEDIATELY?' : 'Cancel subscription at period end?'
        return unless confirm_operation(confirmation_msg, auto_yes: yes)

        # Cancel subscription using StripeClient for retry logic
        require_relative '../lib/stripe_client'
        stripe_client = Billing::StripeClient.new

        canceled = if immediately
          stripe_client.delete(Stripe::Subscription, subscription_id)
        else
          stripe_client.update(Stripe::Subscription, subscription_id, {
            cancel_at_period_end: true
          })
        end

        # Display success with details
        details = {
          subscription_id: canceled.id,
          status: canceled.status
        }
        details[:canceled_at] = format_timestamp(canceled.canceled_at) if canceled.canceled_at
        details[:will_end_at] = format_timestamp(canceled.current_period_end) if canceled.cancel_at_period_end

        display_success('Subscription canceled successfully', details)

      rescue Stripe::StripeError => e
        display_error(
          format_stripe_error('Subscription cancellation failed', e),
          [
            'Verify subscription ID is correct',
            'Check subscription is not already canceled',
            'Review Stripe dashboard for details'
          ]
        )
      end
    end
  end
end

Onetime::CLI.register 'billing subscriptions cancel', Onetime::CLI::BillingSubscriptionsCancelCommand
