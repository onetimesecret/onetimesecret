# apps/web/billing/operations/process_webhook_event.rb
#
# frozen_string_literal: true

#
# Processes Stripe webhook events by dispatching to type-specific handlers.
# Extracted from Webhooks controller for reuse in CLI replay and testing.
#
# This operation handles:
# - checkout.session.completed: Creates/updates organization subscriptions
# - customer.subscription.updated: Updates subscription status
# - customer.subscription.deleted: Clears billing fields
# - product/price updates: Refreshes plan cache
#

module Billing
  module Operations
    class ProcessWebhookEvent
      include Onetime::LoggerMethods

      # @param event [Stripe::Event] The Stripe webhook event to process
      # @param context [Hash] Optional context (e.g., { replay: true, skip_notifications: true })
      def initialize(event:, context: {})
        @event = event
        @context = context
      end

      # Executes the webhook event processing
      #
      # Dispatches to appropriate handler based on event type.
      # Raises exceptions on failure so callers can handle rollback.
      #
      # @return [Boolean] true if event was handled, false if unhandled type
      # @raise [StandardError] If event processing fails
      def call
        case @event.type
        when 'checkout.session.completed'
          handle_checkout_completed(@event.data.object)
          true
        when 'customer.subscription.updated'
          handle_subscription_updated(@event.data.object)
          true
        when 'customer.subscription.deleted'
          handle_subscription_deleted(@event.data.object)
          true
        when 'product.created', 'product.updated', 'price.created', 'price.updated', 'plan.created', 'plan.updated'
          handle_product_or_price_updated(@event.data.object)
          true
        else
          billing_logger.debug 'Unhandled webhook event type', {
            event_type: @event.type,
          }
          false
        end
      end

      private

      # Check if this is a replay (for conditional behavior like notifications)
      def replay?
        @context[:replay] == true
      end

      # Check if notifications should be skipped
      def skip_notifications?
        @context[:skip_notifications] == true
      end

      # Handle checkout.session.completed event
      #
      # Creates or updates organization subscription when checkout completes.
      #
      # @param session [Stripe::Checkout::Session] Completed checkout session
      def handle_checkout_completed(session)
        billing_logger.info 'Processing checkout.session.completed', {
          session_id: session.id,
          customer_id: session.customer,
          replay: replay?,
        }

        # Check if session has a subscription (skip one-time payments)
        unless session.subscription
          billing_logger.info 'Checkout session has no subscription (one-time payment)', {
            session_id: session.id,
            mode: session.mode,
          }
          return
        end

        # Expand subscription to get full details
        subscription = Stripe::Subscription.retrieve(session.subscription)
        metadata     = subscription.metadata

        custid = metadata['custid']
        unless custid
          billing_logger.warn 'No custid in subscription metadata', {
            subscription_id: subscription.id,
          }
          return
        end

        # Load customer
        customer = Onetime::Customer.load(custid)
        unless customer
          billing_logger.error 'Customer not found', {
            custid: custid,
          }
          return
        end

        # Find or create default organization
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

        # Update organization with subscription details
        org.update_from_stripe_subscription(subscription)

        billing_logger.info 'Checkout completed - organization subscription activated', {
          orgid: org.objid,
          subscription_id: subscription.id,
          custid: custid,
        }

        # Future: Send welcome notification unless skip_notifications?
        # send_welcome_notification(customer, org) unless skip_notifications?
      end

      # Handle customer.subscription.updated event
      #
      # Updates organization subscription status when subscription changes.
      #
      # @param subscription [Stripe::Subscription] Updated subscription
      def handle_subscription_updated(subscription)
        billing_logger.info 'Processing customer.subscription.updated', {
          subscription_id: subscription.id,
          status: subscription.status,
          replay: replay?,
        }

        org = find_organization_by_subscription(subscription.id)

        unless org
          billing_logger.warn 'Organization not found for subscription', {
            subscription_id: subscription.id,
          }
          return
        end

        org.update_from_stripe_subscription(subscription)

        billing_logger.info 'Subscription updated', {
          orgid: org.objid,
          subscription_id: subscription.id,
          status: subscription.status,
        }
      end

      # Handle customer.subscription.deleted event
      #
      # Marks organization subscription as canceled when subscription ends.
      #
      # @param subscription [Stripe::Subscription] Deleted subscription
      def handle_subscription_deleted(subscription)
        billing_logger.info 'Processing customer.subscription.deleted', {
          subscription_id: subscription.id,
          replay: replay?,
        }

        org = find_organization_by_subscription(subscription.id)

        unless org
          billing_logger.warn 'Organization not found for subscription', {
            subscription_id: subscription.id,
          }
          return
        end

        org.clear_billing_fields

        billing_logger.info 'Subscription deleted - organization marked as canceled', {
          orgid: org.objid,
          subscription_id: subscription.id,
        }
      end

      # Handle product.updated or price.updated events
      #
      # Refreshes plan cache when Stripe product or price data changes.
      # Note: Errors are logged but not re-raised to avoid failing the webhook
      # for non-critical cache refresh operations.
      #
      # @param object [Stripe::Product, Stripe::Price] Updated product or price
      def handle_product_or_price_updated(object)
        billing_logger.info 'Processing product/price update - refreshing plan cache', {
          object_type: object.object,
          object_id: object.id,
          replay: replay?,
        }

        begin
          Billing::Plan.refresh_from_stripe
          billing_logger.info 'Plan cache refreshed successfully'
        rescue StandardError => ex
          billing_logger.error 'Failed to refresh plan cache', {
            exception: ex,
            message: ex.message,
          }
          # Don't re-raise - cache refresh failure shouldn't fail the webhook
        end
      end

      # Find organization by Stripe subscription ID
      #
      # @param subscription_id [String] Stripe subscription ID
      # @return [Onetime::Organization, nil] Organization or nil if not found
      def find_organization_by_subscription(subscription_id)
        Onetime::Organization.find_by_stripe_subscription_id(subscription_id)
      end
    end
  end
end
