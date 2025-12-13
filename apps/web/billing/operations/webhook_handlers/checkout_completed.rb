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

        # External ID format: prefix + UUID (e.g., ur019b1598-b0ec-760a-85ae-a1391283a1dc)
        EXTID_PATTERN = /\A[a-z]{2}[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

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

          custid = metadata['custid']
          unless custid
            billing_logger.warn 'No custid in subscription metadata', {
              subscription_id: subscription.id,
            }
            return :skipped
          end

          unless valid_identifier?(custid)
            billing_logger.warn 'Invalid custid format in subscription metadata', {
              subscription_id: subscription.id,
              custid: custid.to_s[0, 50], # Truncate for safety
            }
            return :skipped
          end

          customer = load_customer(custid)
          return :not_found unless customer

          org = find_or_create_organization(customer)
          org.update_from_stripe_subscription(subscription)

          billing_logger.info 'Checkout completed - organization subscription activated', {
            orgid: org.objid,
            subscription_id: subscription.id,
            custid: custid,
          }

          # Future: Send welcome notification unless skip_notifications?
          :success
        end

        private

        def valid_identifier?(value)
          return false unless value.is_a?(String) && value.length <= 255

          value.match?(UUID_PATTERN) || value.match?(EXTID_PATTERN) || value.match?(EMAIL_PATTERN)
        end

        def load_customer(custid)
          customer = Onetime::Customer.load(custid)
          unless customer
            billing_logger.error 'Customer not found', { custid: custid }
          end
          customer
        end

        def find_or_create_organization(customer)
          orgs = customer.organization_instances.to_a
          org  = orgs.find { |o| o.is_default }

          unless org
            org            = Onetime::Organization.create!(
              "#{customer.email}'s Workspace",
              customer,
              customer.email,
            )
            org.is_default = true
            org.save
          end

          org
        end
      end
    end
  end
end
