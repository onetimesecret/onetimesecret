# lib/onetime/operations/dlq/store.rb
#
# frozen_string_literal: true

require 'json'
require 'onetime/jobs/queues/config'

module Onetime
  module Operations
    # Dead-Letter-Queue admin operations (epic #42 / D3).
    #
    # Central (cross-cutting) admin verbs — see decision D3 in
    # lib/onetime/operations/README.md. A dead-letter queue is a piece of the
    # RabbitMQ messaging fabric with no single domain owner (billing, email,
    # domains and webhooks all dead-letter into it), so — like the Slice-4
    # {Onetime::Operations::BanIP} / `UnbanIP` and the epic #40 session verbs —
    # these live in the central operations home rather than an app-scoped one.
    #
    # Before this extraction the DLQ list / show / replay / purge capability lived
    # ONLY on `bin/ots queue dlq …` (`lib/onetime/cli/queue/dlq_command.rb`): an
    # operator with no shell had no way to triage or drain a dead-letter queue.
    # These ops are the SINGLE implementation each of those verbs; the CLI and the
    # new colonel endpoints (`/api/colonel/queues/dlq…`) are thin adapters over
    # them.
    module Dlq
      # Shared DLQ primitives — the single source of the RabbitMQ queue-name
      # allowlist, the message projection shapes, and the death-header parsing that
      # the DLQ verbs (List / Peek / Show / Replay / Purge) and the `bin/ots queue
      # dlq` CLI are thin adapters over.
      #
      # Context-free by contract (lib/onetime/operations/README.md): it knows
      # nothing about HTTP or the CLI. Callers pass an already-open Bunny-like
      # connection (the CLI its own short-lived one, the colonel logic the shared
      # boot-time `$rmq_conn`); the ops create + close their own channels off it.
      # Every queue handle is opened `passive: true`, so inspecting a DLQ never
      # declares a queue that does not already exist.
      module Store
        module_function

        # Resolve a caller-supplied name to a full DLQ queue name. Mirrors the
        # historic CLI `resolve_dlq_name` mapping EXACTLY (bit-for-bit): a name that
        # already carries the `dlq.` prefix is returned untouched; otherwise the
        # `dlq.` prefix is prepended. Validity (against {all_dlq_names}) is a
        # SEPARATE concern the adapter enforces ({valid?}), because the CLI and the
        # HTTP edge surface an unknown name differently (a `puts`+exit vs a 404).
        #
        # @param name [String] short (`billing.event`) or full (`dlq.billing.event`)
        # @return [String] the full DLQ queue name
        def resolve(name)
          n = name.to_s
          return n if n.start_with?('dlq.')

          "dlq.#{n}"
        end

        # The fixed set of dead-letter queue names, sourced from the single
        # DEAD_LETTER_CONFIG topology. A bounded allowlist by construction — an
        # operator can only ever act on one of these queues (CONTRACT 6: no
        # unbounded key/queue enumeration on the request path).
        #
        # @return [Array<String>]
        def all_dlq_names
          Onetime::Jobs::QueueConfig::DEAD_LETTER_CONFIG.values.map { |v| v[:queue] }
        end

        # Short (prefix-stripped) forms of {all_dlq_names}, for operator-facing
        # listings ("Available DLQs: billing.event, email.message, …").
        #
        # @return [Array<String>]
        def short_names
          all_dlq_names.map { |n| n.sub('dlq.', '') }
        end

        # Whether a fully-resolved DLQ name is one of the configured dead-letter
        # queues. The security control for the HTTP path: the colonel endpoints
        # reject anything not on this allowlist BEFORE touching the broker.
        #
        # @param dlq_name [String] a resolved name (see {resolve})
        # @return [Boolean]
        def valid?(dlq_name)
          all_dlq_names.include?(dlq_name)
        end

        # Open a passive queue handle. `passive: true` means "fail if it does not
        # already exist" (raising Bunny::NotFound) rather than declaring it — the
        # same flags the CLI used, so inspecting a DLQ never mutates topology.
        #
        # @param channel [Object] a Bunny-like channel
        # @param dlq_name [String]
        # @return [Object] the queue handle
        def queue_handle(channel, dlq_name)
          channel.queue(dlq_name, durable: true, passive: true)
        end

        # Compact per-queue summary row for the DLQ list. Identical shape to the
        # historic CLI `get_queue_info`.
        #
        # @param channel [Object]
        # @param dlq_name [String]
        # @return [Hash] { queue:, messages:, consumers: }
        def summary_row(channel, dlq_name)
          queue = queue_handle(channel, dlq_name)
          {
            queue: dlq_name,
            messages: queue.message_count,
            consumers: queue.consumer_count,
          }
        end

        # Non-destructively peek up to `count` messages from a DLQ. Each message is
        # popped with a manual ack and IMMEDIATELY nack-requeued, so the queue is
        # left exactly as found — a read, not a drain. Byte-for-byte the historic
        # CLI `peek_messages` projection (`payload_preview` is capped at 200 chars).
        #
        # @param channel [Object]
        # @param dlq_name [String]
        # @param count [Integer] how many messages to peek (already clamped)
        # @return [Array<Hash>] message summaries
        def peek(channel, dlq_name, count)
          messages = []
          queue    = queue_handle(channel, dlq_name)

          count.times do
            delivery_info, properties, payload = queue.pop(manual_ack: true)
            break unless delivery_info

            begin
              death = extract_death_info(properties.headers)
              messages << {
                delivery_tag: delivery_info.delivery_tag,
                message_id: properties.message_id,
                timestamp: properties.timestamp&.to_i,
                age: format_age(properties.timestamp),
                original_queue: death[:queue],
                death_reason: death[:reason],
                death_count: death[:count],
                error: death[:error],
                content_type: properties.content_type,
                payload_preview: payload.to_s[0..200],
              }
            ensure
              # Always nack WITH requeue so the peek leaves the DLQ untouched.
              channel.nack(delivery_info.delivery_tag, false, true)
            end
          end

          messages
        end

        # Locate a single message by id or 1-based index, returning its full detail
        # (headers, death info, parsed payload) or nil. Non-destructive: every popped
        # message is nack-requeued. Byte-for-byte the historic CLI `find_message` +
        # `build_message_detail`.
        #
        # @param channel [Object]
        # @param dlq_name [String]
        # @param message_id [String, nil]
        # @param index [Integer, nil] 1-based
        # @param total [Integer] queue depth (caller-measured)
        # @return [Hash, nil]
        def find_message(channel, dlq_name, message_id, index, total)
          queue = queue_handle(channel, dlq_name)
          found = nil

          total.times do |i|
            delivery_info, properties, payload = queue.pop(manual_ack: true)
            break unless delivery_info

            match = if message_id
                      properties.message_id == message_id
                    else
                      (i + 1) == index
                    end

            found = build_message_detail(delivery_info, properties, payload) if match

            # Requeue every message we inspected — read-only.
            channel.nack(delivery_info.delivery_tag, false, true)
            break if found
          end

          found
        end

        # Full single-message detail projection. Byte-for-byte the historic CLI
        # `build_message_detail`.
        #
        # @return [Hash]
        def build_message_detail(delivery_info, properties, payload)
          headers = properties.headers || {}
          death   = headers['x-death']&.first || {}

          {
            delivery_tag: delivery_info.delivery_tag,
            message_id: properties.message_id,
            timestamp: properties.timestamp&.iso8601,
            content_type: properties.content_type,
            headers: headers,
            death_info: {
              original_queue: death['queue'],
              original_exchange: death['exchange'],
              reason: death['reason'],
              count: death['count'],
              time: death['time']&.iso8601,
              routing_keys: death['routing-keys'],
            },
            payload: safe_parse_payload(payload, properties.content_type),
          }
        end

        # Parse a JSON payload, falling back to the raw string on any parse error or
        # non-JSON content-type. Byte-for-byte the historic CLI `safe_parse_payload`.
        #
        # @return [Object]
        def safe_parse_payload(payload, content_type)
          return payload unless content_type&.include?('json')

          JSON.parse(payload)
        rescue JSON::ParserError
          payload
        end

        # Extract the original queue this message dead-lettered from, from the
        # AMQP `x-death` header — used to route a replay back. Byte-for-byte the
        # historic CLI `extract_original_queue`.
        #
        # @param headers [Hash, nil]
        # @return [String, nil]
        def original_queue(headers)
          return nil unless headers

          death = headers['x-death']&.first
          death&.fetch('queue', nil)
        end

        # Strip death-related headers before a replay so the republished message is
        # clean. Byte-for-byte the historic CLI `clean_headers`.
        #
        # @param headers [Hash, nil]
        # @return [Hash]
        def clean_headers(headers)
          return {} unless headers

          headers.reject { |k, _| k.start_with?('x-death', 'x-first-death') }
        end

        # Compact death summary for a peeked message. Byte-for-byte the historic
        # CLI `extract_death_info`.
        #
        # @param headers [Hash, nil]
        # @return [Hash]
        def extract_death_info(headers)
          return {} unless headers

          death = headers['x-death']&.first || {}
          {
            queue: death['queue'],
            reason: death['reason'],
            count: death['count'],
            error: headers['x-exception'] || headers['x-error'],
          }
        end

        # Human-readable age string for a message timestamp. Byte-for-byte the
        # historic CLI `format_age`.
        #
        # @param timestamp [Time, Integer, nil]
        # @return [String]
        def format_age(timestamp)
          return 'unknown' unless timestamp

          age_seconds = Time.now.to_i - timestamp.to_i
          case age_seconds
          when 0..59 then "#{age_seconds}s ago"
          when 60..3599 then "#{age_seconds / 60}m ago"
          when 3600..86_399 then "#{age_seconds / 3600}h ago"
          else "#{age_seconds / 86_400}d ago"
          end
        end
      end
    end
  end
end
