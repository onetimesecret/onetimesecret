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
      include BillingSafetyHelpers

      desc 'Cancel a subscription'

      argument :subscription_id, required: true, desc: 'Subscription ID (sub_xxx)'

      option :immediately, type: :boolean, default: false,
        desc: 'Cancel immediately instead of at period end'
      option :yes, type: :boolean, default: false,
        desc: 'Assume yes to prompts'
      option :dry_run, type: :boolean, default: false,
        desc: 'Preview operation without executing'

      def call(subscription_id:, immediately: false, yes: false, dry_run: false, **)
        boot_application!

        return unless stripe_configured?

        # Retrieve subscription to validate it exists
        begin
          subscription = Stripe::Subscription.retrieve(subscription_id)
        rescue Stripe::InvalidRequestError => ex
          display_error(ex, [
            'Verify the subscription ID is correct',
            'Check if subscription exists: bin/ots billing subscriptions',
          ])
          return
        end

        # Display operation summary
        cancellation_mode = immediately ? 'IMMEDIATE' : 'at period end'
        display_operation_summary(
          'Subscription Cancellation',
          {
            'Subscription ID' => subscription.id,
            'Customer' => subscription.customer,
            'Current Status' => subscription.status,
            'Period End' => format_timestamp(subscription.current_period_end),
            'Cancellation Mode' => cancellation_mode,
          },
          dry_run: dry_run
        )

        # Confirm destructive operation
        message = immediately ? 'This will IMMEDIATELY cancel the subscription' : 'This will cancel at period end'
        return unless confirm_operation(message, auto_yes: yes)

        # Execute or preview operation
        canceled = execute_with_dry_run(dry_run: dry_run) do
          if immediately
            Stripe::Subscription.cancel(subscription_id)
          else
            Stripe::Subscription.update(subscription_id, {
              cancel_at_period_end: true
            })
          end
        end

        return if dry_run

        # Display success
        display_success('Subscription canceled successfully', {
          'Status' => canceled.status,
          'Canceled At' => canceled.canceled_at ? format_timestamp(canceled.canceled_at) : 'N/A',
          'Will End At' => canceled.cancel_at_period_end ? format_timestamp(canceled.current_period_end) : 'N/A',
        })

      rescue Stripe::StripeError => ex
        display_error(ex, [
          'Check Stripe Dashboard for subscription status',
          'Verify API key permissions',
        ])
      end
    end
  end
end

Onetime::CLI.register 'billing subscriptions cancel', Onetime::CLI::BillingSubscriptionsCancelCommand
