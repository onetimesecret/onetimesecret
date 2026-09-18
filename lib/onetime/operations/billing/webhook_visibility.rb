# lib/onetime/operations/billing/webhook_visibility.rb
#
# frozen_string_literal: true

require 'billing/models/stripe_webhook_event'
require 'billing/models/pending_federated_subscription'

module Onetime
  module Operations
    module Billing
      # Read-only, index-backed projections of local billing webhook state.
      #
      # Both listings read a dedicated write-time sorted-set index (newest
      # first by scored timestamp) rather than SCANning the object keyspace.
      # This is the same shape Onetime::Operations::Billing::StripeOrganizations
      # uses, and for the same reason: SCAN bounds the keyspace covered per
      # request rather than the matched keys, so a bounded scan on a large
      # deployment returns an arbitrary sub-sample with no ordering guarantee
      # and pages that duplicate or drop rows across requests.
      #
      # The index is a rebuildable read cache; the object rows remain the code
      # of record. When an id is present in the index but its object no longer
      # loads (TTL expired between the index write and this read), the id is
      # pruned from the index lazily and counted into `stale_count`.
      #
      # No Stripe client is involved. This operation only reads local Redis
      # records and never extends an expiration, writes an audit entry, or
      # mutates claim state.
      class WebhookVisibility
        DEFAULT_PER_PAGE = 50
        MAX_PER_PAGE     = 100

        Page = Data.define(
          :rows,
          :page,
          :per_page,
          :total_count,
          :total_pages,
          :capped,
          :stale_count,
        )

        def initialize(
          webhook_event_model: ::Billing::StripeWebhookEvent,
          pending_subscription_model: ::Billing::PendingFederatedSubscription
        )
          @webhook_event_model        = webhook_event_model
          @pending_subscription_model = pending_subscription_model
        end

        def list_webhook_events(page: 1, per_page: DEFAULT_PER_PAGE)
          index = @webhook_event_model.recent_events
          cap   = ::Billing::StripeWebhookEvent::INDEX_MAX_ENTRIES

          normalized_page, normalized_per_page = normalize_pagination(page, per_page)
          total_count                          = safe_element_count(index)
          capped                               = total_count >= cap

          start = (normalized_page - 1) * normalized_per_page
          stop  = start + normalized_per_page - 1
          ids   = safe_revrange(index, start, stop)

          events       = ids.empty? ? [] : @webhook_event_model.load_multi(ids).compact.select(&:exists?)
          events_by_id = events.to_h { |event| [event_identifier(event), event] }
          stale_ids    = ids.reject { |id| events_by_id.key?(id) }
          prune_stale(index, stale_ids)

          rows = ids.filter_map do |id|
            event = events_by_id[id]
            next if event.nil?

            webhook_event_row(event)
          end

          build_page(rows, total_count, normalized_page, normalized_per_page, capped, stale_ids.size)
        end

        def find_webhook_event(event_id)
          event_id = event_id.to_s
          return nil if event_id.empty?

          @webhook_event_model.find_by_identifier(event_id)
        end

        def webhook_event_row(event)
          {
            event_id: event_identifier(event),
            event_type: blank_to_nil(event.event_type),
            processing_status: blank_to_nil(event.processing_status),
            processing_outcome: optional_field(event, :processing_outcome),
            received_at: epoch_or_nil(event.first_seen_at),
            processed_at: epoch_or_nil(event.processed_at),
            attempt_count: event.attempt_count.to_i,
            retryable: event.retryable? || false,
          }
        end

        # The detail projection remains an allowlist. In particular it excludes
        # event_payload, data_object_id and error_message because they can carry
        # raw Stripe/customer material. Error state is represented without its
        # untrusted message text.
        def webhook_event_detail(event)
          {
            api_version: blank_to_nil(event.api_version),
            livemode: boolean_or_nil(event.livemode),
            stripe_created_at: epoch_or_nil(event.created),
            pending_webhooks: integer_or_nil(event.pending_webhooks),
            last_attempt_at: epoch_or_nil(event.last_attempt_at),
            retryable: event.retryable? || false,
            max_attempts_reached: event.max_attempts_reached? || false,
            circuit_retry_at: epoch_or_nil(event.circuit_retry_at),
            circuit_retry_count: integer_or_nil(event.circuit_retry_count),
            error_present: !event.error_message.to_s.empty?,
          }
        end

        def list_pending_federated_subscriptions(page: 1, per_page: DEFAULT_PER_PAGE)
          index = @pending_subscription_model.recent_records
          cap   = ::Billing::PendingFederatedSubscription::INDEX_MAX_ENTRIES

          normalized_page, normalized_per_page = normalize_pagination(page, per_page)
          total_count                          = safe_element_count(index)
          capped                               = total_count >= cap

          start = (normalized_page - 1) * normalized_per_page
          stop  = start + normalized_per_page - 1
          ids   = safe_revrange(index, start, stop)

          records       = ids.empty? ? [] : @pending_subscription_model.load_multi(ids).compact.select(&:exists?)
          records_by_id = records.to_h { |record| [record.email_hash.to_s, record] }
          stale_ids     = ids.reject { |id| records_by_id.key?(id) }
          prune_stale(index, stale_ids)

          ordered_records = ids.filter_map { |id| records_by_id[id] }
          source_events   = source_events_for(ordered_records)

          rows = ordered_records.map do |subscription|
            pending_subscription_row(subscription, source_events)
          end

          build_page(rows, total_count, normalized_page, normalized_per_page, capped, stale_ids.size)
        end

        private

        # Reverse rank slice: 0 = newest. Errors returning nil are surfaced as
        # an empty page rather than a 500 — this is a read-only admin view.
        def safe_revrange(index, start, stop)
          return [] if stop < start

          Array(index.revrange(start, stop)).map(&:to_s)
        rescue StandardError => ex
          OT.le '[Billing::WebhookVisibility] index revrange failed',
            { exception: ex, message: ex.message }
          []
        end

        def safe_element_count(index)
          index.element_count.to_i
        rescue StandardError
          0
        end

        # Lazy staleness prune: an id in the index whose object no longer
        # loads (TTL expired between write and read) is dropped from the
        # index so it stops occupying a slot and stops repopulating
        # `stale_count` on every request. Best-effort — if the remove itself
        # fails, the next read will try again.
        def prune_stale(index, ids)
          ids.each do |id|
            index.remove(id)
          rescue StandardError => ex
            OT.le '[Billing::WebhookVisibility] index prune failed',
              { exception: ex, message: ex.message, id: id }
          end
        end

        def build_page(rows, total_count, page, per_page, capped, stale_count)
          Page.new(
            rows: rows,
            page: page,
            per_page: per_page,
            total_count: total_count,
            total_pages: (total_count.to_f / per_page).ceil,
            capped: capped,
            stale_count: stale_count,
          )
        end

        def normalize_pagination(page, per_page)
          normalized_page     = page.to_i
          normalized_page     = 1 if normalized_page < 1
          normalized_per_page = per_page.to_i
          normalized_per_page = DEFAULT_PER_PAGE if normalized_per_page < 1
          normalized_per_page = MAX_PER_PAGE if normalized_per_page > MAX_PER_PAGE
          [normalized_page, normalized_per_page]
        end

        def pending_subscription_row(subscription, source_events)
          source_event_id = source_event_identifier(subscription)
          {
            subscription_status: blank_to_nil(subscription.subscription_status),
            planid: blank_to_nil(subscription.planid),
            region: blank_to_nil(subscription.region),
            received_at: epoch_or_nil(subscription.received_at),
            source_webhook: source_event_state(source_event_id, source_events),
          }
        end

        def source_events_for(subscriptions)
          ids = subscriptions.filter_map { |subscription| source_event_identifier(subscription) }.uniq
          return {} if ids.empty?

          @webhook_event_model.load_multi(ids).compact.select(&:exists?).to_h do |event|
            [event_identifier(event), event]
          end
        end

        # New rows use source_stripe_event_id. The alternate spellings tolerate
        # legacy storage without coupling the read API to one migration state.
        def source_event_identifier(subscription)
          value = optional_field(subscription, :source_stripe_event_id)
          value = optional_field(subscription, :source_event_id) if value.nil?
          value = optional_field(subscription, :source_webhook_event_id) if value.nil?
          blank_to_nil(value)
        end

        def source_event_state(source_event_id, source_events)
          no_correlation = {
            state: 'no_correlation',
            processing_status: nil,
            outcome: nil,
          }
          return no_correlation if source_event_id.nil?

          event = source_events[source_event_id]
          return no_correlation.merge(state: 'expired') unless event

          {
            state: 'available',
            processing_status: blank_to_nil(event.processing_status),
            outcome: optional_field(event, :processing_outcome),
          }
        end

        def event_identifier(event)
          event.stripe_event_id.to_s
        end

        def optional_field(record, name)
          return nil unless record.respond_to?(name)

          blank_to_nil(record.public_send(name))
        end

        def blank_to_nil(value)
          string = value.to_s
          string.empty? ? nil : string
        end

        def epoch_or_nil(value)
          string = value.to_s
          string.empty? ? nil : string.to_i
        end

        def integer_or_nil(value)
          string = value.to_s
          string.empty? ? nil : string.to_i
        end

        def boolean_or_nil(value)
          return nil if value.nil? || value.to_s.empty?

          value == true || value.to_s == 'true'
        end
      end
    end
  end
end
