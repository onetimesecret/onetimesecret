# apps/web/billing/operations/webhook_handlers/subscription_paused.rb
#
# frozen_string_literal: true

require_relative 'subscription_handler'
require_relative 'subscription_federation'

module Billing
  module Operations
    module WebhookHandlers
      # Handles customer.subscription.paused events.
      #
      # Updates organization status when subscription is paused.
      # Supports cross-region federation via email hash matching.
      #
      # Two-path matching:
      # - Path 1 (Owner): Organization with matching stripe_customer_id
      # - Path 2 (Federated): Organizations with matching email_hash but no stripe_customer_id
      #
      class SubscriptionPaused < SubscriptionHandler
        include SubscriptionFederation

        def self.handles?(event_type)
          event_type == 'customer.subscription.paused'
        end

        protected

        def process
          subscription = @data_object

          # Check if federation is enabled (FEDERATION_HMAC_SECRET configured)
          # Fall back to standard processing if not
          unless federation_enabled?
            return process_without_federation(subscription)
          end

          process_with_federation(subscription) do |org, is_owner|
            if is_owner
              org.subscription_status = 'paused'
              org.save

              billing_logger.info 'Subscription paused (owner)',
                {
                  orgid: org.objid,
                  subscription_id: subscription.id,
                }
            else
              pause_federated_org(org, subscription)

              billing_logger.info 'Subscription paused (federated)',
                {
                  orgid: org.objid,
                  subscription_id: subscription.id,
                }
            end
          end
        end

        private

        # Standard processing without federation
        def process_without_federation(subscription)
          with_organization do |org|
            org.subscription_status = 'paused'
            org.save

            billing_logger.info 'Subscription paused',
              {
                orgid: org.objid,
                subscription_id: subscription.id,
              }
          end
        end

        # Pause federated organization subscription
        #
        # @param org [Onetime::Organization] Organization to update
        # @param subscription [Stripe::Subscription] Stripe subscription (for logging)
        def pause_federated_org(org, _subscription)
          org.subscription_status = 'paused'
          org.save
        end

        # Check if federation is enabled
        def federation_enabled?
          # Check environment variable first
          secret = ENV.fetch('FEDERATION_HMAC_SECRET', nil)

          # Fall back to config if env var not set and OT.conf is available
          if secret.to_s.empty? && defined?(OT) && OT.respond_to?(:conf) && OT.conf
            secret = OT.conf.dig('features', 'regions', 'federation_hmac_secret')
          end

          !secret.to_s.empty?
        end
      end
    end
  end
end
