# apps/web/billing/operations/webhook_handlers/subscription_updated.rb
#
# frozen_string_literal: true

require_relative 'subscription_handler'
require_relative 'subscription_federation'

module Billing
  module Operations
    module WebhookHandlers
      # Handles customer.subscription.updated events.
      #
      # Updates organization subscription status when subscription changes.
      # Supports cross-region federation via email hash matching.
      #
      # Two-path matching:
      # - Path 1 (Owner): Organization with matching stripe_customer_id
      # - Path 2 (Federated): Organizations with matching email_hash but no stripe_customer_id
      #
      class SubscriptionUpdated < SubscriptionHandler
        include SubscriptionFederation

        def self.handles?(event_type)
          event_type == 'customer.subscription.updated'
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
              old_plan = org.planid
              org.update_from_stripe_subscription(subscription)
              org.save
              new_plan = org.planid

              billing_logger.info 'Subscription updated (owner)',
                {
                  orgid: org.objid,
                  subscription_id: subscription.id,
                  status: subscription.status,
                }

              notify_subscription_changed(org, old_plan, new_plan) unless skip_notifications?
            else
              first_time = update_federated_org(org, subscription)

              billing_logger.info 'Subscription updated (federated)',
                {
                  orgid: org.objid,
                  subscription_id: subscription.id,
                  status: subscription.status,
                  first_federation: first_time,
                }
            end
          end
        end

        private

        # Standard processing without federation
        def process_without_federation(subscription)
          with_organization do |org|
            old_plan = org.planid
            org.update_from_stripe_subscription(subscription)
            new_plan = org.planid

            billing_logger.info 'Subscription updated',
              {
                orgid: org.objid,
                subscription_id: subscription.id,
                status: subscription.status,
              }

            notify_subscription_changed(org, old_plan, new_plan) unless skip_notifications?
          end
        end

        # Best-effort notification to the organization owner that their plan
        # changed. Only sent when the plan id actually changed: subscription
        # .updated also fires for renewals, status flips, quantity and payment
        # method changes, and emailing on every one of those would be spam.
        # Upgrade vs downgrade can't be reliably inferred from plan ids, so the
        # template renders the neutral "change" copy. A delivery failure must
        # not fail webhook processing (which would trigger a Stripe retry).
        def notify_subscription_changed(org, old_plan, new_plan)
          return if old_plan == new_plan

          owner = org.owner
          return unless owner&.email

          Onetime::Jobs::Publisher.enqueue_email(
            :subscription_changed,
            {
              email_address: owner.email,
              old_plan: old_plan,
              new_plan: new_plan,
              effective_date: Time.now.utc.iso8601,
              locale: (owner.respond_to?(:locale) ? owner.locale : nil) || OT.default_locale,
            },
            fallback: :async_thread,
          )
        rescue StandardError => ex
          billing_logger.error 'Failed to send subscription_changed email',
            { orgid: org.objid, error: ex.message }
        end

        # Check if federation is enabled
        def federation_enabled?
          # Check environment variable first
          secret = ENV.fetch('FEDERATION_SECRET', nil)

          # Fall back to config if env var not set and OT.conf is available
          if secret.to_s.empty? && defined?(OT) && OT.respond_to?(:conf) && OT.conf
            secret = OT.conf.dig('site', 'federation_secret')
          end

          !secret.to_s.empty?
        end
      end
    end
  end
end
