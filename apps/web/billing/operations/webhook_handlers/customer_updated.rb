# apps/web/billing/operations/webhook_handlers/customer_updated.rb
#
# frozen_string_literal: true

require_relative 'base_handler'

module Billing
  module Operations
    module WebhookHandlers
      # Handles customer.updated events.
      #
      # Syncs customer metadata changes from Stripe to local customer record.
      # Currently logs email discrepancies but doesn't auto-update.
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
            billing_logger.debug 'Organization not found for Stripe customer', {
              stripe_customer_id: stripe_customer.id,
            }
            return :not_found
          end

          check_email_sync(org, stripe_customer)

          billing_logger.info 'Customer update processed', {
            orgid: org.objid,
            stripe_customer_id: stripe_customer.id,
          }

          :success
        end

        private

        def check_email_sync(org, stripe_customer)
          return unless stripe_customer.email && org.owner

          owner = org.owner
          return if owner.email == stripe_customer.email

          billing_logger.info 'Customer email changed in Stripe', {
            orgid: org.objid,
            stripe_customer_id: stripe_customer.id,
            old_email: owner.email,
            new_email: stripe_customer.email,
          }
          # Note: We don't auto-update email as it may require verification
        end
      end
    end
  end
end
