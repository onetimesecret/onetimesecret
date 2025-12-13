# apps/web/billing/operations/webhook_handlers/catalog_updated.rb
#
# frozen_string_literal: true

require_relative 'base_handler'

module Billing
  module Operations
    module WebhookHandlers
      # Handles product/price/plan update events.
      #
      # Refreshes plan cache when Stripe catalog data changes.
      # Errors are logged but not re-raised to avoid failing the webhook
      # for non-critical cache refresh operations.
      #
      class CatalogUpdated < BaseHandler
        CATALOG_EVENTS = %w[
          product.created product.updated
          price.created price.updated
          plan.created plan.updated
        ].freeze

        def self.handles?(event_type)
          CATALOG_EVENTS.include?(event_type)
        end

        protected

        def process
          billing_logger.info 'Refreshing plan cache', {
            object_type: @data_object.object,
            object_id: @data_object.id,
          }

          Billing::Plan.refresh_from_stripe
          billing_logger.info 'Plan cache refreshed successfully'
          :success
        rescue StandardError => e
          billing_logger.error 'Failed to refresh plan cache', {
            error: e.message,
            backtrace: e.backtrace&.first(5),
          }
          # Don't fail webhook for cache refresh failure
          :success
        end
      end
    end
  end
end
