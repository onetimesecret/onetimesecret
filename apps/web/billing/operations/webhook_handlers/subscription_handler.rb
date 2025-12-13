# apps/web/billing/operations/webhook_handlers/subscription_handler.rb
#
# frozen_string_literal: true

require_relative 'base_handler'

module Billing
  module Operations
    module WebhookHandlers
      # Base class for subscription-related webhook handlers.
      #
      # Provides shared organization lookup logic via #with_organization,
      # which handles the common pattern of:
      # 1. Finding organization by subscription ID
      # 2. Logging warning if not found
      # 3. Yielding organization to block
      # 4. Auto-returning :success after block
      #
      # @example
      #   class SubscriptionPaused < SubscriptionHandler
      #     def self.handles?(event_type)
      #       event_type == 'customer.subscription.paused'
      #     end
      #
      #     protected
      #
      #     def process
      #       with_organization do |org|
      #         org.subscription_status = 'paused'
      #         org.save
      #       end
      #     end
      #   end
      #
      class SubscriptionHandler < BaseHandler
        protected

        # Yields organization if found, returns :not_found otherwise.
        # Auto-returns :success after block execution.
        #
        # @yield [Onetime::Organization] The organization
        # @return [Symbol] :success if found and processed, :not_found otherwise
        def with_organization
          org = find_organization_by_subscription(@data_object.id)

          unless org
            billing_logger.warn 'Organization not found for subscription', {
              subscription_id: @data_object.id,
              event_type: @event.type,
            }
            return :not_found
          end

          yield org
          :success
        end

        private

        def find_organization_by_subscription(subscription_id)
          Onetime::Organization.find_by_stripe_subscription_id(subscription_id)
        end
      end
    end
  end
end
