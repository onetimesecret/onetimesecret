# lib/onetime/operations/notifications/list_delivery_events.rb
#
# frozen_string_literal: true

require 'onetime/models/delivery_event'

module Onetime
  module Operations
    module Notifications
      # Read the delivery-event feed (Onetime::DeliveryEvent), newest first,
      # with optional filters. The single read path for the CLI and for any
      # later colonel endpoint or admin view (#4479).
      #
      # Filters are applied while walking the feed in pages, so a filtered
      # read costs at most one pass over the retained events (bounded by
      # DeliveryEvent::MAX_EVENTS). `more` says whether matches remain past
      # the returned page; there is no total for a filtered read.
      #
      # Read-only: records no audit event.
      class ListDeliveryEvents
        # Fields exposed by the reader, in projection order.
        FIELDS = %w[
          id occurred_at channel stage outcome correlation_id message_id
          event_type template customer_id reason error_class
          http_status target_host provider provider_message_id duration_ms
          attempt_count
        ].freeze

        FILTERS = [:channel, :stage, :outcome, :correlation_id, :event_type, :template].freeze

        MAX_LIMIT = 500
        PAGE      = 500

        Result = Data.define(:events, :limit, :offset, :more, :retained, :filters)

        # @param limit [Integer] max events to return (1..MAX_LIMIT)
        # @param offset [Integer] matching events to skip
        # @param filters [Hash] any of FILTERS => String; nil/blank ignored
        def initialize(limit: 50, offset: 0, **filters)
          @limit   = limit.to_i.clamp(1, MAX_LIMIT)
          @offset  = [offset.to_i, 0].max
          @filters = filters.slice(*FILTERS)
            .transform_values { |value| value.to_s.strip }
            .reject { |_, value| value.empty? }
        end

        # @return [Result]
        def call
          validate_filters!

          matched = []
          seen    = {}
          skipped = 0
          more    = false
          cursor  = 0

          loop do
            page = Onetime::DeliveryEvent.recent(PAGE, cursor)
            break if page.empty?

            page.each do |event|
              # Concurrent inserts can shift previously read events into this page.
              next if seen.key?(event['id'])

              seen[event['id']] = true
              next unless match?(event)

              if skipped < @offset
                skipped += 1
                next
              end

              if matched.size >= @limit
                more = true
                break
              end

              matched << project(event)
            end

            break if more || page.size < PAGE

            cursor += PAGE
          end

          Result.new(
            events: matched,
            limit: @limit,
            offset: @offset,
            more: more,
            retained: Onetime::DeliveryEvent.count,
            filters: @filters,
          )
        end

        private

        def validate_filters!
          checks = {
            channel: Onetime::DeliveryEvent::CHANNELS,
            stage: Onetime::DeliveryEvent::STAGES,
            outcome: Onetime::DeliveryEvent::OUTCOMES,
          }
          checks.each do |name, allowed|
            value = @filters[name]
            next if value.nil? || allowed.include?(value)

            raise ArgumentError, "#{name} must be one of: #{allowed.join(', ')}"
          end
        end

        def match?(event)
          @filters.all? { |name, value| event[name.to_s].to_s == value }
        end

        # Emit fields explicitly, never the raw stored hash.
        def project(event)
          FIELDS.to_h { |field| [field.to_sym, event[field]] }
        end
      end
    end
  end
end
