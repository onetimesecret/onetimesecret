# apps/web/billing/operations/webhook_handlers/subscription_updated.rb
#
# frozen_string_literal: true

require_relative 'subscription_handler'

module Billing
  module Operations
    module WebhookHandlers
      # Handles customer.subscription.updated events.
      #
      # Updates organization subscription status when subscription changes.
      #
      class SubscriptionUpdated < SubscriptionHandler
        def self.handles?(event_type)
          event_type == 'customer.subscription.updated'
        end

        protected

        def process
          with_organization do |org|
            org.update_from_stripe_subscription(@data_object)

            billing_logger.info 'Subscription updated',
              {
                orgid: org.objid,
                subscription_id: @data_object.id,
                status: @data_object.status,
              }
          end
        end
      end
    end
  end
end
