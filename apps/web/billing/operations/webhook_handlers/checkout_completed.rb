# apps/web/billing/operations/webhook_handlers/checkout_completed.rb
#
# frozen_string_literal: true

require_relative 'base_handler'

module Billing
  module Operations
    module WebhookHandlers
      # Handles checkout.session.completed events.
      #
      # Creates or updates organization subscription when checkout completes.
      # Skips one-time payments (sessions without subscriptions).
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
            billing_logger.info 'Checkout session has no subscription (one-time payment)', {
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
            billing_logger.warn 'No customer_extid in subscription metadata', {
              subscription_id: subscription.id,
            }
            return :skipped
          end

          unless valid_identifier?(customer_extid)
            billing_logger.warn 'Invalid customer_extid format in subscription metadata', {
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
            billing_logger.info 'Checkout already processed (idempotent replay)', {
              orgid: org.objid,
              subscription_id: subscription.id,
            }
            return :success
          end

          org.update_from_stripe_subscription(subscription)

          billing_logger.info 'Checkout completed - organization subscription activated', {
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
          org = orgs.find { |o| o.is_default }
          return org if org

          # 4. Create default org (shouldn't happen - checkout requires org)
          billing_logger.warn 'Creating default org during checkout (unexpected)', { customer_extid: customer.extid }
          org = Onetime::Organization.create!(
            "#{customer.email}'s Workspace",
            customer,
            customer.email,
          )
          org.is_default = true
          org.save
          org
        end
      end
    end
  end
end
