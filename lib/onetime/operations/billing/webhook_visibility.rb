# lib/onetime/operations/billing/webhook_visibility.rb
#
# frozen_string_literal: true

require 'billing/models/stripe_webhook_event'
require 'billing/models/pending_federated_subscription'

module Onetime
  module Operations
    module Billing
      # Read-only, bounded projections of local billing webhook state.
      #
      # The webhook and pending-federation stores have no read index. This
      # operation therefore scans object keys with a hard row and round bound,
      # then sorts the collected records by their received timestamp and stable
      # identifier. A capped response is deliberately a lower-bound view: it
      # must never be presented as the complete population.
      #
      # No Stripe client is involved. This operation only reads the local Redis
      # records and never extends an expiration, writes an audit entry, or
      # mutates claim state.
      class WebhookVisibility
        DEFAULT_PER_PAGE = 50
        MAX_PER_PAGE     = 100
        MAX_SCAN_ROWS    = 5_000
        MAX_SCAN_ROUNDS  = 100
        SCAN_COUNT       = 100

        Page = Data.define(
          :rows,
          :page,
          :per_page,
          :total_count,
          :total_pages,
          :capped,
        )

        def initialize(
          dbclient: Familia.dbclient,
          webhook_event_model: ::Billing::StripeWebhookEvent,
          pending_subscription_model: ::Billing::PendingFederatedSubscription
        )
          @dbclient                   = dbclient
          @webhook_event_model        = webhook_event_model
          @pending_subscription_model = pending_subscription_model
        end

        def list_webhook_events(page: 1, per_page: DEFAULT_PER_PAGE)
          records, capped = bounded_records(@webhook_event_model)
          paginate(records.sort_by { |event| event_sort_key(event) }, page, per_page, capped) do |event|
            webhook_event_row(event)
          end
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
          records, capped                      = bounded_records(@pending_subscription_model)
          ordered                              = records.sort_by { |subscription| pending_sort_key(subscription) }
          normalized_page, normalized_per_page = normalize_pagination(page, per_page)
          start                                = (normalized_page - 1) * normalized_per_page
          slice                                = ordered[start, normalized_per_page] || []
          source_events                        = source_events_for(slice)

          rows = slice.map do |subscription|
            pending_subscription_row(subscription, source_events)
          end

          build_page(rows, ordered.size, normalized_page, normalized_per_page, capped)
        end

        private

        # Scan only object keys: identifiers are recovered without reading any
        # raw stored field, then load_multi performs one bounded batched read.
        # SCAN may return duplicate keys while Redis is being modified, so the
        # identifier set is deduplicated before the row cap is applied.
        def bounded_records(model)
          identifiers, capped = bounded_identifiers(model)
          return [[], capped] if identifiers.empty?

          records = model.load_multi(identifiers).compact
          # An object can expire between SCAN and the batched read. Its absence
          # means this response cannot honestly claim an exact population.
          [records, capped || records.size != identifiers.size]
        end

        def bounded_identifiers(model)
          identifiers = []
          seen        = {}
          cursor      = '0'
          rounds      = 0
          capped      = false

          loop do
            cursor, keys = @dbclient.scan(
              cursor,
              match: "#{model.prefix}:*:object",
              count: SCAN_COUNT,
            )
            rounds      += 1

            keys.sort.each do |key|
              identifier = identifier_from_object_key(model, key)
              next if identifier.empty? || seen.key?(identifier)

              seen[identifier] = true
              if identifiers.size >= MAX_SCAN_ROWS
                capped = true
                break
              end

              identifiers << identifier
            end

            break if capped || cursor == '0' || rounds >= MAX_SCAN_ROUNDS || identifiers.size >= MAX_SCAN_ROWS
          end

          # A nonterminal cursor means a row/round bound ended the walk. A scan
          # batch that itself overflowed MAX_SCAN_ROWS is capped even if Redis
          # returned its terminal cursor in that batch.
          capped ||= cursor != '0'
          [identifiers, capped]
        end

        def identifier_from_object_key(model, key)
          key.to_s.delete_prefix("#{model.prefix}:").delete_suffix(':object')
        end

        def paginate(records, page, per_page, capped, &)
          normalized_page, normalized_per_page = normalize_pagination(page, per_page)
          start                                = (normalized_page - 1) * normalized_per_page
          rows                                 = (records[start, normalized_per_page] || []).map(&)

          build_page(rows, records.size, normalized_page, normalized_per_page, capped)
        end

        def build_page(rows, total_count, page, per_page, capped)
          Page.new(
            rows: rows,
            page: page,
            per_page: per_page,
            total_count: total_count,
            total_pages: (total_count.to_f / per_page).ceil,
            capped: capped,
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

        # Negative timestamp creates newest-first order; event id resolves ties
        # deterministically across an otherwise unordered SCAN result.
        def event_sort_key(event)
          [-epoch_or_nil(event.first_seen_at).to_i, event_identifier(event)]
        end

        def pending_sort_key(subscription)
          [-epoch_or_nil(subscription.received_at).to_i, subscription.email_hash.to_s]
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

          @webhook_event_model.load_multi(ids).compact.to_h do |event|
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
