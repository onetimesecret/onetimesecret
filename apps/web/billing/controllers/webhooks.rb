# apps/web/billing/controllers/webhooks.rb

require_relative 'base'
require 'stripe'

module Billing
  module Controllers
    class Webhooks
      include Controllers::Base

      # Handle Stripe webhook events
      #
      # Processes subscription lifecycle events and product/price updates.
      # Webhook signature is verified to ensure authenticity.
      #
      # POST /billing/webhook
      #
      # @return [HTTP 200] Success response
      # @return [HTTP 400] Invalid payload or signature
      #
      def handle_event
        payload = req.body.read
        sig_header = req.env['HTTP_STRIPE_SIGNATURE']

        unless sig_header
          billing_logger.warn "Webhook received without signature header"
          res.status = 400
          return json_error("Missing signature header", status: 400)
        end

        # Verify webhook signature
        webhook_secret = OT.conf.dig('billing', 'webhook_signing_secret')
        unless webhook_secret
          billing_logger.error "Webhook signing secret not configured"
          res.status = 500
          return json_error("Webhook not configured", status: 500)
        end

        begin
          event = Stripe::Webhook.construct_event(
            payload, sig_header, webhook_secret
          )
        rescue JSON::ParserError => ex
          billing_logger.error "Invalid webhook payload", {
            exception: ex
          }
          res.status = 400
          return json_error("Invalid payload", status: 400)
        rescue Stripe::SignatureVerificationError => ex
          billing_logger.error "Invalid webhook signature", {
            exception: ex
          }
          res.status = 400
          return json_error("Invalid signature", status: 400)
        end

        billing_logger.info "Webhook event received", {
          event_type: event.type,
          event_id: event.id
        }

        # Process event based on type
        case event.type
        when 'checkout.session.completed'
          handle_checkout_completed(event.data.object)
        when 'customer.subscription.updated'
          handle_subscription_updated(event.data.object)
        when 'customer.subscription.deleted'
          handle_subscription_deleted(event.data.object)
        when 'product.updated', 'price.updated'
          handle_product_or_price_updated(event.data.object)
        else
          billing_logger.debug "Unhandled webhook event type", {
            event_type: event.type
          }
        end

        res.status = 200
        json_success("Event processed")
      end

      private

      # Handle checkout.session.completed event
      #
      # Creates or updates organization subscription when checkout completes.
      # This is the primary subscription activation flow.
      #
      # @param session [Stripe::Checkout::Session] Completed checkout session
      def handle_checkout_completed(session)
        billing_logger.info "Processing checkout.session.completed", {
          session_id: session.id,
          customer_id: session.customer
        }

        # Expand subscription to get full details
        subscription = Stripe::Subscription.retrieve(session.subscription)
        metadata = subscription.metadata

        custid = metadata['custid']
        unless custid
          billing_logger.warn "No custid in subscription metadata", {
            subscription_id: subscription.id
          }
          return
        end

        # Load customer
        customer = Onetime::Customer.load(custid)
        unless customer
          billing_logger.error "Customer not found", {
            custid: custid
          }
          return
        end

        # Find or create default organization
        orgs = customer.organization_instances.to_a
        org = orgs.find { |o| o.is_default }

        unless org
          org = Onetime::Organization.create!(
            "#{customer.email}'s Workspace",
            customer,
            customer.email
          )
          org.is_default = true
          org.save
        end

        # Update organization with subscription details
        org.update_from_stripe_subscription(subscription)

        billing_logger.info "Checkout completed - organization subscription activated", {
          orgid: org.orgid,
          subscription_id: subscription.id,
          custid: custid
        }
      end

      # Handle customer.subscription.updated event
      #
      # Updates organization subscription status when subscription changes
      # (e.g., plan change, past_due, active, etc.)
      #
      # @param subscription [Stripe::Subscription] Updated subscription
      def handle_subscription_updated(subscription)
        billing_logger.info "Processing customer.subscription.updated", {
          subscription_id: subscription.id,
          status: subscription.status
        }

        # Find organization by subscription ID
        org = find_organization_by_subscription(subscription.id)

        unless org
          billing_logger.warn "Organization not found for subscription", {
            subscription_id: subscription.id
          }
          return
        end

        # Update organization with new subscription data
        org.update_from_stripe_subscription(subscription)

        billing_logger.info "Subscription updated", {
          orgid: org.orgid,
          subscription_id: subscription.id,
          status: subscription.status
        }
      end

      # Handle customer.subscription.deleted event
      #
      # Marks organization subscription as canceled when subscription ends.
      #
      # @param subscription [Stripe::Subscription] Deleted subscription
      def handle_subscription_deleted(subscription)
        billing_logger.info "Processing customer.subscription.deleted", {
          subscription_id: subscription.id
        }

        # Find organization by subscription ID
        org = find_organization_by_subscription(subscription.id)

        unless org
          billing_logger.warn "Organization not found for subscription", {
            subscription_id: subscription.id
          }
          return
        end

        # Clear billing fields
        org.clear_billing_fields

        billing_logger.info "Subscription deleted - organization marked as canceled", {
          orgid: org.orgid,
          subscription_id: subscription.id
        }
      end

      # Handle product.updated or price.updated events
      #
      # Refreshes plan cache when Stripe product or price data changes.
      #
      # @param object [Stripe::Product, Stripe::Price] Updated product or price
      def handle_product_or_price_updated(object)
        billing_logger.info "Processing product/price update - refreshing plan cache", {
          object_type: object.object,
          object_id: object.id
        }

        begin
          Billing::Models::PlanCache.refresh_from_stripe
          billing_logger.info "Plan cache refreshed successfully"
        rescue StandardError => ex
          billing_logger.error "Failed to refresh plan cache", {
            exception: ex,
            message: ex.message
          }
        end
      end

      # Find organization by Stripe subscription ID
      #
      # Uses unique index for O(1) lookup instead of O(n) iteration.
      # The stripe_subscription_id unique_index is defined in WithStripeAccount feature.
      #
      # @param subscription_id [String] Stripe subscription ID
      # @return [Onetime::Organization, nil] Organization or nil if not found
      def find_organization_by_subscription(subscription_id)
        # Use Familia auto-generated finder from unique_index for O(1) lookup
        Onetime::Organization.find_by_stripe_subscription_id(subscription_id)
      end

    end
  end
end
