# apps/web/billing/operations/webhook_handlers/customer_updated.rb
#
# frozen_string_literal: true

require_relative 'base_handler'

module Billing
  module Operations
    module WebhookHandlers
      # Handles customer.updated events.
      #
      # Syncs customer changes from Stripe to local Organization record.
      #
      # ## Two-Way Email Sync
      #
      # Billing email can be updated from two sources:
      # 1. OTS Settings page -> Stripe (via UpdateOrganization logic)
      # 2. Stripe Customer Portal -> OTS (via this webhook handler)
      #
      # The Stripe Customer email is the billing contact email, which is
      # independent of the user's account email. This allows customers to
      # use a different email for billing (e.g., accounts@company.com).
      #
      # ## Important: Billing Email vs Account Email
      #
      # - billing_email: Stripe Customer email, used for invoices and billing
      # - contact_email: Same as billing_email (kept in sync for consistency)
      # - owner.email: User's account email (NOT synced from Stripe)
      #
      class CustomerUpdated < BaseHandler
        def self.handles?(event_type)
          event_type == 'customer.updated'
        end

        protected

        def process
          stripe_customer = @data_object

          org = Onetime::Organization.find_by_stripe_customer_id(stripe_customer.id)

          unless org
            billing_logger.debug 'Organization not found for Stripe customer',
              {
                stripe_event_id: @event.id,
                stripe_customer_id: stripe_customer.id,
              }
            return :not_found
          end

          sync_billing_email(org, stripe_customer)

          billing_logger.info 'Customer update processed',
            {
              stripe_event_id: @event.id,
              orgid: org.objid,
              stripe_customer_id: stripe_customer.id,
            }

          :success
        end

        private

        # Sync billing email from Stripe to Organization
        #
        # Updates both billing_email and contact_email fields to keep them
        # consistent. The Stripe Customer email is authoritative for billing.
        #
        # @param org [Onetime::Organization] Organization to update
        # @param stripe_customer [Stripe::Customer] Stripe customer object
        def sync_billing_email(org, stripe_customer)
          stripe_email = stripe_customer.email
          return if stripe_email.to_s.empty?

          # Check if email actually changed
          current_billing_email = org.billing_email.to_s
          return if current_billing_email == stripe_email

          billing_logger.info 'Syncing billing email from Stripe',
            {
              stripe_event_id: @event.id,
              org_extid: org.extid,
              stripe_customer_id: stripe_customer.id,
              old_email: current_billing_email,
              new_email: stripe_email,
            }

          # Set skip-sync flag to prevent the OTS->Stripe sync from triggering
          # when this webhook-initiated change is detected by UpdateOrganization
          Billing::WebhookSyncFlag.set_skip_stripe_sync(org.extid)

          # Update both billing_email and contact_email for consistency
          org.billing_email  = stripe_email
          org.contact_email  = stripe_email
          org.updated        = Familia.now.to_i
          org.save

          billing_logger.info 'Billing email synced from Stripe',
            {
              stripe_event_id: @event.id,
              org_extid: org.extid,
              stripe_customer_id: stripe_customer.id,
              new_email: stripe_email,
            }
        rescue StandardError => ex
          # If save fails, clear the flag to avoid blocking subsequent updates
          Billing::WebhookSyncFlag.clear_skip_stripe_sync(org.extid)
          billing_logger.error 'Failed to save organization during billing email sync',
            {
              stripe_event_id: @event.id,
              org_extid: org.extid,
              error: ex.message,
            }
          # Re-raise to ensure the webhook processing is marked as failed
          raise
        end
      end
    end
  end
end
