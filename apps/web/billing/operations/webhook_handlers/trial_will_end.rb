# apps/web/billing/operations/webhook_handlers/trial_will_end.rb
#
# frozen_string_literal: true

require_relative 'subscription_handler'

module Billing
  module Operations
    module WebhookHandlers
      # Handles customer.subscription.trial_will_end events.
      #
      # Logs notification that trial is ending soon (3 days before trial end).
      # Future: Send notification to customer about upcoming trial end.
      #
      class TrialWillEnd < SubscriptionHandler
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

            # Future: Send trial ending notification unless skip_notifications?
          end
        end
      end
    end
  end
end
