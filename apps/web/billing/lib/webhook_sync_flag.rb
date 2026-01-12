# apps/web/billing/lib/webhook_sync_flag.rb
#
# frozen_string_literal: true

module Billing
  # WebhookSyncFlag - Prevents sync loops between OTS and Stripe
  #
  # When a webhook updates billing_email from Stripe, we don't want the
  # subsequent save to trigger another sync back to Stripe. This utility
  # provides short-lived Redis flags to break the loop.
  #
  # ## Flow Without Flag (Loop)
  #
  #   1. User updates email in Stripe Portal
  #   2. Stripe sends customer.updated webhook
  #   3. OTS updates org.billing_email
  #   4. org.save triggers UpdateOrganization
  #   5. UpdateOrganization syncs email back to Stripe
  #   6. Stripe sends another customer.updated webhook
  #   7. ... infinite loop ...
  #
  # ## Flow With Flag (No Loop)
  #
  #   1. User updates email in Stripe Portal
  #   2. Stripe sends customer.updated webhook
  #   3. CustomerUpdated sets skip-sync flag
  #   4. OTS updates org.billing_email
  #   5. UpdateOrganization checks flag, skips Stripe sync
  #   6. Flag expires after 30 seconds
  #   7. Done - no loop
  #
  # ## Usage
  #
  #   # In webhook handler (before updating org)
  #   Billing::WebhookSyncFlag.set_skip_stripe_sync(org.extid)
  #
  #   # In UpdateOrganization (before Stripe sync)
  #   return if Billing::WebhookSyncFlag.skip_stripe_sync?(org.extid)
  #
  class WebhookSyncFlag
    # TTL for skip-sync flag (seconds)
    # Long enough for the save operation, short enough to not affect
    # subsequent legitimate updates from the user
    SKIP_SYNC_TTL = 30

    # Redis key prefix for skip-sync flags
    KEY_PREFIX = 'billing:skip_stripe_sync'

    class << self
      # Set flag to skip Stripe sync for an organization
      #
      # @param org_extid [String] Organization external ID
      # @return [Boolean] True if flag was set
      def set_skip_stripe_sync(org_extid)
        key = redis_key(org_extid)
        Familia.dbclient.setex(key, SKIP_SYNC_TTL, '1')
        true
      end

      # Check if Stripe sync should be skipped for an organization
      #
      # @param org_extid [String] Organization external ID
      # @return [Boolean] True if sync should be skipped
      def skip_stripe_sync?(org_extid)
        key = redis_key(org_extid)
        Familia.dbclient.exists?(key)
      end

      # Clear the skip-sync flag (for testing or manual override)
      #
      # @param org_extid [String] Organization external ID
      # @return [Boolean] True if flag was cleared
      def clear_skip_stripe_sync(org_extid)
        key = redis_key(org_extid)
        Familia.dbclient.del(key)
        true
      end

      private

      def redis_key(org_extid)
        "#{KEY_PREFIX}:#{org_extid}"
      end
    end
  end
end
