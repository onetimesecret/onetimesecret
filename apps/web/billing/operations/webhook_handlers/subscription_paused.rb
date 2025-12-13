# apps/web/billing/operations/webhook_handlers/subscription_paused.rb
#
# frozen_string_literal: true

require_relative 'subscription_handler'

module Billing
  module Operations
    module WebhookHandlers
      # Handles customer.subscription.paused events.
      #
      # Updates organization status when subscription is paused.
      #
      class SubscriptionPaused < SubscriptionHandler
        def self.handles?(event_type)
          event_type == 'customer.subscription.paused'
        end

        protected

        def process
          with_organization do |org|
            org.subscription_status = 'paused'
            org.save

            billing_logger.info 'Subscription paused', {
              orgid: org.objid,
              subscription_id: @data_object.id,
            }
          end
        end
      end
    end
  end
end
