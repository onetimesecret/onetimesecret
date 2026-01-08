# apps/web/billing/operations/webhook_handlers/catalog_updated.rb
#
# frozen_string_literal: true

require_relative 'base_handler'
require_relative '../../lib/stripe_circuit_breaker'

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
      # ## Circuit Breaker Integration
      #
      # When the Stripe circuit breaker is open, instead of failing the webhook,
      # this handler schedules the event for retry via the CatalogRetryJob.
      # This ensures catalog updates are eventually processed after Stripe
      # recovers, without losing webhook delivery acknowledgment.
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
        rescue Billing::CircuitOpenError => ex
          schedule_circuit_retry(ex)
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

        # Schedule event for retry when circuit breaker is open
        #
        # Uses the webhook event record (if available in context) to schedule
        # a retry via CatalogRetryJob. If no event record is available (e.g.,
        # during CLI replay), logs and returns success.
        #
        # @param error [Billing::CircuitOpenError] The circuit open error
        # @return [Symbol] :queued if scheduled, :success otherwise
        def schedule_circuit_retry(error)
          webhook_event = @context[:webhook_event]

          # If no event record available, we can't schedule retry
          # This happens during CLI replays or sync fallback processing
          unless webhook_event
            billing_logger.warn '[CatalogUpdated] Circuit breaker open, no event record for retry', {
              event_type: @event.type,
              object_id: @data_object.id,
              retry_after: error.retry_after,
            }
            return :success
          end

          # Check if already at max retries
          if webhook_event.circuit_retry_exhausted?
            billing_logger.error '[CatalogUpdated] Circuit retry exhausted', {
              event_type: @event.type,
              object_id: @data_object.id,
              retry_count: webhook_event.circuit_retry_count,
            }
            webhook_event.mark_failed!(error)
            return :success
          end

          # Schedule retry with delay from circuit breaker or exponential backoff
          delay = error.retry_after || 60
          webhook_event.schedule_circuit_retry(delay_seconds: delay)

          billing_logger.warn '[CatalogUpdated] Circuit breaker open, scheduled retry', {
            event_type: @event.type,
            object_id: @data_object.id,
            retry_after: delay,
            retry_count: webhook_event.circuit_retry_count,
          }

          :queued
        end

        # Fetch from Stripe with circuit breaker and exponential backoff
        #
        # Uses circuit breaker to prevent cascade failures during Stripe outages.
        # Implements retry logic with jitter to handle Stripe rate limiting
        # gracefully. The delay doubles with each retry plus random jitter
        # to prevent thundering herd.
        #
        # @param max_retries [Integer] Maximum retry attempts (default: 3)
        # @yield Block containing Stripe API call
        # @return Result of the block
        # @raise [Stripe::RateLimitError] After max_retries exceeded
        # @raise [Billing::CircuitOpenError] If circuit breaker is open
        def fetch_with_retry(max_retries: 3)
          Billing::StripeCircuitBreaker.call do
            retries = 0
            begin
              yield
            rescue Stripe::RateLimitError
              retries += 1
              if retries <= max_retries
                delay = (2**retries) + rand # Exponential backoff with jitter
                billing_logger.warn '[CatalogUpdated] Rate limited, retry ' \
                                    "#{retries}/#{max_retries} after #{delay.round(1)}s"
                sleep(delay)
                retry
              end
              billing_logger.error "[CatalogUpdated] Rate limit exceeded after #{max_retries} retries"
              raise
            end
          end
        end

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
          product = fetch_with_retry { Stripe::Product.retrieve(product_id) }

          # Only sync OTS products (filter by app metadata)
          return unless product.metadata['app'] == 'onetimesecret'

          # Get all active prices for this product
          prices = fetch_with_retry { Stripe::Price.list(product: product_id, active: true) }
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
          price = fetch_with_retry { Stripe::Price.retrieve(price_id) }
          product = fetch_with_retry { Stripe::Product.retrieve(price.product) }

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
