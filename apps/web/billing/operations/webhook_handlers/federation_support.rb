# apps/web/billing/operations/webhook_handlers/federation_support.rb
#
# frozen_string_literal: true

require_relative '../../metadata'

module Billing
  module Operations
    module WebhookHandlers
      # FederationSupport - Configuration detection and non-match observability
      # for cross-region subscription federation.
      #
      # Lives apart from {SubscriptionFederation} because it is needed by
      # subscription handlers that do NOT federate (TrialWillEnd) as well as
      # those that do. {SubscriptionHandler} includes it, so every subscription
      # handler reports a non-match the same way.
      #
      # ## Why the no-match line exists
      #
      # A subscription webhook that matches no organization in this region is
      # the failure mode operators care about most: someone paid and their
      # account was not upgraded. Both non-match paths used to be effectively
      # silent — the non-federation fallback logged a bare warning carrying only
      # the subscription id, and the federated path logged nothing at all before
      # storing a pending record. The first signal was a support ticket, weeks
      # after the purchase.
      #
      # The event name is a single stable string so it can be grepped and
      # alerted on, with the correlation fields in the structured payload:
      #
      #   federation.no_match region=CA email_hash=a1b2c3d4... customer=cus_x
      #     subscription=sub_y event_type=customer.subscription.created
      #     reason=no_org_match federation_enabled=true pending_stored=true
      #
      module FederationSupport
        include Onetime::LoggerMethods

        # Greppable event name. Alerts key on this string — keep it stable.
        NO_MATCH_EVENT = 'federation.no_match'

        # Federated path: neither an owner org (by stripe_customer_id) nor any
        # federated org (by email_hash) exists in this region.
        REASON_NO_ORG_MATCH = 'no_org_match'

        # Non-federated path: no org in this region is linked to this
        # subscription id.
        REASON_NO_SUBSCRIPTION_MATCH = 'no_subscription_id_match'

        # Region label used when Billing::Metadata.current_region cannot answer
        # (regions enabled with no jurisdiction set — a misconfiguration). The
        # no-match line must never raise on its way out; the ConfigError is
        # already surfaced by every non-logging caller of current_region.
        UNKNOWN_REGION = 'unknown'

        private

        # Whether cross-region federation is configured for this deployment.
        #
        # Federation needs FEDERATION_SECRET to compute the HMAC email hashes
        # it matches on, so the secret's presence is the feature flag. Checks
        # the environment first, then site config.
        #
        # @return [Boolean]
        #
        def federation_enabled?
          secret = ENV.fetch('FEDERATION_SECRET', nil)

          # Fall back to config if env var not set and OT.conf is available
          if secret.to_s.empty? && defined?(OT) && OT.respond_to?(:conf) && OT.conf
            secret = OT.conf.dig('site', 'federation_secret')
          end

          !secret.to_s.empty?
        end

        # Emit the structured non-match warning.
        #
        # The email_hash is logged in full rather than truncated to a prefix
        # (as the divergence warnings do) because correlation is the entire
        # point here: the same value keys the PendingFederatedSubscription
        # record, the Stripe customer metadata, and the org's email_hash index,
        # so an operator can follow one grep across regions. The hash is a
        # truncated HMAC-SHA256 under a deployment secret — one-way, and
        # already at rest in Redis and in Stripe metadata.
        #
        # @param subscription [Stripe::Subscription] Subscription from the event
        # @param reason [String] One of the REASON_* constants
        # @param email_hash [String, nil] Hash matched on, when federation ran
        # @param pending_stored [Boolean] Whether a pending record was stored
        # @return [void]
        #
        def log_federation_no_match(subscription:, reason:, email_hash: nil, pending_stored: false)
          billing_logger.warn NO_MATCH_EVENT,
            {
              region: federation_region_label,
              email_hash: email_hash,
              customer: (subscription.customer if subscription.respond_to?(:customer)),
              subscription: (subscription.id if subscription.respond_to?(:id)),
              event_type: @event&.type,
              reason: reason,
              federation_enabled: federation_enabled?,
              pending_stored: pending_stored,
            }
        end

        # Current region, or UNKNOWN_REGION when it cannot be determined.
        #
        # @return [String]
        #
        def federation_region_label
          Billing::Metadata.current_region
        rescue StandardError
          UNKNOWN_REGION
        end
      end
    end
  end
end
