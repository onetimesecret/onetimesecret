# apps/web/billing/operations/webhook_handlers/checkout_completed.rb
#
# frozen_string_literal: true

require_relative 'base_handler'
require 'onetime/utils/email_hash'

module Billing
  module Operations
    module WebhookHandlers
      # Handles checkout.session.completed events.
      #
      # Creates or updates organization subscription when checkout completes.
      # Skips one-time payments (sessions without subscriptions).
      #
      # ## Federation: Email Hash in Stripe Metadata
      #
      # At checkout completion, this handler sets the `email_hash` in Stripe
      # customer metadata for cross-region subscription federation. The hash:
      #
      # - Is computed from the Stripe customer's email using HMAC-SHA256
      # - Is IMMUTABLE once set (never updated even if email changes)
      # - Enables subscription benefit federation across regions
      # - Prevents email-swap attacks (hash computed at creation, not at use)
      #
      # @see Onetime::Utils::EmailHash
      # @see SubscriptionFederation
      #
      class CheckoutCompleted < BaseHandler
        # UUID format: 8-4-4-4-12 hex chars (e.g., 019b1598-b0ec-760a-85ae-a1391283a1dc)
        UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

        # External ID format: 2-letter prefix + base36 (25 alphanumeric chars)
        # Derived deterministically from objid via Familia's ExternalIdentifier feature
        # e.g., urasakn4f2nl2ew0pq275ky8j3v
        EXTID_PATTERN = /\A[a-z]{2}[a-z0-9]{25}\z/i

        # Basic email format (legacy custid format, pre-v0.22)
        EMAIL_PATTERN = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

        private_constant :UUID_PATTERN, :EXTID_PATTERN, :EMAIL_PATTERN

        def self.handles?(event_type)
          event_type == 'checkout.session.completed'
        end

        protected

        def process
          session = @data_object

          # Skip one-time payments
          unless session.subscription
            billing_logger.info 'Checkout session has no subscription (one-time payment)',
              {
                session_id: session.id,
                mode: session.mode,
              }
            return :skipped
          end

          # Expand subscription to get full details
          subscription = Stripe::Subscription.retrieve(session.subscription)
          metadata     = subscription.metadata

          customer_extid = metadata['customer_extid']
          unless customer_extid
            billing_logger.warn 'No customer_extid in subscription metadata',
              {
                subscription_id: subscription.id,
              }
            return :skipped
          end

          unless valid_identifier?(customer_extid)
            billing_logger.warn 'Invalid customer_extid format in subscription metadata',
              {
                subscription_id: subscription.id,
                customer_extid: customer_extid.to_s[0, 50], # Truncate for safety
              }
            return :skipped
          end

          customer = load_customer(customer_extid)
          return :not_found unless customer

          # Find the specific org that initiated checkout (from subscription metadata)
          # Fall back to customer's default org for legacy/manual subscriptions
          org = find_target_organization(customer, metadata)
          return :not_found unless org

          # Idempotency: Check if already processed (same org + same subscription)
          if org.stripe_subscription_id == subscription.id
            billing_logger.info 'Checkout already processed (idempotent replay)',
              {
                orgid: org.objid,
                subscription_id: subscription.id,
              }
            return :success
          end

          org.update_from_stripe_subscription(subscription)

          # Set email_hash in Stripe customer metadata for federation
          # This enables cross-region subscription benefit sharing
          stripe_customer_id = @data_object&.customer
          stripe_hash        = set_stripe_customer_email_hash(stripe_customer_id)

          # Ensure organization has email_hash computed from billing_email
          ensure_org_email_hash!(org)
          warn_if_email_hash_divergence(org, stripe_hash)

          if stripe_hash && org.email_hash.to_s.length.positive? && stripe_hash != org.email_hash
            billing_logger.warn 'Email hash divergence: Stripe and org hashes differ — federation matching will fail',
              {
                orgid: org.objid,
                stripe_customer_id: stripe_customer_id,
                stripe_hash_prefix: stripe_hash[0..7],
                org_hash_prefix: org.email_hash[0..7],
              }
          end

          billing_logger.info 'Checkout completed - organization subscription activated',
            {
              orgid: org.objid,
              subscription_id: subscription.id,
              customer_extid: customer_extid,
            }

          # Future: Send welcome notification unless skip_notifications?
          :success
        end

        private

        def valid_identifier?(value)
          return false unless value.is_a?(String) && value.length <= 255

          value.match?(UUID_PATTERN) || value.match?(EXTID_PATTERN) || value.match?(EMAIL_PATTERN)
        end

        def load_customer(customer_extid)
          customer = Onetime::Customer.find_by_extid(customer_extid)
          unless customer
            billing_logger.error 'Customer not found', { customer_extid: customer_extid }
          end
          customer
        end

        # Set email_hash in Stripe customer metadata for cross-region federation
        #
        # CRITICAL: This hash is computed at subscription creation and MUST NEVER
        # be updated, even if the customer's email changes. This immutability is
        # the primary defense against email-swap attacks.
        #
        # The hash enables subscription benefits to flow to organizations in other
        # regions that share the same billing email (matched by hash).
        #
        # @param stripe_customer_id [String] Stripe customer ID
        # @return [String, nil] The email_hash written to Stripe, or nil on skip/failure
        #
        def set_stripe_customer_email_hash(stripe_customer_id)
          return nil if stripe_customer_id.to_s.empty?

          begin
            stripe_customer = Stripe::Customer.retrieve(stripe_customer_id)

            # Check if email_hash already exists (immutability - never overwrite)
            existing_hash = stripe_customer.metadata['email_hash']
            if existing_hash.to_s.length.positive?
              billing_logger.debug 'Stripe customer already has email_hash (preserving immutability)',
                {
                  stripe_customer_id: stripe_customer_id,
                  hash_prefix: existing_hash[0..7],
                }
              return existing_hash
            end

            # Compute hash from Stripe customer email
            email = stripe_customer.email
            if email.to_s.empty?
              billing_logger.warn 'Stripe customer has no email - cannot set email_hash',
                { stripe_customer_id: stripe_customer_id }
              return nil
            end

            email_hash = Onetime::Utils::EmailHash.compute(email)
            if email_hash.nil?
              billing_logger.warn 'Could not compute email_hash',
                { stripe_customer_id: stripe_customer_id }
              return nil
            end

            # Fetch existing metadata and merge (Stripe replaces all metadata on update)
            existing_metadata = stripe_customer.metadata.to_h
            merged_metadata   = existing_metadata.merge(
              'email_hash' => email_hash,
              'email_hash_created_at' => Time.now.to_i.to_s,
              'home_region' => OT.conf.dig(:site, :region) || 'default',
            )

            Stripe::Customer.update(stripe_customer_id, metadata: merged_metadata)

            billing_logger.info 'Set email_hash in Stripe customer metadata',
              {
                stripe_customer_id: stripe_customer_id,
                hash_prefix: email_hash[0..7],
              }

            email_hash
          rescue Stripe::StripeError, Onetime::Problem => ex
            # Log but don't fail checkout - federation is a secondary concern
            billing_logger.error 'Failed to set email_hash in Stripe metadata',
              {
                stripe_customer_id: stripe_customer_id,
                error: ex.message,
              }
            nil
          end
        end

        # Warn if the email hash stored in Stripe customer metadata diverges
        # from the organization's locally computed hash. A mismatch means
        # cross-region federated matching will silently fail for this org.
        #
        # @param org [Onetime::Organization] Organization to check
        # @param stripe_customer_id [String] Stripe customer ID
        # @return [void]
        #
        def warn_if_email_hash_divergence(org, stripe_hash)
          return if org.email_hash.to_s.empty?
          return if stripe_hash.to_s.empty?

          return if stripe_hash == org.email_hash

          billing_logger.warn 'Email hash divergence: Stripe customer and org hashes differ (federation will not match)',
            {
              orgid: org.extid,
              org_hash_prefix: org.email_hash[0..7],
              stripe_hash_prefix: stripe_hash[0..7],
            }
        rescue Stripe::StripeError => ex
          billing_logger.warn 'Could not verify email hash consistency', { error: ex.message }
        end

        # Ensure organization has computed email_hash
        #
        # Computes and saves email_hash if not already present. This ensures
        # the organization can be found by federated lookups.
        #
        # @param org [Onetime::Organization] Organization to update
        # @return [void]
        #
        def ensure_org_email_hash!(org)
          return if org.email_hash.to_s.length.positive?
          return if org.billing_email.to_s.empty?

          org.compute_email_hash!
          org.save

          billing_logger.debug 'Computed organization email_hash',
            {
              orgid: org.objid,
              hash_prefix: org.email_hash[0..7],
            }
        rescue StandardError => ex
          # Log but don't fail checkout
          billing_logger.error 'Failed to compute organization email_hash',
            {
              orgid: org.objid,
              error: ex.message,
            }
        end

        # Find the target organization for this checkout
        #
        # Priority:
        # 1. orgid from subscription metadata (explicit org that initiated checkout)
        # 2. Org already linked to this Stripe customer (idempotent replay)
        # 3. Customer's default org (legacy/fallback)
        # 4. Create new default org (shouldn't happen in normal flow)
        #
        # @param customer [Onetime::Customer] The customer
        # @param metadata [Stripe::StripeObject] Subscription metadata
        # @return [Onetime::Organization, nil] The target organization
        def find_target_organization(customer, metadata)
          # 1. Explicit org from metadata (most reliable)
          orgid = metadata['orgid']
          if orgid
            org = Onetime::Organization.load(orgid)
            if org
              billing_logger.debug 'Found org from subscription metadata', { orgid: orgid }
              return org
            end
            billing_logger.warn 'orgid in metadata not found', { orgid: orgid }
          end

          # 2. Org already linked to Stripe customer (idempotent replay case)
          stripe_customer_id = @data_object&.customer
          if stripe_customer_id
            org = Onetime::Organization.find_by_stripe_customer_id(stripe_customer_id)
            if org
              billing_logger.debug 'Found org by stripe_customer_id', { stripe_customer_id: stripe_customer_id }
              return org
            end
          end

          # 3. Customer's default org
          orgs = customer.organization_instances.to_a
          org  = orgs.find { |o| o.is_default }
          return org if org

          # 4. Create default org (self-healing fallback - shouldn't happen, checkout requires org)
          # See: apps/web/auth/operations/create_default_workspace.rb
          billing_logger.warn 'Creating default org during checkout (unexpected)', { customer_extid: customer.extid }
          Onetime::Organization.create!(
            "#{customer.email}'s Workspace",
            customer,
            customer.email,
            is_default: true,
          )
        end
      end
    end
  end
end
