# apps/web/billing/operations/webhook_handlers/subscription_handler.rb
#
# frozen_string_literal: true

require_relative 'base_handler'
require_relative 'federation_support'

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
        include FederationSupport

        abstract_handler! # Intermediate base class, not registered

        protected

        # Yields organization if found, returns :not_found otherwise.
        # Auto-returns :success after block execution.
        #
        # @yield [Onetime::Organization] The organization
        # @return [Symbol] :success if found and processed, :not_found otherwise
        def with_organization
          org = find_organization_by_subscription(@data_object.id)

          unless org
            billing_logger.warn 'Organization not found for subscription',
              {
                subscription_id: @data_object.id,
                event_type: @event.type,
              }

            # An unmatched subscription event means someone's account is not
            # in the state they paid for. Emit the greppable, alertable line
            # alongside the warning above so the drop is visible at webhook
            # time rather than at support-ticket time.
            log_federation_no_match(
              subscription: @data_object,
              reason: FederationSupport::REASON_NO_SUBSCRIPTION_MATCH,
            )

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
