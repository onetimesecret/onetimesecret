# apps/web/billing/operations/webhook_handlers/trial_will_end.rb
#
# frozen_string_literal: true

require_relative 'subscription_handler'

module Billing
  module Operations
    module WebhookHandlers
      # Handles customer.subscription.trial_will_end events.
      #
      # Logs that the trial is ending soon (Stripe fires this ~3 days before
      # trial end) and emails the organization owner a heads-up.
      #
      class TrialWillEnd < SubscriptionHandler
        SECONDS_PER_DAY = 86_400

        def self.handles?(event_type)
          event_type == 'customer.subscription.trial_will_end'
        end

        protected

        def process
          with_organization do |org|
            billing_logger.info 'Trial ending soon',
              {
                orgid: org.objid,
                subscription_id: @data_object.id,
                trial_end: @data_object.trial_end,
              }

            notify_trial_expiring(org) unless skip_notifications?
          end
        end

        private

        # Best-effort trial-ending notification to the organization owner. A
        # delivery failure must not fail webhook processing (which would trigger
        # a Stripe retry).
        def notify_trial_expiring(org)
          owner     = org.owner
          trial_end = @data_object.trial_end
          return unless owner&.email && trial_end

          ends_at = Time.at(trial_end).utc
          days_remaining = [((ends_at - Time.now.utc) / SECONDS_PER_DAY).ceil, 0].max

          Onetime::Jobs::Publisher.enqueue_email(
            :trial_expiring,
            {
              email_address: owner.email,
              plan_name: org.planid,
              trial_ends_at: ends_at.iso8601,
              days_remaining: days_remaining,
              locale: (owner.respond_to?(:locale) ? owner.locale : nil) || OT.default_locale,
            },
            fallback: :async_thread,
          )
        rescue StandardError => ex
          billing_logger.error 'Failed to send trial_expiring email',
            { orgid: org.objid, error: ex.message }
        end
      end
    end
  end
end
