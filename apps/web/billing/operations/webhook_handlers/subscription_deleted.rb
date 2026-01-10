# apps/web/billing/operations/webhook_handlers/subscription_deleted.rb
#
# frozen_string_literal: true

require_relative 'subscription_handler'

module Billing
  module Operations
    module WebhookHandlers
      # Handles customer.subscription.deleted events.
      #
      # Marks organization subscription as canceled when subscription ends.
      #
      class SubscriptionDeleted < SubscriptionHandler
        def self.handles?(event_type)
          event_type == 'customer.subscription.deleted'
        end

        protected

        def process
          with_organization do |org|
            org.clear_billing_fields

            billing_logger.info 'Subscription deleted - organization marked as canceled',
              {
                orgid: org.objid,
                subscription_id: @data_object.id,
              }
          end
        end
      end
    end
  end
end
