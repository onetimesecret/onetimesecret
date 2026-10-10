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
    # domains and webhooks all dead-letter into it), so — like the epic #40
    # session verbs — these live in the central operations home rather than an
    # app-scoped one.
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
      # the DLQ verbs (List / Peek / Show / Replay / Discard / Purge) and the
      # `bin/ots queue dlq` CLI are thin adapters over.
      #
      # Context-free by contract (lib/onetime/operations/README.md): it knows
      # nothing about HTTP or the CLI. Callers pass an already-open Bunny-like
      # connection (the CLI its own short-lived one, the colonel logic the shared
      # boot-time `$rmq_conn`); the ops create + close their own channels off it.
      # Every queue handle is opened `passive: true`, so inspecting a DLQ never
      # declares a queue that does not already exist.
      module Store
        module_function

        # Default and request-path bound on the deliveries one per-message
        # lookup ({with_message}) pops (CONTRACT 6: bounded work on the
        # request path). The colonel endpoints never pass another value; the
        # CLI may raise it (`--max-scan`) for an operator at the shell. Every popped
        # delivery is a synchronous basic.get round trip and stays unacked
        # until the scan ends, so the bound caps both the request time and
        # how many messages one lookup hides from other consumers. An
        # operator finds an id through Peek, which shows at most
        # {Peek::MAX_LIMIT} (100) messages from the head; five times that
        # still reaches the id after messages a consumer held during the
        # peek have returned ahead of it. At a few milliseconds per round
        # trip, 500 pops stay well inside the proxy's 15 s read timeout.
        MAX_SCAN = 500

        # The outcome of a per-message lookup that did not find the id. The
        # id was not among the deliveries this scan could see, which is not
        # proof it is gone: a consumer may hold it unacked (the email DLQ
        # consumer holds deliveries for up to its 240 s run budget), it may
        # sit deeper than {MAX_SCAN}, or the queue may not be declared yet.
        NOT_VISIBLE = 'not_visible'

        # Result of {with_message}.
        #
        # @!attribute found [r] Boolean the id was among the popped deliveries
        # @!attribute scanned [r] Integer deliveries popped, the match included
        # @!attribute truncated [r] Boolean the scan stopped at its bound
        #   without a match while messages were still ready behind it
        # @!attribute value [r] the block's return value; nil on a miss
        Scan = Data.define(:found, :scanned, :truncated, :value)

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

        # Peek up to `count` messages without consuming them. Each pop is a
        # manual-ack delivery held until the scan ends: requeueing it at once can
        # put the same message back at the head before the next pop, so the scan
        # would read the head again instead of moving on. While held, scanned
        # messages are invisible to other consumers and to `message_count`.
        # Requeue may change order. The historic CLI projection caps
        # `payload_preview` at 200 chars.
        #
        # @param channel [Object]
        # @param dlq_name [String]
        # @param count [Integer] how many messages to peek (already clamped)
        # @return [Array<Hash>] message summaries
        def peek(channel, dlq_name, count)
          messages      = []
          delivery_tags = []
          queue         = queue_handle(channel, dlq_name)

          count.times do
            delivery_info, properties, payload = queue.pop(manual_ack: true)
            break unless delivery_info

            delivery_tags << delivery_info.delivery_tag
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
          end

          messages
        ensure
          requeue_deliveries(channel, dlq_name, delivery_tags)
        end

        # Locate a single message by id or 1-based index, returning its full detail
        # (headers, death info, parsed payload) or nil. Scanned messages stay
        # unacked until traversal ends, then are nack-requeued without consuming
        # them (see {peek}). The scan stops at the match, an empty pop, or
        # `total` messages, so a miss holds up to `total` deliveries at once.
        # Requeue may change order. Uses the historic CLI detail projection.
        #
        # @param channel [Object]
        # @param dlq_name [String]
        # @param message_id [String, nil]
        # @param index [Integer, nil] 1-based
        # @param total [Integer] queue depth (caller-measured)
        # @return [Hash, nil]
        def find_message(channel, dlq_name, message_id, index, total)
          delivery_tags = []
          queue         = queue_handle(channel, dlq_name)
          found         = nil

          total.times do |i|
            delivery_info, properties, payload = queue.pop(manual_ack: true)
            break unless delivery_info

            delivery_tags << delivery_info.delivery_tag
            match = if message_id
                      properties.message_id == message_id
                    else
                      (i + 1) == index
                    end

            found = build_message_detail(delivery_info, properties, payload) if match

            break if found
          end

          found
        ensure
          requeue_deliveries(channel, dlq_name, delivery_tags)
        end

        # Find one message by id and hand its delivery to the block, for the
        # per-message verbs (Show, and the live Replay and Discard).
        # {find_message} cannot serve the live verbs: it requeues every
        # delivery it popped, the match included.
        #
        # Pops up to `max_scan` deliveries ({MAX_SCAN} unless the caller,
        # only ever the CLI, asks for more). A delivery that does not match is held unacked, so the next pop moves
        # on to the message behind it: nack-requeueing it at once would put it
        # back at the head, where the next pop returns it again and the scan
        # never gets past the first message (#4650). The scan stops at the
        # match, an empty pop, or the bound.
        #
        # The held deliveries are nack-requeued one tag at a time in delivery
        # order ({requeue_deliveries}) as soon as the scan ends, in an
        # `ensure`, and BEFORE the block runs: so they are back in the queue
        # whatever the block does, and the nacks are not caught in a
        # transaction the block selects. RabbitMQ returns a requeued delivery
        # to its original position in a classic queue when no other consumer
        # took messages in between, and no other consumer can: this scan held
        # everything ahead of the match. The queue therefore keeps its order.
        # The channel must not be in transaction mode when this is called.
        #
        # The block receives the matched delivery and owns it: it acks it, or
        # leaves it unacked. An unacked match returns to its position in the
        # queue when the caller closes the channel, which every DLQ op does
        # in its own `ensure`. The block runs only on a match.
        #
        # @param channel [Object] a Bunny-like channel dedicated to this lookup
        # @param dlq_name [String]
        # @param message_id [String] the AMQP message id to find
        # @param max_scan [Integer] scan bound, a positive integer
        # @yieldparam delivery_info [Object]
        # @yieldparam properties [Object]
        # @yieldparam payload [String]
        # @return [Scan]
        # @raise [Bunny::NotFound] from the passive declare when the queue does
        #   not exist; the caller decides what that means
        def with_message(channel, dlq_name, message_id, max_scan: MAX_SCAN)
          raise ArgumentError, 'message_id is required' if message_id.to_s.empty?

          limit = Integer(max_scan, exception: false)
          raise ArgumentError, 'max_scan must be a positive integer' unless limit&.positive?

          queue     = queue_handle(channel, dlq_name)
          held      = []
          scanned   = 0
          match     = nil
          truncated = false

          begin
            while scanned < limit
              delivery_info, properties, payload = queue.pop(manual_ack: true)
              break unless delivery_info

              scanned += 1
              # Held before the comparison, so a delivery whose properties
              # raise is still returned.
              held << delivery_info.delivery_tag
              next unless properties.message_id == message_id

              held.pop
              match = [delivery_info, properties, payload]
              break
            end

            # Asked while the scanned prefix is still held, so the count is
            # only what lies behind it.
            truncated = match.nil? && scanned >= limit && queue.message_count.positive?
          ensure
            requeue_deliveries(channel, dlq_name, held)
          end

          value = match ? yield(*match) : nil
          Scan.new(found: !match.nil?, scanned: scanned, truncated: truncated, value: value)
        end

        # Nack-requeue the deliveries an inspection held, one tag at a time in
        # delivery order. Per-tag nacks (not `multiple: true`) touch only this
        # scan's deliveries even if the caller's channel carries others.
        #
        # A failed nack leaves the rest outstanding. Closing the channel makes the
        # broker requeue every unacked delivery on it, including tags not yet
        # attempted, so callers pass a channel dedicated to the inspection (Peek,
        # Show, Replay and Discard do). The error is then re-raised.
        #
        # @param channel [Object]
        # @param dlq_name [String] for the failure log
        # @param delivery_tags [Array<Integer>]
        def requeue_deliveries(channel, dlq_name, delivery_tags)
          delivery_tags.each { |tag| channel.nack(tag, false, true) }
        rescue StandardError => ex
          Onetime.get_logger('Operations').warn 'DLQ inspection requeue failed; closing channel',
            queue: dlq_name,
            deliveries: delivery_tags.size,
            error: ex.message,
            error_class: ex.class.name
          channel.close if channel.open?
          raise
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
