# apps/web/billing/operations/webhook_handlers/catalog_updated.rb
#
# frozen_string_literal: true

require_relative 'base_handler'

module Billing
  module Operations
    module WebhookHandlers
      # Handles product/price catalog update events with incremental sync.
      #
      # Instead of triggering a full catalog refresh on every event, this handler
      # performs targeted updates for the specific product or price that changed.
      # This eliminates the race condition where the catalog is briefly empty
      # during a full refresh.
      #
      # Deletion events mark plans as inactive (soft-delete) rather than
      # destroying them, preserving historical data and preventing lookup failures.
      #
      # Errors are logged but not re-raised to avoid failing the webhook
      # for non-critical catalog sync operations.
      #
      class CatalogUpdated < BaseHandler
        CATALOG_EVENTS = %w[
          product.created product.updated product.deleted
          price.created price.updated price.deleted
          plan.created plan.updated
        ].freeze

        def self.handles?(event_type)
          CATALOG_EVENTS.include?(event_type)
        end

        protected

        def process
          case @event.type
          when 'product.created', 'product.updated'
            sync_single_product(@data_object.id)
          when 'price.created', 'price.updated'
            sync_single_price(@data_object.id)
          when 'product.deleted'
            mark_product_inactive(@data_object.id)
          when 'price.deleted'
            mark_price_inactive(@data_object.id)
          when 'plan.created', 'plan.updated'
            # Legacy plan events - still trigger full refresh for compatibility
            Billing::Plan.refresh_from_stripe
            billing_logger.info '[CatalogUpdated] Legacy plan event, full refresh complete'
          end

          :success
        rescue StandardError => ex
          billing_logger.error '[CatalogUpdated] Sync failed', {
            error: ex.message,
            event_type: @event.type,
            object_id: @data_object.id,
            backtrace: ex.backtrace&.first(3),
          }
          # Don't fail webhook for sync errors - prevents retry storms
          :success
        end

        private

        # Sync a single product and all its active prices
        #
        # Fetches fresh data from Stripe (webhook payload may be stale) and
        # upserts plans for all recurring prices on this product.
        #
        # Stripe API key is already configured by the StripeSetup initializer
        # before any webhook processing occurs.
        #
        # @param product_id [String] Stripe product ID
        def sync_single_product(product_id)
          # Fetch fresh from Stripe - webhook payload is a snapshot and may be stale
          product = Stripe::Product.retrieve(product_id)

          # Only sync OTS products (filter by app metadata)
          return unless product.metadata['app'] == 'onetimesecret'

          # Get all active prices for this product
          prices = Stripe::Price.list(product: product_id, active: true)
          synced_count = 0

          prices.auto_paging_each do |price|
            # Skip non-recurring prices (one-time payments, etc.)
            next unless price.type == 'recurring'

            plan_data = Billing::Plan.extract_plan_data(product, price)
            Billing::Plan.upsert_from_stripe_data(plan_data)
            synced_count += 1
          end

          Billing::Plan.rebuild_stripe_price_id_cache

          billing_logger.info '[CatalogUpdated] Synced product', {
            product_id: product_id,
            product_name: product.name,
            prices_synced: synced_count,
          }
        end

        # Sync a single price and its parent product
        #
        # Fetches fresh price and product data from Stripe and upserts the
        # corresponding plan.
        #
        # @param price_id [String] Stripe price ID
        def sync_single_price(price_id)
          # Fetch fresh price and its product
          price = Stripe::Price.retrieve(price_id)
          product = Stripe::Product.retrieve(price.product)

          # Only sync OTS products
          return unless product.metadata['app'] == 'onetimesecret'

          # Skip non-recurring prices
          return unless price.type == 'recurring'

          plan_data = Billing::Plan.extract_plan_data(product, price)
          Billing::Plan.upsert_from_stripe_data(plan_data)
          Billing::Plan.rebuild_stripe_price_id_cache

          billing_logger.info '[CatalogUpdated] Synced price', {
            price_id: price_id,
            plan_id: plan_data[:plan_id],
          }
        end

        # Mark all plans for a deleted product as inactive
        #
        # Uses soft-delete pattern - sets active='false' rather than destroying
        # the plan. This preserves historical data for existing subscriptions.
        #
        # @param product_id [String] Stripe product ID
        def mark_product_inactive(product_id)
          marked_count = 0

          Billing::Plan.list_plans.each do |plan|
            next unless plan.stripe_product_id == product_id

            plan.active = 'false'
            plan.last_synced_at = Time.now.to_i.to_s
            plan.save

            billing_logger.info '[CatalogUpdated] Marked plan inactive (product deleted)', {
              plan_id: plan.plan_id,
              product_id: product_id,
            }
            marked_count += 1
          end

          Billing::Plan.rebuild_stripe_price_id_cache if marked_count > 0

          billing_logger.info '[CatalogUpdated] Product deletion processed', {
            product_id: product_id,
            plans_marked_inactive: marked_count,
          }
        end

        # Mark a plan for a deleted price as inactive
        #
        # Uses soft-delete pattern - sets active='false' rather than destroying
        # the plan.
        #
        # @param price_id [String] Stripe price ID
        def mark_price_inactive(price_id)
          plan = Billing::Plan.find_by_stripe_price_id(price_id)

          unless plan
            billing_logger.info '[CatalogUpdated] Price deletion - no matching plan', {
              price_id: price_id,
            }
            return
          end

          plan.active = 'false'
          plan.last_synced_at = Time.now.to_i.to_s
          plan.save

          Billing::Plan.rebuild_stripe_price_id_cache

          billing_logger.info '[CatalogUpdated] Marked plan inactive (price deleted)', {
            plan_id: plan.plan_id,
            price_id: price_id,
          }
        end
      end
    end
  end
end
