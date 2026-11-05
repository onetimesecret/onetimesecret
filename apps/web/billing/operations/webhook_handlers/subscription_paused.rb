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

          # Check if federation is enabled (FEDERATION_SECRET configured)
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
        # Not gated on the owner's mailbox proof: it only removes access. For
        # a deferred workspace the pending record is refreshed as well, so
        # the claim that runs after verification does not apply an earlier
        # active snapshot (#4754 review, F3).
        #
        # For every other workspace the pause is a direct sync like any other
        # federated update: it records the sync marker before the save and
        # retires a pending record the workspace now supersedes after it, as
        # update_federated_org and clear_federated_org do. Without that, an
        # active record stored before the workspace had its email hash
        # survived the pause, and the next claim retry (a repeat verification
        # of the owner) replayed its snapshot over the pause (#4754 review).
        # Never on the deferred branch: a sync marker drawn after
        # defer_federated_update would mark the record it just refreshed as
        # superseded, and retire_for! does not count the workspace it retires
        # for as waiting, so the record would be destroyed.
        #
        # @param org [Onetime::Organization] Organization to update
        # @param subscription [Stripe::Subscription] Stripe subscription
        def pause_federated_org(org, subscription)
          deferred = federation_deferred_for?(org)
          if deferred
            defer_federated_update(org, subscription)
          else
            mark_federated_sync!(org)
          end

          org.subscription_status = 'paused'
          org.save
          discard_superseded_pending(org) unless deferred
        end
      end
    end
  end
end
